import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_service.dart';
import 'pharmacy_store_provider.dart';

class PharmacyOrdersState {
  final List<Map<String, dynamic>> orders;
  final bool isLoading;
  final bool isRefreshing;
  final String? error;
  final String? filter;
  final String searchQuery;
  final String? loadedStoreId;
  final Set<String> busyOrderIds;

  final List<Map<String, dynamic>> prescriptionQueue;
  final bool isQueueLoading;
  final bool isQueueRefreshing;
  final String? queueError;
  final Map<String, Map<String, dynamic>> orderDetailsCache;

  /// The latest unfiltered list (no search), from the live poll or an "All"
  /// load. A chip filters this on the phone so the result shows instantly,
  /// while the server fetch confirms it in the background.
  final List<Map<String, dynamic>> allOrders;

  /// A filter or search fetch is in flight behind what is on screen. Drives
  /// the thin progress bar, so a stale-looking list never reads as final.
  final bool isSwitching;

  /// Orders the store has not accepted or rejected yet, newest first. Kept
  /// fresh by the live poll regardless of the filter on the Orders screen,
  /// because Home and the tab badge show it.
  final List<Map<String, dynamic>> awaitingOrders;

  /// Bumped each time the poll sees an order that was not waiting before.
  /// The shell listens to this to ring and show the new-order banner.
  final int arrivalTick;
  final Map<String, dynamic>? lastArrival;

  /// Every order that arrived in the latest tick, newest first. Three test
  /// orders landing in one poll used to announce only the first.
  final List<Map<String, dynamic>> lastArrivals;

  const PharmacyOrdersState({
    this.orders = const [],
    this.isLoading = false,
    this.isRefreshing = false,
    this.error,
    this.filter,
    this.searchQuery = '',
    this.loadedStoreId,
    this.busyOrderIds = const {},
    this.prescriptionQueue = const [],
    this.isQueueLoading = false,
    this.isQueueRefreshing = false,
    this.queueError,
    this.orderDetailsCache = const {},
    this.allOrders = const [],
    this.isSwitching = false,
    this.awaitingOrders = const [],
    this.arrivalTick = 0,
    this.lastArrival,
    this.lastArrivals = const [],
  });

  PharmacyOrdersState copyWith({
    List<Map<String, dynamic>>? orders,
    bool? isLoading,
    bool? isRefreshing,
    String? error,
    bool clearError = false,
    String? filter,
    bool clearFilter = false,
    String? searchQuery,
    String? loadedStoreId,
    bool clearLoadedStore = false,
    Set<String>? busyOrderIds,
    List<Map<String, dynamic>>? prescriptionQueue,
    bool? isQueueLoading,
    bool? isQueueRefreshing,
    String? queueError,
    bool clearQueueError = false,
    Map<String, Map<String, dynamic>>? orderDetailsCache,
    List<Map<String, dynamic>>? allOrders,
    bool? isSwitching,
    List<Map<String, dynamic>>? awaitingOrders,
    int? arrivalTick,
    Map<String, dynamic>? lastArrival,
    List<Map<String, dynamic>>? lastArrivals,
  }) {
    return PharmacyOrdersState(
      orders: orders ?? this.orders,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      error: clearError ? null : (error ?? this.error),
      filter: clearFilter ? null : (filter ?? this.filter),
      searchQuery: searchQuery ?? this.searchQuery,
      loadedStoreId: clearLoadedStore
          ? null
          : (loadedStoreId ?? this.loadedStoreId),
      busyOrderIds: busyOrderIds ?? this.busyOrderIds,
      prescriptionQueue: prescriptionQueue ?? this.prescriptionQueue,
      isQueueLoading: isQueueLoading ?? this.isQueueLoading,
      isQueueRefreshing: isQueueRefreshing ?? this.isQueueRefreshing,
      queueError: clearQueueError ? null : (queueError ?? this.queueError),
      orderDetailsCache: orderDetailsCache ?? this.orderDetailsCache,
      allOrders: allOrders ?? this.allOrders,
      isSwitching: isSwitching ?? this.isSwitching,
      awaitingOrders: awaitingOrders ?? this.awaitingOrders,
      arrivalTick: arrivalTick ?? this.arrivalTick,
      lastArrival: lastArrival ?? this.lastArrival,
      lastArrivals: lastArrivals ?? this.lastArrivals,
    );
  }
}

