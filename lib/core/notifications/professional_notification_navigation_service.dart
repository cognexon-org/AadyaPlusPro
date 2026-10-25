import 'package:flutter/material.dart';

import '../../features/notifications/screens/notification_screen.dart';
import '../../features/pharmacy/screens/order_details_screen.dart';
import '../../features/pharmacy/widgets/pharmacy_motion.dart';

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

  /// Builds the appointment details screen for an appointment id. Set by
  /// the dashboard for doctors and physiotherapists (each has its own
  /// details screen); null for other roles, whose appointment notifications
  /// open the notification centre.
  static Widget Function(String appointmentId)? appointmentScreen;

  /// The lab order screen, set by the dashboard for pathology labs.
  static Widget Function(String labTestId)? labOrderScreen;

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

    await navigator.push(_routeFor(data));
  }

  /// The screen for a payload, built *immediately* — no network wait before
  /// it opens. An order notification opens the order screen with just the
  /// id; that screen paints from memory or a skeleton and fetches the order
  /// itself. Waiting for the fetch before navigating left a tap looking
  /// like it had done nothing for a second or two.
  Route<void> _routeFor(Map<String, dynamic> data) {
    final labId = _labTestId(data);
    final labScreen = ProfessionalNotificationNavigationService.labOrderScreen;
    if (labId != null && labScreen != null) {
      return PharmacyPageRoute(builder: (_) => labScreen(labId));
    }
    final appointmentId = _appointmentId(data);
    final appointmentScreen =
        ProfessionalNotificationNavigationService.appointmentScreen;
    if (appointmentId != null && appointmentScreen != null) {
      return PharmacyPageRoute(
        builder: (_) => appointmentScreen(appointmentId),
      );
    }
    final id = _orderId(data);
    if (id == null) {
      return MaterialPageRoute(
        builder: (_) => const ProfessionalNotificationScreen(),
      );
    }
    return PharmacyPageRoute(
      builder: (_) => OrderDetailsScreen(order: {'_id': id}),
    );
  }

  /// The pharmacy order a payload points at, or null for anything else.
  String? _orderId(Map<String, dynamic> data) {
    final entity = '${data['relatedEntity'] ?? data['entityType'] ?? ''}';
    if (entity != 'pharmacy_order') return null;
    final id = '${data['relatedEntityId'] ?? data['orderId'] ?? ''}'.trim();
    return id.isEmpty ? null : id;
  }

  /// The lab order (LabTest) a payload points at, or null.
  String? _labTestId(Map<String, dynamic> data) {
    final entity = '${data['relatedEntity'] ?? data['entityType'] ?? ''}';
    if (entity.toLowerCase() != 'labtest') return null;
    final id = '${data['relatedEntityId'] ?? data['labTestId'] ?? ''}'.trim();
    return id.isEmpty ? null : id;
  }

  /// The doctor/physio appointment a payload points at, or null.
  String? _appointmentId(Map<String, dynamic> data) {
    final entity = '${data['relatedEntity'] ?? data['entityType'] ?? ''}';
    if (entity.toLowerCase() != 'appointment') return null;
    final id = '${data['relatedEntityId'] ?? data['appointmentId'] ?? ''}'
        .trim();
    return id.isEmpty ? null : id;
  }

  /// Opens a notification the user tapped in the in-app list.
  ///
  /// The stored record nests its deep-link fields differently from a push
  /// payload, so they are flattened here first. Non-order notifications have
  /// nowhere further to go, so the tap stays in the list.
  Future<void> openFromRecord(Map<String, dynamic> row) async {
    final data = <String, dynamic>{
      if (row['data'] is Map) ...Map<String, dynamic>.from(row['data'] as Map),
      'relatedEntity': row['relatedEntity'],
      'relatedEntityId': row['relatedEntityId'],
    };
    final opensAppointment =
        (_appointmentId(data) != null && appointmentScreen != null) ||
        (_labTestId(data) != null && labOrderScreen != null);
    if (_orderId(data) == null && !opensAppointment) return;
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    await navigator.push(_routeFor(data));
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
