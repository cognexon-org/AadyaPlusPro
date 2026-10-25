import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../doctor/widgets/doctor_ui.dart';

// ---------------------------------------------------------------------------
// Parsing helpers
// ---------------------------------------------------------------------------

List<Map<String, dynamic>> _list(dynamic data, String key) {
  final raw = data is Map ? (data[key] ?? data['data']) : data;
  return (raw is List ? raw : const [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

Map<String, dynamic>? _map(dynamic data, String key) {
  final raw = data is Map ? data[key] : null;
  return raw is Map ? Map<String, dynamic>.from(raw) : null;
}

/// The id of a ref that may be populated (`{_id, name}`) or bare.
String refId(dynamic v) => v is Map ? '${v['_id'] ?? ''}' : '${v ?? ''}';

int _int(dynamic v) => num.tryParse('${v ?? ''}')?.round() ?? 0;

DateTime? parseDate(dynamic v) => DateTime.tryParse('${v ?? ''}')?.toLocal();

// ---------------------------------------------------------------------------
// Treatment course fields
// ---------------------------------------------------------------------------

int courseTotal(Map<String, dynamic> c) => _int(c['totalSessions']);
int courseUsed(Map<String, dynamic> c) => _int(c['sessionsUsed']);

/// `sessionsLeft` is a server virtual; computed here when it's missing.
int courseLeft(Map<String, dynamic> c) {
  final v = num.tryParse('${c['sessionsLeft'] ?? ''}');
  return v != null
      ? v.round()
      : math.max(0, courseTotal(c) - courseUsed(c)).toInt();
}

String courseStatus(Map<String, dynamic> c) => '${c['status'] ?? 'active'}';
String coursePayment(Map<String, dynamic> c) =>
    '${c['paymentStatus'] ?? 'pending'}';
String coursePatientId(Map<String, dynamic> c) => refId(c['patientId']);

String courseTitle(Map<String, dynamic> c) {
  final t = '${c['title'] ?? ''}'.trim();
  return t.isEmpty ? 'Treatment course' : t;
}

DateTime? courseExpires(Map<String, dynamic> c) => parseDate(c['expiresAt']);

/// Whether [appointment] is already linked to [course] (either side).
bool courseHasAppointment(
  Map<String, dynamic> course,
  Map<String, dynamic> appointment,
) {
  final id = '${appointment['_id'] ?? ''}';
  if (id.isEmpty) return false;
  if (refId(appointment['treatmentCourseId']) == '${course['_id']}') {
    return true;
  }
  final ids = course['appointmentIds'];
  return ids is List && ids.any((e) => refId(e) == id);
}

String courseStatusLabel(String s) => switch (s) {
  'active' => 'Active',
  'completed' => 'Completed',
  'cancelled' => 'Cancelled',
  'expired' => 'Expired',
  _ => capitalised(s),
};

String paymentMethodLabel(String m) => switch (m) {
  'upi' => 'UPI',
  'cash' => 'Cash',
  'online' => 'Online',
  _ => capitalised(m),
};

// ---------------------------------------------------------------------------
// Outcome measures
// ---------------------------------------------------------------------------

class OutcomeMeasureInfo {
  final String code;
  final String label;
  final num? maxScore;

  /// Null when the direction is unknown (OTHER).
  final bool? lowerIsBetter;
  const OutcomeMeasureInfo(
    this.code,
    this.label,
    this.maxScore,
    this.lowerIsBetter,
  );
}

const kOutcomeMeasures = <String, OutcomeMeasureInfo>{
  'ODI': OutcomeMeasureInfo('ODI', 'Oswestry disability', 100, true),
  'NDI': OutcomeMeasureInfo('NDI', 'Neck disability', 50, true),
  'LEFS': OutcomeMeasureInfo('LEFS', 'Lower extremity function', 80, false),
  'DASH': OutcomeMeasureInfo('DASH', 'Arm, shoulder and hand', 100, true),
  'KOOS': OutcomeMeasureInfo('KOOS', 'Knee injury and OA', 100, false),
  'WOMAC': OutcomeMeasureInfo('WOMAC', 'Hip and knee OA', 96, true),
  'PSFS': OutcomeMeasureInfo('PSFS', 'Patient-specific function', 10, false),
  'OTHER': OutcomeMeasureInfo('OTHER', 'Other measure', null, null),
};

/// +1 improved, -1 worse, 0 unchanged or unknown direction.
int outcomeDirection(String code, num? first, num? latest) {
  final lower = kOutcomeMeasures[code]?.lowerIsBetter;
  if (lower == null || first == null || latest == null || first == latest) {
    return 0;
  }
  final down = latest < first;
  return down == lower ? 1 : -1;
}

String sideLabel(String s) => switch (s) {
  'left' => 'Left',
  'right' => 'Right',
  'bilateral' => 'Both',
  _ => '',
};

String assessmentTypeLabel(String t) => switch (t) {
  'initial' => 'Initial',
  'discharge' => 'Discharge',
  _ => 'Progress',
};

// ---------------------------------------------------------------------------
// Courses
// ---------------------------------------------------------------------------

class PhysioCoursesState {
  /// Newest first, as the server sorts them.
  final List<Map<String, dynamic>> courses;
  final bool isLoading;
  final bool isRefreshing;
  final String? error;
  final DateTime? loadedAt;

  const PhysioCoursesState({
    this.courses = const [],
    this.isLoading = false,
    this.isRefreshing = false,
    this.error,
    this.loadedAt,
  });

  bool get hasLoaded => loadedAt != null;

  List<Map<String, dynamic>> forPatient(String patientId) =>
      courses.where((c) => coursePatientId(c) == patientId).toList();

  /// The patient's newest active course, if any.
  Map<String, dynamic>? activeFor(String patientId) {
    for (final c in courses) {
      if (coursePatientId(c) == patientId && courseStatus(c) == 'active') {
        return c;
      }
    }
    return null;
  }

  PhysioCoursesState copyWith({
    List<Map<String, dynamic>>? courses,
    bool? isLoading,
    bool? isRefreshing,
    String? error,
    bool clearError = false,
    DateTime? loadedAt,
  }) => PhysioCoursesState(
    courses: courses ?? this.courses,
    isLoading: isLoading ?? this.isLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    error: clearError ? null : (error ?? this.error),
    loadedAt: loadedAt ?? this.loadedAt,
  );
}

/// Every treatment course of the signed-in physio (`GET /physio-care/me/
/// courses`), with create / update / link. Mutations update the list in
/// place, then reload quietly so derived fields (expiry, counts) stay true.
class PhysioCoursesNotifier extends StateNotifier<PhysioCoursesState> {
  PhysioCoursesNotifier() : super(const PhysioCoursesState());

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
      final res = await _api.getPhysioCourses();
      if (seq != _seq || !mounted) return;
      state = state.copyWith(
        courses: _list(res.data, 'courses'),
        isLoading: false,
        isRefreshing: false,
        loadedAt: DateTime.now(),
      );
    } catch (e) {
      if (seq != _seq || !mounted) return;
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        error: doctorError(e, fallback: 'Couldn’t load treatment courses.'),
      );
    }
  }

  /// Puts [course] into the list, keeping a populated patient the server's
  /// mutation responses leave as a bare id.
  void _upsert(Map<String, dynamic> course, {Map<String, dynamic>? patient}) {
    final id = '${course['_id'] ?? ''}';
    if (id.isEmpty) return;
    final list = [...state.courses];
    final i = list.indexWhere((c) => '${c['_id']}' == id);
    final known = i >= 0 ? list[i]['patientId'] : null;
    final merged = {
      ...course,
      if (course['patientId'] is! Map && known is Map) 'patientId': known,
      if (course['patientId'] is! Map && patient != null)
        'patientId': {...patient, '_id': refId(course['patientId'])},
    };
    if (i >= 0) {
      list[i] = merged;
    } else {
      list.insert(0, merged);
    }
    state = state.copyWith(courses: list);
    // Reconcile with the server; drops any older in-flight load.
    unawaited(load(silent: true));
  }

  /// Starts a course: `{packageId}` or `{totalSessions, price, ...}`.
  /// Throws on failure (the caller shows the error).
  Future<Map<String, dynamic>> create(
    String patientId,
    Map<String, dynamic> body, {
    Map<String, dynamic>? patient,
  }) async {
    final res = await _api.createPhysioCourse(patientId, body);
    final course = _map(res.data, 'course') ?? const {};
    if (mounted) _upsert(course, patient: patient);
    return course;
  }

  Future<Map<String, dynamic>> update(
    String id,
    Map<String, dynamic> body,
  ) async {
    final res = await _api.updatePhysioCourse(id, body);
    final course = _map(res.data, 'course') ?? const {};
    if (mounted) _upsert(course);
    return course;
  }

  /// Counts [appointmentId] into the course (idempotent on the server).
  Future<({Map<String, dynamic> course, bool alreadyLinked})> link(
    String courseId,
    String appointmentId,
  ) async {
    final res = await _api.linkPhysioCourseAppointment(courseId, appointmentId);
    final course = _map(res.data, 'course') ?? const {};
    final data = res.data;
    if (mounted) _upsert(course);
    return (
      course: course,
      alreadyLinked: data is Map && data['alreadyLinked'] == true,
    );
  }
}

