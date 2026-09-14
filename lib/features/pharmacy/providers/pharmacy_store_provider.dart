import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/network/api_service.dart';
import '../../../core/theme/app_theme.dart';

class PharmacyStoreState {
  final Map<String, dynamic> organization;
  final List<Map<String, dynamic>> stores;
  final String? selectedStoreId;
  final String organizationRole;
  final bool loading;
  final String? error;

  const PharmacyStoreState({
    this.organization = const {},
    this.stores = const [],
    this.selectedStoreId,
    this.organizationRole = 'owner',
    this.loading = false,
    this.error,
  });

  Map<String, dynamic>? get selectedStore {
    if (stores.isEmpty) return null;
    for (final store in stores) {
      if (store['_id']?.toString() == selectedStoreId) return store;
    }
    return stores.first;
  }

  PharmacyStoreState copyWith({
    Map<String, dynamic>? organization,
    List<Map<String, dynamic>>? stores,
    String? selectedStoreId,
    bool clearSelectedStore = false,
    String? organizationRole,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return PharmacyStoreState(
      organization: organization ?? this.organization,
      stores: stores ?? this.stores,
      selectedStoreId: clearSelectedStore ? null : (selectedStoreId ?? this.selectedStoreId),
      organizationRole: organizationRole ?? this.organizationRole,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class PharmacyStoreNotifier extends StateNotifier<PharmacyStoreState> {
  PharmacyStoreNotifier() : super(const PharmacyStoreState());

  static const _prefKey = 'aadya_selected_pharmacy_store_id';
  final ApiService _api = ApiService();
  bool _initialized = false;

  Future<void> initialize({bool force = false}) async {
    if (_initialized && !force) return;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null && saved.isNotEmpty) _api.setPharmacyStoreId(saved);

      final response = await _api.getPharmacyTenantContext();
      final data = response.data is Map ? Map<String, dynamic>.from(response.data as Map) : <String, dynamic>{};
      final stores = _maps(data['stores']);
      final defaultStoreId = data['defaultStoreId']?.toString();

      String? selected = saved;
      final allowedIds = stores.map((e) => e['_id']?.toString()).whereType<String>().toSet();
      if (selected == null || !allowedIds.contains(selected)) {
        selected = (defaultStoreId != null && allowedIds.contains(defaultStoreId))
            ? defaultStoreId
            : (stores.isNotEmpty ? stores.first['_id']?.toString() : null);
      }

      if (selected != null && selected.isNotEmpty) {
        _api.setPharmacyStoreId(selected);
        await prefs.setString(_prefKey, selected);
      } else {
        _api.setPharmacyStoreId(null);
        await prefs.remove(_prefKey);
      }

      state = PharmacyStoreState(
        organization: _map(data['organization']),
        stores: stores,
        selectedStoreId: selected,
        organizationRole: data['organizationRole']?.toString() ?? 'owner',
        loading: false,
      );
      _initialized = true;
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _message(e));
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> selectStore(String storeId) async {
    if (storeId == state.selectedStoreId) return;
    if (!state.stores.any((e) => e['_id']?.toString() == storeId)) {
      state = state.copyWith(error: 'The selected branch is no longer available.');
      await initialize(force: true);
      return;
    }

    state = state.copyWith(loading: true, clearError: true);
    try {
      await _api.selectPharmacyStore(storeId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, storeId);
      _api.setPharmacyStoreId(storeId);
      state = state.copyWith(selectedStoreId: storeId, loading: false);
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _message(e));
      await initialize(force: true);
    }
  }

  Future<void> refresh() => initialize(force: true);

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  static String _message(DioException e) {
    final data = e.response?.data;
    if (data is Map) return data['message']?.toString() ?? data['error']?.toString() ?? 'Unable to load pharmacy branches';
    return e.message ?? 'Unable to load pharmacy branches';
  }
}

final pharmacyStoreProvider = StateNotifierProvider<PharmacyStoreNotifier, PharmacyStoreState>(
  (ref) => PharmacyStoreNotifier(),
);


class PharmacyStoreSelector extends ConsumerWidget {
  const PharmacyStoreSelector({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pharmacyStoreProvider);
    if (state.loading && state.stores.isEmpty) {
      return const SizedBox(height: 44, child: Center(child: LinearProgressIndicator()));
    }
    if (state.stores.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
        child: Text(state.error ?? 'No pharmacy branch available', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.error)),
      );
    }

    final selected = state.selectedStoreId ?? state.stores.first['_id']?.toString();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: 4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: state.stores.any((s) => s['_id']?.toString() == selected) ? selected : state.stores.first['_id']?.toString(),
          isExpanded: true,
          icon: state.loading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.store_mall_directory_outlined, size: 18),
          items: state.stores.map((store) {
            final id = store['_id']?.toString() ?? '';
            final name = store['name']?.toString() ?? 'Pharmacy branch';
            final code = store['code']?.toString();
            return DropdownMenuItem<String>(
              value: id,
              child: Text(
                code == null || code.isEmpty ? name : '$name · $code',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(fontSize: compact ? 12 : 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
              ),
            );
          }).toList(),
          onChanged: state.loading
              ? null
              : (id) {
                  if (id != null && id.isNotEmpty) ref.read(pharmacyStoreProvider.notifier).selectStore(id);
                },
        ),
      ),
    );
  }
}
