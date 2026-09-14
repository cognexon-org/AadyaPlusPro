import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/network/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/pharmacy_store_provider.dart';
import 'add_medicine.dart';
import 'medicine_details.dart';

class PharmacyMedicines extends ConsumerStatefulWidget {
  const PharmacyMedicines({super.key});

  @override
  ConsumerState<PharmacyMedicines> createState() => _PharmacyMedicinesState();
}

class _PharmacyMedicinesState extends ConsumerState<PharmacyMedicines> {
  final _api = ApiService();
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;
  String? _loadedStoreId;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(pharmacyStoreProvider.notifier).initialize();
      if (mounted) await _load();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final storeId = ref.read(pharmacyStoreProvider).selectedStoreId;
    if (storeId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.getMedicines(queryParams: {
        'limit': 200,
        if (_search.text.trim().isNotEmpty) 'search': _search.text.trim(),
      });
      final data = response.data;
      final list = data is Map ? data['medicines'] : data;
      if (!mounted) return;
      setState(() {
        _items = _maps(list);
        _loadedStoreId = storeId;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(pharmacyStoreProvider);
    if (store.selectedStoreId != null && store.selectedStoreId != _loadedStoreId && !_loading) {
      Future.microtask(_load);
    }
    return Scaffold(
      backgroundColor: AppTheme.surface,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddMedicine()));
          if (mounted) await _load();
        },
        icon: const Icon(Iconsax.add),
        label: const Text('Medicine'),
      ),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Branch Inventory', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
              const SizedBox(height: 12),
              const PharmacyStoreSelector(compact: true),
              const SizedBox(height: 10),
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _load(),
                decoration: InputDecoration(
                  hintText: 'Search name, generic, brand or barcode',
                  prefixIcon: const Icon(Iconsax.search_normal, size: 18),
                  suffixIcon: IconButton(icon: const Icon(Iconsax.refresh, size: 18), onPressed: _load),
                ),
              ),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.error)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _items.isEmpty
                            ? ListView(children: const [SizedBox(height: 120), Center(child: Text('No medicines in this branch'))])
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                                itemCount: _items.length,
                                itemBuilder: (_, index) => _card(_items[index]),
                              ),
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _card(Map<String, dynamic> item) {
    final qty = num.tryParse((item['quantity'] ?? item['stock_quantity'] ?? 0).toString()) ?? 0;
    final reorder = num.tryParse((item['reorderLevel'] ?? item['reorder_level'] ?? 0).toString()) ?? 0;
    final low = qty <= reorder;
    return InkWell(
      onTap: () async {
        final id = item['_id']?.toString();
        if (id == null || id.isEmpty) return;
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MedicineDetails(medicineId: id)));
        if (mounted) await _load();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: low ? AppTheme.warning.withValues(alpha: .5) : AppTheme.border)),
        child: Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: (low ? AppTheme.warning : AppTheme.primary).withValues(alpha: .10), borderRadius: BorderRadius.circular(11)), child: Icon(Iconsax.box, color: low ? AppTheme.warning : AppTheme.primary, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item['medicineName']?.toString() ?? item['name']?.toString() ?? 'Medicine', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700)),
            Text([item['genericName'] ?? item['generic_name'], item['brandName'] ?? item['brand']].where((e) => e != null && e.toString().isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textSecondary)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$qty ${item['unit'] ?? ''}', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800, color: low ? AppTheme.warning : AppTheme.textPrimary)),
            Text('₹${item['sellingPrice'] ?? item['price_per_unit'] ?? 0}', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textSecondary)),
          ]),
        ]),
      ),
    );
  }

  static List<Map<String, dynamic>> _maps(dynamic value) => value is List ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
  static String _message(DioException e) {
    final d = e.response?.data;
    if (d is Map) return d['message']?.toString() ?? d['error']?.toString() ?? 'Request failed';
    return e.message ?? 'Request failed';
  }
}
