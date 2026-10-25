import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../widgets/lab_ui.dart';

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _list(dynamic v) => (v is List ? v : const [])
    .whereType<Map>()
    .map((e) => Map<String, dynamic>.from(e))
    .toList();

// ─────────────────────────── Orders ───────────────────────────

class LabOrdersState {
  final List<Map<String, dynamic>> all;
  final bool isLoading;
  final bool isRefreshing;
  final String? error;
  final DateTime? loadedAt;

  /// Bumped when a poll sees a booking that wasn't there before.
  final int arrivalTick;
  final List<Map<String, dynamic>> lastArrivals;

  const LabOrdersState({
    this.all = const [],
    this.isLoading = false,
    this.isRefreshing = false,
    this.error,
    this.loadedAt,
    this.arrivalTick = 0,
    this.lastArrivals = const [],
  });

  bool get hasLoaded => loadedAt != null;

  LabOrdersState copyWith({
    List<Map<String, dynamic>>? all,
    bool? isLoading,
    bool? isRefreshing,
    String? error,
    bool clearError = false,
    DateTime? loadedAt,
    int? arrivalTick,
    List<Map<String, dynamic>>? lastArrivals,
  }) => LabOrdersState(
    all: all ?? this.all,
    isLoading: isLoading ?? this.isLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    error: clearError ? null : (error ?? this.error),
    loadedAt: loadedAt ?? this.loadedAt,
    arrivalTick: arrivalTick ?? this.arrivalTick,
    lastArrivals: lastArrivals ?? this.lastArrivals,
  );

  List<Map<String, dynamic>> inStage(LabStage s) =>
      all.where((o) => labStage(o) == s).toList();

  /// Orders whose collection slot is today, in time order.
  List<Map<String, dynamic>> get today {
    final now = DateTime.now();
    final list = all.where((o) {
      final d = labSlot(o);
      return d != null &&
          d.year == now.year &&
          d.month == now.month &&
          d.day == now.day &&
          labStage(o) != LabStage.cancelled;
    }).toList();
    list.sort((a, b) => (labSlot(a) ?? now).compareTo(labSlot(b) ?? now));
    return list;
  }

  List<Map<String, dynamic>> get overdue => all.where(labOverdue).toList();

  /// Home collections still waiting for a phlebotomist.
  List<Map<String, dynamic>> get unassigned => all
      .where(
        (o) =>
            labIsHome(o) &&
            labStage(o) == LabStage.collect &&
            labCollection(o) == 'unassigned',
      )
      .toList();
}

/// Every order of the signed-in lab (most recent 200), refreshed every 30
/// seconds while the app is in front. Screens filter it locally, so switching
/// a chip on Orders is instant instead of a round trip.
class LabOrdersNotifier extends StateNotifier<LabOrdersState> {
  LabOrdersNotifier() : super(const LabOrdersState());

  final _api = ApiService();
  int _seq = 0;
  Timer? _poll;
  AppLifecycleListener? _lifecycle;
  bool _foreground = true;
  Set<String>? _known;

