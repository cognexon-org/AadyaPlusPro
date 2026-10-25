import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_service.dart';
import '../../../core/location/field_location_service.dart';

class MrState {
  final bool isLoading;
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
  final List<Map<String, dynamic>> detailing;

  const MrState({
    this.isLoading = false,
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
    this.detailing = const [],
  });

  MrState copyWith({
    bool? isLoading,
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
    List<Map<String, dynamic>>? detailing,
  }) {
    return MrState(
      isLoading: isLoading ?? this.isLoading,
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
      detailing: detailing ?? this.detailing,
    );
  }
}

class MrNotifier extends StateNotifier<MrState> {
  final ApiService _api = ApiService();
  MrNotifier() : super(const MrState());

  List<Map<String, dynamic>> _list(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }
    return const [];
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  String get designation =>
      '${state.profile['designation'] ?? state.dashboard['experience'] ?? 'MR'}'
          .toUpperCase();

  bool get isManager => const {'ABM', 'RBM', 'ZSM'}.contains(designation);

  String? get ownProfileId {
    final direct = state.profile['_id'] ?? state.profile['id'];
    if (direct != null) return '$direct';
    final p = state.dashboard['profile'];
    if (p is Map) return '${p['id'] ?? p['_id'] ?? ''}';
    return null;
  }

  Future<void> loadAll() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await Future.wait([
        loadMe(),
        loadDashboard(),
        loadAccounts(),
        loadVisits(),
        loadAttendance(),
        loadPlans(),
        loadExpenses(),
        loadPob(),
        loadTeam(),
        loadTerritories(),
        loadTargets(),
        loadSamples(),
        loadDetailing(),
      ]);
      if (isManager) await loadAnalytics();
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMe() async {
    final res = await _api.getMrMe();
    final data = res.data;
    state = state.copyWith(profile: _map(data is Map ? data['profile'] : null));
  }

  Future<void> loadDashboard() async {
    final res = await _api.getMrDashboard();
    state = state.copyWith(dashboard: _map(res.data));
  }

  Future<void> loadAnalytics() async {
    try {
      final res = await _api.getMrAnalytics();
      state = state.copyWith(analytics: _map(res.data));
    } catch (_) {
      state = state.copyWith(analytics: const {});
    }
  }

  Future<void> loadAccounts({String? query, String? type}) async {
    final res = await _api.getMrAccounts(
      queryParams: {
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        if (type != null && type.isNotEmpty) 'type': type,
      },
    );
    final data = res.data;
    state = state.copyWith(
      accounts: _list(data is Map ? data['accounts'] : null),
    );
  }

  Future<void> loadVisits() async {
    final res = await _api.getMrVisits();
    final data = res.data;
    state = state.copyWith(visits: _list(data is Map ? data['visits'] : null));
  }

  Future<void> loadAttendance() async {
    final res = await _api.getMrAttendance();
    final data = res.data;
    state = state.copyWith(
      attendance: _list(data is Map ? data['attendance'] : null),
    );
  }

  Future<void> loadPlans() async {
    final res = await _api.getMrTourPlans();
    final data = res.data;
    state = state.copyWith(
      tourPlans: _list(data is Map ? data['plans'] : null),
    );
  }

  Future<void> loadExpenses() async {
    final res = await _api.getMrExpenses();
    final data = res.data;
    state = state.copyWith(
      expenses: _list(data is Map ? data['expenses'] : null),
    );
  }

  Future<void> loadPob() async {
    final res = await _api.getMrPob();
    final data = res.data;
    state = state.copyWith(
      pobOrders: _list(data is Map ? data['orders'] : null),
    );
  }

  Future<void> loadTeam() async {
    final res = await _api.getMrTeam();
    final data = res.data;
    state = state.copyWith(team: _list(data is Map ? data['profiles'] : null));
  }

  Future<void> loadTerritories() async {
    final res = await _api.getMrTerritories();
    final data = res.data;
    state = state.copyWith(
      territories: _list(data is Map ? data['territories'] : null),
    );
  }

  Future<void> loadTargets() async {
    final res = await _api.getMrTargets();
    final data = res.data;
    state = state.copyWith(targets: _list(data is Map ? data['rows'] : null));
  }

  Future<void> loadSamples() async {
    final res = await _api.getMrSamples();
    final data = res.data;
    state = state.copyWith(
      sampleBalances: _list(data is Map ? data['balances'] : null),
    );
  }

  Future<void> loadDetailing() async {
    final res = await _api.getMrDetailing();
    final data = res.data;
    state = state.copyWith(
      detailing: _list(data is Map ? data['content'] : null),
    );
  }

  Future<void> punchIn({String workType = 'field', String? notes}) async {
    final geo = await FieldLocationService.currentPayload();
    await _api.mrPunchIn({
      ...geo,
      'workType': workType,
      if (notes != null) 'notes': notes,
    });
    await Future.wait([loadAttendance(), loadDashboard()]);
  }

