import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/notifications/professional_push_notification_service.dart';

/// Rings for new orders until someone acknowledges them.
///
/// A pharmacy works with the phone on the counter, often across the room. A
/// single chime is easy to miss; partner apps (Swiggy, Zomato) keep ringing
/// until a person responds, and this does the same.
///
/// It posts one notification on the "New orders" channel with Android's
/// `FLAG_INSISTENT`, which makes the system repeat the sound until the
/// notification is tapped, swiped away or cancelled — so it keeps ringing
/// even if the phone is locked or another app is in front. It stops when:
///
/// * someone opens the Orders tab or taps the notification ([stop]),
/// * nothing is waiting any more ([stop] from the shell), or
/// * five minutes pass (`timeoutAfter`), so a shop left unattended is not
///   ringing all night.
///
/// Doctors and physiotherapists get the same treatment for appointment
/// requests ([ringAppointments]), on the "New appointments" channel.
class PharmacyOrderRinger {
  PharmacyOrderRinger._();
  static final PharmacyOrderRinger instance = PharmacyOrderRinger._();

  /// One notification id for all waiting orders: a second order updates the
  /// ringing notification instead of stacking another one.
  static const _notificationId = 47011;

  /// Android's Notification.FLAG_INSISTENT.
  static const _flagInsistent = 4;

  bool _ringing = false;
  bool get isRinging => _ringing;

  FlutterLocalNotificationsPlugin get _local =>
      ProfessionalPushNotificationService.instance.localNotifications;

  /// Starts (or refreshes) the ringing notification for [waiting] orders, led
  /// by [latest]. Safe to call repeatedly.
  Future<void> ring({
    required Map<String, dynamic> latest,
    required int waiting,
  }) async {
    final patient = latest['patientId'];
    final name = patient is Map ? '${patient['name'] ?? ''}'.trim() : '';
    final rx = '${latest['orderStatus']}' == 'prescription_review';
    final title = waiting > 1
        ? '$waiting orders waiting'
        : rx
        ? 'New order · prescription to review'
        : 'New order received';
    final body = [
      if (name.isNotEmpty) name,
      '${latest['orderNumber'] ?? ''}'.trim(),
      'Tap to open',
    ].where((v) => v.isNotEmpty).join(' · ');

    await _show(
      channel: pharmacyOrdersChannel,
      title: title,
      body: body,
      // Same shape a push carries, so a tap opens the order.
      payload: {
        'relatedEntity': 'pharmacy_order',
        'relatedEntityId': '${latest['_id'] ?? ''}',
        'entityType': 'pharmacy_order',
        'orderId': '${latest['_id'] ?? ''}',
      },
    );
  }

  /// Starts (or refreshes) the ringing notification for [waiting] appointment
  /// requests, led by [latest] — already formatted by the caller as
  /// [who] and [when]. [noun] is "appointment" or "session".
  Future<void> ringAppointments({
    required Map<String, dynamic> latest,
    required int waiting,
    required String who,
    required String when,
    String noun = 'appointment',
  }) async {
    final title = waiting > 1
        ? '$waiting $noun requests waiting'
        : 'New $noun request';
    final body = [
      if (who.isNotEmpty) who,
      if (when.isNotEmpty) when,
      'Tap to accept or decline',
    ].join(' · ');
    await _show(
      channel: appointmentRequestsChannel,
      title: title,
      body: body,
      payload: {
        'relatedEntity': 'appointment',
        'relatedEntityId': '${latest['_id'] ?? ''}',
        'entityType': 'appointment',
        'appointmentId': '${latest['_id'] ?? ''}',
      },
    );
  }

  Future<void> _show({
    required AndroidNotificationChannel channel,
    required String title,
    required String body,
    required Map<String, String> payload,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        additionalFlags: Int32List.fromList([_flagInsistent]),
        timeoutAfter: const Duration(minutes: 5).inMilliseconds,
        autoCancel: true,
        onlyAlertOnce: false,
        ticker: title,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );

    try {
      await _local.show(
        id: _notificationId,
        title: title,
        body: body,
        notificationDetails: details,
        payload: jsonEncode(payload),
      );
      _ringing = true;
    } catch (error) {
      debugPrint('Ringer failed: $error');
    }
  }

  /// Stops the ringing. Called when someone has seen the orders.
  Future<void> stop() async {
    if (!_ringing) return;
    _ringing = false;
    try {
      await _local.cancel(id: _notificationId);
    } catch (error) {
      debugPrint('Order ringer stop failed: $error');
    }
  }
}
