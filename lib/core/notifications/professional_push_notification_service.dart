import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../network/api_service.dart';
import '../network/token_storage.dart';
import 'professional_notification_navigation_service.dart';

const AndroidNotificationChannel _aadyaProChannel = AndroidNotificationChannel(
  'aadya_pro_high_importance',
  'Aadya Plus Professional alerts',
  description: 'Clinical, pharmacy, diagnostics and field-force alerts',
  importance: Importance.high,
);

FirebaseOptions? _firebaseOptionsFromEnvironment() {
  const genericApiKey = String.fromEnvironment('AADYA_FIREBASE_API_KEY');
  const genericAppId = String.fromEnvironment('AADYA_FIREBASE_APP_ID');
  const androidApiKey = String.fromEnvironment(
    'AADYA_FIREBASE_ANDROID_API_KEY',
  );
  const androidAppId = String.fromEnvironment('AADYA_FIREBASE_ANDROID_APP_ID');
  const iosApiKey = String.fromEnvironment('AADYA_FIREBASE_IOS_API_KEY');
  const iosAppId = String.fromEnvironment('AADYA_FIREBASE_IOS_APP_ID');
  const senderId = String.fromEnvironment('AADYA_FIREBASE_MESSAGING_SENDER_ID');
  const projectId = String.fromEnvironment('AADYA_FIREBASE_PROJECT_ID');
  const storageBucket = String.fromEnvironment('AADYA_FIREBASE_STORAGE_BUCKET');
  const iosBundleId = String.fromEnvironment('AADYA_FIREBASE_IOS_BUNDLE_ID');

  var apiKey = genericApiKey;
  var appId = genericAppId;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    if (androidApiKey.trim().isNotEmpty) apiKey = androidApiKey;
    if (androidAppId.trim().isNotEmpty) appId = androidAppId;
  } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    if (iosApiKey.trim().isNotEmpty) apiKey = iosApiKey;
    if (iosAppId.trim().isNotEmpty) appId = iosAppId;
  }

  if ([
    apiKey,
    appId,
    senderId,
    projectId,
  ].any((value) => value.trim().isEmpty)) {
    return null;
  }

  return FirebaseOptions(
    apiKey: apiKey.trim(),
    appId: appId.trim(),
    messagingSenderId: senderId.trim(),
    projectId: projectId.trim(),
    storageBucket: storageBucket.trim().isEmpty ? null : storageBucket.trim(),
    iosBundleId: iosBundleId.trim().isEmpty ? null : iosBundleId.trim(),
  );
}

Future<void> _ensureFirebaseInitialized() async {
  if (Firebase.apps.isNotEmpty) return;
  final options = _firebaseOptionsFromEnvironment();
  if (options != null) {
    await Firebase.initializeApp(options: options);
  } else {
    await Firebase.initializeApp();
  }
}

@pragma('vm:entry-point')
Future<void> aadyaProFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  try {
    await _ensureFirebaseInitialized();
  } catch (error) {
    debugPrint('Aadya Pro background Firebase initialization failed: $error');
  }
}

/// Native push lifecycle for the professional app.
///
/// Device tokens are registered only when a JWT exists and are unregistered on
/// logout. Failure to initialize Firebase never blocks the clinical app.
class ProfessionalPushNotificationService {
  ProfessionalPushNotificationService._();

  static final ProfessionalPushNotificationService instance =
      ProfessionalPushNotificationService._();

  final ApiService _api = ApiService();
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final StreamController<int> _events = StreamController<int>.broadcast();

  Stream<int> get notificationEvents => _events.stream;