class PharmacyOrdersNotifier extends StateNotifier<PharmacyOrdersState> {
  final Ref _ref;
  final ApiService _api = ApiService();

  PharmacyOrdersNotifier(this._ref) : super(const PharmacyOrdersState());

  /// Filter value for "everything the store still has to act on" — both
  /// `placed` and `prescription_review`. The API filters by one status, so
  /// this one is applied here instead of being sent to the server.
  static const awaitingFilter = 'awaiting';

  /// An order the store still has to accept or reject.
  static bool isAwaitingAction(Map<String, dynamic> order) {
    final status = '${order['orderStatus'] ?? ''}';
    return status == 'placed' || status == 'prescription_review';
  }

  // ─────────────────────────── Live updates ──────────────────────────

  static const _pollEvery = Duration(seconds: 20);
  Timer? _live;
  AppLifecycleListener? _lifecycle;
  bool _foreground = true;
  bool _polling = false;

  /// Ids seen waiting on the previous poll. Null until the first poll, so the
  /// orders already waiting when the app opens do not all "arrive" at once.
  Set<String>? _knownAwaiting;

  /// Starts the background refresh that keeps waiting orders current. Safe
  /// to call repeatedly. Pauses while the app is in the background and polls
  /// immediately on return, so a phone left in a pocket costs nothing.
  void startLiveUpdates() {
    _lifecycle ??= AppLifecycleListener(
      onResume: () {
        _foreground = true;
        _poll();
      },
      onHide: () => _foreground = false,
      onPause: () => _foreground = false,
    );
    if (_live != null) return;
    _live = Timer.periodic(_pollEvery, (_) => _poll());
    _poll();
  }

  /// Checks for new orders now, outside the 20-second cycle — called when a
  /// push arrives while the app is open.
  Future<void> pollNow() => _poll();

  Future<void> _poll() async {
    if (!_foreground || _polling) return;
    final storeId = _ref.read(pharmacyStoreProvider).selectedStoreId;
    if (storeId == null) return;
    _polling = true;
    try {
      final response = await _api.getMerchantOrders(
        queryParams: const {'limit': 100},
      );
      if (!mounted) return;
      if (_ref.read(pharmacyStoreProvider).selectedStoreId != storeId) return;
      final data = response.data;
      final latest = _maps(data is Map ? data['orders'] : data);
      _applyAwaiting(latest);
      _haveAllOrders = true;
      state = state.copyWith(allOrders: latest);
      // The unfiltered list is exactly what the Orders screen shows when no
      // filter or search is set, so reuse it rather than fetching twice.
      // Skipped while a chip's own fetch is in flight, which owns the list.
      if (state.searchQuery.trim().isEmpty && !state.isSwitching) {
        if (state.filter == null) {
          state = state.copyWith(orders: latest, loadedStoreId: storeId);
        } else if (state.filter == awaitingFilter) {
          state = state.copyWith(
            orders: state.awaitingOrders,
            loadedStoreId: storeId,
          );
        }
      }
    } catch (_) {
      // A missed poll is retried on the next tick.
    } finally {
      _polling = false;
    }
  }

  /// Recomputes the waiting list from [orders] and flags anything new.
  void _applyAwaiting(List<Map<String, dynamic>> orders) {
    final awaiting = orders.where(isAwaitingAction).toList();
    final ids = awaiting.map((o) => '${o['_id']}').toSet();
    final known = _knownAwaiting;
    _knownAwaiting = ids;
    final fresh = known == null
        ? const <Map<String, dynamic>>[]
        : awaiting.where((o) => !known.contains('${o['_id']}')).toList();
    state = state.copyWith(
      awaitingOrders: awaiting,
      arrivalTick: fresh.isEmpty ? null : state.arrivalTick + 1,
      lastArrival: fresh.isEmpty ? null : fresh.first,
      lastArrivals: fresh.isEmpty ? null : fresh,
    );
  }

