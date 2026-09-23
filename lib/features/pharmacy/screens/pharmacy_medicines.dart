import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/pharmacy_type.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../core/network/api_service.dart';
import '../theme/pharmacy_colors.dart';
import '../providers/pharmacy_store_provider.dart';
import '../widgets/pharmacy_ui.dart';
import 'add_medicine.dart';
import 'bulk_upload_medicines.dart';
import 'medicine_details.dart';

enum _MedFilter { all, lowStock, expiring }

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
  _MedFilter _filter = _MedFilter.all;

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
      final response = await _api.getMedicines(
        queryParams: {
          'limit': 200,
          if (_search.text.trim().isNotEmpty) 'search': _search.text.trim(),
        },
      );
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

  bool _isLow(Map<String, dynamic> item) {
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

  bool _isExpiring(Map<String, dynamic> item) {
    final expiry = DateTime.tryParse(
      '${item['nearestExpiryDate'] ?? item['expiryDate'] ?? ''}',
    );
    if (expiry == null) return false;
    return expiry.difference(DateTime.now()).inDays <= 30;
  }

  List<Map<String, dynamic>> get _filtered {
    switch (_filter) {
      case _MedFilter.lowStock:
        return _items.where(_isLow).toList();
      case _MedFilter.expiring:
        return _items.where(_isExpiring).toList();
      case _MedFilter.all:
        return _items;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(pharmacyStoreProvider);
    if (store.selectedStoreId != null &&
        store.selectedStoreId != _loadedStoreId &&
        !_loading) {
      Future.microtask(_load);
    }
    final lowCount = _items.where(_isLow).length;
    final expiringCount = _items.where(_isExpiring).length;
    final visible = _filtered;

    return Scaffold(
      backgroundColor: PharmacyColors.bg,
      floatingActionButton: FloatingActionButton(
        backgroundColor: PharmacyColors.green,
        elevation: 2,
        onPressed: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AddMedicine()));
          if (mounted) await _load();
        },
        child: const Icon(CupertinoIcons.add, color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PharmacyScreenHeader(
                    title: 'Medicines',
                    subtitle: 'Search, restock and manage medicines',
                    trailing: IconButton(
                      tooltip: 'Bulk upload from CSV/Excel',
                      // Green, not grey: in this design every tappable thing
                      // (View All, active chips, the FAB) carries the brand
                      // colour — a grey glyph here reads as decoration and
                      // gets missed.
                      // `fileUp` is one page with an arrow — it reads as
                      // "upload a document", which is not what this does.
                      // A spreadsheet glyph says the thing that actually
                      // distinguishes this action from the + beside it: many
                      // medicines at once, out of a CSV/Excel file.
                      // Sized up from 20: it is the only action in this
                      // header, and Lucide's 2px stroke reads light at small
                      // sizes against the header's heavy title.
                      icon: const Icon(LucideIcons.fileSpreadsheet, size: 26),
                      iconSize: 26,
                      color: PharmacyColors.green,
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const BulkUploadMedicines(),
                          ),
                        );
                        if (mounted) await _load();
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  PharmacySearchField(
                    controller: _search,
                    hint: 'Search by name, generic, brand or barcode',
                    onSubmitted: _load,
                    onRefresh: _load,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _filterChip('All (${_items.length})', _MedFilter.all),
                      const SizedBox(width: 8),
                      _filterChip('Low Stock ($lowCount)', _MedFilter.lowStock),
                      const SizedBox(width: 8),
                      _filterChip(
                        'Expiring ($expiringCount)',
                        _MedFilter.expiring,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      children: const [PharmacyListSkeleton(count: 6)],
                    )
                  : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: PharmacyErrorBanner(
                        message: _error!,
                        onRetry: _load,
                      ),
                    )
                  : RefreshIndicator(
                      color: PharmacyColors.green,
                      onRefresh: _load,
                      child: visible.isEmpty
                          ? ListView(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                100,
                              ),
                              children: [
                                const SizedBox(height: 40),
                                PharmacyEmptyStateInline(
                                  icon: Icons.medication_outlined,
                                  text: _items.isEmpty
                                      ? 'No medicines in this branch yet.\nTap + to add your first one.'
                                      : 'No medicines match this filter.',
                                ),
                              ],
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                100,
                              ),
                              itemCount: visible.length,
                              itemBuilder: (_, index) => _card(visible[index]),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, _MedFilter value) => PharmacyFilterChip(
    label: label,
    selected: _filter == value,
    onTap: () => setState(() => _filter = value),
  );

  static const _swatches = [
    Color(0xFF3978D8),
    Color(0xFFD64545),
    Color(0xFFD98200),
    Color(0xFF6651B8),
    Color(0xFF0A9F62),
  ];

  Widget _card(Map<String, dynamic> item) {
    final qty =
        num.tryParse(
          (item['quantity'] ?? item['stock_quantity'] ?? 0).toString(),
        ) ??
        0;
    final low = _isLow(item);
    final name =
        item['medicineName']?.toString() ??
        item['name']?.toString() ??
        'Medicine';
    final categoryKey = item['category']?.toString();
    final swatch = _swatches[name.hashCode.abs() % _swatches.length];
    return PharmacyCard(
      onTap: () async {
        final id = item['_id']?.toString();
        if (id == null || id.isEmpty) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => MedicineDetails(medicineId: id)),
        );
        if (mounted) await _load();
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PharmacyIconBadge(
            icon: medicineCategoryIcon(categoryKey),
            color: swatch,
            size: 40,
            iconSize: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: PharmacyType.sans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: PharmacyColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                        kMedicineCategories[item['category']] ??
                            item['category'],
                        item['genericName'] ?? item['generic_name'],
                      ]
                      .where((e) => e != null && e.toString().isNotEmpty)
                      .join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PharmacyType.sans(
                    fontSize: 12,
                    color: PharmacyColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  low ? 'Stock: $qty  ·  Low Stock' : 'Stock: $qty',
                  style: PharmacyType.sans(
                    fontSize: 11.5,
                    fontWeight: low ? FontWeight.w600 : FontWeight.w400,
                    color: low
                        ? PharmacyColors.warning
                        : PharmacyColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '₹${item['sellingPrice'] ?? item['price_per_unit'] ?? 0}',
            style: PharmacyType.sans(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: PharmacyColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  static List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];
  static String _message(DioException e) {
    final d = e.response?.data;
    if (d is Map)
      return d['message']?.toString() ??
          d['error']?.toString() ??
          'Request failed';
    return e.message ?? 'Request failed';
  }
}