  void startLiveUpdates() {
    if (_poll != null) return;
    load();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_foreground) load(silent: true);
    });
    _lifecycle = AppLifecycleListener(
      onResume: () {
        _foreground = true;
        load(silent: true);
      },
      onPause: () => _foreground = false,
    );
  }

  Future<void> ensureLoaded() async {
    if (!state.hasLoaded && !state.isLoading) await load();
  }

  Future<void> load({bool silent = false}) async {
    final seq = ++_seq;
    state = state.hasLoaded || silent
        ? state.copyWith(isRefreshing: true, clearError: true)
        : state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _api.getDiagnosticsMerchantOrders(
        queryParams: {'limit': 100, 'page': 1},
      );
      final second =
          _map(res.data)['pagination'] is Map &&
              (int.tryParse('${_map(res.data)['pagination']['pages']}') ?? 1) >
                  1
          ? await _api.getDiagnosticsMerchantOrders(
              queryParams: {'limit': 100, 'page': 2},
            )
          : null;
      if (seq != _seq || !mounted) return;
      final list = [
        ..._list(_map(res.data)['orders']),
        if (second != null) ..._list(_map(second.data)['orders']),
      ];
      _noticeArrivals(list);
      state = state.copyWith(
        all: list,
        isLoading: false,
        isRefreshing: false,
        loadedAt: DateTime.now(),
      );
    } catch (e) {
      if (seq != _seq || !mounted) return;
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        error: labError(e, fallback: 'Couldn’t load orders.'),
      );
    }
  }

  void _noticeArrivals(List<Map<String, dynamic>> list) {
    final ids = list.map((o) => '${o['_id']}').toSet();
    final known = _known;
    _known = ids;
    if (known == null) return;
    final fresh = list
        .where(
          (o) =>
              !known.contains('${o['_id']}') && labStage(o) == LabStage.collect,
        )
        .toList();
    if (fresh.isEmpty) return;
    state = state.copyWith(
      arrivalTick: state.arrivalTick + 1,
      lastArrivals: fresh,
    );
  }

  void upsert(Map<String, dynamic> order) {
    final id = '${order['_id']}';
    final list = [...state.all];
    final i = list.indexWhere((o) => '${o['_id']}' == id);
    // Keep list-only fields (populated patient, decoration) if the action
    // response came back thinner.
    final merged = i >= 0 ? {...list[i], ...order} : order;
    if (order['patientId'] is! Map && i >= 0) {
      merged['patientId'] = list[i]['patientId'];
    }
    if (i >= 0) {
      list[i] = merged;
    } else {
      list.insert(0, merged);
    }
    _known?.add(id);
    state = state.copyWith(all: list);
  }

  /// Fetches one order with its catalogue parameters ({order, catalog}).
  Future<({Map<String, dynamic> order, Map<String, dynamic> catalog})> fetch(
    String id,
  ) async {
    final res = await _api.getDiagnosticsMerchantOrder(id);
    final body = _map(res.data);
    final order = _map(body['order']);
    if (order.isNotEmpty) upsert(order);
    return (order: order, catalog: _map(body['catalog']));
  }

  Future<Map<String, dynamic>> _act(Future<dynamic> Function() call) async {
    final res = await call();
    final order = _map(_map((res as dynamic).data)['order']);
    if (order.isNotEmpty) upsert(order);
    return order;
  }

  Future<Map<String, dynamic>> collectSample(
    String id, {
    String? barcode,
    String? sampleType,
    String? collectedBy,
  }) => _act(
    () => _api.updateDiagnosticsOrderStatus(
      id,
      'sample_collected',
      extra: {
        if ((barcode ?? '').trim().isNotEmpty) 'barcode': barcode!.trim(),
        if ((sampleType ?? '').trim().isNotEmpty) 'sampleType': sampleType,
        if ((collectedBy ?? '').trim().isNotEmpty) 'collectedBy': collectedBy,
      },
    ),
  );

  Future<Map<String, dynamic>> setStatus(
    String id,
    String status, {
    String? reason,
  }) =>
      _act(() => _api.updateDiagnosticsOrderStatus(id, status, reason: reason));

  Future<Map<String, dynamic>> cancel(String id, String reason) =>
      setStatus(id, 'cancelled', reason: reason);

  Future<Map<String, dynamic>> assign(String id, String staffId) =>
      _act(() => _api.assignDiagnosticsCollector(id, staffId));

  /// Moves a home collection along. For 'collected', pass the tube
  /// [barcode] and who collected it; 'failed' takes a [note] as the reason.
  Future<Map<String, dynamic>> collection(
    String id,
    String status, {
    String? note,
    String? barcode,
    String? collectedBy,
  }) => _act(
    () => _api.updateDiagnosticsCollectionStatus(
      id,
      status,
      note: note,
      extra: {
        if ((barcode ?? '').trim().isNotEmpty) 'barcode': barcode!.trim(),
        if ((collectedBy ?? '').trim().isNotEmpty) 'collectedBy': collectedBy,
        if (status == 'failed' && (note ?? '').trim().isNotEmpty)
          'reason': note!.trim(),
      },
    ),
  );

  Future<Map<String, dynamic>> recordPayment(String id, String method) {
    final o = state.all.firstWhere(
      (x) => '${x['_id']}' == id,
      orElse: () => const {},
    );
    return _act(
      () => _api.recordDiagnosticsOfflinePayment(
        id,
        amount: labTotal(o),
        method: method,
      ),
    );
  }

  Future<Map<String, dynamic>> saveResults(
    String id, {
    required List<Map<String, dynamic>> results,
    String? notes,
    bool finalise = false,
  }) => _act(
    () => _api.saveDiagnosticsResults(id, {
      'results': results,
      'notes': ?notes,
      'final': finalise,
    }),
  );

  Future<Map<String, dynamic>> release(String id, {String? signedBy}) =>
      _act(() => _api.releaseDiagnosticsReport(id, signedBy: signedBy));

  Future<Map<String, dynamic>> uploadReport(String id, String path) =>
      _act(() => _api.uploadDiagnosticsReport(id, path));

  Future<List<int>> reportBytes(String id) async {
    final res = await _api.downloadDiagnosticsReport(id);
    return res.data ?? const [];
  }

  @override
  void dispose() {
    _poll?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }
}

