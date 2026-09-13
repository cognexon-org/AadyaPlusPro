import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../core/network/api_service.dart';

/// Generic async state for dashboard data
class DashboardData {
  final Map<String, dynamic> stats;
  final List<Map<String, dynamic>> appointments;
  final List<Map<String, dynamic>> recentTransactions;
  final List<Map<String, dynamic>> medicines;
  final List<Map<String, dynamic>> prescriptions;
  final List<Map<String, dynamic>> invoices;
  final Map<String, dynamic> earnings;
  final Map<String, dynamic> profile;
  final bool isLoading;
  final String? error;

  const DashboardData({
    this.stats = const {},
    this.appointments = const [],
    this.recentTransactions = const [],
    this.medicines = const [],
    this.prescriptions = const [],
    this.invoices = const [],
    this.earnings = const {},
    this.profile = const {},
    this.isLoading = false,
    this.error,
  });

  DashboardData copyWith({
    Map<String, dynamic>? stats,
    List<Map<String, dynamic>>? appointments,
    List<Map<String, dynamic>>? recentTransactions,
    List<Map<String, dynamic>>? medicines,
    List<Map<String, dynamic>>? prescriptions,
    List<Map<String, dynamic>>? invoices,
    Map<String, dynamic>? earnings,
    Map<String, dynamic>? profile,
    bool? isLoading,
    String? error,
  }) {
    return DashboardData(
      stats: stats ?? this.stats,
      appointments: appointments ?? this.appointments,
      recentTransactions: recentTransactions ?? this.recentTransactions,
      medicines: medicines ?? this.medicines,
      prescriptions: prescriptions ?? this.prescriptions,
      invoices: invoices ?? this.invoices,
      earnings: earnings ?? this.earnings,
      profile: profile ?? this.profile,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// ==================== DOCTOR DASHBOARD ====================

class DoctorDashboardNotifier extends StateNotifier<DashboardData> {
  final ApiService _api = ApiService();
  DoctorDashboardNotifier() : super(const DashboardData());

  Future<void> loadDashboard() async {
    try {
      final response = await _api.getDoctorDashboard();
      final data = response.data;
      // Backend returns { success: true, stats: { ... } }
      final backendStats = data['stats'] ?? data['data'] ?? (data is Map ? data : {});
      
      final mergedStats = Map<String, dynamic>.from(state.stats);
      if (backendStats is Map) {
        mergedStats.addAll(Map<String, dynamic>.from(backendStats));
      }

      state = state.copyWith(stats: mergedStats);
    } catch (_) {}
  }

  Future<void> loadAppointments({String? status}) async {
    try {
      final params = <String, dynamic>{'limit': 1000, 'page': 1};
      if (status != null && status != 'all') params['status'] = status;
      final response = await _api.getDoctorAppointments(queryParams: params);
      final data = response.data;
      final list = _extractList(data);
      
      final now = DateTime.now();
      final totalAppointments = list.length;
      final completedAppointments = list.where((a) => a['status'] == 'completed').length;
      final pendingAppointments = list.where((a) => a['status'] == 'pending' || a['status'] == 'confirmed').length;
      
      final upcomingApps = list.where((a) {
        final dateStr = a['appointmentDate']?.toString() ?? '';
        try {
          final d = DateTime.parse(dateStr);
          return d.isAfter(now.subtract(const Duration(hours: 1))) && 
                 ['confirmed', 'accepted', 'pending'].contains(a['status']);
        } catch (_) { return false; }
      }).toList();
      
      upcomingApps.sort((a, b) {
        final da = DateTime.tryParse(a['appointmentDate']?.toString() ?? '') ?? now;
        final db = DateTime.tryParse(b['appointmentDate']?.toString() ?? '') ?? now;
        return da.compareTo(db);
      });

      final patientMap = <String, Map<String, dynamic>>{};
      for (final a in list) {
        final p = a['patientId'];
        if (p is Map && p['_id'] != null && !patientMap.containsKey(p['_id'])) {
          patientMap[p['_id']] = Map<String, dynamic>.from(p);
        }
      }

      final weeklyData = List.generate(7, (i) {
        final date = now.subtract(Duration(days: 6 - i));
        return list.where((a) {
          try {
            final d = DateTime.parse(a['appointmentDate']?.toString() ?? '');
            return d.year == date.year && d.month == date.month && d.day == date.day;
          } catch (_) { return false; }
        }).length;
      });

      // Filter to 'Upcoming' for Dashboard
      final List<Map<String, dynamic>> displayList = list.where((a) {
        final dateStr = a['appointmentDate']?.toString() ?? '';
        try {
          final d = DateTime.parse(dateStr);
          // Include today (subtract small buffer) and future
          return d.isAfter(now.subtract(const Duration(hours: 1))) && 
                 ['confirmed', 'accepted', 'pending'].contains(a['status']);
        } catch (_) { return false; }
      }).toList();

      // Update state but PRESERVE other fields by using the latest state
      final currentStats = Map<String, dynamic>.from(state.stats);
      currentStats['totalAppointments'] = totalAppointments;
      currentStats['completedAppointments'] = completedAppointments;
      currentStats['pendingAppointments'] = pendingAppointments;
      currentStats['upcomingAppointments'] = upcomingApps.length;
      currentStats['totalPatients'] = patientMap.length;
      currentStats['weeklyAppointments'] = weeklyData;

      state = state.copyWith(
        stats: currentStats,
        appointments: displayList.take(status == null ? 20 : 1000).toList(),
        recentTransactions: patientMap.values.toList(),
      );
    } catch (_) {}
  }

  Future<void> loadEarnings() async {
    try {
      final response = await _api.getCommissions(queryParams: {'limit': 1000, 'page': 1});
      final data = response.data;
      final commissions = _extractList(data);
      final totals = data is Map ? (data['totals'] ?? {}) : {};
      
      final totalEarnings = totals['totalProfessionalEarnings'] ??
          commissions.fold<num>(0, (sum, c) => sum + (c['professionalEarning'] ?? 0));

      final currentStats = Map<String, dynamic>.from(state.stats);
      currentStats['totalEarnings'] = totalEarnings;

      state = state.copyWith(
        stats: currentStats,
        earnings: {
          'totalEarnings': totalEarnings,
          'commissions': commissions,
          'totals': totals,
        },
      );
    } catch (_) {}
  }

  Future<void> loadProfile() async {
    try {
      final response = await _api.getDoctorProfile();
      final data = response.data;
      final profileData = data['doctor'] ?? data['data'] ?? data['profile'] ?? data;
      final profileMap = Map<String, dynamic>.from(profileData is Map ? profileData : {});
      
      final currentStats = Map<String, dynamic>.from(state.stats);
      if (profileMap['averageRating'] != null) {
        currentStats['averageRating'] = profileMap['averageRating'];
      }
      
      state = state.copyWith(profile: profileMap, stats: currentStats);
    } catch (_) {}
  }

  Future<void> loadAll() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      // Execute sequentially to avoid state overwrite race conditions
      await loadDashboard();
      await loadAppointments();
      await loadEarnings();
      await loadProfile();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }
}

// ==================== PHYSIO DASHBOARD ====================

class PhysioDashboardNotifier extends StateNotifier<DashboardData> {
  final ApiService _api = ApiService();
  PhysioDashboardNotifier() : super(const DashboardData());

  Future<void> loadDashboard() async {
    try {
      final response = await _api.getPhysioDashboard();
      final data = response.data;
      // Backend: { stats: {totalConsultations, totalEarnings, averageRating,
      //                    todaysAppointments, pendingAppointments, monthlyEarnings},
      //           recentAppointments: [...], profile:{name, specialization} }
      final backendStats = data['stats'] ?? data['data'] ?? data;

      final currentStats = Map<String, dynamic>.from(state.stats);
      if (backendStats is Map) {
        currentStats.addAll(Map<String, dynamic>.from(backendStats));
        // Normalize field names for home screen display
        currentStats['totalAppointments'] = backendStats['todaysAppointments'] ?? currentStats['totalAppointments'];
        currentStats['upcoming'] = backendStats['todaysAppointments'] ?? currentStats['upcoming'];
        currentStats['totalEarnings'] = backendStats['totalEarnings'] ?? currentStats['totalEarnings'];
        currentStats['earnings'] = currentStats['totalEarnings'];
      }

      List<Map<String, dynamic>> recentApts = [];
      if (data['recentAppointments'] is List) {
        recentApts = _extractList(data['recentAppointments']);
      }

      state = state.copyWith(
        stats: currentStats,
        appointments: recentApts.isNotEmpty ? recentApts : state.appointments,
      );
    } catch (_) {}
  }


  Future<void> loadAppointments({String? status}) async {
    try {
      final params = <String, dynamic>{'limit': 100};
      if (status != null && status != 'all') params['status'] = status;
      final response = await _api.getPhysioAppointments(queryParams: params);
      final data = response.data;
      final list = _extractList(data);
      
      state = state.copyWith(appointments: list);
    } catch (_) {}
  }

  Future<void> loadPatients() async {
    try {
      final response = await _api.getPhysioPatients();
      final data = response.data;
      // Backend: { success: true, patients: [...] }
      final list = data is Map
          ? _extractList(data['patients'] ?? data)
          : _extractList(data);
      state = state.copyWith(recentTransactions: list);
    } catch (_) {}
  }

  Future<void> loadEarnings() async {
    try {
      final response = await _api.getCommissions(queryParams: {'limit': 1000, 'page': 1});
      final data = response.data;
      final commissions = _extractList(data);
      final totals = data is Map ? (data['totals'] ?? {}) : {};
      
      final totalEarnings = totals['totalProfessionalEarnings'] ??
          commissions.fold<num>(0, (sum, c) => sum + (c['professionalEarning'] ?? 0));

      final currentStats = Map<String, dynamic>.from(state.stats);
      currentStats['totalEarnings'] = totalEarnings;

      state = state.copyWith(
        stats: currentStats,
        earnings: {
          'totalEarnings': totalEarnings,
          'commissions': commissions,
          'totals': totals,
          'transactions': commissions, // For backwards compatibility with physio_earnings expected shape
        },
      );
    } catch (_) {}
  }

  Future<void> loadProfile() async {
    try {
      final response = await _api.getPhysioProfile();
      final data = response.data;
      final profileData = data['physio'] ?? data['data'] ?? data['profile'] ?? data;
      state = state.copyWith(profile: Map<String, dynamic>.from(profileData is Map ? profileData : {}));
    } catch (_) {}
  }

  Future<bool> updateProfile(Map<String, dynamic> data) async {
    try {
      final response = await _api.updatePhysioProfile(data);
      if (response.data['success'] == true) {
        final profileData = response.data['physio'] ?? response.data['data'] ?? response.data['profile'] ?? response.data;
        state = state.copyWith(profile: Map<String, dynamic>.from(profileData is Map ? profileData : {}));
        return true;
      }
      return false;
    } catch (e) {
      print('Update profile error: $e');
      return false;
    }
  }

  Future<void> loadExercises() async {
    try {
      // The remote backend does not have the /physio/exercises route yet.
      // Mocking the exercise library to prevent HTTP 400 'Invalid physiotherapist id'
      await Future.delayed(const Duration(milliseconds: 300));
      final mockData = [
        {'_id': '1', 'name': 'Squats', 'category': 'Strength Training', 'difficulty': 'Beginner', 'sets': 3, 'reps': 12, 'description': 'Basic lower body exercise'},
        {'_id': '2', 'name': 'Lunges', 'category': 'Balance', 'difficulty': 'Intermediate', 'sets': 3, 'reps': 10, 'description': 'Improves balance and leg strength'},
        {'_id': '3', 'name': 'Plank', 'category': 'Core', 'difficulty': 'Beginner', 'sets': 3, 'reps': 1, 'description': 'Static core exercise'},
        {'_id': '4', 'name': 'Pelvic Tilts', 'category': 'Rehabilitation', 'difficulty': 'Beginner', 'sets': 3, 'reps': 15, 'description': 'Great for lower back pain'},
      ];
      state = state.copyWith(medicines: mockData); // Reuse medicines field for exercises
    } catch (_) {}
  }

  Future<void> loadAll() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await loadDashboard();
      await loadAppointments();
      await loadPatients();
      await loadEarnings();
      await loadProfile();
      await loadExercises();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }
}

// ==================== PATHOLOGY DASHBOARD ====================

class PathologyDashboardNotifier extends StateNotifier<DashboardData> {
  final ApiService _api = ApiService();
  PathologyDashboardNotifier() : super(const DashboardData());

