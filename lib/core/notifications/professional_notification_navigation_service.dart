import 'package:flutter/material.dart';

import '../../features/notifications/screens/notification_screen.dart';

/// Safe navigation target for push notifications in AadyaPlusPro.
///
/// Push payloads are never allowed to provide an arbitrary route or URL. The
/// current backend B1 notification contract is normalized into the
/// authenticated notification center; domain-specific drill-down can be added
/// later without trusting remote navigation strings.
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
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => const ProfessionalNotificationScreen(),
      ),
    );
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
