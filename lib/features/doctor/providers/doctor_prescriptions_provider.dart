import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../widgets/doctor_ui.dart';
import '../widgets/prescription_ui.dart';

/// The prescriptions this doctor has written (`GET /prescription`, newest
/// first), kept in step with every save, issue and cancel made from the
/// list, the details screen and the editor.
class DoctorPrescriptionsState {
  final List<Map<String, dynamic>> items;
  final bool isLoading;
  final bool isRefreshing;
  final String? error;
  final DateTime? loadedAt;

  const DoctorPrescriptionsState({
    this.items = const [],
    this.isLoading = false,
    this.isRefreshing = false,
    this.error,
    this.loadedAt,
  });

  DoctorPrescriptionsState copyWith({
    List<Map<String, dynamic>>? items,
    bool? isLoading,
    bool? isRefreshing,
    String? error,
    bool clearError = false,
    DateTime? loadedAt,
  }) => DoctorPrescriptionsState(
    items: items ?? this.items,
    isLoading: isLoading ?? this.isLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    error: clearError ? null : (error ?? this.error),
    loadedAt: loadedAt ?? this.loadedAt,
  );

  bool get hasLoaded => loadedAt != null;

  /// The prescription with [id], if it is in the list.
  Map<String, dynamic>? byId(String id) {
    if (id.isEmpty) return null;
    for (final rx in items) {
      if (rxId(rx) == id) return rx;
    }
    return null;
  }
}

/// The appointment id a prescription belongs to, populated or not.
String _apptIdOf(Map<String, dynamic> rx) {
  final a = rx['appointmentId'];
  return a is Map ? '${a['_id'] ?? ''}' : '${a ?? ''}';
}

