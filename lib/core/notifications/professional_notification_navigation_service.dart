import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../features/notifications/screens/notification_screen.dart';
import '../../features/pharmacy/screens/order_details_screen.dart';
import '../network/api_service.dart';

/// Safe navigation target for push notifications in AadyaPlusPro.
///
/// Push payloads are never allowed to provide an arbitrary route or URL. The
/// backend's notification contract is normalized here into a small set of
/// known destinations, keyed on `relatedEntity` — a remote payload can pick
/// *which* of our screens opens, never *what* a route string points at.
///
/// Anything unrecognised falls back to the notification centre, which is what
/// every notification did before typed drill-down existed.
class ProfessionalNotificationNavigationService {
  ProfessionalNotificationNavigationService._();

  static final ProfessionalNotificationNavigationService instance =
      ProfessionalNotificationNavigationService._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  Map<String, dynamic>? _pending;
  bool _authenticatedReady = false;

  void setAuthenticatedReady(bool value) {
    _authenticatedReady = value;
    if (value) Future.microtask(drainPending);
  }

  Future<void> open(Map<String, dynamic> data) async {
    final navigator = navigatorKey.currentState;
    if (!_authenticatedReady || navigator == null) {
      _pending = Map<String, dynamic>.from(data);
      return;
    }

    _pending = null;

    final target = await _resolve(data);
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => target ?? const ProfessionalNotificationScreen(),
      ),
    );
  }

  /// Turns a payload into a screen, or null to use the notification centre.
  ///
  /// The order is fetched here rather than passed through the payload: a push
  /// carries a handful of strings, and the details screen needs the whole
  /// record. Fetching also means a stale notification opens the order as it is
  /// *now*, not as it was when the push was sent.
  Future<Widget?> _resolve(Map<String, dynamic> data) async {
    final entity = '${data['relatedEntity'] ?? data['entityType'] ?? ''}';
    if (entity != 'pharmacy_order') return null;

    final id = '${data['relatedEntityId'] ?? data['orderId'] ?? ''}'.trim();
    if (id.isEmpty) return null;

    try {
      final response = await ApiService().getMerchantOrder(id);
      final body = response.data;
      if (body is Map && body['order'] is Map) {
        return OrderDetailsScreen(
          order: Map<String, dynamic>.from(body['order'] as Map),
        );
      }
    } on DioException {
      // Not this pharmacy's order, deleted, or offline — the notification
      // centre is a safe landing spot rather than an error screen.
    }
    return null;
  }

  /// Opens a notification the user tapped in the in-app list.
  ///
  /// The stored record nests its deep-link fields differently from a push
  /// payload, so they are flattened here rather than teaching [_resolve] about
  /// two shapes.
  Future<void> openFromRecord(Map<String, dynamic> row) async {
    final data = <String, dynamic>{
      if (row['data'] is Map) ...Map<String, dynamic>.from(row['data'] as Map),
      'relatedEntity': row['relatedEntity'],
      'relatedEntityId': row['relatedEntityId'],
    };
    final target = await _resolve(data);
    if (target == null) return;
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    await navigator.push(MaterialPageRoute(builder: (_) => target));
  }

  Future<void> drainPending() async {
    final pending = _pending;
    if (pending == null ||
        !_authenticatedReady ||
        navigatorKey.currentState == null) {
      return;
    }
    _pending = null;
    await open(pending);
  }
}