  @override
  void dispose() {
    _live?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> initialize({bool force = false}) async {
    final currentStoreId = _ref.read(pharmacyStoreProvider).selectedStoreId;
    if (currentStoreId == null) return;
    if (!force &&
        state.loadedStoreId == currentStoreId &&
        state.orders.isNotEmpty) {
      return;
    }
    await loadOrders(storeId: currentStoreId);
  }

  /// Bumped per list fetch; a response that is no longer the latest request
  /// is dropped, so tapping All → Needs action → Placed quickly can't end
  /// with the slow "All" response painted under the "Placed" chip.
  int _requestSeq = 0;

  /// Set once [PharmacyOrdersState.allOrders] holds a real unfiltered fetch
  /// (an empty one is a real answer too, unlike the initial empty default).
  bool _haveAllOrders = false;

  /// [filter] applied on the phone to the last full list, or null when there
  /// is no full list yet to filter.
  List<Map<String, dynamic>>? _filterLocally(String? filter) {
    if (!_haveAllOrders) return null;
    final all = state.allOrders;
    if (filter == null) return all;
    if (filter == awaitingFilter) return all.where(isAwaitingAction).toList();
    return all.where((o) => '${o['orderStatus']}' == filter).toList();
  }

  Future<void> loadOrders({
    bool silent = false,
    String? filter,
    String? search,
    String? storeId,
  }) async {
    final targetStoreId =
        storeId ?? _ref.read(pharmacyStoreProvider).selectedStoreId;
    if (targetStoreId == null) return;
    final seq = ++_requestSeq;

    final effectiveFilter = filter ?? state.filter;
    final effectiveSearch = search ?? state.searchQuery;

    if (silent || state.orders.isNotEmpty) {
      state = state.copyWith(isRefreshing: true, clearError: true);
    } else {
      state = state.copyWith(isLoading: true, clearError: true);
    }

    try {
      final response = await _api.getMerchantOrders(
        queryParams: {
          'limit': 100,
          if (effectiveFilter != null && effectiveFilter != awaitingFilter)
            'status': effectiveFilter,
          if (effectiveSearch.trim().isNotEmpty) 'q': effectiveSearch.trim(),
        },
      );
      if (seq != _requestSeq || !mounted) return;
      final data = response.data;
      final rawList = data is Map ? data['orders'] : data;
      var list = _maps(rawList);
      if ((effectiveFilter == null || effectiveFilter == awaitingFilter) &&
          effectiveSearch.trim().isEmpty) {
        _applyAwaiting(list);
        if (effectiveFilter == null) {
          _haveAllOrders = true;
          state = state.copyWith(allOrders: list);
        }
      }
      if (effectiveFilter == awaitingFilter) {
        list = list.where(isAwaitingAction).toList();
      }
      state = state.copyWith(
        orders: list,
        loadedStoreId: targetStoreId,
        isLoading: false,
        isRefreshing: false,
        isSwitching: false,
        filter: effectiveFilter,
        clearFilter: effectiveFilter == null,
        searchQuery: effectiveSearch,
      );
    } on DioException catch (e) {
      if (seq != _requestSeq || !mounted) return;
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        isSwitching: false,
        error: _message(e),
      );
    } catch (e) {
      if (seq != _requestSeq || !mounted) return;
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        isSwitching: false,
        error: e.toString(),
      );
    }
  }

  /// Shows the chip's result at once from the last full list, then confirms
  /// it with the server (which also covers orders older than that list).
  /// With no list to filter yet, the skeleton shows — never "No orders".
  Future<void> setFilter(String? status) async {
    if (status == state.filter) return;
    final local = state.searchQuery.trim().isEmpty
        ? _filterLocally(status)
        : null;
    state = state.copyWith(
      filter: status,
      clearFilter: status == null,
      orders: local ?? const [],
      isLoading: local == null,
      isSwitching: true,
      clearError: true,
    );
    await loadOrders(filter: status, silent: local != null);
  }

  Future<void> setSearch(String query) async {
    final q = query.trim().toLowerCase();
    // Narrow what is on screen straight away; the server result follows.
    final narrowed = q.isEmpty
        ? (_filterLocally(state.filter) ?? state.orders)
        : state.orders
              .where(
                (o) => '${o['orderNumber'] ?? ''}'.toLowerCase().contains(q),
              )
              .toList();
    state = state.copyWith(
      searchQuery: query,
      orders: narrowed,
      isLoading: narrowed.isEmpty,
      isSwitching: true,
      clearError: true,
    );
    await loadOrders(search: query, silent: narrowed.isNotEmpty);
  }

  void setOrderBusy(String orderId, bool busy) {
    final next = Set<String>.from(state.busyOrderIds);
    if (busy) {
      next.add(orderId);
    } else {
      next.remove(orderId);
    }
    state = state.copyWith(busyOrderIds: next);
  }

  Future<void> loadPrescriptionQueue({
    bool silent = false,
    bool force = false,
  }) async {
    final targetStoreId = _ref.read(pharmacyStoreProvider).selectedStoreId;
    if (targetStoreId == null) return;

    if (state.prescriptionQueue.isNotEmpty && !force) {
      state = state.copyWith(isQueueRefreshing: true, clearQueueError: true);
    } else if (silent || state.prescriptionQueue.isNotEmpty) {
      state = state.copyWith(isQueueRefreshing: true, clearQueueError: true);
    } else {
      state = state.copyWith(isQueueLoading: true, clearQueueError: true);
    }

    try {
      final response = await _api.getMerchantOrders(
        queryParams: {'prescriptionStatus': 'pending_review', 'limit': 100},
      );
      final data = response.data is Map ? response.data as Map : const {};
      final raw = (data['orders'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final queue = raw.where((o) {
        final rx = '${o['prescriptionStatus'] ?? o['rxStatus'] ?? ''}'
            .toLowerCase();
        return rx.contains('pending') ||
            rx.contains('review') ||
            o['prescriptionRequired'] == true;
      }).toList();

      state = state.copyWith(
        prescriptionQueue: queue,
        isQueueLoading: false,
        isQueueRefreshing: false,
      );
    } on DioException catch (e) {
      state = state.copyWith(
        isQueueLoading: false,
        isQueueRefreshing: false,
        queueError: _message(e),
      );
    } catch (e) {
      state = state.copyWith(
        isQueueLoading: false,
        isQueueRefreshing: false,
        queueError: e.toString(),
      );
    }
  }

  Future<Map<String, dynamic>?> loadOrderDetails(
    String orderId, {
    bool force = false,
  }) async {
    if (!force && state.orderDetailsCache.containsKey(orderId)) {
      _silentRefreshOrderDetails(orderId);
      return state.orderDetailsCache[orderId];
    }

    try {
      final response = await _api.getMerchantOrder(orderId);
      final data = response.data;
      if (data is Map && data['order'] is Map) {
        final fullOrder = Map<String, dynamic>.from(data['order'] as Map);
        upsertOrder(fullOrder);
        return fullOrder;
      }
    } catch (_) {
      // A cached copy is still worth showing; with nothing to fall back on,
      // the caller has to know the fetch failed rather than get a silent null.
      final cached = state.orderDetailsCache[orderId];
      if (cached != null) return cached;
      rethrow;
    }
    return state.orderDetailsCache[orderId];
  }

  Future<void> _silentRefreshOrderDetails(String orderId) async {
    try {
      final response = await _api.getMerchantOrder(orderId);
      final data = response.data;
      if (data is Map && data['order'] is Map) {
        final fullOrder = Map<String, dynamic>.from(data['order'] as Map);
        upsertOrder(fullOrder);
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> reviewPrescription(
    String orderId, {
    required bool approved,
    String? reason,
    Map<String, dynamic>? checklist,
  }) async {
    final res = await _api.reviewMerchantPrescription(
      orderId,
      approved: approved,
      reason: reason,
      checklist: checklist,
    );
    final data = res.data;
    if (data is Map && data['order'] is Map) {
      final updated = Map<String, dynamic>.from(data['order'] as Map);
      upsertOrder(updated);
      return updated;
    } else {
      await loadPrescriptionQueue(silent: true, force: true);
      return null;
    }
  }

  void upsertOrder(Map<String, dynamic> order) {
    final id = order['_id']?.toString();
    if (id == null || id.isEmpty) return;

    final updated = List<Map<String, dynamic>>.from(state.orders);
    final idx = updated.indexWhere((o) => o['_id']?.toString() == id);
    if (idx >= 0) {
      updated[idx] = Map<String, dynamic>.from(order);
    } else {
      updated.insert(0, Map<String, dynamic>.from(order));
    }

    final newCache = Map<String, Map<String, dynamic>>.from(
      state.orderDetailsCache,
    );
    newCache[id] = Map<String, dynamic>.from(order);

    final queue = List<Map<String, dynamic>>.from(state.prescriptionQueue);
    final qIdx = queue.indexWhere((o) => o['_id']?.toString() == id);
    final rxStatus = '${order['prescriptionStatus'] ?? ''}'.toLowerCase();
    final isStillPending =
        rxStatus.contains('pending') || rxStatus.contains('review');

    if (isStillPending) {
      if (qIdx >= 0) {
        queue[qIdx] = Map<String, dynamic>.from(order);
      } else {
        queue.insert(0, Map<String, dynamic>.from(order));
      }
    } else {
      if (qIdx >= 0) {
        queue.removeAt(qIdx);
      }
    }

    final awaiting = List<Map<String, dynamic>>.from(state.awaitingOrders)
      ..removeWhere((o) => o['_id']?.toString() == id);
    if (isAwaitingAction(order)) awaiting.insert(0, Map.from(order));
    _knownAwaiting = awaiting.map((o) => '${o['_id']}').toSet();

    state = state.copyWith(
      orders: updated,
      orderDetailsCache: newCache,
      prescriptionQueue: queue,
      awaitingOrders: awaiting,
    );
  }

  void removeOrder(String orderId) {
    final updated = state.orders
        .where((o) => o['_id']?.toString() != orderId)
        .map((o) => Map<String, dynamic>.from(o))
        .toList();
    final queue = state.prescriptionQueue
        .where((o) => o['_id']?.toString() != orderId)
        .map((o) => Map<String, dynamic>.from(o))
        .toList();
    final newCache = Map<String, Map<String, dynamic>>.from(
      state.orderDetailsCache,
    );
    newCache.remove(orderId);

    state = state.copyWith(
      orders: updated,
      prescriptionQueue: queue,
      orderDetailsCache: newCache,
      awaitingOrders: state.awaitingOrders
          .where((o) => o['_id']?.toString() != orderId)
          .toList(),
    );
  }

  void onStoreChanged(String newStoreId) {
    if (state.loadedStoreId == newStoreId) return;
    state = state.copyWith(
      orders: const [],
      prescriptionQueue: const [],
      orderDetailsCache: const {},
      clearLoadedStore: true,
      clearError: true,
      clearQueueError: true,
      searchQuery: '',
      clearFilter: true,
      busyOrderIds: const {},
      awaitingOrders: const [],
      allOrders: const [],
      isSwitching: false,
    );
    _knownAwaiting = null;
    _haveAllOrders = false;
    loadOrders(storeId: newStoreId);
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

final pharmacyOrdersProvider =
    StateNotifierProvider<PharmacyOrdersNotifier, PharmacyOrdersState>((ref) {
      final notifier = PharmacyOrdersNotifier(ref);
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