class DoctorPrescriptionsNotifier
    extends StateNotifier<DoctorPrescriptionsState> {
  DoctorPrescriptionsNotifier() : super(const DoctorPrescriptionsState());

  final _api = ApiService();
  int _seq = 0;

  Future<void> ensureLoaded() async {
    if (state.hasLoaded || state.isLoading) return;
    await load();
  }

  Future<void> load({bool silent = false}) async {
    final seq = ++_seq;
    state = state.hasLoaded || silent
        ? state.copyWith(isRefreshing: true, clearError: true)
        : state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _api.getPrescriptions(queryParams: {'limit': 100});
      if (seq != _seq || !mounted) return;
      final data = res.data;
      final raw = data is Map
          ? (data['prescriptions'] ?? data['data'] ?? const [])
          : data;
      state = state.copyWith(
        items: rxMaps(raw),
        isLoading: false,
        isRefreshing: false,
        loadedAt: DateTime.now(),
      );
    } catch (e) {
      if (seq != _seq || !mounted) return;
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        error: doctorError(e, fallback: 'Couldn’t load prescriptions.'),
      );
    }
  }

  /// Puts [rx] into the list (merged over the copy already there, so a
  /// response with bare ids doesn't lose the populated patient/appointment)
  /// and returns the stored copy. New ones go first.
  Map<String, dynamic> upsert(Map<String, dynamic> rx) {
    final id = rxId(rx);
    if (id.isEmpty || !mounted) return rx;
    final list = [...state.items];
    final i = list.indexWhere((r) => rxId(r) == id);
    final merged = i < 0 ? rx : _merge(list[i], rx);
    if (i >= 0) {
      list[i] = merged;
    } else {
      list.insert(0, merged);
    }
    state = state.copyWith(items: list);
    return merged;
  }

  static Map<String, dynamic> _merge(
    Map<String, dynamic> old,
    Map<String, dynamic> fresh,
  ) {
    final out = {...old, ...fresh};
    for (final k in const ['patientId', 'appointmentId', 'doctorId']) {
      if (fresh[k] is! Map && old[k] is Map) out[k] = old[k];
    }
    return out;
  }

  /// The full record from `GET /prescription/:id`.
  Future<Map<String, dynamic>> fetch(String id) async {
    final res = await _api.getPrescriptionById(id);
    final rx = rxFromResponse(res.data);
    if (rx == null) throw Exception('Prescription not found');
    return upsert(rx);
  }

  /// The appointment's current prescription, or null when it has none
  /// (404). Other errors are rethrown.
  Future<Map<String, dynamic>?> forAppointment(String appointmentId) async {
    try {
      final res = await _api.getPrescriptionByAppointment(appointmentId);
      final rx = rxFromResponse(res.data);
      return rx == null ? null : upsert(rx);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// `POST /prescription`; throws if the server answers without an id.
  Future<Map<String, dynamic>> create(Map<String, dynamic> payload) async {
    final res = await _api.createPrescription(payload);
    final rx = rxFromResponse(res.data);
    if (rx == null || rxId(rx).isEmpty) {
      throw Exception('Saved without an id');
    }
    return upsert(rx);
  }

  /// `PUT /prescription/:id`. Updating an issued prescription returns a new
  /// revision draft. When the response carries no prescription, [base] with
  /// the payload applied stands in.
  Future<Map<String, dynamic>> update(
    String id,
    Map<String, dynamic> payload, {
    Map<String, dynamic>? base,
  }) async {
    final res = await _api.updatePrescription(id, payload);
    final rx =
        rxFromResponse(res.data) ??
        {
          ...(base ?? state.byId(id) ?? {'_id': id}),
          ...payload,
        };
    return upsert(rx);
  }

  /// Creates the draft for [appointmentId], or updates [current] — the one
  /// the editor already has. An issued prescription is revised: the server
  /// returns a new draft that replaces it once issued. If the visit already
  /// has one (409), that one is continued instead.
  Future<Map<String, dynamic>> saveDraft(
    Map<String, dynamic> payload, {
    required String? appointmentId,
    Map<String, dynamic>? current,
  }) async {
    if (current != null && !{'draft', 'issued'}.contains(rxStatus(current))) {
      current = null;
    }
    if (current == null) {
      try {
        return await create({
          ...payload,
          'appointmentId': appointmentId,
          'saveAsDraft': true,
        });
      } on DioException catch (e) {
        // Someone (or an earlier attempt) already started one for this
        // visit: continue that one instead.
        final data = e.response?.data;
        if (e.response?.statusCode != 409 ||
            data is! Map ||
            data['prescriptionId'] == null) {
          rethrow;
        }
        current = {
          '_id': '${data['prescriptionId']}',
          'status': '${data['status'] ?? 'draft'}',
        };
      }
    }
    return update(rxId(current), payload, base: current);
  }

  /// `POST /prescription/:id/issue`. Issuing a revision supersedes the one
  /// issued before it for the same visit.
  Future<Map<String, dynamic>> issue(String id) async {
    final res = await _api.issuePrescription(id);
    final rx =
        rxFromResponse(res.data) ??
        {
          ...(state.byId(id) ?? {'_id': id}),
          'status': 'issued',
        };
    final stored = upsert(rx);
    final appt = _apptIdOf(stored);
    if (appt.isNotEmpty && mounted) {
      state = state.copyWith(
        items: [
          for (final r in state.items)
            rxId(r) != id && _apptIdOf(r) == appt && rxStatus(r) == 'issued'
                ? {...r, 'status': 'superseded'}
                : r,
        ],
      );
    }
    return stored;
  }

  /// `POST /prescription/:id/cancel`.
  Future<Map<String, dynamic>> cancel(String id, String reason) async {
    final res = await _api.cancelPrescription(id, reason: reason);
    final rx =
        rxFromResponse(res.data) ??
        {
          ...(state.byId(id) ?? {'_id': id}),
          'status': 'cancelled',
          'cancellationReason': reason,
        };
    return upsert(rx);
  }

  /// The printable PDF.
  Future<List<int>> pdfBytes(String id) async {
    final res = await _api.downloadPrescriptionPdf(id);
    final bytes = res.data;
    if (bytes == null || bytes.isEmpty) throw Exception('Empty file');
    return bytes;
  }

  // ───────────── Appointment lookups for the editor ─────────────

  /// One appointment (patient populated), or null if the response has none.
  Future<Map<String, dynamic>?> appointment(String id) async {
    final res = await _api.getAppointmentById(id);
    final data = res.data;
    final appt = data is Map
        ? rxMap(data['appointment'] ?? data['data'] ?? data)
        : <String, dynamic>{};
    return appt.isEmpty ? null : appt;
  }

  /// Recent appointments a prescription can be written against, newest
  /// first. The server has no text search, so [query] (patient name or
  /// phone) filters on the device.
  Future<List<Map<String, dynamic>>> searchAppointments([
    String query = '',
  ]) async {
    final res = await _api.getAppointments(
      queryParams: {
        'status': 'confirmed,accepted,in_progress,completed',
        'limit': 100,
        'sort': 'appointmentDate:desc',
      },
    );
    final data = res.data;
    final raw = data is Map
        ? (data['appointments'] ?? data['data'] ?? const [])
        : data;
    final list = rxMaps(
      raw,
    ).where((a) => apptPatient(a)['_id'] != null).toList();
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((a) {
      final p = apptPatient(a);
      return '${p['name'] ?? ''}'.toLowerCase().contains(q) ||
          '${p['phone'] ?? ''}'.contains(q);
    }).toList();
  }
}

final doctorPrescriptionsProvider =
    StateNotifierProvider<
      DoctorPrescriptionsNotifier,
      DoctorPrescriptionsState
    >((ref) {
      // Fresh per signed-in account (see doctorAppointmentsProvider).
      ref.watch(authProvider.select((s) => s.user?.id));
      return DoctorPrescriptionsNotifier();
    });
