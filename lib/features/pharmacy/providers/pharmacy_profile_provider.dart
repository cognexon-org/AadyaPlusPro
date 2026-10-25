import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_service.dart';
import 'pharmacy_store_provider.dart';

class PharmacyProfileState {
  final Map<String, dynamic> profile;
  final bool isProfileLoading;
  final bool isProfileRefreshing;
  final String? profileError;

  final Map<String, dynamic> onlineSettings;
  final bool isSettingsLoading;
  final bool isSettingsRefreshing;
  final String? settingsError;

  final List<Map<String, dynamic>> coupons;
  final bool isCouponsLoading;
  final bool isCouponsRefreshing;
  final String? couponsError;

  final String? loadedStoreId;

  const PharmacyProfileState({
    this.profile = const {},
    this.isProfileLoading = false,
    this.isProfileRefreshing = false,
    this.profileError,
    this.onlineSettings = const {},
    this.isSettingsLoading = false,
    this.isSettingsRefreshing = false,
    this.settingsError,
    this.coupons = const [],
    this.isCouponsLoading = false,
    this.isCouponsRefreshing = false,
    this.couponsError,
    this.loadedStoreId,
  });

  PharmacyProfileState copyWith({
    Map<String, dynamic>? profile,
    bool? isProfileLoading,
    bool? isProfileRefreshing,
    String? profileError,
    bool clearProfileError = false,
    Map<String, dynamic>? onlineSettings,
    bool? isSettingsLoading,
    bool? isSettingsRefreshing,
    String? settingsError,
    bool clearSettingsError = false,
    List<Map<String, dynamic>>? coupons,
    bool? isCouponsLoading,
    bool? isCouponsRefreshing,
    String? couponsError,
    bool clearCouponsError = false,
    String? loadedStoreId,
    bool clearLoadedStore = false,
  }) {
    return PharmacyProfileState(
      profile: profile ?? this.profile,
      isProfileLoading: isProfileLoading ?? this.isProfileLoading,
      isProfileRefreshing: isProfileRefreshing ?? this.isProfileRefreshing,
      profileError: clearProfileError
          ? null
          : (profileError ?? this.profileError),
      onlineSettings: onlineSettings ?? this.onlineSettings,
      isSettingsLoading: isSettingsLoading ?? this.isSettingsLoading,
      isSettingsRefreshing: isSettingsRefreshing ?? this.isSettingsRefreshing,
      settingsError: clearSettingsError
          ? null
          : (settingsError ?? this.settingsError),
      coupons: coupons ?? this.coupons,
      isCouponsLoading: isCouponsLoading ?? this.isCouponsLoading,
      isCouponsRefreshing: isCouponsRefreshing ?? this.isCouponsRefreshing,
      couponsError: clearCouponsError
          ? null
          : (couponsError ?? this.couponsError),
      loadedStoreId: clearLoadedStore
          ? null
          : (loadedStoreId ?? this.loadedStoreId),
    );
  }
}

class PharmacyProfileNotifier extends StateNotifier<PharmacyProfileState> {
  final Ref _ref;
  final ApiService _api = ApiService();

  PharmacyProfileNotifier(this._ref) : super(const PharmacyProfileState());

  Future<void> initialize({bool force = false}) async {
    final currentStoreId = _ref.read(pharmacyStoreProvider).selectedStoreId;
    if (currentStoreId == null) return;
    if (!force &&
        state.loadedStoreId == currentStoreId &&
        state.profile.isNotEmpty) {
      return;
    }
    await Future.wait([
      loadProfile(storeId: currentStoreId, force: force),
      loadOnlineSettings(storeId: currentStoreId, force: force),
    ]);
  }

