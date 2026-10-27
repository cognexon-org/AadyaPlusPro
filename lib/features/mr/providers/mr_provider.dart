import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/location/field_location_service.dart';
import '../../../core/network/api_service.dart';
import '../../../shared/ui/app_ui.dart' show appErrorMessage;
import '../../auth/providers/auth_provider.dart';

/// Everything the field force works with, loaded once per sign-in and then
/// refreshed section by section as the rep acts.
class MrState {
  final bool isLoading;
  final bool hasLoaded;
  final String? error;
  final Map<String, dynamic> profile;
  final Map<String, dynamic> dashboard;
  final Map<String, dynamic> analytics;
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> visits;
  final List<Map<String, dynamic>> attendance;
  final List<Map<String, dynamic>> tourPlans;
  final List<Map<String, dynamic>> expenses;
  final List<Map<String, dynamic>> pobOrders;
  final List<Map<String, dynamic>> team;
  final List<Map<String, dynamic>> territories;
  final List<Map<String, dynamic>> targets;
  final List<Map<String, dynamic>> sampleBalances;
  final List<Map<String, dynamic>> sampleTransactions;
  final List<Map<String, dynamic>> detailing;
  final List<Map<String, dynamic>> leaves;

  const MrState({
    this.isLoading = false,
    this.hasLoaded = false,
    this.error,
    this.profile = const {},
    this.dashboard = const {},
    this.analytics = const {},
    this.accounts = const [],
    this.visits = const [],
    this.attendance = const [],
    this.tourPlans = const [],
    this.expenses = const [],
    this.pobOrders = const [],
    this.team = const [],
    this.territories = const [],
    this.targets = const [],
    this.sampleBalances = const [],
    this.sampleTransactions = const [],
    this.detailing = const [],
    this.leaves = const [],
  });

  MrState copyWith({
    bool? isLoading,
    bool? hasLoaded,
    String? error,
    bool clearError = false,
    Map<String, dynamic>? profile,
    Map<String, dynamic>? dashboard,
    Map<String, dynamic>? analytics,
    List<Map<String, dynamic>>? accounts,
    List<Map<String, dynamic>>? visits,
    List<Map<String, dynamic>>? attendance,
    List<Map<String, dynamic>>? tourPlans,
    List<Map<String, dynamic>>? expenses,
    List<Map<String, dynamic>>? pobOrders,
    List<Map<String, dynamic>>? team,
    List<Map<String, dynamic>>? territories,
    List<Map<String, dynamic>>? targets,
    List<Map<String, dynamic>>? sampleBalances,
    List<Map<String, dynamic>>? sampleTransactions,
    List<Map<String, dynamic>>? detailing,
    List<Map<String, dynamic>>? leaves,
  }) => MrState(
    isLoading: isLoading ?? this.isLoading,
    hasLoaded: hasLoaded ?? this.hasLoaded,
    error: clearError ? null : (error ?? this.error),
    profile: profile ?? this.profile,
    dashboard: dashboard ?? this.dashboard,
    analytics: analytics ?? this.analytics,
    accounts: accounts ?? this.accounts,
    visits: visits ?? this.visits,
    attendance: attendance ?? this.attendance,
    tourPlans: tourPlans ?? this.tourPlans,
    expenses: expenses ?? this.expenses,
    pobOrders: pobOrders ?? this.pobOrders,
    team: team ?? this.team,
    territories: territories ?? this.territories,
    targets: targets ?? this.targets,
    sampleBalances: sampleBalances ?? this.sampleBalances,
    sampleTransactions: sampleTransactions ?? this.sampleTransactions,
    detailing: detailing ?? this.detailing,
    leaves: leaves ?? this.leaves,
  );

  /// MR, ABM, RBM or ZSM.
  String get designation =>
      '${profile['designation'] ?? mapOf(dashboard['profile'])['designation'] ?? 'MR'}'.toUpperCase();

  bool get isManager => const {'ABM', 'RBM', 'ZSM'}.contains(designation);

  String get ownProfileId {
    final direct = profile['_id'] ?? profile['id'];
    if (direct != null) return '$direct';
    return '${mapOf(dashboard['profile'])['id'] ?? ''}';
  }

  String get name {
    final user = profile['userId'];
    if (user is Map && (user['name'] ?? '').toString().isNotEmpty) return user['name'].toString();
    return '${mapOf(dashboard['profile'])['name'] ?? ''}';
  }