  Future<void> loadDashboard() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _api.getPathologyDashboard();
      final data = response.data;
      // Backend: { stats: { monthly: {totalTests, totalRevenue, pendingTests, completedTests},
      //                     weekly: {...}, today: {...} },
      //           profile: { labName, averageRating, totalTestsConducted, homeCollectionAvailable },
      //           recentTests: [...], upcomingTests: [...] }
      final statsNested = data['stats'] ?? {};
      final monthly = statsNested['monthly'] ?? {};
      final today = statsNested['today'] ?? {};
      final profileData = data['profile'] ?? {};

      final mergedStats = Map<String, dynamic>.from(state.stats);
      mergedStats['totalTests'] = profileData['totalTestsConducted'] ?? monthly['totalTests'] ?? 0;
      mergedStats['totalEarnings'] = monthly['totalRevenue'] ?? 0;
      mergedStats['pendingTests'] = monthly['pendingTests'] ?? today['pendingTests'] ?? 0;
      mergedStats['completedTests'] = monthly['completedTests'] ?? 0;
      mergedStats['homeCollections'] = profileData['homeCollectionAvailable'] == true ? 1 : 0;
      mergedStats['averageRating'] = profileData['averageRating'] ?? 0;
      mergedStats['labName'] = profileData['labName'] ?? '';
      // For home screen chart - today's count
      mergedStats['todayTests'] = today['totalTests'] ?? 0;