final physioCoursesProvider =
    StateNotifierProvider<PhysioCoursesNotifier, PhysioCoursesState>((ref) {
      ref.watch(authProvider.select((s) => s.user?.id));
      return PhysioCoursesNotifier();
    });

/// The physio's active packages, for the "Start a course" sheet.
final physioCoursePackagesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final res = await ApiService().getPhysioPackages();
      return _list(res.data, 'packages');
    });

// ---------------------------------------------------------------------------
// One patient: sessions, assessments, progress, exercise plans
// ---------------------------------------------------------------------------

/// The patient's sessions with the signed-in physio (server-scoped), newest
/// first. The endpoint returns a bare array with the patient as an id.
final physioPatientSessionsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, patientId) async {
      final res = await ApiService().getAppointmentsByPatient(patientId);
      final list = _list(res.data, 'appointments')
        ..sort((a, b) {
          final da = apptStart(a) ?? DateTime(2000);
          final db = apptStart(b) ?? DateTime(2000);
          return db.compareTo(da);
        });
      return list;
    });

/// Newest first.
final physioAssessmentsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, patientId) async {
      final res = await ApiService().getPhysioAssessments(patientId);
      return _list(res.data, 'assessments')..sort(
        (a, b) => (parseDate(b['assessedAt']) ?? DateTime(2000)).compareTo(
          parseDate(a['assessedAt']) ?? DateTime(2000),
        ),
      );
    });

final physioAssessmentProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) async {
      final res = await ApiService().getPhysioAssessment(id);
      return _map(res.data, 'assessment') ?? const {};
    });

/// `{assessmentCount, pain, outcomeMeasures, rom, latest, firstToLatestChange}`.
final physioProgressProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, patientId) async {
      final res = await ApiService().getPhysioPatientProgress(patientId);
      return _map(res.data, 'progress') ?? const {};
    });

/// An exercise plan with its adherence (null when it couldn't be computed,
/// e.g. a plan starting in the future).
class PhysioPlanSummary {
  final Map<String, dynamic> plan;
  final Map<String, dynamic>? adherence;
  const PhysioPlanSummary(this.plan, this.adherence);

  String get id => '${plan['_id'] ?? ''}';
  String get title {
    final t = '${plan['title'] ?? ''}'.trim();
    return t.isEmpty ? 'Exercise plan' : t;
  }

  String get status => '${plan['status'] ?? 'active'}';
  int get exerciseCount =>
      plan['exercises'] is List ? (plan['exercises'] as List).length : 0;

  Map<String, dynamic> get _overall =>
      adherence?['overall'] is Map ? Map.from(adherence!['overall']) : {};
  int? get compliance =>
      num.tryParse('${_overall['compliancePercent'] ?? ''}')?.round();
  DateTime? get lastLogged => parseDate(_overall['lastLoggedAt']);
}

/// The patient's plans with adherence for the ones not cancelled. Uses the
/// API directly so this hub doesn't depend on the exercises module's state.
final physioCarePlansProvider = FutureProvider.autoDispose
    .family<List<PhysioPlanSummary>, String>((ref, patientId) async {
      final api = ApiService();
      final res = await api.getPhysioPatientExercisePlans(patientId);
      final plans = _list(res.data, 'plans');
      return Future.wait([
        for (final p in plans)
          '${p['status']}' == 'cancelled'
              ? Future.value(PhysioPlanSummary(p, null))
              : api
                    .getPhysioExercisePlanAdherence('${p['_id']}')
                    .then(
                      (r) => PhysioPlanSummary(p, _map(r.data, 'adherence')),
                    )
                    .catchError((Object _) => PhysioPlanSummary(p, null)),
      ]);
    });
