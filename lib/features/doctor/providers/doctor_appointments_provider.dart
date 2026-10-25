import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../widgets/doctor_ui.dart';

/// Everything the doctor's day is built from: one list of appointments
/// around today, with the views the screens need derived from it.
///
/// Uses `GET /appointment` (role-scoped by the server) rather than
/// `/doctor/me/appointments`: it takes several statuses, a date window and a
/// sort, and returns the patient populated.
class DoctorAppointmentsState {
  final List<Map<String, dynamic>> all;
  final bool isLoading;
  final bool isRefreshing;
  final String? error;
  final DateTime? loadedAt;

  /// Bumped when a poll sees a request that wasn't there before; the shell
  /// listens to it to alert the doctor.
  final int arrivalTick;
  final List<Map<String, dynamic>> lastArrivals;

  const DoctorAppointmentsState({
    this.all = const [],
    this.isLoading = false,
    this.isRefreshing = false,
    this.error,
    this.loadedAt,
    this.arrivalTick = 0,
    this.lastArrivals = const [],
  });

  DoctorAppointmentsState copyWith({
    List<Map<String, dynamic>>? all,
    bool? isLoading,
    bool? isRefreshing,
    String? error,
    bool clearError = false,
    DateTime? loadedAt,
    int? arrivalTick,
    List<Map<String, dynamic>>? lastArrivals,
  }) => DoctorAppointmentsState(
    all: all ?? this.all,
    isLoading: isLoading ?? this.isLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    error: clearError ? null : (error ?? this.error),
    loadedAt: loadedAt ?? this.loadedAt,
    arrivalTick: arrivalTick ?? this.arrivalTick,
    lastArrivals: lastArrivals ?? this.lastArrivals,
  );

  bool get hasLoaded => loadedAt != null;

  /// Waiting for the doctor to accept or decline, soonest first.
  List<Map<String, dynamic>> get requests =>
      _sorted(all.where((a) => apptStatus(a) == 'pending'), asc: true);

  /// Today's accepted visits (and ones already seen), in time order.
  List<Map<String, dynamic>> get today {
    final now = DateTime.now();
    return _sorted(
      all.where((a) {
        final s = apptStatus(a);
        final d = apptStart(a);
        return d != null &&
            _sameDay(d, now) &&
            const {
              'confirmed',
              'accepted',
              'in_progress',
              'completed',
              'no_show',
              'rescheduled',
            }.contains(s);
      }),
      asc: true,
    );
  }

  /// Accepted visits after today.
  List<Map<String, dynamic>> get upcoming {
    final tomorrow = _startOfDay(DateTime.now()).add(const Duration(days: 1));
    return _sorted(
      all.where((a) {
        final d = apptStart(a);
        return d != null &&
            !d.isBefore(tomorrow) &&
            const {
              'confirmed',
              'accepted',
              'rescheduled',
            }.contains(apptStatus(a));
      }),
      asc: true,
    );
  }

  /// Finished, cancelled, declined or missed — newest first.
  List<Map<String, dynamic>> get past => _sorted(
    all.where(
      (a) => const {
        'completed',
        'cancelled',
        'rejected',
        'no_show',
      }.contains(apptStatus(a)),
    ),
    asc: false,
  );

  /// The visit happening now or next today, if any.
  Map<String, dynamic>? get nowOrNext {
    final now = DateTime.now();
    for (final a in today) {
      final s = apptStatus(a);
      if (s == 'in_progress') return a;
    }
    for (final a in today) {
      final end = apptEnd(a) ?? apptStart(a);
      if (end != null &&
          end.isAfter(now) &&
          const {'confirmed', 'accepted'}.contains(apptStatus(a))) {
        return a;
      }
    }
    return null;
  }

  /// Appointments per day for the last 7 days ending today (oldest first).
  List<int> get lastSevenDays {
    final today = _startOfDay(DateTime.now());
    return List.generate(7, (i) {
      final day = today.subtract(Duration(days: 6 - i));
      return all.where((a) {
        final d = apptStart(a);
        return d != null &&
            _sameDay(d, day) &&
            !const {'cancelled', 'rejected'}.contains(apptStatus(a));
      }).length;
    });
  }

  static List<Map<String, dynamic>> _sorted(
    Iterable<Map<String, dynamic>> list, {
    required bool asc,
  }) {
    final out = list.toList();
    out.sort((a, b) {
      final da = apptStart(a) ?? DateTime(2000);
      final db = apptStart(b) ?? DateTime(2000);
      return asc ? da.compareTo(db) : db.compareTo(da);
    });
    return out;
  }
}

DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class DoctorAppointmentsNotifier
    extends StateNotifier<DoctorAppointmentsState> {
  DoctorAppointmentsNotifier() : super(const DoctorAppointmentsState());

  final _api = ApiService();
  int _seq = 0;
  Timer? _poll;
  AppLifecycleListener? _lifecycle;
  bool _foreground = true;

  /// Request ids seen on the previous load; null until the first load so the
  /// requests already waiting at sign-in don't all "arrive" at once.
  Set<String>? _knownRequests;

  /// The window loaded: 60 days back (history, patients) to 60 ahead.
  Map<String, dynamic> get _query {
    final now = DateTime.now();
    String ymd(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return {
      'startDate': ymd(now.subtract(const Duration(days: 60))),
      'endDate': ymd(now.add(const Duration(days: 60))),
      'limit': 500,
      'sort': 'appointmentDate:asc',
    };
  }

  /// Loads now and then every 30 seconds while the app is in front.
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

  Future<void> load({bool silent = false}) async {
    final seq = ++_seq;
    state = state.hasLoaded || silent
        ? state.copyWith(isRefreshing: true, clearError: true)
        : state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _api.getAppointments(queryParams: _query);
      if (seq != _seq || !mounted) return;
      final data = res.data;
      final raw = data is Map ? data['appointments'] : data;
      final list = (raw is List ? raw : const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
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
        error: e is DioException
            ? doctorErrorMessage(e)
            : 'Couldn’t load appointments.',
      );
    }
  }

  void _noticeArrivals(List<Map<String, dynamic>> list) {
    final requests = list.where((a) => apptStatus(a) == 'pending').toList();
    final ids = requests.map((a) => '${a['_id']}').toSet();
    final known = _knownRequests;
    _knownRequests = ids;
    if (known == null) return;
    final fresh = requests.where((a) => !known.contains('${a['_id']}'));
    if (fresh.isEmpty) return;
    state = state.copyWith(
      arrivalTick: state.arrivalTick + 1,
      lastArrivals: fresh.toList(),
    );
  }

  /// Replaces one appointment after an action or a detail fetch.
  void upsert(Map<String, dynamic> appointment) {
    final id = '${appointment['_id']}';
    final list = [...state.all];
    final i = list.indexWhere((a) => '${a['_id']}' == id);
    // The list populates the patient; a detail response may carry only the
    // id, so keep the richer copy.
    final merged = i >= 0 && appointment['patientId'] is! Map
        ? {...appointment, 'patientId': list[i]['patientId']}
        : appointment;
    if (i >= 0) {
      list[i] = merged;
    } else {
      list.add(merged);
    }
    if (apptStatus(merged) != 'pending') {
      _knownRequests?.remove(id);
    }
    state = state.copyWith(all: list);
  }

  Future<Map<String, dynamic>?> _act(Future<Response> Function() call) async {
    final res = await call();
    final data = res.data;
    final appt = data is Map ? (data['appointment'] ?? data['data']) : null;
    if (appt is Map) {
      final map = Map<String, dynamic>.from(appt);
      upsert(map);
      return map;
    }
    await load(silent: true);
    return null;
  }

  Future<Map<String, dynamic>?> accept(String id) =>
      _act(() => _api.updateAppointmentStatus(id, 'accepted'));

  Future<Map<String, dynamic>?> decline(String id) =>
      _act(() => _api.updateAppointmentStatus(id, 'rejected'));

  Future<Map<String, dynamic>?> cancel(String id, {String? reason}) =>
      _act(() => _api.cancelAppointment(id, reason: reason));

  Future<Map<String, dynamic>?> complete(String id) =>
      _act(() => _api.completeAppointment(id));

  /// The patient didn't come. The server only allows it once the start time
  /// has passed (400 NO_SHOW_TOO_EARLY otherwise).
  Future<Map<String, dynamic>?> markNoShow(String id, {String? reason}) =>
      _act(() => _api.updateAppointmentStatus(id, 'no_show'));

  /// Opens (or reuses) the chat thread with this appointment's patient and
  /// returns its session id.
  Future<String> chatSession({
    required String patientId,
    required String appointmentId,
  }) async {
    final res = await _api.getOrCreateChatSession({
      'patientId': patientId,
      'appointmentId': appointmentId,
    });
    final session = res.data is Map ? res.data['session'] : null;
    final id = session is Map ? '${session['_id'] ?? ''}' : '';
    if (id.isEmpty) throw StateError('Couldn’t open the chat. Try again.');
    return id;
  }

  /// Fresh copy of one appointment from the server.
  Future<Map<String, dynamic>?> refreshOne(String id) async {
    final res = await _api.getAppointmentById(id);
    final data = res.data;
    final appt = data is Map ? (data['appointment'] ?? data['data']) : null;
    if (appt is! Map) return null;
    final map = Map<String, dynamic>.from(appt);
    upsert(map);
    return state.all.firstWhere((a) => '${a['_id']}' == id, orElse: () => map);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }
}

final doctorAppointmentsProvider =
    StateNotifierProvider<DoctorAppointmentsNotifier, DoctorAppointmentsState>((
      ref,
    ) {
      // A new notifier per signed-in account, so a second doctor on the
      // same phone never sees the first one's schedule.
      ref.watch(authProvider.select((s) => s.user?.id));
      return DoctorAppointmentsNotifier();
    });
