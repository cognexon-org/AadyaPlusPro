import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../widgets/doctor_ui.dart';

/// The doctor's earnings, computed on the device from the per-consultation
/// commission rows (`GET /commission`).
///
/// Why not `/doctor/me/earnings(/report)`: the server creates a commission
/// row when an appointment is *booked* and never voids it, so its totals
/// include cancelled and declined bookings, and it groups months in UTC.
/// Here each row is matched to its appointment (`GET /appointment`, which
/// carries the status) and rows for cancelled/declined appointments are left
/// out; months are keyed by local year + month.
class DoctorEarningsState {
  final List<Map<String, dynamic>> rows;

  /// The doctor's appointments by id (status, time, populated patient), for
  /// the rows' detail view.
  final Map<String, Map<String, dynamic>> appointmentsById;

  /// Commission rows left out because their appointment was cancelled or
  /// declined.
  final int excluded;
  final bool isLoading;
  final String? error;
  final DateTime? loadedAt;

  const DoctorEarningsState({
    this.rows = const [],
    this.appointmentsById = const {},
    this.excluded = 0,
    this.isLoading = false,
    this.error,
    this.loadedAt,
  });

  bool get hasLoaded => loadedAt != null;

  /// The row's appointment: the full one when loaded, else the populated
  /// stub on the row (date, type, fee).
  Map<String, dynamic> appointmentOf(Map<String, dynamic> r) {
    final a = r['appointmentId'];
    final stub = a is Map ? Map<String, dynamic>.from(a) : <String, dynamic>{};
    final id = a is Map ? '${a['_id']}' : '${a ?? ''}';
    return appointmentsById[id] ?? stub;
  }

  static num _n(dynamic v) => num.tryParse('${v ?? 0}') ?? 0;
  static num earning(Map<String, dynamic> r) => _n(r['professionalEarning']);
  static num fee(Map<String, dynamic> r) => _n(r['consultationFee']);
  static num commission(Map<String, dynamic> r) => _n(r['platformCommission']);

  static DateTime? createdAt(Map<String, dynamic> r) =>
      DateTime.tryParse('${r['createdAt'] ?? ''}')?.toLocal();

  /// `year * 100 + month` — never just the month, so October 2025 and
  /// October 2026 stay apart.
  static int monthKey(DateTime d) => d.year * 100 + d.month;

  static bool isSettled(Map<String, dynamic> r) =>
      '${r['payoutStatus']}' == 'paid';

  Map<int, ({num earned, int count})> get _byMonth {
    final out = <int, ({num earned, int count})>{};
    for (final r in rows) {
      final d = createdAt(r);
      if (d == null) continue;
      final k = monthKey(d);
      final cur = out[k] ?? (earned: 0, count: 0);
      out[k] = (earned: cur.earned + earning(r), count: cur.count + 1);
    }
    return out;
  }

  /// The last six calendar months ending with this one, oldest first,
  /// zero-filled.
  List<({DateTime month, num earned, int count})> get lastSixMonths {
    final now = DateTime.now();
    final by = _byMonth;
    return [
      for (var i = 5; i >= 0; i--)
        () {
          final m = DateTime(now.year, now.month - i);
          final v = by[monthKey(m)];
          return (month: m, earned: v?.earned ?? 0, count: v?.count ?? 0);
        }(),
    ];
  }

  num get thisMonth => lastSixMonths.last.earned;
  num get lastMonth => lastSixMonths[4].earned;
  int get consultationsThisMonth => lastSixMonths.last.count;

  num get pending =>
      rows.where((r) => !isSettled(r)).fold<num>(0, (a, r) => a + earning(r));
  num get settled =>
      rows.where(isSettled).fold<num>(0, (a, r) => a + earning(r));

  /// The platform's cut in percent, from the newest row that states it.
  num? get commissionRate {
    for (final r in rows) {
      final rate = num.tryParse('${r['commissionRate'] ?? ''}');
      if (rate != null) return rate;
      final f = fee(r);
      if (f > 0) return commission(r) / f * 100;
    }
    return null;
  }

  DoctorEarningsState copyWith({
    List<Map<String, dynamic>>? rows,
    Map<String, Map<String, dynamic>>? appointmentsById,
    int? excluded,
    bool? isLoading,
    String? error,
    bool clearError = false,
    DateTime? loadedAt,
  }) => DoctorEarningsState(
    rows: rows ?? this.rows,
    appointmentsById: appointmentsById ?? this.appointmentsById,
    excluded: excluded ?? this.excluded,
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : (error ?? this.error),
    loadedAt: loadedAt ?? this.loadedAt,
  );
}

class DoctorEarningsNotifier extends StateNotifier<DoctorEarningsState> {
  DoctorEarningsNotifier() : super(const DoctorEarningsState());

  final _api = ApiService();
  int _seq = 0;

  static const _void = {'cancelled', 'rejected'};

  static List<Map<String, dynamic>> _list(dynamic data, String key) {
    final raw = data is Map ? data[key] : data;
    return (raw is List ? raw : const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> load() async {
    final seq = ++_seq;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final commissions = _api.getCommissions(queryParams: {'limit': 1000});
      // Statuses only; if this fails the rows are still shown, unfiltered.
      final appointments = _api
          .getAppointments(
            queryParams: {'limit': 1000, 'sort': 'appointmentDate:desc'},
          )
          .then<dynamic>((r) => r.data)
          .catchError((Object _) => null);
      final res = await commissions;
      final apptData = await appointments;
      if (seq != _seq || !mounted) return;

      final byId = <String, Map<String, dynamic>>{
        for (final a in _list(apptData, 'appointments')) '${a['_id']}': a,
      };
      final rows = <Map<String, dynamic>>[];
      var excluded = 0;
      for (final r in _list(res.data, 'commissions')) {
        final appt = r['appointmentId'];
        final id = appt is Map ? '${appt['_id']}' : '${appt ?? ''}';
        final status =
            (appt is Map && appt['status'] != null
                ? '${appt['status']}'
                : null) ??
            (byId[id] == null ? null : apptStatus(byId[id]!));
        if (_void.contains(status) || '${r['payoutStatus']}' == 'cancelled') {
          excluded++;
          continue;
        }
        rows.add(r);
      }
      rows.sort((a, b) {
        final da = DoctorEarningsState.createdAt(a) ?? DateTime(2000);
        final db = DoctorEarningsState.createdAt(b) ?? DateTime(2000);
        return db.compareTo(da);
      });
      state = state.copyWith(
        rows: rows,
        appointmentsById: byId,
        excluded: excluded,
        isLoading: false,
        loadedAt: DateTime.now(),
      );
    } catch (e) {
      if (seq != _seq || !mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: doctorError(e, fallback: 'Couldn’t load your earnings.'),
      );
    }
  }
}

final doctorEarningsProvider =
    StateNotifierProvider<DoctorEarningsNotifier, DoctorEarningsState>((ref) {
      // Fresh per signed-in account (see doctorAppointmentsProvider).
      ref.watch(authProvider.select((s) => s.user?.id));
      return DoctorEarningsNotifier();
    });
