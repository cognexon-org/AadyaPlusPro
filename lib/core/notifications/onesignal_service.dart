import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import '../network/api_service.dart';
import 'professional_notification_navigation_service.dart';

/// OneSignal push for the professional app.
///
/// The backend targets users by **external id** — their Mongo `_id` — so this
/// calls `OneSignal.login()` after sign-in and `logout()` on sign-out. Nothing
/// device-specific is ever sent to our server: one account signed in on three
/// phones resolves to three subscriptions under the same external id, and a
/// reinstalled device re-registers itself without the backend knowing.
///
/// FCM (`ProfessionalPushNotificationService`) is left in place as the
/// fallback for builds where [appId] is not configured.
class OneSignalService {
  OneSignalService._();

  static final OneSignalService instance = OneSignalService._();

  /// Supplied at build time so the key is not committed:
  /// `--dart-define=ONE_SIGNAL_APP_ID=...`
  static const String appId = String.fromEnvironment(
    'ONE_SIGNAL_APP_ID',
    defaultValue: '8c6ad5e2-c496-48e7-8ed9-af46bdc38724',
  );

  bool _initialised = false;

  bool get isConfigured => appId.isNotEmpty;

  Future<void> initialize() async {
    if (_initialised || !isConfigured) return;
    _initialised = true;

    try {
      OneSignal.initialize(appId);

      // Taps are the whole point: the payload's relatedEntity decides which
      // screen opens, and the navigation service refuses anything it does not
      // recognise rather than trusting a remote route string.
      OneSignal.Notifications.addClickListener((event) {
        final data = event.notification.additionalData;
        if (data == null) return;
        ProfessionalNotificationNavigationService.instance.open(
          Map<String, dynamic>.from(data),
        );
      });
    } catch (error) {
      debugPrint('OneSignal init failed: $error');
    }
  }

  /// Asks for permission, then binds this device to the signed-in user.
  ///
  /// Called after login rather than at startup so the prompt lands on someone
  /// who has already seen what the app does — and so the subscription is
  /// attached to a known user from its first moment.
  Future<void> bindUser(String userId) async {
    if (!isConfigured || userId.isEmpty) return;
    try {
      await initialize();
      await OneSignal.Notifications.requestPermission(true);
      await OneSignal.login(userId);
    } catch (error) {
      debugPrint('OneSignal bindUser failed: $error');
    }
  }

  Future<void> unbindUser() async {
    if (!isConfigured) return;
    try {
      await OneSignal.logout().timeout(const Duration(seconds: 5));
    } catch (error) {
      debugPrint('OneSignal logout failed: $error');
    }
  }

  /// Asks the server to send the day's greeting.
  ///
  /// Safe to call on every launch: the once-a-day rule is enforced on the
  /// server, because an app can be force-stopped and reopened repeatedly and
  /// the same account can be open on several devices.
  Future<void> requestDailyWelcome() async {
    try {
      await ApiService().sendDailyWelcome();
    } catch (_) {
      // A missed greeting is not worth surfacing or retrying.
    }
  }
}
