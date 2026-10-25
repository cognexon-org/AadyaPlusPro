import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../doctor/widgets/doctor_ui.dart' show doctorError;

// ═══════════════════════════════ Helpers ═══════════════════════════════

List<Map<String, dynamic>> exMaps(dynamic value) => value is List
    ? [
        for (final e in value)
          if (e is Map) Map<String, dynamic>.from(e),
      ]
    : <Map<String, dynamic>>[];

Map<String, dynamic> exMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<String> exStrings(dynamic value) => value is List
    ? [
        for (final e in value)
          if ('${e ?? ''}'.trim().isNotEmpty) '$e'.trim(),
      ]
    : <String>[];

String exId(Map<String, dynamic> m) => '${m['_id'] ?? m['id'] ?? ''}';

String exName(Map<String, dynamic> ex) {
  final n = '${ex['name'] ?? ''}'.trim();
  return n.isEmpty ? 'Exercise' : n;
}

DateTime? exDate(dynamic iso) => DateTime.tryParse('${iso ?? ''}')?.toLocal();

/// A number from the server, or null when missing / zero-meaning-unset.
int? exInt(dynamic v) {
  if (v == null || '$v'.isEmpty) return null;
  final n = num.tryParse('$v');
  return n?.round();
}

/// The exercise a plan item points at (populated by the server), or an
/// empty map when only the id came back.
Map<String, dynamic> planItemExercise(Map<String, dynamic> item) =>
    exMap(item['exerciseId']);

String planItemExerciseId(Map<String, dynamic> item) {
  final e = item['exerciseId'];
  return e is Map ? '${e['_id'] ?? ''}' : '${e ?? ''}';
}

String planStatus(Map<String, dynamic> plan) => '${plan['status'] ?? 'active'}';

String planStatusLabel(String s) => switch (s) {
  'active' => 'Active',
  'completed' => 'Completed',
  'cancelled' => 'Cancelled',
  _ => s.isEmpty ? 'Active' : '${s[0].toUpperCase()}${s.substring(1)}',
};

String exDifficultyLabel(String d) => switch (d) {
  'easy' => 'Easy',
  'moderate' => 'Moderate',
  'hard' => 'Hard',
  _ => d.isEmpty ? '' : '${d[0].toUpperCase()}${d.substring(1)}',
};

String exSideLabel(String s) => switch (s) {
  'left' => 'Left side',
  'right' => 'Right side',
  'both' => 'Both sides',
  _ => '',
};

String exSeconds(int s) {
  if (s < 60) return '${s}s';
  final m = s ~/ 60;
  final r = s % 60;
  return r == 0 ? '$m min' : '$m min ${r}s';
}

/// "3 × 10 · hold 5s · both sides · 2×/day · 5 days/wk" for a plan item.
String planItemDosing(Map<String, dynamic> item, {bool schedule = true}) {
  final sets = exInt(item['sets']) ?? 0;
  final reps = exInt(item['reps']) ?? 0;
  final dur = exInt(item['durationSec']) ?? 0;
  final hold = exInt(item['holdSec']) ?? 0;
  final rest = exInt(item['restSec']) ?? 0;
  final side = exSideLabel('${item['side'] ?? ''}');
  final load = '${item['load'] ?? ''}'.trim();
  final tpd = exInt(item['timesPerDay']);
  final dpw = exInt(item['daysPerWeek']);
  final freq = '${item['frequency'] ?? ''}'.trim();
  return [
    if (sets > 0 && reps > 0)
      '$sets × $reps'
    else if (sets > 0)
      '$sets set${sets == 1 ? '' : 's'}'
    else if (reps > 0)
      '$reps reps',
    if (dur > 0) exSeconds(dur),
    if (hold > 0) 'hold ${exSeconds(hold)}',
    if (rest > 0) 'rest ${exSeconds(rest)}',
    if (side.isNotEmpty) side.toLowerCase(),
    if (load.isNotEmpty) load,
    if (schedule && (tpd != null || dpw != null))
      '${tpd ?? 1}×/day · ${dpw ?? 7} days/wk'
    else if (schedule && freq.isNotEmpty)
      freq,
  ].join(' · ');
}

/// "3 × 10 · 30s · daily" from an exercise's library defaults.
String exDefaultsLine(Map<String, dynamic> ex) => [
  planItemDosing({
    'sets': ex['defaultSets'],
    'reps': ex['defaultReps'],
    'durationSec': ex['defaultDurationSec'],
  }, schedule: false),
  '${ex['defaultFrequency'] ?? ''}'.trim(),
].where((e) => e.isNotEmpty).join(' · ');