      // Seed appointments from recentTests if available
      List<Map<String, dynamic>> recentTests = [];
      if (data['recentTests'] is List) {
        recentTests = _extractList(data['recentTests']);
      }

      state = state.copyWith(
        stats: mergedStats,
        appointments: recentTests.isNotEmpty ? recentTests : state.appointments,
        isLoading: false,
      );
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: _extractError(e));
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadTests() async {
    try {
      final response = await _api.getPathologyTests();
      final data = response.data;
      // Backend: { success, labTests: [...], pagination: {...} }
      final list = data is Map
          ? _extractList(data['labTests'] ?? data['tests'] ?? data)
          : _extractList(data);

      final currentStats = Map<String, dynamic>.from(state.stats);
      if (list.isNotEmpty) {
        currentStats['totalTests'] = currentStats['totalTests'] ?? list.length;
        final pending = list.where((t) => ['requested', 'scheduled', 'sample_collected', 'processing'].contains(t['status'])).length;
        final homeCollections = list.where((t) => t['type'] == 'home').length;
        currentStats['pendingTests'] = currentStats['pendingTests'] ?? pending;
        currentStats['homeCollections'] = currentStats['homeCollections'] ?? homeCollections;
      }

      state = state.copyWith(recentTransactions: list, stats: currentStats);
    } on DioException catch (e) {
      state = state.copyWith(error: _extractError(e));
    } catch (_) {}
  }