  Map<String, dynamic> get metrics => mapOf(dashboard['metrics']);
  Map<String, dynamic> get selfPerformance => mapOf(dashboard['selfPerformance']);

  /// Today's attendance row, if any.
  Map<String, dynamic>? get today {
    final key = dateKey(DateTime.now());
    for (final row in attendance) {
      if (row['dateKey'] == key) return row;
    }
    return null;
  }

  /// Approved or pending leave covering [day], the rep's own.
  Map<String, dynamic>? leaveOn(DateTime day) {
    final key = dateKey(day);
    for (final l in leaves) {
      if (!isMine(l['profileId'])) continue;
      if (l['status'] != 'approved' && l['status'] != 'pending') continue;
      if ('${l['fromDate']}'.compareTo(key) <= 0 && '${l['toDate']}'.compareTo(key) >= 0) return l;
    }
    return null;
  }

  bool isMine(dynamic profileValue) {
    final own = ownProfileId;
    if (own.isEmpty) return true;
    return idOf(profileValue) == own;
  }
}

/// `YYYY-MM-DD` for a local day.
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// `YYYY-MM` for a local month.
String monthKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

String idOf(dynamic v) => v is Map ? '${v['_id'] ?? v['id'] ?? ''}' : '${v ?? ''}';

Map<String, dynamic> mapOf(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> listOf(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Map<String, dynamic>>[];

class MrNotifier extends StateNotifier<MrState> {
  final ApiService _api = ApiService();
  MrNotifier() : super(const MrState());

  Future<void>? _loading;

  /// Loads everything once; later calls share the first load.
  Future<void> ensureLoaded() => state.hasLoaded ? Future.value() : loadAll();

  /// Loads every section. One failing section (a manager-only list, say)
  /// leaves the rest intact; only the profile itself failing is an error.
  Future<void> loadAll() {
    return _loading ??= _loadAll().whenComplete(() => _loading = null);
  }

  Future<void> _loadAll() async {
    state = state.copyWith(isLoading: true, clearError: true);
    Object? coreError;
    try {
      await Future.wait([loadMe(), loadDashboard()]);
    } catch (e) {
      coreError = e;
    }
    await Future.wait([
      _quiet(loadAccounts),
      _quiet(loadVisits),
      _quiet(loadAttendance),
      _quiet(loadPlans),
      _quiet(loadExpenses),
      _quiet(loadPob),
      _quiet(loadTargets),
      _quiet(loadSamples),
      _quiet(loadDetailing),
      _quiet(loadTerritories),
      _quiet(loadLeaves),
      if (state.isManager) _quiet(loadTeam),
      if (state.isManager) _quiet(loadAnalytics),
    ]);
    state = state.copyWith(
      isLoading: false,
      hasLoaded: coreError == null,
      error: coreError == null ? null : _message(coreError, 'Couldn’t load your field data. Pull down to try again.'),
    );
  }

  Future<void> _quiet(Future<void> Function() load) async {
    try {
      await load();
    } catch (_) {}
  }

  static String _message(Object e, String fallback) {
    if (e is StateError) return e.message; // GPS off or permission denied
    if (e is MrException) return e.message;
    return appErrorMessage(e, fallback: fallback);
  }

  // ── Reads ──

  Future<void> loadMe() async {
    final res = await _api.getMrMe();
    state = state.copyWith(profile: mapOf(res.data['profile']));
  }

  Future<void> loadDashboard({String? month}) async {
    final res = await _api.getMrDashboard(queryParams: {'month': ?month});
    state = state.copyWith(dashboard: mapOf(res.data));
  }

  Future<void> loadAnalytics() async {
    final res = await _api.getMrAnalytics();
    state = state.copyWith(analytics: mapOf(res.data));
  }

  Future<void> loadAccounts({String? query, String? type}) async {
    final res = await _api.getMrAccounts(queryParams: {
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      'type': ?type,
    });
    state = state.copyWith(accounts: listOf(res.data['accounts']));
  }

  Future<void> loadVisits({String? month}) async {
    final res = await _api.getMrVisits(queryParams: {'month': month ?? monthKey(DateTime.now())});
    state = state.copyWith(visits: listOf(res.data['visits']));
  }

  Future<void> loadAttendance() async {
    final res = await _api.getMrAttendance(queryParams: {'month': monthKey(DateTime.now())});
    state = state.copyWith(attendance: listOf(res.data['attendance']));
  }

  Future<void> loadPlans() async {
    final res = await _api.getMrTourPlans();
    state = state.copyWith(tourPlans: listOf(res.data['plans']));
  }

  Future<void> loadExpenses() async {
    final res = await _api.getMrExpenses();
    state = state.copyWith(expenses: listOf(res.data['expenses']));
  }

  Future<void> loadPob() async {
    final res = await _api.getMrPob();
    state = state.copyWith(pobOrders: listOf(res.data['orders']));
  }

  Future<void> loadTeam() async {
    final res = await _api.getMrTeam(includeInactive: true);
    state = state.copyWith(team: listOf(res.data['profiles']));
  }

  Future<void> loadTerritories() async {
    final res = await _api.getMrTerritories();
    state = state.copyWith(territories: listOf(res.data['territories']));
  }

  Future<void> loadTargets({String? month}) async {
    final res = await _api.getMrTargets(queryParams: {'month': ?month});
    state = state.copyWith(targets: listOf(res.data['rows']));
  }

  Future<void> loadSamples() async {
    final res = await _api.getMrSamples();
    state = state.copyWith(
      sampleBalances: listOf(res.data['balances']),
      sampleTransactions: listOf(res.data['transactions']),
    );
  }

  Future<void> loadLeaves() async {
    final res = await _api.getMrLeaves();
    state = state.copyWith(leaves: listOf(res.data['leaves']));
  }

  Future<void> loadDetailing() async {
    final res = await _api.getMrDetailing();
    state = state.copyWith(detailing: listOf(res.data['content']));
  }

  // ── Actions ── each throws a readable message on failure.

  Future<T> _act<T>(Future<T> Function() action, String fallback) async {
    try {
      return await action();
    } catch (e) {
      throw MrException(_message(e, fallback));
    }
  }

  Future<void> punchIn({String workType = 'field', String? notes}) => _act(() async {
    final geo = await FieldLocationService.currentPayload();
    await _api.mrPunchIn({...geo, 'workType': workType, if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim()});
    await Future.wait([loadAttendance(), loadDashboard()]);
  }, 'Couldn’t start your day');

  Future<void> punchOut() => _act(() async {
    final geo = await FieldLocationService.currentPayload();
    await _api.mrPunchOut(geo);
    await Future.wait([loadAttendance(), loadDashboard()]);
  }, 'Couldn’t end your day');

  Future<Map<String, dynamic>> createVisit(String accountId, {DateTime? when, List<String> jointWith = const []}) => _act(() async {
    final res = await _api.createMrVisit({
      'accountId': accountId,
      if (when != null) 'visitDate': when.toUtc().toIso8601String(),
      if (jointWith.isNotEmpty) 'jointWithProfileIds': jointWith,
    });
    await loadVisits();
    return mapOf(res.data['visit']);
  }, 'Couldn’t plan this call');

  Future<void> checkInVisit(String visitId) => _act(() async {
    final geo = await FieldLocationService.currentPayload();
    await _api.mrVisitCheckIn(visitId, geo);
    await loadVisits();
  }, 'Couldn’t check in');

  Future<void> checkOutVisit(
    String visitId, {
    String? discussionNotes,
    String? doctorFeedback,
    DateTime? nextVisitDate,
    List<String> products = const [],
    List<({String name, int qty})> samples = const [],
    List<({String name, int qty})> gifts = const [],
    num? pobAmount,
  }) => _act(() async {
    final geo = await FieldLocationService.currentPayload();
    await _api.mrVisitCheckOut(visitId, {
      ...geo,
      if (discussionNotes != null && discussionNotes.trim().isNotEmpty) 'discussionNotes': discussionNotes.trim(),
      if (doctorFeedback != null && doctorFeedback.trim().isNotEmpty) 'doctorFeedback': doctorFeedback.trim(),
      if (nextVisitDate != null) 'nextVisitDate': nextVisitDate.toUtc().toIso8601String(),
      'productsDiscussed': [for (final p in products) {'productName': p}],
      'samples': [for (final s in samples) {'productName': s.name, 'quantity': s.qty}],
      'gifts': [for (final g in gifts) {'itemName': g.name, 'quantity': g.qty}],
      'pobAmount': ?pobAmount,
    });
    await Future.wait([loadVisits(), loadDashboard()]);
  }, 'Couldn’t check out');

  Future<void> submitVisit(String visitId) => _act(() async {
    await _api.mrVisitSubmit(visitId, {});
    await loadVisits();
  }, 'Couldn’t submit this report');

  Future<void> reviewVisit(String visitId, String decision, {String? comment}) => _act(() async {
    await _api.mrVisitReview(visitId, decision, comment: comment);
    await Future.wait([loadVisits(), loadDashboard(), loadSamples()]);
  }, 'Couldn’t save the review');

  /// Replaces this month's plan days (the server keeps one plan a month).
  Future<void> saveTourPlan(String month, List<Map<String, dynamic>> days) => _act(() async {
    await _api.saveMrTourPlan({'month': month, 'days': days});
    await loadPlans();
  }, 'Couldn’t save the tour plan');

  Future<void> submitTourPlan(String id) => _act(() async {
    await _api.submitMrTourPlan(id);
    await Future.wait([loadPlans(), loadDashboard()]);
  }, 'Couldn’t submit the plan');

  Future<void> reviewTourPlan(String id, String decision, {String? comment}) => _act(() async {
    await _api.reviewMrTourPlan(id, decision, comment: comment);
    await Future.wait([loadPlans(), loadDashboard()]);
  }, 'Couldn’t save the review');

  Future<void> createExpense({required String category, required num amount, required DateTime date, String? description, String? receiptPath, bool submit = false}) => _act(() async {
    final res = await _api.createMrExpense({
      'category': category,
      'amount': amount,
      'expenseDate': DateTime(date.year, date.month, date.day, 12).toUtc().toIso8601String(),
      if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
    });
    final id = idOf(res.data['expense']);
    if (id.isNotEmpty && receiptPath != null) await _api.uploadMrExpenseReceipt(id, receiptPath);
    if (submit && id.isNotEmpty) await _api.submitMrExpense(id);
    await Future.wait([loadExpenses(), loadDashboard()]);
  }, 'Couldn’t save the expense');

  Future<void> uploadReceipt(String expenseId, String filePath) => _act(() async {
    await _api.uploadMrExpenseReceipt(expenseId, filePath);
    await loadExpenses();
  }, 'Couldn’t attach the receipt');

  /// The receipt file's bytes, fetched with the signed-in session.
  Future<List<int>> receiptBytes(String expenseId) => _act(() async {
    final res = await _api.getMrExpenseReceipt(expenseId);
    return List<int>.from(res.data as List);
  }, 'Couldn’t open the receipt');

  Future<void> payExpense(String id, {String? reference}) => _act(() async {
    await _api.payMrExpense(id, reference: reference);
    await Future.wait([loadExpenses(), loadDashboard()]);
  }, 'Couldn’t mark this paid');

  Future<void> applyLeave({required DateTime from, required DateTime to, required String leaveType, bool halfDay = false, String? reason}) => _act(() async {
    await _api.applyMrLeave({
      'fromDate': dateKey(from),
      'toDate': dateKey(to),
      'leaveType': leaveType,
      'halfDay': halfDay,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
    await loadLeaves();
  }, 'Couldn’t send the leave request');

  Future<void> cancelLeave(String id) => _act(() async {
    await _api.cancelMrLeave(id);
    await Future.wait([loadLeaves(), loadAttendance()]);
  }, 'Couldn’t cancel this leave');

  Future<void> reviewLeave(String id, String decision, {String? comment}) => _act(() async {
    await _api.reviewMrLeave(id, decision, comment: comment);
    await Future.wait([loadLeaves(), loadDashboard()]);
  }, 'Couldn’t save the review');

  /// Doctors or pharmacies already on Aadya Plus, for linking a customer.
  Future<List<Map<String, dynamic>>> searchDirectory(String kind, String q) => _act(() async {
    final res = await _api.searchMrDirectory(kind, q);
    return listOf(res.data['results']);
  }, 'Couldn’t search Aadya Plus');

  Future<void> updateAccount(String id, Map<String, dynamic> data) => _act(() async {
    await _api.updateMrAccount(id, data);
    await loadAccounts();
  }, 'Couldn’t update this customer');

  Future<void> submitExpense(String id) => _act(() async {
    await _api.submitMrExpense(id);
    await Future.wait([loadExpenses(), loadDashboard()]);
  }, 'Couldn’t submit the expense');

  Future<void> reviewExpense(String id, String decision, {String? comment}) => _act(() async {
    await _api.reviewMrExpense(id, decision, comment: comment);
    await Future.wait([loadExpenses(), loadDashboard()]);
  }, 'Couldn’t save the review');

  Future<void> createPob({required String accountId, required List<({String name, num qty, num rate})> items, String? notes}) => _act(() async {
    await _api.createMrPob({
      'accountId': accountId,
      'items': [for (final i in items) {'productName': i.name, 'quantity': i.qty, 'rate': i.rate}],
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
    await Future.wait([loadPob(), loadDashboard()]);
  }, 'Couldn’t book this order');

  Future<void> setPobStatus(String id, String status) => _act(() async {
    await _api.updateMrPobStatus(id, status);
    await Future.wait([loadPob(), loadDashboard()]);
  }, 'Couldn’t update the order');

  /// The device's position, for saving a customer's location.
  Future<Map<String, dynamic>> currentLocation() => _act(() => FieldLocationService.currentPayload(), 'Couldn’t read your location');

  Future<void> createAccount(Map<String, dynamic> data) => _act(() async {
    await _api.createMrAccount(data);
    await loadAccounts();
  }, 'Couldn’t add this customer');

  Future<void> updateName(String name) => _act(() async {
    await _api.updateMrMe({'name': name.trim()});
    await Future.wait([loadMe(), loadDashboard()]);
  }, 'Couldn’t save your name');

  Future<void> changePassword(String current, String next) => _act(
    () => _api.changePassword(current, next),
    'Couldn’t change the password',
  );

  /// Adds the next level down to the manager's team (an ABM adds an MR).
  Future<void> addTeamMember(Map<String, dynamic> data) => _act(() async {
    await _api.createMrTeamUser(data);
    await Future.wait([loadTeam(), loadDashboard()]);
  }, 'Couldn’t add this person');

  Future<void> updateTeamMember(String id, Map<String, dynamic> data) => _act(() async {
    await _api.updateMrTeamMember(id, data);
    await Future.wait([loadTeam(), loadDashboard()]);
  }, 'Couldn’t save the changes');

  Future<void> saveTerritory(String? id, Map<String, dynamic> data) => _act(() async {
    if (id == null) {
      await _api.createMrTerritory(data);
    } else {
      await _api.updateMrTerritory(id, data);
    }
    await Future.wait([loadTerritories(), loadMe()]);
  }, 'Couldn’t save the territory');

  Future<void> saveDetailing(String? id, Map<String, dynamic> data) => _act(() async {
    if (id == null) {
      await _api.createMrDetailing(data);
    } else {
      await _api.updateMrDetailing(id, data);
    }
    await loadDetailing();
  }, 'Couldn’t save this content');

  Future<void> setTarget({
    required String profileId,
    required String month,
    num callTarget = 0,
    num doctorCallTarget = 0,
    num pobTarget = 0,
    num workingDaysTarget = 0,
  }) => _act(() async {
    await _api.setMrTarget({
      'profileId': profileId,
      'month': month,
      'callTarget': callTarget,
      'doctorCallTarget': doctorCallTarget,
      'pobTarget': pobTarget,
      'workingDaysTarget': workingDaysTarget,
    });
    await Future.wait([loadTargets(month: month), loadDashboard(), if (state.isManager) loadAnalytics()]);
  }, 'Couldn’t save the target');

  /// A manager hands samples or gifts to a rep (or takes stock back).
  Future<void> issueSamples({
    required String profileId,
    required String productName,
    required int quantity,
    String itemType = 'sample',
    String transactionType = 'issue',
    String? batchNumber,
  }) => _act(() async {
    await _api.createMrSampleTransaction({
      'profileId': profileId,
      'itemType': itemType,
      'productName': productName,
      'transactionType': transactionType,
      'quantity': quantity,
      if (batchNumber != null && batchNumber.trim().isNotEmpty) 'batchNumber': batchNumber.trim(),
    });
    await loadSamples();
  }, 'Couldn’t record the samples');
}

class MrException implements Exception {
  final String message;
  const MrException(this.message);
  @override
  String toString() => message;
}

/// Field data belongs to one signed-in account: switching account or
/// signing out starts fresh.
/// Asks the Plan tab to open a section (1 = leave), e.g. from the profile.
final mrPlanSectionProvider = StateProvider<int?>((ref) => null);

final mrProvider = StateNotifierProvider<MrNotifier, MrState>((ref) {
  ref.watch(authProvider.select((s) => s.user?.id));
  return MrNotifier();
});
