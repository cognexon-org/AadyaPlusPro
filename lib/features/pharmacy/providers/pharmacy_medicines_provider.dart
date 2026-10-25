import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_service.dart';
import 'pharmacy_store_provider.dart';

enum MedFilter { all, lowStock, expiring }

class MedicineDetailData {
  final Map<String, dynamic> medicine;
  final List<dynamic> batches;
  final List<dynamic> adjustments;
  final bool isLoading;
  final bool isRefreshing;
  final bool hasLoadedBatches;
  final String? error;

  const MedicineDetailData({
    this.medicine = const {},
    this.batches = const [],
    this.adjustments = const [],
    this.isLoading = false,
    this.isRefreshing = false,
    this.hasLoadedBatches = false,
    this.error,
  });

  MedicineDetailData copyWith({
    Map<String, dynamic>? medicine,
    List<dynamic>? batches,
    List<dynamic>? adjustments,
    bool? isLoading,
    bool? isRefreshing,
    bool? hasLoadedBatches,
    String? error,
    bool clearError = false,
  }) {
    return MedicineDetailData(
      medicine: medicine ?? this.medicine,
      batches: batches ?? this.batches,
      adjustments: adjustments ?? this.adjustments,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      hasLoadedBatches: hasLoadedBatches ?? this.hasLoadedBatches,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class PharmacyMedicinesState {
  final List<Map<String, dynamic>> items;
  final bool isLoading;
  final bool isRefreshing;
  final String? error;
  final String searchQuery;
  final MedFilter filter;
  final String? loadedStoreId;
  final Map<String, MedicineDetailData> detailsCache;

  const PharmacyMedicinesState({
    this.items = const [],
    this.isLoading = false,
    this.isRefreshing = false,
    this.error,
    this.searchQuery = '',
    this.filter = MedFilter.all,
    this.loadedStoreId,
    this.detailsCache = const {},
  });

  PharmacyMedicinesState copyWith({
    List<Map<String, dynamic>>? items,
    bool? isLoading,
    bool? isRefreshing,
    String? error,
    bool clearError = false,
    String? searchQuery,
    MedFilter? filter,
    String? loadedStoreId,
    bool clearLoadedStore = false,
    Map<String, MedicineDetailData>? detailsCache,
  }) {
    return PharmacyMedicinesState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      error: clearError ? null : (error ?? this.error),
      searchQuery: searchQuery ?? this.searchQuery,
      filter: filter ?? this.filter,
      loadedStoreId: clearLoadedStore
          ? null
          : (loadedStoreId ?? this.loadedStoreId),
      detailsCache: detailsCache ?? this.detailsCache,
    );
  }

  static bool isLow(Map<String, dynamic> item) {
    final qty =
        num.tryParse(
          (item['quantity'] ?? item['stock_quantity'] ?? 0).toString(),
        ) ??
        0;
    final reorder =
        num.tryParse(
          (item['reorderLevel'] ?? item['reorder_level'] ?? 0).toString(),
        ) ??
        0;
    return qty <= reorder;
  }

  static bool isExpiring(Map<String, dynamic> item) {
    final expiry = DateTime.tryParse(
      '${item['nearestExpiryDate'] ?? item['expiryDate'] ?? ''}',
    );
    if (expiry == null) return false;
    return expiry.difference(DateTime.now()).inDays <= 30;
  }

  List<Map<String, dynamic>> get filteredItems {
    switch (filter) {
      case MedFilter.lowStock:
        return items.where(isLow).toList();
      case MedFilter.expiring:
        return items.where(isExpiring).toList();
      case MedFilter.all:
        return items;
    }
  }

  int get lowStockCount => items.where(isLow).length;
  int get expiringCount => items.where(isExpiring).length;
}

class PharmacyMedicinesNotifier extends StateNotifier<PharmacyMedicinesState> {
  final Ref _ref;
  final ApiService _api = ApiService();

  PharmacyMedicinesNotifier(this._ref) : super(const PharmacyMedicinesState());

  Future<void> initialize({bool force = false}) async {
    final currentStoreId = _ref.read(pharmacyStoreProvider).selectedStoreId;
    if (currentStoreId == null) return;
    if (!force &&
        state.loadedStoreId == currentStoreId &&
        state.items.isNotEmpty) {
      return;
    }
    await loadMedicines(storeId: currentStoreId);
  }

  /// Drops a search response that a newer keystroke has superseded.
  int _requestSeq = 0;

  Future<void> loadMedicines({
    bool silent = false,
    String? search,
    String? storeId,
  }) async {
    final targetStoreId =
        storeId ?? _ref.read(pharmacyStoreProvider).selectedStoreId;
    if (targetStoreId == null) return;
    final seq = ++_requestSeq;

    final effectiveSearch = search ?? state.searchQuery;

    if (silent || state.items.isNotEmpty) {
      state = state.copyWith(isRefreshing: true, clearError: true);
    } else {
      state = state.copyWith(isLoading: true, clearError: true);
    }

    try {
      final response = await _api.getMedicines(
        queryParams: {
          'limit': 200,
          if (effectiveSearch.trim().isNotEmpty)
            'search': effectiveSearch.trim(),
        },
      );
      if (seq != _requestSeq || !mounted) return;
      final data = response.data;
      final list = data is Map ? data['medicines'] : data;
      state = state.copyWith(
        items: _maps(list),
        loadedStoreId: targetStoreId,
        isLoading: false,
        isRefreshing: false,
        searchQuery: effectiveSearch,
      );
    } on DioException catch (e) {
      if (seq != _requestSeq || !mounted) return;
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        error: _message(e),
      );
    } catch (e) {
      if (seq != _requestSeq || !mounted) return;
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        error: e.toString(),
      );
    }
  }

