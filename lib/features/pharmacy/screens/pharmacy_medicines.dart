import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../providers/pharmacy_medicines_provider.dart';
import '../providers/pharmacy_store_provider.dart';
import '../theme/pharmacy_colors.dart';
import '../theme/pharmacy_type.dart';
import '../../../core/network/api_service.dart';
import '../widgets/pharmacy_barcode_scanner.dart';
import '../widgets/pharmacy_ui.dart';
import 'add_medicine.dart';
import 'bulk_upload_medicines.dart';
import 'medicine_details.dart';

/// The branch's catalogue. Each row shows what the pharmacist scans for —
/// name, how much is on the shelf relative to the reorder level, price — and
/// flags what needs action (low, out, expiring, prescription-only).
class PharmacyMedicines extends ConsumerStatefulWidget {
  const PharmacyMedicines({super.key});

  @override
  ConsumerState<PharmacyMedicines> createState() => _PharmacyMedicinesState();
}

class _PharmacyMedicinesState extends ConsumerState<PharmacyMedicines> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(pharmacyStoreProvider.notifier).initialize();
      if (mounted) {
        ref.read(pharmacyMedicinesProvider.notifier).initialize();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Searches as you type, once typing pauses — the old field only searched
  /// on the keyboard's submit key, which many pharmacists never pressed.
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final query = value.trim();
      if (query == ref.read(pharmacyMedicinesProvider).searchQuery) return;
      ref.read(pharmacyMedicinesProvider.notifier).setSearch(query);
    });
  }

  /// Scans a pack and goes straight to that medicine. An unknown code offers
  /// to add it with the barcode filled in, so the catalogue learns barcodes
  /// as stock is handled.
  Future<void> _scan() async {
    final code = await scanPharmacyBarcode(context);
    if (code == null || !mounted) return;
    try {
      final res = await ApiService().getMedicineByBarcode(code);
      final data = res.data;
      final med = data is Map && data['medicine'] is Map
          ? Map<String, dynamic>.from(data['medicine'] as Map)
          : null;
      if (!mounted) return;
      if (med != null && med['_id'] != null) {
        await _push(
          MedicineDetails(medicineId: '${med['_id']}', initialMedicine: med),
        );
        return;
      }
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) {
        if (mounted) {
          showPharmacyError(
            context,
            e,
            fallback: "Couldn't look up that code.",
          );
        }
        return;
      }
    }
    if (!mounted) return;
    final add = await showPharmacySheet<bool>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Not in your catalogue',
            style: PharmacyType.sans(
              fontSize: PharmacyType.title,
              fontWeight: FontWeight.w700,
              color: PharmacyColors.textStrong,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'No medicine at this branch has the barcode $code.',
            style: PharmacyType.sans(
              fontSize: PharmacyType.small,
              color: PharmacyColors.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          PharmacyButton(
            label: 'Add as new medicine',
            icon: LucideIcons.plus,
            onPressed: () => Navigator.pop(ctx, true),
          ),
          const SizedBox(height: 8),
          PharmacySecondaryButton(
            label: 'Cancel',
            onPressed: () => Navigator.pop(ctx, false),
          ),
        ],
      ),
    );
    if (add == true && mounted) {
      await _push(AddMedicine(initialBarcode: code));
    }
  }

  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(PharmacyPageRoute(builder: (_) => page));
    if (mounted) {
      ref.read(pharmacyMedicinesProvider.notifier).loadMedicines(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final medState = ref.watch(pharmacyMedicinesProvider);
    final visible = medState.filteredItems;

    return Scaffold(
      backgroundColor: PharmacyColors.bg,
      floatingActionButton: PharmacyEntrance(
        delay: const Duration(milliseconds: 250),
        offsetY: 24,
        child: PharmacyFab(
          label: 'Add medicine',
          icon: LucideIcons.plus,
          onPressed: () => _push(const AddMedicine()),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: PharmacyColors.bg,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PharmacyScreenHeader(
                    title: 'Medicines',
                    subtitle: medState.items.isEmpty
                        ? 'Search, restock and manage medicines'
                        : '${medState.items.length} in this branch',
                    trailing: IconButton(
                      tooltip: 'Bulk upload from CSV/Excel',
                      icon: const Icon(LucideIcons.fileSpreadsheet, size: 24),
                      color: PharmacyColors.greenDark,
                      onPressed: () => _push(const BulkUploadMedicines()),
                    ),
                  ),
                  const SizedBox(height: 12),
                  PharmacySearchField(
                    controller: _search,
                    hint: 'Search name, generic, brand or barcode',
                    onChanged: _onSearchChanged,
                    onScan: _scan,
                    onSubmitted: () {
                      _debounce?.cancel();
                      ref
                          .read(pharmacyMedicinesProvider.notifier)
                          .setSearch(_search.text.trim());
                    },
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _filterChip(
                          'All (${medState.items.length})',
                          MedFilter.all,
                          medState.filter,
                        ),
                        const SizedBox(width: 8),
                        _filterChip(
                          'Low stock (${medState.lowStockCount})',
                          MedFilter.lowStock,
                          medState.filter,
                        ),
                        const SizedBox(width: 8),
                        _filterChip(
                          'Expiring (${medState.expiringCount})',
                          MedFilter.expiring,
                          medState.filter,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _body(medState, visible)),
          ],
        ),
      ),
    );
  }

  Widget _body(
    PharmacyMedicinesState medState,
    List<Map<String, dynamic>> visible,
  ) {
    if (medState.isLoading && medState.items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
        children: const [PharmacyListSkeleton(count: 6)],
      );
    }
    if (medState.error != null && medState.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: PharmacyErrorBanner(
          message: medState.error!,
          onRetry: () =>
              ref.read(pharmacyMedicinesProvider.notifier).loadMedicines(),
        ),
      );
    }
    return RefreshIndicator(
      color: PharmacyColors.green,
      onRefresh: () => ref
          .read(pharmacyMedicinesProvider.notifier)
          .loadMedicines(silent: true),
      child: visible.isEmpty
          ? ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 100),
              children: [
                PharmacyEmptyStateInline(
                  icon: LucideIcons.pill,
                  text: medState.items.isEmpty
                      ? (medState.searchQuery.isNotEmpty
                            ? 'No medicines match "${medState.searchQuery}".'
                            : 'No medicines in this branch yet.\nAdd your first one to start selling online.')
                      : 'No medicines match this filter.',
                  action: medState.items.isEmpty && medState.searchQuery.isEmpty
                      ? SizedBox(
                          width: 190,
                          child: PharmacyButton(
                            label: 'Add medicine',
                            icon: LucideIcons.plus,
                            onPressed: () => _push(const AddMedicine()),
                          ),
                        )
                      : null,
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: visible.length,
              itemBuilder: (_, i) => PharmacyEntrance(
                key: ValueKey('med-${visible[i]['_id']}'),
                index: i,
                child: _card(visible[i]),
              ),
            ),
    );
  }

  Widget _filterChip(String label, MedFilter value, MedFilter current) =>
      PharmacyFilterChip(
        label: label,
        selected: current == value,
        onTap: () =>
            ref.read(pharmacyMedicinesProvider.notifier).setFilter(value),
      );

  Widget _card(Map<String, dynamic> item) {
    final qty =
        num.tryParse('${item['quantity'] ?? item['stock_quantity'] ?? 0}') ?? 0;
    final reorder =
        num.tryParse('${item['reorderLevel'] ?? item['reorder_level'] ?? 0}') ??
        0;
    final low = PharmacyMedicinesState.isLow(item);
    final out = qty <= 0;
    final expiring = PharmacyMedicinesState.isExpiring(item);
    final rx =
        item['prescriptionRequired'] == true ||
        item['prescription_required'] == true;
    final name =
        item['medicineName']?.toString() ??
        item['name']?.toString() ??
        'Medicine';
    final categoryKey = item['category']?.toString();
    final subtitle = [
      kMedicineCategories[categoryKey] ?? categoryKey,
      item['strength'],
      item['genericName'] ?? item['generic_name'],
    ].where((e) => e != null && '$e'.trim().isNotEmpty).join(' · ');

    // Fullness relative to a comfortable stock of three reorder levels, so a
    // medicine sitting exactly at its reorder level shows a third full.
    final target = reorder > 0 ? reorder * 3 : (qty > 0 ? qty : 1);
    final fill = (qty / target).clamp(0.0, 1.0).toDouble();
    final tone = out
        ? PharmacyColors.error
        : low
        ? PharmacyColors.warning
        : PharmacyColors.green;
    final reduced = PharmacyMotion.reduced(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PharmacyPressable(
        scale: 0.985,
        onTap: () {
          final id = item['_id']?.toString();
          if (id == null || id.isEmpty) return;
          _push(MedicineDetails(medicineId: id, initialMedicine: item));
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          decoration: BoxDecoration(
            color: PharmacyColors.panel,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: PharmacyColors.bg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      medicineCategoryIcon(categoryKey),
                      size: 19,
                      color: PharmacyColors.textHeading,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PharmacyType.sans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: PharmacyColors.textStrong,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PharmacyType.sans(
                              fontSize: 11.5,
                              color: PharmacyColors.textSecondary,
                            ),
                          ),
                        ],
                        if (rx || expiring || out || low) ...[
                          const SizedBox(height: 6),
                          // Status as coloured words, not filled badges.
                          Text.rich(
                            TextSpan(
                              children: [
                                for (final (i, t) in [
                                  if (out)
                                    ('Out of stock', PharmacyColors.error)
                                  else if (low)
                                    ('Low stock', PharmacyColors.warning),
                                  if (expiring)
                                    ('Expiring soon', PharmacyColors.warning),
                                  if (rx)
                                    ('Rx only', PharmacyColors.textSecondary),
                                ].indexed) ...[
                                  if (i > 0)
                                    const TextSpan(
                                      text: '  ·  ',
                                      style: TextStyle(
                                        color: PharmacyColors.textDisabled,
                                      ),
                                    ),
                                  TextSpan(
                                    text: t.$1,
                                    style: TextStyle(color: t.$2),
                                  ),
                                ],
                              ],
                            ),
                            style: PharmacyType.sans(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        pharmacyRupees(
                          item['sellingPrice'] ?? item['price_per_unit'],
                        ),
                        style: PharmacyType.number(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: PharmacyColors.textStrong,
                        ),
                      ),
                      Text(
                        'per unit',
                        style: PharmacyType.sans(
                          fontSize: 10.5,
                          color: PharmacyColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Stack(
                        children: [
                          Container(height: 6, color: PharmacyColors.bg),
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: reduced ? fill : 0, end: fill),
                            duration: const Duration(milliseconds: 800),
                            curve: Curves.easeOutCubic,
                            builder: (_, f, _) => FractionallySizedBox(
                              widthFactor: f,
                              child: Container(height: 6, color: tone),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${qty % 1 == 0 ? qty.toInt() : qty} in stock',
                    style: PharmacyType.number(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: out || low ? tone : PharmacyColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
