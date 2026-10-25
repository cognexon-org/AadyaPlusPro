import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_service.dart';
import 'pharmacy_store_provider.dart';

class PharmacyProcurementState {
  final List<Map<String, dynamic>> suppliers;
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> grns;
  final List<Map<String, dynamic>> medicines;
  final bool isLoading;
  final bool isRefreshing;
  final String? error;
  final String? loadedStoreId;

  const PharmacyProcurementState({
    this.suppliers = const [],
    this.orders = const [],
    this.grns = const [],
    this.medicines = const [],
    this.isLoading = false,
    this.isRefreshing = false,
    this.error,
    this.loadedStoreId,
  });

  bool get isEmpty => suppliers.isEmpty && orders.isEmpty && grns.isEmpty;

  PharmacyProcurementState copyWith({
    List<Map<String, dynamic>>? suppliers,
    List<Map<String, dynamic>>? orders,
    List<Map<String, dynamic>>? grns,
    List<Map<String, dynamic>>? medicines,
    bool? isLoading,
    bool? isRefreshing,
    String? error,
    bool clearError = false,
    String? loadedStoreId,
    bool clearLoadedStore = false,
  }) {
    return PharmacyProcurementState(
      suppliers: suppliers ?? this.suppliers,
      orders: orders ?? this.orders,
      grns: grns ?? this.grns,
      medicines: medicines ?? this.medicines,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      error: clearError ? null : (error ?? this.error),
      loadedStoreId: clearLoadedStore
          ? null
          : (loadedStoreId ?? this.loadedStoreId),
    );
  }
}

class PharmacyProcurementNotifier
    extends StateNotifier<PharmacyProcurementState> {
  final Ref _ref;
  final ApiService _api = ApiService();

  PharmacyProcurementNotifier(this._ref)
    : super(const PharmacyProcurementState());

  Future<void> initialize({bool force = false}) async {
    final currentStoreId = _ref.read(pharmacyStoreProvider).selectedStoreId;
    if (currentStoreId == null) return;
    if (!force && state.loadedStoreId == currentStoreId && !state.isEmpty) {
      return;
    }
    await loadProcurement(storeId: currentStoreId);
  }

  Future<void> loadProcurement({
    bool silent = false,
    bool force = false,
    String? storeId,
  }) async {
    final targetStoreId =
        storeId ?? _ref.read(pharmacyStoreProvider).selectedStoreId;
    if (targetStoreId == null) return;

    if (!state.isEmpty && !force) {
      state = state.copyWith(isRefreshing: true, clearError: true);
    } else if (silent || !state.isEmpty) {
      state = state.copyWith(isRefreshing: true, clearError: true);
    } else {
      state = state.copyWith(isLoading: true, clearError: true);
    }

    try {
      final r = await Future.wait([
        _api.getSuppliers(queryParams: {'limit': 100}),
        _api.getPurchaseOrders(queryParams: {'limit': 100}),
        _api.getGoodsReceipts(),
        _api.getMedicines(queryParams: {'limit': 200, 'isActive': 'true'}),
      ]);

      final suppliers = _list(r[0].data, 'suppliers');
      var orders = _list(r[1].data, 'purchaseOrders');
      if (orders.isEmpty) orders = _list(r[1].data, 'orders');
      final grns = _list(r[2].data, 'grns');
      final medicines = _list(r[3].data, 'medicines');

      state = state.copyWith(
        suppliers: suppliers,
        orders: orders,
        grns: grns,
        medicines: medicines,
        loadedStoreId: targetStoreId,
        isLoading: false,
        isRefreshing: false,
      );
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        error: _message(e),
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        error: e.toString(),
      );
    }
  }

  Future<void> createSupplier(Map<String, dynamic> data) async {
    await _api.createSupplier(data);
    await loadProcurement(silent: true, force: true);
  }

  Future<void> createPurchaseOrder(Map<String, dynamic> data) async {
    await _api.createPurchaseOrder(data);
    await loadProcurement(silent: true, force: true);
  }

  Future<void> approvePurchaseOrder(String id) async {
    await _api.approvePurchaseOrder(id);
    await loadProcurement(silent: true, force: true);
  }

  Future<void> markPurchaseOrderOrdered(String id) async {
    await _api.markPurchaseOrderOrdered(id);
    await loadProcurement(silent: true, force: true);
  }

  Future<void> receivePurchaseOrder(
    String id,
    Map<String, dynamic> data,
  ) async {
    await _api.receivePurchaseOrder(id, data);
    await loadProcurement(silent: true, force: true);
  }

  Future<void> cancelPurchaseOrder(String id) async {
    await _api.cancelPurchaseOrder(id);
    await loadProcurement(silent: true, force: true);
  }

  Future<void> recordPurchasePayment(String id, num amount) async {
    await _api.recordPurchasePayment(id, amount);
    await loadProcurement(silent: true, force: true);
  }

  void onStoreChanged(String newStoreId) {
    if (state.loadedStoreId == newStoreId) return;
    state = state.copyWith(
      suppliers: const [],
      orders: const [],
      grns: const [],
      medicines: const [],
      clearLoadedStore: true,
      clearError: true,
    );
    loadProcurement(storeId: newStoreId);
  }

  static List<Map<String, dynamic>> _list(dynamic data, String key) {
    if (data is Map && data[key] is List) {
      return (data[key] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  static String _message(DioException e) {
    final d = e.response?.data;
    if (d is Map) {
      return d['message']?.toString() ??
          d['error']?.toString() ??
          'Request failed';
    }
    return e.message ?? 'Request failed';
  }
}

final pharmacyProcurementProvider =
    StateNotifierProvider<
      PharmacyProcurementNotifier,
      PharmacyProcurementState
    >((ref) {
      final notifier = PharmacyProcurementNotifier(ref);
      ref.listen<String?>(
        pharmacyStoreProvider.select((s) => s.selectedStoreId),
        (previous, next) {
          if (previous != next && next != null) {
            notifier.onStoreChanged(next);
          }
        },
      );
      return notifier;
    });