  Future<void> loadMedicineDetails(
    String medicineId, {
    bool force = false,
    Map<String, dynamic>? initialMedicine,
  }) async {
    final existing = state.detailsCache[medicineId];

    if (existing != null && !force && existing.hasLoadedBatches) {
      // Data and batches are already loaded in cache.
      // Silently refresh in background without altering loading flags or flashing skeletons.
      _silentRefreshMedicineDetails(medicineId);
      return;
    }

    Map<String, dynamic>? initial = initialMedicine;
    if (initial == null || initial.isEmpty) {
      for (final m in state.items) {
        if (m['_id']?.toString() == medicineId) {
          initial = m;
          break;
        }
      }
    }

    if (existing != null && !force && existing.medicine.isNotEmpty) {
      state = state.copyWith(
        detailsCache: {
          ...state.detailsCache,
          medicineId: existing.copyWith(
            isRefreshing: true,
            clearError: true,
            hasLoadedBatches: existing.hasLoadedBatches,
          ),
        },
      );
    } else {
      final newDetail = MedicineDetailData(
        medicine: initial != null
            ? Map<String, dynamic>.from(initial)
            : const {},
        batches: existing?.batches ?? const [],
        adjustments: existing?.adjustments ?? const [],
        isLoading: initial == null,
        isRefreshing: initial != null,
        hasLoadedBatches: existing?.hasLoadedBatches ?? false,
      );

      state = state.copyWith(
        detailsCache: {...state.detailsCache, medicineId: newDetail},
      );
    }

    try {
      final response = await _api.getMedicineById(medicineId);
      final data = response.data;
      final rawMed = data is Map && data['medicine'] is Map
          ? Map<String, dynamic>.from(data['medicine'] as Map)
          : <String, dynamic>{};
      final rawBatches = data is Map && data['batches'] is List
          ? data['batches'] as List
          : const [];
      final rawAdjustments = data is Map && data['adjustments'] is List
          ? data['adjustments'] as List
          : const [];

      final current = state.detailsCache[medicineId];
      final updatedDetail = MedicineDetailData(
        medicine: rawMed.isNotEmpty ? rawMed : (current?.medicine ?? const {}),
        batches: rawBatches,
        adjustments: rawAdjustments,
        isLoading: false,
        isRefreshing: false,
        hasLoadedBatches: true,
      );

      state = state.copyWith(
        detailsCache: {...state.detailsCache, medicineId: updatedDetail},
      );

      if (rawMed.isNotEmpty) {
        upsertMedicine(rawMed);
      }
    } on DioException catch (e) {
      final current = state.detailsCache[medicineId];
      if (current != null) {
        state = state.copyWith(
          detailsCache: {
            ...state.detailsCache,
            medicineId: current.copyWith(
              isLoading: false,
              isRefreshing: false,
              hasLoadedBatches: true,
              error: _message(e),
            ),
          },
        );
      }
    } catch (e) {
      final current = state.detailsCache[medicineId];
      if (current != null) {
        state = state.copyWith(
          detailsCache: {
            ...state.detailsCache,
            medicineId: current.copyWith(
              isLoading: false,
              isRefreshing: false,
              hasLoadedBatches: true,
              error: e.toString(),
            ),
          },
        );
      }
    }
  }