/// Sessions a plan expects per week: Σ timesPerDay × daysPerWeek.
double planWeeklyTarget(Map<String, dynamic> plan) {
  var total = 0.0;
  for (final item in exMaps(plan['exercises'])) {
    total +=
        (exInt(item['timesPerDay']) ?? 1) * (exInt(item['daysPerWeek']) ?? 7);
  }
  return total;
}

String _err(Object e, String fallback) =>
    e is PhysioLoadError ? e.message : doctorError(e, fallback: fallback);

/// A load failure whose text is ready to show.
class PhysioLoadError implements Exception {
  final String message;
  const PhysioLoadError(this.message);
  @override
  String toString() => message;
}

Map<String, dynamic> _pick(dynamic data, String key) {
  if (data is! Map) return const {};
  final v = data[key] ?? data['data'];
  return exMap(v is Map ? v : null);
}

// ═══════════════════════════════ Catalogue ═══════════════════════════════

/// The physio's own exercise library (`GET /physio-exercises/catalog`,
/// active only, by name). Filters run on the device; a text search is also
/// sent to the server so matches the device can't see still show up.
class PhysioExerciseCatalogState {
  final List<Map<String, dynamic>> items;
  final bool isLoading;
  final bool isRefreshing;
  final String? error;
  final DateTime? loadedAt;

  /// The text the server was last asked about, and the ids it matched.
  final String serverQuery;
  final Set<String> serverMatches;

  const PhysioExerciseCatalogState({
    this.items = const [],
    this.isLoading = false,
    this.isRefreshing = false,
    this.error,
    this.loadedAt,
    this.serverQuery = '',
    this.serverMatches = const {},
  });

  PhysioExerciseCatalogState copyWith({
    List<Map<String, dynamic>>? items,
    bool? isLoading,
    bool? isRefreshing,
    String? error,
    bool clearError = false,
    DateTime? loadedAt,
    String? serverQuery,
    Set<String>? serverMatches,
  }) => PhysioExerciseCatalogState(
    items: items ?? this.items,
    isLoading: isLoading ?? this.isLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    error: clearError ? null : (error ?? this.error),
    loadedAt: loadedAt ?? this.loadedAt,
    serverQuery: serverQuery ?? this.serverQuery,
    serverMatches: serverMatches ?? this.serverMatches,
  );

  bool get hasLoaded => loadedAt != null;

  Map<String, dynamic>? byId(String id) {
    for (final e in items) {
      if (exId(e) == id) return e;
    }
    return null;
  }