  Future<void> loadAppointments({String? status}) async {
    try {
      final params = <String, dynamic>{};
      if (status != null && status != 'all') params['status'] = status;
      final response = await _api.getPathologyAppointments(queryParams: params);
      final data = response.data;
      // Backend: { success, appointments: [...] }
      final list = data is Map
          ? _extractList(data['appointments'] ?? data)
          : _extractList(data);
      state = state.copyWith(appointments: list);
    } on DioException catch (e) {
      state = state.copyWith(error: _extractError(e));
    } catch (_) {}
  }

  Future<void> loadProfile() async {
    try {
      final response = await _api.getPathologyProfile();
      final data = response.data;
      // Backend: { success, profile: {...} }
      final profileData = data['profile'] ?? data['data'] ?? data;
      final profileMap = Map<String, dynamic>.from(profileData is Map ? profileData : {});

      // Merge useful profile fields into stats
      final currentStats = Map<String, dynamic>.from(state.stats);
      if (profileMap['totalTestsConducted'] != null) currentStats['totalTests'] = profileMap['totalTestsConducted'];
      if (profileMap['totalEarnings'] != null) currentStats['totalEarnings'] = profileMap['totalEarnings'];
      if (profileMap['averageRating'] != null) currentStats['averageRating'] = profileMap['averageRating'];

      state = state.copyWith(profile: profileMap, stats: currentStats);
    } on DioException catch (e) {
      state = state.copyWith(error: _extractError(e));
    } catch (_) {}
  }