  Future<void> _silentRefreshMedicineDetails(String medicineId) async {
    try {
      final response = await _api.getMedicineById(medicineId);
      final data = response.data;
      final rawMed = data is Map && data['medicine'] is Map
          ? Map<String, dynamic>.from(data['medicine'] as Map)
          : <String, dynamic>{};
      final rawBatches = data is Map && data['batches'] is List
          ? data['batches'] as List
          : const [];
      final rawAdjustments = data is Map && data['adjustments'] is List
          ? data['adjustments'] as List
          : const [];

      final current = state.detailsCache[medicineId];
      if (current != null) {
        state = state.copyWith(
          detailsCache: {
            ...state.detailsCache,
            medicineId: current.copyWith(
              medicine: rawMed.isNotEmpty ? rawMed : current.medicine,
              batches: rawBatches,
              adjustments: rawAdjustments,
              hasLoadedBatches: true,
            ),
          },
        );
      }
      if (rawMed.isNotEmpty) {
        upsertMedicine(rawMed);
      }
    } catch (_) {}
  }

  void setFilter(MedFilter filter) {
    if (state.filter == filter) return;
    state = state.copyWith(filter: filter);
  }

  /// Narrows the list on the phone at once (name, generic or barcode), then
  /// replaces it with the server's matches. With nothing local to show, the
  /// skeleton shows rather than "No medicines match".
  Future<void> setSearch(String query) async {
    final q = query.trim().toLowerCase();
    final narrowed = q.isEmpty
        ? state.items
        : state.items.where((m) {
            return [
              m['medicineName'],
              m['genericName'],
              m['brandName'],
              m['barcode'],
            ].any((v) => '${v ?? ''}'.toLowerCase().contains(q));
          }).toList();
    state = state.copyWith(
      searchQuery: query,
      items: narrowed,
      isLoading: narrowed.isEmpty,
      isRefreshing: narrowed.isNotEmpty,
    );
    await loadMedicines(search: query, silent: narrowed.isNotEmpty);
  }

  void upsertMedicine(Map<String, dynamic> medicine) {
    final id = medicine['_id']?.toString();
    if (id == null || id.isEmpty) return;

    final updated = List<Map<String, dynamic>>.from(state.items);
    final idx = updated.indexWhere((m) => m['_id']?.toString() == id);
    if (idx >= 0) {
      updated[idx] = Map<String, dynamic>.from(medicine);
    } else {
      updated.insert(0, Map<String, dynamic>.from(medicine));
    }

    final newDetails = Map<String, MedicineDetailData>.from(state.detailsCache);
    if (newDetails.containsKey(id)) {
      newDetails[id] = newDetails[id]!.copyWith(
        medicine: Map<String, dynamic>.from(medicine),
      );
    }

    state = state.copyWith(items: updated, detailsCache: newDetails);
  }

  void removeMedicine(String medicineId) {
    final updated = state.items
        .where((m) => m['_id']?.toString() != medicineId)
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    final newDetails = Map<String, MedicineDetailData>.from(state.detailsCache)
      ..remove(medicineId);
    state = state.copyWith(items: updated, detailsCache: newDetails);
  }

  void onStoreChanged(String newStoreId) {
    if (state.loadedStoreId == newStoreId) return;
    state = state.copyWith(
      items: const [],
      detailsCache: const {},
      clearLoadedStore: true,
      clearError: true,
      searchQuery: '',
      filter: MedFilter.all,
    );
    loadMedicines(storeId: newStoreId);
  }

  static List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

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

final pharmacyMedicinesProvider =
    StateNotifierProvider<PharmacyMedicinesNotifier, PharmacyMedicinesState>((
      ref,
    ) {
      final notifier = PharmacyMedicinesNotifier(ref);
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