final labOrdersProvider =
    StateNotifierProvider<LabOrdersNotifier, LabOrdersState>((ref) {
      // A new notifier per account: a second lab on the phone starts clean.
      ref.watch(authProvider.select((s) => s.user?.id));
      return LabOrdersNotifier();
    });

// ─────────────────────────── Simple resources ───────────────────────────
//
// Dashboard, catalogue, staff, profile and timetable share one shape: a
// payload, loading flags and an error, refreshed behind the current data.

class LabResource {
  final Map<String, dynamic> data;
  final bool isLoading;
  final bool isRefreshing;
  final bool isSaving;
  final String? error;
  final DateTime? loadedAt;

  const LabResource({
    this.data = const {},
    this.isLoading = false,
    this.isRefreshing = false,
    this.isSaving = false,
    this.error,
    this.loadedAt,
  });

  bool get hasLoaded => loadedAt != null;

  LabResource copyWith({
    Map<String, dynamic>? data,
    bool? isLoading,
    bool? isRefreshing,
    bool? isSaving,
    String? error,
    bool clearError = false,
    DateTime? loadedAt,
  }) => LabResource(
    data: data ?? this.data,
    isLoading: isLoading ?? this.isLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    isSaving: isSaving ?? this.isSaving,
    error: clearError ? null : (error ?? this.error),
    loadedAt: loadedAt ?? this.loadedAt,
  );
}

abstract class LabResourceNotifier extends StateNotifier<LabResource> {
  LabResourceNotifier() : super(const LabResource());

  final api = ApiService();
  int _seq = 0;

  Future<Map<String, dynamic>> fetch();
  String get loadError;

  Future<void> ensureLoaded() async {
    if (!state.hasLoaded && !state.isLoading) await load();
  }

  Future<void> load({bool silent = false}) async {
    final seq = ++_seq;
    state = state.hasLoaded || silent
        ? state.copyWith(isRefreshing: true, clearError: true)
        : state.copyWith(isLoading: true, clearError: true);
    try {
      final data = await fetch();
      if (seq != _seq || !mounted) return;
      state = state.copyWith(
        data: data,
        isLoading: false,
        isRefreshing: false,
        loadedAt: DateTime.now(),
      );
    } catch (e) {
      if (seq != _seq || !mounted) return;
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        error: labError(e, fallback: loadError),
      );
    }
  }

  /// Runs a write with the saving flag, then [after] (usually a reload).
  Future<T> saving<T>(
    Future<T> Function() write, {
    Future<void> Function()? after,
  }) async {
    state = state.copyWith(isSaving: true);
    try {
      final r = await write();
      if (after != null) await after();
      return r;
    } finally {
      if (mounted) state = state.copyWith(isSaving: false);
    }
  }
}

/// GET /diagnostics/merchant/dashboard: { lab, stats, today, attention }.
class LabDashboardNotifier extends LabResourceNotifier {
  @override
  String get loadError => 'Couldn’t load today.';

  @override
  Future<Map<String, dynamic>> fetch() async =>
      _map((await api.getDiagnosticsMerchantDashboard()).data);

  Map<String, dynamic> get lab => _map(state.data['lab']);
  Map<String, dynamic> get stats => _map(state.data['stats']);
}

final labDashboardProvider =
    StateNotifierProvider<LabDashboardNotifier, LabResource>((ref) {
      ref.watch(authProvider.select((s) => s.user?.id));
      return LabDashboardNotifier();
    });

/// The lab's tests and packages, plus the starter library.
class LabCatalogNotifier extends LabResourceNotifier {
  @override
  String get loadError => 'Couldn’t load your tests.';

  @override
  Future<Map<String, dynamic>> fetch() async =>
      _map((await api.getDiagnosticsCatalog()).data);

  List<Map<String, dynamic>> get tests => _list(state.data['tests']);
  List<Map<String, dynamic>> get packages => _list(state.data['packages']);

  Future<void> saveTest(Map<String, dynamic> data, {String? id}) => saving(
    () => id == null
        ? api.createDiagnosticsCatalogTest(data)
        : api.updateDiagnosticsCatalogTest(id, data),
    after: () => load(silent: true),
  );

  Future<void> setTestActive(String id, bool active) => saving(
    () => active
        ? api.updateDiagnosticsCatalogTest(id, {'isActive': true})
        : api.deleteDiagnosticsCatalogTest(id),
    after: () => load(silent: true),
  );

  Future<void> savePackage(Map<String, dynamic> data, {String? id}) => saving(
    () => id == null
        ? api.createDiagnosticsPackage(data)
        : api.updateDiagnosticsPackage(id, data),
    after: () => load(silent: true),
  );