  List<String> _values(String key) {
    final seen = <String, String>{};
    for (final e in items) {
      final v = '${e[key] ?? ''}'.trim();
      if (v.isNotEmpty) seen.putIfAbsent(v.toLowerCase(), () => v);
    }
    return seen.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  List<String> get bodyParts => _values('bodyPart');
  List<String> get categories => _values('category');
  List<String> get difficulties {
    final present = _values('difficulty').map((d) => d.toLowerCase()).toSet();
    return [
      for (final d in const ['easy', 'moderate', 'hard'])
        if (present.contains(d)) d,
    ];
  }

  /// The exercises matching every given filter. Text matches name,
  /// description, body part, category and equipment, plus whatever the
  /// server matched for the same text.
  List<Map<String, dynamic>> filtered({
    String query = '',
    String? bodyPart,
    String? category,
    String? difficulty,
  }) {
    final q = query.trim().toLowerCase();
    bool same(dynamic a, String? b) =>
        b == null || '${a ?? ''}'.trim().toLowerCase() == b.toLowerCase();
    return items.where((e) {
      if (!same(e['bodyPart'], bodyPart)) return false;
      if (!same(e['category'], category)) return false;
      if (!same(e['difficulty'], difficulty)) return false;
      if (q.isEmpty) return true;
      final hay = [
        e['name'],
        e['description'],
        e['bodyPart'],
        e['category'],
        ...exStrings(e['equipment']),
      ].map((v) => '${v ?? ''}'.toLowerCase()).join(' ');
      if (hay.contains(q)) return true;
      return serverQuery == q && serverMatches.contains(exId(e));
    }).toList();
  }
}

class PhysioExerciseCatalogNotifier
    extends StateNotifier<PhysioExerciseCatalogState> {
  PhysioExerciseCatalogNotifier() : super(const PhysioExerciseCatalogState());

  final _api = ApiService();
  int _seq = 0;
  int _searchSeq = 0;

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
      final res = await _api.getPhysioExercises();
      if (seq != _seq || !mounted) return;
      final data = res.data;
      final raw = data is Map ? (data['exercises'] ?? data['data']) : data;
      state = state.copyWith(
        items: exMaps(raw),
        isLoading: false,
        isRefreshing: false,
        loadedAt: DateTime.now(),
      );
    } catch (e) {
      if (seq != _seq || !mounted) return;
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        error: _err(e, 'Couldn’t load the exercise library.'),
      );
    }
  }

  /// Asks the server about [query]; a newer search drops older answers.
  /// Exercises the server returns that aren't loaded yet are added.
  Future<void> search(String query) async {
    final q = query.trim().toLowerCase();
    final seq = ++_searchSeq;
    if (q.isEmpty) {
      state = state.copyWith(serverQuery: '', serverMatches: const {});
      return;
    }
    try {
      final res = await _api.getPhysioExercises(queryParams: {'search': q});
      if (seq != _searchSeq || !mounted) return;
      final data = res.data;
      final found = exMaps(
        data is Map ? (data['exercises'] ?? data['data']) : data,
      );
      final known = {for (final e in state.items) exId(e)};
      final extra = found.where((e) => !known.contains(exId(e))).toList();
      state = state.copyWith(
        items: extra.isEmpty ? null : _sorted([...state.items, ...extra]),
        serverQuery: q,
        serverMatches: {for (final e in found) exId(e)},
      );
    } catch (_) {
      // The device-side match still stands.
    }
  }

  static List<Map<String, dynamic>> _sorted(List<Map<String, dynamic>> l) => l
    ..sort(
      (a, b) => exName(a).toLowerCase().compareTo(exName(b).toLowerCase()),
    );

  Map<String, dynamic> _upsert(Map<String, dynamic> ex) {
    final id = exId(ex);
    if (id.isEmpty || !mounted) return ex;
    final list = [...state.items];
    final i = list.indexWhere((e) => exId(e) == id);
    if (i >= 0) {
      list[i] = {...list[i], ...ex};
    } else {
      list.add(ex);
    }
    state = state.copyWith(items: _sorted(list));
    return i >= 0 ? list.firstWhere((e) => exId(e) == id) : ex;
  }

  /// `POST /catalog`. Returns the saved exercise.
  Future<Map<String, dynamic>> create(Map<String, dynamic> data) async {
    final res = await _api.createPhysioExercise(data);
    final ex = _pick(res.data, 'exercise');
    if (exId(ex).isEmpty) throw Exception('Saved without an id');
    return _upsert(ex);
  }

  /// `PATCH /catalog/:id`.
  Future<Map<String, dynamic>> update(
    String id,
    Map<String, dynamic> data,
  ) async {
    final res = await _api.updatePhysioExercise(id, data);
    final ex = _pick(res.data, 'exercise');
    return _upsert(
      exId(ex).isEmpty ? {...?state.byId(id), ...data, '_id': id} : ex,
    );
  }

  /// `DELETE /catalog/:id` — archives it: gone from the library and from
  /// new plans; plans already using it keep it.
  Future<void> archive(String id) async {
    await _api.deletePhysioExercise(id);
    if (!mounted) return;
    state = state.copyWith(
      items: state.items.where((e) => exId(e) != id).toList(),
    );
  }
}

final physioExerciseCatalogProvider =
    StateNotifierProvider<
      PhysioExerciseCatalogNotifier,
      PhysioExerciseCatalogState
    >((ref) {
      // Fresh per signed-in account.
      ref.watch(authProvider.select((s) => s.user?.id));
      return PhysioExerciseCatalogNotifier();
    });

// ═════════════════════════════════ Plans ═════════════════════════════════

/// A patient's exercise plans with this physio, newest first.
final physioPatientPlansProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, patientId) async {
      ref.watch(authProvider.select((s) => s.user?.id));
      try {
        final res = await ApiService().getPhysioPatientExercisePlans(patientId);
        final data = res.data;
        return exMaps(data is Map ? (data['plans'] ?? data['data']) : data);
      } catch (e) {
        throw PhysioLoadError(_err(e, 'Couldn’t load exercise plans.'));
      }
    });

/// One plan with its progress logs (newest first) and their summary.
class PhysioPlanDetail {
  final Map<String, dynamic> plan;
  final List<Map<String, dynamic>> progress;
  final Map<String, dynamic> summary;

  const PhysioPlanDetail({
    required this.plan,
    this.progress = const [],
    this.summary = const {},
  });