  Future<void> loadEarnings() async {
    try {
      final response = await _api.getCommissions(queryParams: {'limit': 1000, 'page': 1});
      final data = response.data;
      final commissions = _extractList(data);
      final totals = data is Map ? (data['totals'] ?? {}) : {};
      
      final totalEarnings = totals['totalProfessionalEarnings'] ??
          commissions.fold<num>(0, (sum, c) => sum + (c['professionalEarning'] ?? 0));

      final currentStats = Map<String, dynamic>.from(state.stats);
      currentStats['totalEarnings'] = totalEarnings;

      state = state.copyWith(
        stats: currentStats,
        earnings: {
          'totalEarnings': totalEarnings,
          'commissions': commissions,
          'totals': totals,
        },
      );
    } catch (_) {}
  }

  Future<void> loadAll() async {
    state = state.copyWith(isLoading: true);
    await Future.wait([
      loadDashboard(),
      loadTests(),
      loadAppointments(),
      loadProfile(),
      loadEarnings(),
    ]);
    state = state.copyWith(isLoading: false);
  }
}

// ==================== PHARMACY DASHBOARD ====================

class PharmacyDashboardNotifier extends StateNotifier<DashboardData> {
  final ApiService _api = ApiService();
  PharmacyDashboardNotifier() : super(const DashboardData());

  Future<void> loadProfile() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _api.getPharmacyProfile();
      final data = response.data;
      final profileData = data['pharmacy'] ?? data['data'] ?? data['profile'] ?? data;
      state = state.copyWith(
        profile: Map<String, dynamic>.from(profileData is Map ? profileData : {}),
        isLoading: false,
      );
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: _extractError(e));
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadSales() async {
    try {
      final response = await _api.getPharmacySales(queryParams: {'limit': 100});
      final data = response.data;
      final sales = _extractList(data['sales'] ?? data);
      
      final totals = data['totals'] ?? {};
      final currentStats = Map<String, dynamic>.from(state.stats);
      currentStats['totalSales'] = totals['totalSales'] ?? 0;
      currentStats['salesCount'] = totals['count'] ?? sales.length;

      state = state.copyWith(recentTransactions: sales, stats: currentStats);
    } catch (_) {}
  }

  Future<void> loadMedicines() async {
    try {
      final response = await _api.getMedicines(queryParams: {'limit': 1000});
      final data = response.data;
      state = state.copyWith(medicines: _extractList(data['medicines'] ?? data));
    } catch (_) {}
  }

  Future<void> loadPrescriptions() async {
    try {
      final response = await _api.getPrescriptions(queryParams: {'limit': 50});
      final data = response.data;
      state = state.copyWith(prescriptions: _extractList(data['prescriptions'] ?? data));
    } catch (_) {}
  }

  Future<void> loadInvoices() async {
    try {
      final response = await _api.getInvoices(queryParams: {'limit': 20});
      final data = response.data;
      state = state.copyWith(invoices: _extractList(data['invoices'] ?? data));
    } catch (_) {}
  }

  Future<void> loadLowStock() async {
    try {
      final response = await _api.getLowStockMedicines();
      final data = response.data;
      final list = _extractList(data['medicines'] ?? data);
      
      final currentStats = Map<String, dynamic>.from(state.stats);
      currentStats['lowStockCount'] = list.length;
      
      state = state.copyWith(stats: currentStats);
    } catch (_) {}
  }

  Future<void> loadExpiring() async {
    try {
      final response = await _api.getExpiringMedicines();
      final data = response.data;
      // You can store this in a separate field if needed, for now just for stats
      final list = _extractList(data['medicines'] ?? data);
      
      final currentStats = Map<String, dynamic>.from(state.stats);
      currentStats['expiringCount'] = list.length;
      
      state = state.copyWith(stats: currentStats);
    } catch (_) {}
  }

  Future<void> loadEarnings() async {
    try {
      final response = await _api.getPharmacySalesReport(queryParams: {'groupBy': 'month'});
      final data = response.data;
      
      state = state.copyWith(
        earnings: {
          'report': data['report'] ?? [],
          'topCustomers': data['topCustomers'] ?? [],
        },
      );
    } catch (_) {}
  }

  Future<void> loadAll() async {
    state = state.copyWith(isLoading: true);
    await Future.wait([
      loadProfile(),
      loadSales(),
      loadMedicines(),
      loadPrescriptions(),
      loadInvoices(),
      loadLowStock(),
      loadExpiring(),
      loadEarnings(),
    ]);
    state = state.copyWith(isLoading: false);
  }
}