  Future<void> setPackageActive(String id, bool active) => saving(
    () => active
        ? api.updateDiagnosticsPackage(id, {'isActive': true})
        : api.deleteDiagnosticsPackage(id),
    after: () => load(silent: true),
  );

  Future<List<Map<String, dynamic>>> library() async =>
      _list(_map((await api.getDiagnosticsLibrary()).data)['tests']);

  /// Adds library tests ([{testCode, price}]); returns the server message.
  Future<String> importTests(List<Map<String, dynamic>> items) =>
      saving(() async {
        final res = await api.importDiagnosticsLibrary(items);
        return '${_map(res.data)['message'] ?? 'Tests added'}';
      }, after: () => load(silent: true));
}

final labCatalogProvider =
    StateNotifierProvider<LabCatalogNotifier, LabResource>((ref) {
      ref.watch(authProvider.select((s) => s.user?.id));
      return LabCatalogNotifier();
    });

/// Phlebotomists, technicians and front desk, with today's collection load.
class LabStaffNotifier extends LabResourceNotifier {
  @override
  String get loadError => 'Couldn’t load your team.';

  @override
  Future<Map<String, dynamic>> fetch() async =>
      _map((await api.getDiagnosticsStaff()).data);

  List<Map<String, dynamic>> get staff => _list(state.data['staff']);

  List<Map<String, dynamic>> get phlebotomists => staff
      .where((s) => s['role'] == 'phlebotomist' && s['isActive'] != false)
      .toList();

  Future<void> save(Map<String, dynamic> data, {String? id}) => saving(
    () => id == null
        ? api.createDiagnosticsStaff(data)
        : api.updateDiagnosticsStaff(id, data),
    after: () => load(silent: true),
  );

  Future<void> setActive(String id, bool active) => saving(
    () => active
        ? api.updateDiagnosticsStaff(id, {'isActive': true})
        : api.deleteDiagnosticsStaff(id),
    after: () => load(silent: true),
  );
}

final labStaffProvider = StateNotifierProvider<LabStaffNotifier, LabResource>((
  ref,
) {
  ref.watch(authProvider.select((s) => s.user?.id));
  return LabStaffNotifier();
});

/// The lab's own profile (GET/PUT /pathology/me/profile).
class LabProfileNotifier extends LabResourceNotifier {
  @override
  String get loadError => 'Couldn’t load your lab profile.';

  @override
  Future<Map<String, dynamic>> fetch() async {
    final body = _map((await api.getPathologyProfile()).data);
    return _map(body['profile'] ?? body['data']);
  }

  Future<void> save(Map<String, dynamic> updates) => saving(() async {
    final res = await api.updatePathologyProfile(updates);
    final body = _map(res.data);
    final profile = _map(body['profile'] ?? body['data']);
    if (profile.isNotEmpty && mounted) {
      state = state.copyWith(data: profile, loadedAt: DateTime.now());
    }
  });
}

final labProfileProvider =
    StateNotifierProvider<LabProfileNotifier, LabResource>((ref) {
      ref.watch(authProvider.select((s) => s.user?.id));
      return LabProfileNotifier();
    });

/// The weekly collection timetable and the next 14 days it produces.
class LabScheduleNotifier extends LabResourceNotifier {
  @override
  String get loadError => 'Couldn’t load your collection slots.';

  @override
  Future<Map<String, dynamic>> fetch() async =>
      _map((await api.getDiagnosticsSchedule()).data);

  List<Map<String, dynamic>> get days =>
      _list(_map(state.data['template'])['days']);
  List<Map<String, dynamic>> get upcoming => _list(state.data['upcoming']);
  List<String> get holidays =>
      (state.data['holidays'] is List
              ? state.data['holidays'] as List
              : const [])
          .map((e) => '$e')
          .toList();

  Future<void> saveWeek(List<Map<String, dynamic>> days) => saving(() async {
    final res = await api.saveDiagnosticsSchedule(days);
    if (mounted) {
      state = state.copyWith(data: _map(res.data), loadedAt: DateTime.now());
    }
  });

  Future<void> setHoliday(String date, {required bool closed}) => saving(
    () async {
      final res = await api.setDiagnosticsHoliday(date, closed: closed);
      if (mounted) {
        state = state.copyWith(data: _map(res.data), loadedAt: DateTime.now());
      }
    },
  );
}

final labScheduleProvider =
    StateNotifierProvider<LabScheduleNotifier, LabResource>((ref) {
      ref.watch(authProvider.select((s) => s.user?.id));
      return LabScheduleNotifier();
    });

/// Earnings for a range: '7d' | '30d' | 'month' | 'year'.
final labEarningsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, range) async {
      ref.watch(authProvider.select((s) => s.user?.id));
      final res = await ApiService().getDiagnosticsEarnings(range);
      return _map(res.data);
    });
