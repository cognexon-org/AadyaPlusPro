import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../widgets/doctor_ui.dart';
import '../widgets/patient_summary.dart';

List<Map<String, dynamic>> _list(dynamic data, String key) {
  final raw = data is Map ? (data[key] ?? data['data']) : data;
  return (raw is List ? raw : const [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

// ---------------------------------------------------------------------------
// Patient list
// ---------------------------------------------------------------------------

/// Everyone the doctor has seen or will see, grouped from their appointments
/// (the server has no "my patients" endpoint). Loads the full history — not
/// the dashboard's ±60-day window — so older patients appear too.
class DoctorPatientsState {
  final List<PatientSummary> patients;
  final bool isLoading;

  /// A reload with patients already on screen; the list stays visible.
  final bool isRefreshing;
  final String? error;
  final DateTime? loadedAt;

  const DoctorPatientsState({
    this.patients = const [],
    this.isLoading = false,
    this.isRefreshing = false,
    this.error,
    this.loadedAt,
  });

  bool get hasLoaded => loadedAt != null;

  DoctorPatientsState copyWith({
    List<PatientSummary>? patients,
    bool? isLoading,
    bool? isRefreshing,
    String? error,
    bool clearError = false,
    DateTime? loadedAt,
  }) => DoctorPatientsState(
    patients: patients ?? this.patients,
    isLoading: isLoading ?? this.isLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    error: clearError ? null : (error ?? this.error),
    loadedAt: loadedAt ?? this.loadedAt,
  );
}

class DoctorPatientsNotifier extends StateNotifier<DoctorPatientsState> {
  DoctorPatientsNotifier() : super(const DoctorPatientsState());

  static const _pageSize = 500;
  static const _maxPages = 6;

  final _api = ApiService();
  int _seq = 0;

  /// Loads once; later calls do nothing while a load is running or done.
  Future<void> ensureLoaded() async {
    if (state.hasLoaded || state.isLoading) return;
    await load();
  }

  /// Pages `GET /appointment` (newest first, up to 6 × 500) and groups the
  /// rows by patient. [silent] (or any reload after the first) keeps the
  /// current list on screen.
  Future<void> load({bool silent = false}) async {
    final seq = ++_seq;
    state = state.hasLoaded || silent
        ? state.copyWith(isRefreshing: true, clearError: true)
        : state.copyWith(isLoading: true, clearError: true);
    try {
      final all = <Map<String, dynamic>>[];
      var page = 1;
      var pages = 1;
      do {
        final res = await _api.getAppointments(
          queryParams: {
            'limit': _pageSize,
            'page': page,
            'sort': 'appointmentDate:desc',
          },
        );
        if (seq != _seq || !mounted) return;
        final data = res.data;
        final raw = data is Map ? data['appointments'] : data;
        final list = (raw is List ? raw : const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        all.addAll(list);
        final pg = data is Map ? data['pagination'] : null;
        pages = pg is Map ? (int.tryParse('${pg['pages']}') ?? 1) : 1;
        if (list.length < _pageSize) break;
        page++;
      } while (page <= pages && page <= _maxPages);
      if (seq != _seq || !mounted) return;
      state = state.copyWith(
        patients: groupPatients(all),
        isLoading: false,
        isRefreshing: false,
        loadedAt: DateTime.now(),
      );
    } catch (e) {
      if (seq != _seq || !mounted) return;
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        error: doctorError(e, fallback: 'Couldn’t load your patients.'),
      );
    }
  }
}

final doctorPatientsProvider =
    StateNotifierProvider<DoctorPatientsNotifier, DoctorPatientsState>((ref) {
      // Fresh per signed-in account (see doctorAppointmentsProvider).
      ref.watch(authProvider.select((s) => s.user?.id));
      return DoctorPatientsNotifier();
    });

// ---------------------------------------------------------------------------
// One patient's history
// ---------------------------------------------------------------------------

/// One patient's visits and prescriptions with the signed-in doctor.
class PatientHistory {
  /// Newest first, each with `patientId` set to the populated [patient].
  final List<Map<String, dynamic>> appointments;
  final List<Map<String, dynamic>> prescriptions;

  /// The patient as the prescriptions populate them (may be just `_id`).
  final Map<String, dynamic> patient;

  const PatientHistory({
    this.appointments = const [],
    this.prescriptions = const [],
    this.patient = const {},
  });

  /// [seed] (what the caller already knew) wins; gaps are filled from the
  /// prescriptions' populated patient.
  Map<String, dynamic> mergedPatient(Map<String, dynamic> seed) {
    final out = {...seed};
    for (final e in patient.entries) {
      final v = e.value;
      if (v != null && '$v'.isNotEmpty && out[e.key] == null) out[e.key] = v;
    }
    return out;
  }

  /// This history with every appointment carrying [merged] as its patient.
  PatientHistory withPatient(Map<String, dynamic> merged) => PatientHistory(
    appointments: [
      for (final a in appointments) {...a, 'patientId': merged},
    ],
    prescriptions: prescriptions,
    patient: merged,
  );
}

/// `GET /appointment/patient/:id` and `GET /prescription/patient/:id`, in
/// parallel. Refresh with `ref.refresh(patientHistoryProvider(id).future)`.
final patientHistoryProvider = FutureProvider.autoDispose
    .family<PatientHistory, String>((ref, patientId) async {
      final api = ApiService();
      final results = await Future.wait([
        api.getAppointmentsByPatient(patientId),
        api.getPrescriptionsByPatient(patientId),
      ]);
      final rx = _list(results[1].data, 'prescriptions');
      // The prescriptions carry the patient populated; gather their fields.
      final patient = <String, dynamic>{'_id': patientId};
      for (final r in rx) {
        final p = r['patientId'];
        if (p is! Map) continue;
        for (final e in p.entries) {
          final v = e.value;
          if (v != null && '$v'.isNotEmpty && patient['${e.key}'] == null) {
            patient['${e.key}'] = v;
          }
        }
      }
      // The history endpoint returns the patient as a bare id; give each
      // appointment the populated patient so the cards can show the name.
      final appts =
          _list(
            results[0].data,
            'appointments',
          ).map((a) => {...a, 'patientId': patient}).toList()..sort((a, b) {
            final da = apptStart(a) ?? DateTime(2000);
            final db = apptStart(b) ?? DateTime(2000);
            return db.compareTo(da);
          });
      return PatientHistory(
        appointments: appts,
        prescriptions: rx,
        patient: patient,
      );
    });