// ==================== APPOINTMENT ACTIONS ====================

class AppointmentActionsNotifier extends StateNotifier<AsyncValue<void>> {
  final ApiService _api = ApiService();
  AppointmentActionsNotifier() : super(const AsyncValue.data(null));

  Future<bool> updateStatus(String appointmentId, String status) async {
    state = const AsyncValue.loading();
    try {
      await _api.updateAppointmentStatus(appointmentId, status);
      state = const AsyncValue.data(null);
      return true;
    } on DioException catch (e) {
      state = AsyncValue.error(_extractError(e), StackTrace.current);
      return false;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  Future<bool> cancel(String appointmentId, {String? reason}) async {
    state = const AsyncValue.loading();
    try {
      await _api.cancelAppointment(appointmentId, reason: reason);
      state = const AsyncValue.data(null);
      return true;
    } on DioException catch (e) {
      state = AsyncValue.error(_extractError(e), StackTrace.current);
      return false;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  Future<bool> complete(String appointmentId) async {
    state = const AsyncValue.loading();
    try {
      await _api.completeAppointment(appointmentId);
      state = const AsyncValue.data(null);
      return true;
    } on DioException catch (e) {
      state = AsyncValue.error(_extractError(e), StackTrace.current);
      return false;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}

// ==================== PROVIDERS ====================

final doctorDashboardProvider = StateNotifierProvider<DoctorDashboardNotifier, DashboardData>(
  (ref) => DoctorDashboardNotifier(),
);

final physioDashboardProvider = StateNotifierProvider<PhysioDashboardNotifier, DashboardData>(
  (ref) => PhysioDashboardNotifier(),
);

final pathologyDashboardProvider = StateNotifierProvider<PathologyDashboardNotifier, DashboardData>(
  (ref) => PathologyDashboardNotifier(),
);

final pharmacyDashboardProvider = StateNotifierProvider<PharmacyDashboardNotifier, DashboardData>(
  (ref) => PharmacyDashboardNotifier(),
);

final appointmentActionsProvider = StateNotifierProvider<AppointmentActionsNotifier, AsyncValue<void>>(
  (ref) => AppointmentActionsNotifier(),
);

// ==================== HELPERS ====================

String _extractError(DioException e) {
  if (e.response?.data != null) {
    final data = e.response!.data;
    if (data is Map) return data['message'] ?? data['error'] ?? 'Request failed';
    if (data is String) return data;
  }
  return e.message ?? 'Something went wrong';
}

List<Map<String, dynamic>> _extractList(dynamic data) {
  if (data == null) return [];
  if (data is List) return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  if (data is Map) {
    // Try common keys in order of priority
    for (final key in [
      'data', 'appointments', 'patients', 'tests', 'labTests', 'orders', 'commissions',
      'results', 'sales', 'medicines', 'invoices', 'prescriptions', 'batches',
      'exercises', 'labTests', 'items'
    ]) {
      if (data[key] is List) {
        return (data[key] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    }
  }
  return [];
}