  Future<void> loadProfile({
    bool silent = false,
    String? storeId,
    bool force = false,
  }) async {
    final targetStoreId =
        storeId ?? _ref.read(pharmacyStoreProvider).selectedStoreId;
    if (targetStoreId == null) return;

    if (state.profile.isNotEmpty && !force) {
      state = state.copyWith(
        isProfileRefreshing: true,
        clearProfileError: true,
      );
    } else if (silent || state.profile.isNotEmpty) {
      state = state.copyWith(
        isProfileRefreshing: true,
        clearProfileError: true,
      );
    } else {
      state = state.copyWith(isProfileLoading: true, clearProfileError: true);
    }

    try {
      final response = await _api.getPharmacyProfile();
      final body = response.data;
      final raw = body is Map
          ? (body['pharmacy'] ?? body['profile'] ?? body['data'] ?? body)
          : <String, dynamic>{};
      final profileMap = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};

      state = state.copyWith(
        profile: profileMap,
        loadedStoreId: targetStoreId,
        isProfileLoading: false,
        isProfileRefreshing: false,
      );
    } on DioException catch (e) {
      state = state.copyWith(
        isProfileLoading: false,
        isProfileRefreshing: false,
        profileError: _message(e),
      );
    } catch (e) {
      state = state.copyWith(
        isProfileLoading: false,
        isProfileRefreshing: false,
        profileError: e.toString(),
      );
    }
  }

  void updateProfile(Map<String, dynamic> updatedProfile) {
    state = state.copyWith(profile: {...state.profile, ...updatedProfile});
  }

  Future<void> loadOnlineSettings({
    bool silent = false,
    String? storeId,
    bool force = false,
  }) async {
    final targetStoreId =
        storeId ?? _ref.read(pharmacyStoreProvider).selectedStoreId;
    if (targetStoreId == null) return;

    if (state.onlineSettings.isNotEmpty && !force) {
      state = state.copyWith(
        isSettingsRefreshing: true,
        clearSettingsError: true,
      );
    } else if (silent || state.onlineSettings.isNotEmpty) {
      state = state.copyWith(
        isSettingsRefreshing: true,
        clearSettingsError: true,
      );
    } else {
      state = state.copyWith(isSettingsLoading: true, clearSettingsError: true);
    }

    try {
      final response = await _api.getMerchantSettings();
      final body = response.data;
      final raw = body is Map
          ? (body['settings'] ?? body['ecommerce'] ?? body['data'] ?? body)
          : <String, dynamic>{};
      final settingsMap = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};

      state = state.copyWith(
        onlineSettings: settingsMap,
        loadedStoreId: targetStoreId,
        isSettingsLoading: false,
        isSettingsRefreshing: false,
      );
    } on DioException catch (e) {
      state = state.copyWith(
        isSettingsLoading: false,
        isSettingsRefreshing: false,
        settingsError: _message(e),
      );
    } catch (e) {
      state = state.copyWith(
        isSettingsLoading: false,
        isSettingsRefreshing: false,
        settingsError: e.toString(),
      );
    }
  }

  void updateOnlineSettings(Map<String, dynamic> updatedSettings) {
    state = state.copyWith(
      onlineSettings: {...state.onlineSettings, ...updatedSettings},
    );
  }

  Future<void> loadCoupons({bool silent = false, bool force = false}) async {
    final targetStoreId = _ref.read(pharmacyStoreProvider).selectedStoreId;
    if (targetStoreId == null) return;

    if (state.coupons.isNotEmpty && !force) {
      state = state.copyWith(
        isCouponsRefreshing: true,
        clearCouponsError: true,
      );
    } else if (silent || state.coupons.isNotEmpty) {
      state = state.copyWith(
        isCouponsRefreshing: true,
        clearCouponsError: true,
      );
    } else {
      state = state.copyWith(isCouponsLoading: true, clearCouponsError: true);
    }

    try {
      final response = await _api.getMerchantCoupons();
      final data = response.data is Map ? response.data as Map : const {};
      final list = (data['coupons'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      state = state.copyWith(
        coupons: list,
        isCouponsLoading: false,
        isCouponsRefreshing: false,
      );
    } on DioException catch (e) {
      state = state.copyWith(
        isCouponsLoading: false,
        isCouponsRefreshing: false,
        couponsError: _message(e),
      );
    } catch (e) {
      state = state.copyWith(
        isCouponsLoading: false,
        isCouponsRefreshing: false,
        couponsError: e.toString(),
      );
    }
  }

  Future<void> createCoupon(Map<String, dynamic> couponData) async {
    await _api.createMerchantCoupon(couponData);
    await loadCoupons(silent: true, force: true);
  }

  Future<void> toggleCoupon(String id, bool active) async {
    final prevCoupons = List<Map<String, dynamic>>.from(state.coupons);
    final idx = prevCoupons.indexWhere((c) => '${c['_id']}' == id);
    if (idx >= 0) {
      prevCoupons[idx] = {...prevCoupons[idx], 'isActive': active};
      state = state.copyWith(coupons: prevCoupons);
    }

    try {
      await _api.updateMerchantCoupon(id, {'isActive': active});
    } catch (e) {
      await loadCoupons(silent: true, force: true);
      rethrow;
    }
  }

  void onStoreChanged(String newStoreId) {
    if (state.loadedStoreId == newStoreId) return;
    state = state.copyWith(
      profile: const {},
      onlineSettings: const {},
      coupons: const [],
      clearLoadedStore: true,
      clearProfileError: true,
      clearSettingsError: true,
      clearCouponsError: true,
    );
    initialize(force: true);
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

final pharmacyProfileProvider =
    StateNotifierProvider<PharmacyProfileNotifier, PharmacyProfileState>((ref) {
      final notifier = PharmacyProfileNotifier(ref);
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