  String get status => planStatus(plan);
  bool get isActive => status == 'active';
  List<Map<String, dynamic>> get items {
    final list = exMaps(plan['exercises']);
    list.sort(
      (a, b) =>
          (exInt(a['sortOrder']) ?? 0).compareTo(exInt(b['sortOrder']) ?? 0),
    );
    return list;
  }

  Map<String, dynamic> get patient => exMap(plan['patientId']);
  String get patientId {
    final p = plan['patientId'];
    return p is Map ? '${p['_id'] ?? ''}' : '${p ?? ''}';
  }
}

final physioPlanDetailProvider = FutureProvider.autoDispose
    .family<PhysioPlanDetail, String>((ref, planId) async {
      ref.watch(authProvider.select((s) => s.user?.id));
      try {
        final res = await ApiService().getPhysioExercisePlan(planId);
        final data = res.data;
        final plan = _pick(data, 'plan');
        if (plan.isEmpty) {
          throw const PhysioLoadError('This exercise plan wasn’t found.');
        }
        return PhysioPlanDetail(
          plan: plan,
          progress: data is Map ? exMaps(data['progress']) : const [],
          summary: data is Map ? exMap(data['summary']) : const {},
        );
      } catch (e) {
        throw PhysioLoadError(_err(e, 'Couldn’t load the exercise plan.'));
      }
    });

/// Which slice of a plan's adherence to compute: the whole plan so far, or
/// only the last [lastDays] days.
typedef PhysioAdherenceQuery = ({String planId, int? lastDays});

/// `{from, to, days, weeks, overall: {...}, items: [...]}` from
/// `GET /plans/:id/adherence`.
final physioPlanAdherenceProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, PhysioAdherenceQuery>((ref, q) async {
      ref.watch(authProvider.select((s) => s.user?.id));
      final params = <String, dynamic>{};
      if (q.lastDays != null) {
        final now = DateTime.now();
        params['from'] = DateTime(
          now.year,
          now.month,
          now.day - (q.lastDays! - 1),
        ).toUtc().toIso8601String();
        params['to'] = now.toUtc().toIso8601String();
      }
      try {
        final res = await ApiService().getPhysioExercisePlanAdherence(
          q.planId,
          queryParams: params.isEmpty ? null : params,
        );
        final data = res.data;
        return data is Map ? exMap(data['adherence']) : <String, dynamic>{};
      } catch (e) {
        throw PhysioLoadError(_err(e, 'Couldn’t work out adherence.'));
      }
    });

/// Plan writes. Each one refreshes the providers whose data it changes.
class PhysioExercisePlanActions {
  final Ref _ref;
  PhysioExercisePlanActions(this._ref);

  final _api = ApiService();

  void _refresh({String? planId}) {
    _ref.invalidate(physioPatientPlansProvider);
    if (planId != null) {
      _ref.invalidate(physioPlanDetailProvider(planId));
    }
    _ref.invalidate(physioPlanAdherenceProvider);
  }

  /// `POST /patients/:patientId/plans`. Returns the new plan.
  Future<Map<String, dynamic>> create(
    String patientId,
    Map<String, dynamic> data,
  ) async {
    final res = await _api.createPhysioPatientExercisePlan(patientId, data);
    final plan = _pick(res.data, 'plan');
    _refresh();
    return plan;
  }

  /// `PATCH /plans/:id`.
  Future<Map<String, dynamic>> update(
    String planId,
    Map<String, dynamic> data,
  ) async {
    final res = await _api.updatePhysioExercisePlan(planId, data);
    _refresh(planId: planId);
    return _pick(res.data, 'plan');
  }

  Future<void> complete(String planId) =>
      update(planId, {'status': 'completed'});

  /// `DELETE /plans/:id` — marks it cancelled.
  Future<void> cancel(String planId) async {
    await _api.cancelPhysioExercisePlan(planId);
    _refresh(planId: planId);
  }

  /// Logs one in-clinic entry (`planItemId`, `setsCompleted`,
  /// `repsCompleted`, `durationSec`, `painBefore`, `painAfter`,
  /// `perceivedDifficulty`, `completed`, `notes`, `performedAt`).
  /// Call [refreshAfterLogging] once a batch is done.
  Future<void> log(String planId, Map<String, dynamic> entry) async {
    await _api.logPhysioExercisePlanProgress(planId, entry);
  }

  void refreshAfterLogging(String planId) => _refresh(planId: planId);
}

final physioExercisePlanActionsProvider = Provider<PhysioExercisePlanActions>(
  (ref) => PhysioExercisePlanActions(ref),
);