  bool _initialized = false;
  bool _available = false;
  String? _currentToken;
  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<RemoteMessage>? _foreground;
  StreamSubscription<RemoteMessage>? _opened;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await _ensureFirebaseInitialized();
      FirebaseMessaging.onBackgroundMessage(
        aadyaProFirebaseMessagingBackgroundHandler,
      );
      _available = true;

      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );

      await _local.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload == null || payload.isEmpty) return;
          try {
            final decoded = jsonDecode(payload);
            if (decoded is Map) {
              openNotificationData(Map<String, dynamic>.from(decoded));
            }
          } catch (error) {
            debugPrint('Invalid Aadya Pro notification payload: $error');
          }
        },
      );

      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_aadyaProChannel);

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        announcement: false,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
      );
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );

      _foreground = FirebaseMessaging.onMessage.listen(_onForeground);
      _opened = FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => openNotificationData(_messageData(message)),
      );
      _tokenRefresh = messaging.onTokenRefresh.listen((token) async {
        _currentToken = token;
        await _registerToken(token);
      });

      final localLaunch = await _local.getNotificationAppLaunchDetails();
      final localPayload = localLaunch?.notificationResponse?.payload;
      if (localLaunch?.didNotificationLaunchApp == true &&
          localPayload != null &&
          localPayload.isNotEmpty) {
        try {
          final decoded = jsonDecode(localPayload);
          if (decoded is Map) {
            await openNotificationData(Map<String, dynamic>.from(decoded));
          }
        } catch (error) {
          debugPrint('Invalid local launch payload: $error');
        }
      }

      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        await openNotificationData(_messageData(initial));
      }

      await syncAuthenticatedDevice();
    } catch (error) {
      _available = false;
      debugPrint(
        'Aadya Pro push unavailable: $error. Configure Firebase before release.',
      );
    }
  }

  Future<void> syncAuthenticatedDevice() async {
    if (!_initialized) await initialize();
    if (!_available) return;

    final jwt = await TokenStorage.getToken();
    if (jwt == null || jwt.isEmpty) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      _currentToken = token;
      await _registerToken(token);
    } catch (error) {
      debugPrint('Unable to sync Aadya Pro push token: $error');
    }
  }

  Future<void> unregisterAuthenticatedDevice() async {
    if (!_available) return;
    try {
      final token =
          _currentToken ?? await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await _api.unregisterDeviceToken({'token': token, 'app': 'aadyapluspro'});
    } catch (error) {
      debugPrint('Unable to unregister Aadya Pro push token: $error');
    }
  }

  Future<void> openNotificationData(Map<String, dynamic> data) async {
    final notificationId =
        data['notificationId']?.toString() ?? data['_id']?.toString() ?? '';
    if (notificationId.isNotEmpty) {
      try {
        await _api.markNotificationRead(notificationId);
      } catch (_) {}
    }
    _events.add(DateTime.now().millisecondsSinceEpoch);
    await ProfessionalNotificationNavigationService.instance.open(data);
  }

  Future<void> _onForeground(RemoteMessage message) async {
    final data = _messageData(message);
    _events.add(DateTime.now().millisecondsSinceEpoch);

    final title = message.notification?.title ?? data['title']?.toString();
    final body = message.notification?.body ?? data['message']?.toString();
    if ((title ?? '').isEmpty && (body ?? '').isEmpty) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'aadya_pro_high_importance',
        'Aadya Plus Professional alerts',
        channelDescription:
            'Clinical, pharmacy, diagnostics and field-force alerts',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    final id =
        (message.messageId?.hashCode ??
            DateTime.now().millisecondsSinceEpoch.hashCode) &
        0x7fffffff;
    await _local.show(
      id: id,
      title: title ?? 'Aadya Plus Professional',
      body: body ?? '',
      notificationDetails: details,
      payload: jsonEncode(data),
    );
  }

  Future<void> _registerToken(String token) async {
    final jwt = await TokenStorage.getToken();
    if (jwt == null || jwt.isEmpty) return;
    try {
      await _api.registerDeviceToken({
        'token': token,
        'platform': _platformName(),
        'app': 'aadyapluspro',
      });
    } catch (error) {
      debugPrint('Aadya Pro device-token registration failed: $error');
    }
  }

  Map<String, dynamic> _messageData(RemoteMessage message) {
    final data = Map<String, dynamic>.from(message.data);
    if (message.notification?.title != null) {
      data.putIfAbsent('title', () => message.notification!.title!);
    }
    if (message.notification?.body != null) {
      data.putIfAbsent('message', () => message.notification!.body!);
    }
    return data;
  }

  String _platformName() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return 'unknown';
    }
  }
}