  Future<void> punchOut() async {
    final geo = await FieldLocationService.currentPayload();
    await _api.mrPunchOut(geo);
    await Future.wait([loadAttendance(), loadDashboard()]);
  }

  Future<void> createVisit(String accountId, {String callType = 'solo'}) async {
    await _api.createMrVisit({'accountId': accountId, 'callType': callType});
    await loadVisits();
  }

  Future<void> checkInVisit(String visitId) async {
    final geo = await FieldLocationService.currentPayload();
    await _api.mrVisitCheckIn(visitId, geo);
    await Future.wait([loadVisits(), loadDashboard()]);
  }

  Future<void> checkOutVisit(
    String visitId, {
    String? discussionNotes,
    String? doctorFeedback,
    String? nextVisitDate,
    List<Map<String, dynamic>>? productsDiscussed,
    List<Map<String, dynamic>>? samples,
    List<Map<String, dynamic>>? gifts,
    num? pobAmount,
  }) async {
    final geo = await FieldLocationService.currentPayload();
    await _api.mrVisitCheckOut(visitId, {
      ...geo,
      if (discussionNotes != null) 'discussionNotes': discussionNotes,
      if (doctorFeedback != null) 'doctorFeedback': doctorFeedback,
      if (nextVisitDate != null) 'nextVisitDate': nextVisitDate,
      if (productsDiscussed != null) 'productsDiscussed': productsDiscussed,
      if (samples != null) 'samples': samples,
      if (gifts != null) 'gifts': gifts,
      if (pobAmount != null) 'pobAmount': pobAmount,
    });
    await Future.wait([loadVisits(), loadDashboard(), loadSamples()]);
  }

  Future<void> submitVisit(String visitId, {String? discussionNotes}) async {
    await _api.mrVisitSubmit(visitId, {
      if (discussionNotes != null) 'discussionNotes': discussionNotes,
    });
    await loadVisits();
  }

  Future<void> reviewVisit(
    String visitId,
    String decision, {
    String? comment,
  }) async {
    await _api.mrVisitReview(visitId, decision, comment: comment);
    await Future.wait([loadVisits(), loadDashboard()]);
  }

  Future<void> saveTourDay({
    required String month,
    required DateTime date,
    required String area,
    required String objective,
  }) async {
    final own = state.tourPlans.cast<Map<String, dynamic>?>().firstWhere(
      (row) => row?['month'] == month && _belongsToMe(row?['profileId']),
      orElse: () => null,
    );
    final existingDays = _list(own?['days']);
    final dateKey =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    existingDays.removeWhere((row) => '${row['date']}'.startsWith(dateKey));
    existingDays.add({
      'date': DateTime(
        date.year,
        date.month,
        date.day,
      ).toUtc().toIso8601String(),
      'area': area,
      'objective': objective,
      'accountIds': const [],
    });
    await _api.saveMrTourPlan({'month': month, 'days': existingDays});
    await loadPlans();
  }

  bool _belongsToMe(dynamic profileValue) {
    final own = ownProfileId;
    if (own == null || own.isEmpty) return true;
    if (profileValue is Map) {
      return '${profileValue['_id'] ?? profileValue['id'] ?? ''}' == own;
    }
    return '$profileValue' == own;
  }

  Future<void> submitTourPlan(String id) async {
    await _api.submitMrTourPlan(id);
    await loadPlans();
  }

  Future<void> reviewTourPlan(
    String id,
    String decision, {
    String? comment,
  }) async {
    await _api.reviewMrTourPlan(id, decision, comment: comment);
    await Future.wait([loadPlans(), loadDashboard()]);
  }

  Future<void> createExpense({
    required String category,
    required num amount,
    String? description,
  }) async {
    await _api.createMrExpense({
      'category': category,
      'amount': amount,
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
    });
    await loadExpenses();
  }

  Future<void> submitExpense(String id) async {
    await _api.submitMrExpense(id);
    await loadExpenses();
  }

  Future<void> reviewExpense(
    String id,
    String decision, {
    String? comment,
  }) async {
    await _api.reviewMrExpense(id, decision, comment: comment);
    await Future.wait([loadExpenses(), loadDashboard()]);
  }

  Future<void> createPob({
    required String accountId,
    required String productName,
    required num quantity,
    required num rate,
    String? notes,
  }) async {
    await _api.createMrPob({
      'accountId': accountId,
      'items': [
        {'productName': productName, 'quantity': quantity, 'rate': rate},
      ],
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
    await Future.wait([loadPob(), loadDashboard()]);
  }

  Future<void> setTarget({
    required String profileId,
    required String month,
    num callTarget = 0,
    num pobTarget = 0,
    num workingDaysTarget = 0,
  }) async {
    await _api.setMrTarget({
      'profileId': profileId,
      'month': month,
      'callTarget': callTarget,
      'pobTarget': pobTarget,
      'workingDaysTarget': workingDaysTarget,
    });
    await Future.wait([loadTargets(), loadDashboard(), loadAnalytics()]);
  }
}

final mrProvider = StateNotifierProvider<MrNotifier, MrState>(
  (ref) => MrNotifier(),
);
