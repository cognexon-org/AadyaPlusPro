import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/pharmacy_type.dart';
import 'package:intl/intl.dart';
import '../theme/pharmacy_colors.dart';
import '../../../core/network/api_service.dart';
import '../providers/pharmacy_medicines_provider.dart';
import '../widgets/pharmacy_barcode_scanner.dart';
import '../widgets/pharmacy_ui.dart';

class MedicineDetails extends ConsumerStatefulWidget {
  final String medicineId;
  final Map<String, dynamic>? initialMedicine;
  const MedicineDetails({
    super.key,
    required this.medicineId,
    this.initialMedicine,
  });

  @override
  ConsumerState<MedicineDetails> createState() => _MedicineDetailsState();
}

class _MedicineDetailsState extends ConsumerState<MedicineDetails> {
  /// 0 = batches, 1 = stock log.
  int _tab = 0;
  Map<String, dynamic>? _medicine;
  List<dynamic> _batches = [];
  List<dynamic> _adjustments = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref
          .read(pharmacyMedicinesProvider.notifier)
          .loadMedicineDetails(
            widget.medicineId,
            initialMedicine: widget.initialMedicine,
          );
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadDetails() async {
    await ref
        .read(pharmacyMedicinesProvider.notifier)
        .loadMedicineDetails(widget.medicineId, force: true);
  }

  Future<void> _showEditSheet() async {
    final m = _medicine!;
    final nameCtrl = TextEditingController(
      text: m['medicineName']?.toString() ?? '',
    );
    final genericCtrl = TextEditingController(
      text: m['genericName']?.toString() ?? '',
    );
    String category = kMedicineCategories.containsKey(m['category']?.toString())
        ? m['category'].toString()
        : 'other';
    final priceCtrl = TextEditingController(
      text: (m['sellingPrice'] ?? '').toString(),
    );
    final reorderCtrl = TextEditingController(
      text: (m['reorderLevel'] ?? '').toString(),
    );
    final barcodeCtrl = TextEditingController(
      text: (m['barcode'] ?? '').toString(),
    );
    bool prescriptionRequired = m['prescriptionRequired'] == true;

    final result = await showPharmacySheet<bool>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Edit medicine',
              style: PharmacyType.sans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: PharmacyColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PharmacyTextField(
                      label: 'Medicine Name',
                      controller: nameCtrl,
                      icon: LucideIcons.pill,
                      required: true,
                    ),
                    PharmacyTextField(
                      label: 'Barcode',
                      controller: barcodeCtrl,
                      icon: LucideIcons.barcode,
                      hint: 'Scan the pack to link it',
                      trailing: IconButton(
                        tooltip: 'Scan barcode',
                        icon: const Icon(
                          LucideIcons.scanBarcode,
                          size: 20,
                          color: PharmacyColors.green,
                        ),
                        onPressed: () async {
                          final code = await scanPharmacyBarcode(ctx);
                          if (code != null) {
                            setSheetState(() => barcodeCtrl.text = code);
                          }
                        },
                      ),
                    ),
                    PharmacyTextField(
                      label: 'Generic Name',
                      controller: genericCtrl,
                      icon: LucideIcons.type,
                    ),
                    PharmacyDropdownField<String>(
                      label: 'Category',
                      value: category,
                      items: kMedicineCategories.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Row(
                                children: [
                                  Icon(
                                    medicineCategoryIcon(e.key),
                                    size: 17,
                                    color: PharmacyColors.green,
                                  ),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      e.value,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setSheetState(() => category = v ?? category),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: PharmacyTextField(
                            label: 'Selling Price (₹)',
                            controller: priceCtrl,
                            icon: LucideIcons.indianRupee,
                            isDecimal: true,
                            required: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PharmacyTextField(
                            label: 'Reorder Level',
                            controller: reorderCtrl,
                            icon: LucideIcons.triangleAlert,
                            isNum: true,
                          ),
                        ),
                      ],
                    ),
                    PharmacySwitchRow(
                      label: 'Prescription Required',
                      subtitle: 'Buyers must attach a valid prescription',
                      icon: LucideIcons.fileText,
                      value: prescriptionRequired,
                      onChanged: (v) =>
                          setSheetState(() => prescriptionRequired = v),
                      margin: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: PharmacySecondaryButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.pop(ctx, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PharmacyButton(
                    label: 'Save changes',
                    onPressed: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (result != true) return;

    try {
      await ApiService().updateMedicine(widget.medicineId, {
        'medicineName': nameCtrl.text.trim(),
        'genericName': genericCtrl.text.trim(),
        'category': category,
        'sellingPrice':
            double.tryParse(priceCtrl.text) ?? m['sellingPrice'] ?? 0,
        'reorderLevel':
            int.tryParse(reorderCtrl.text) ?? m['reorderLevel'] ?? 10,
        'prescriptionRequired': prescriptionRequired,
        'barcode': barcodeCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Medicine updated'),
            backgroundColor: PharmacyColors.success,
          ),
        );
        _loadDetails();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pharmacyErrorMessage(e, fallback: 'Couldn\'t save your changes.'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: PharmacyColors.error,
          ),
        );
      }
    }
  }

  Future<void> _showAddStockSheet() async {
    final batchCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final purchaseCtrl = TextEditingController();
    DateTime? expiryDate;

    final result = await showPharmacySheet<bool>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add stock',
              style: PharmacyType.sans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: PharmacyColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PharmacyTextField(
                      label: 'Batch Number',
                      controller: batchCtrl,
                      icon: LucideIcons.hash,
                      required: true,
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: PharmacyTextField(
                            label: 'Quantity',
                            controller: qtyCtrl,
                            icon: LucideIcons.package,
                            isNum: true,
                            required: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PharmacyTextField(
                            label: 'Purchase Price (₹)',
                            controller: purchaseCtrl,
                            icon: LucideIcons.indianRupee,
                            isDecimal: true,
                          ),
                        ),
                      ],
                    ),
                    PharmacyPickerField(
                      label: 'Expiry Date',
                      required: true,
                      valueText: expiryDate == null
                          ? 'Select expiry date'
                          : '${expiryDate!.day}/${expiryDate!.month}/${expiryDate!.year}',
                      margin: EdgeInsets.zero,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                          firstDate: DateTime.now().add(
                            const Duration(days: 1),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 3650),
                          ),
                        );
                        if (picked != null) {
                          setSheetState(() => expiryDate = picked);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: PharmacySecondaryButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.pop(ctx, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PharmacyButton(
                    label: 'Add stock',
                    onPressed: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (result != true) return;

    if (batchCtrl.text.trim().isEmpty ||
        qtyCtrl.text.trim().isEmpty ||
        expiryDate == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Batch number, quantity and expiry date are required',
            ),
            backgroundColor: PharmacyColors.warning,
          ),
        );
      }
      return;
    }

    try {
      await ApiService().addMedicineStock(widget.medicineId, {
        'batchNumber': batchCtrl.text.trim(),
        'quantity': int.tryParse(qtyCtrl.text) ?? 0,
        'purchasePrice':
            double.tryParse(purchaseCtrl.text) ??
            _medicine!['sellingPrice'] ??
            0,
        'sellingPrice': _medicine!['sellingPrice'] ?? 0,
        'expiryDate': expiryDate!.toIso8601String(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stock added'),
            backgroundColor: PharmacyColors.success,
          ),
        );
        _loadDetails();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pharmacyErrorMessage(e, fallback: 'Couldn\'t add that stock.'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: PharmacyColors.error,
          ),
        );
      }
    }
  }

  Future<void> _confirmDeactivate() async {
    final confirm = await PharmacyDialog.confirm(
      context,
      title: 'Deactivate Medicine',
      message:
          'This medicine will no longer be available for sale or online ordering. Continue?',
      confirmLabel: 'Deactivate',
    );

    if (!confirm) return;

    try {
      await ApiService().deactivateMedicine(widget.medicineId);
      if (mounted) {
        ref
            .read(pharmacyMedicinesProvider.notifier)
            .removeMedicine(widget.medicineId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Medicine deactivated'),
            backgroundColor: PharmacyColors.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pharmacyErrorMessage(
                e,
                fallback: 'Couldn\'t deactivate this medicine.',
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: PharmacyColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final medState = ref.watch(pharmacyMedicinesProvider);
    final detail = medState.detailsCache[widget.medicineId];

    Map<String, dynamic>? itemFromList = widget.initialMedicine;
    if (itemFromList == null || itemFromList.isEmpty) {
      for (final m in medState.items) {
        if (m['_id']?.toString() == widget.medicineId) {
          itemFromList = m;
          break;
        }
      }
    }

    final medicine = (detail != null && detail.medicine.isNotEmpty)
        ? detail.medicine
        : itemFromList;
    _medicine = medicine;
    _batches = detail?.batches ?? const [];
    _adjustments = detail?.adjustments ?? const [];

    final isLoading = detail == null
        ? medicine == null
        : (detail.isLoading && medicine == null);

    // The loading and not-found states keep the same app bar as the loaded
    // screen. Without it the page had no back button while it loaded, and it
    // jumped by the app bar's height the moment data arrived.
    if (isLoading || _medicine == null) {
      return Scaffold(
        backgroundColor: PharmacyColors.bg,
        appBar: _appBar(showEdit: false),
        body: SafeArea(
          top: false,
          child: isLoading
              ? const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: PharmacyDetailSkeleton(),
                )
              : const Center(
                  child: PharmacyEmptyStateInline(
                    icon: LucideIcons.packageSearch,
                    text: 'This medicine could not be loaded',
                  ),
                ),
        ),
      );
    }

    final name = '${_medicine!['medicineName'] ?? 'Medicine'}';
    final qty = num.tryParse('${_medicine!['quantity'] ?? 0}') ?? 0;
    final reorder = num.tryParse('${_medicine!['reorderLevel'] ?? 0}') ?? 0;
    final category =
        kMedicineCategories[_medicine!['category']] ??
        _medicine!['category'] ??
        'General';
    final categoryKey = _medicine!['category']?.toString();
    final requiresRx = _medicine!['prescriptionRequired'] == true;
    final out = qty <= 0;
    final low = !out && qty <= reorder;
    final tone = out
        ? PharmacyColors.error
        : low
        ? PharmacyColors.warning
        : PharmacyColors.greenDark;

    return Scaffold(
      backgroundColor: PharmacyColors.bg,
      appBar: _appBar(),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadDetails,
              color: PharmacyColors.green,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  PharmacyEntrance(
                    // Minimal: the header sits on the page, not in a card.
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: const BoxDecoration(
                                  color: PharmacyColors.panel,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  medicineCategoryIcon(categoryKey),
                                  size: 23,
                                  color: PharmacyColors.textHeading,
                                ),
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: PharmacyType.sans(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.3,
                                        color: PharmacyColors.textStrong,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      [
                                        '$category',
                                        '${_medicine!['strength'] ?? ''}'
                                            .trim(),
                                        '${_medicine!['genericName'] ?? ''}'
                                            .trim(),
                                      ].where((e) => e.isNotEmpty).join(' · '),
                                      style: PharmacyType.sans(
                                        fontSize: 11.5,
                                        color: PharmacyColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: out
                                      ? 'Out of stock'
                                      : low
                                      ? 'Low stock'
                                      : 'In stock',
                                  style: TextStyle(color: tone),
                                ),
                                if (requiresRx)
                                  const TextSpan(
                                    text: '  ·  Prescription required',
                                    style: TextStyle(
                                      color: PharmacyColors.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                            style: PharmacyType.sans(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _statBox(
                                  'On shelf',
                                  PharmacyCountUp(
                                    value: qty,
                                    format: (v) => '${v.round()}',
                                    style: PharmacyType.number(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: tone,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _statBox(
                                  'Reorder at',
                                  Text(
                                    '${reorder % 1 == 0 ? reorder.toInt() : reorder}',
                                    style: PharmacyType.number(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: PharmacyColors.textStrong,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _statBox(
                                  'Price',
                                  Text(
                                    pharmacyRupees(_medicine!['sellingPrice']),
                                    maxLines: 1,
                                    style: PharmacyType.number(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      color: PharmacyColors.textStrong,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  PharmacyEntrance(index: 1, child: _segmented()),
                  const SizedBox(height: 12),
                  // Rendered inline, not in a fixed-height TabBarView: the old
                  // 420px box scrolled inside this list, so the two fought over
                  // every drag.
                  AnimatedSwitcher(
                    duration: PharmacyMotion.medium,
                    switchInCurve: PharmacyMotion.enter,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                        position: Tween(
                          begin: const Offset(0, 0.03),
                          end: Offset.zero,
                        ).animate(a),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(_tab),
                      child: _tab == 0
                          ? _batchesTab(detail)
                          : _stockLogTab(detail),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              color: PharmacyColors.bg,
              border: Border(top: BorderSide(color: PharmacyColors.border)),
            ),
            // Without this the buttons sit under the device gesture bar.
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: PharmacySecondaryButton(
                      label: 'Deactivate',
                      color: PharmacyColors.error,
                      onPressed: _confirmDeactivate,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: PharmacyButton(
                      label: 'Add stock',
                      icon: LucideIcons.plus,
                      onPressed: _showAddStockSheet,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _appBar({bool showEdit = true}) => AppBar(
    backgroundColor: PharmacyColors.bg,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    iconTheme: const IconThemeData(color: PharmacyColors.textPrimary),
    title: Text(
      'Medicine details',
      style: PharmacyType.sans(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: PharmacyColors.textPrimary,
      ),
    ),
    actions: [
      if (showEdit)
        TextButton(
          onPressed: _showEditSheet,
          child: Text(
            'Edit',
            style: PharmacyType.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: PharmacyColors.green,
            ),
          ),
        ),
    ],
  );

  Widget _statBox(String label, Widget value) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
    decoration: BoxDecoration(
      color: PharmacyColors.panel,
      borderRadius: BorderRadius.circular(13),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: value,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: PharmacyType.sans(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: PharmacyColors.textSecondary,
          ),
        ),
      ],
    ),
  );

  /// Batches / Stock log switch. The white thumb slides between the halves.
  Widget _segmented() {
    final labels = [
      'Batches (${_batches.length})',
      'Stock log (${_adjustments.length})',
    ];
    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: PharmacyColors.panel,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: PharmacyMotion.medium,
            curve: PharmacyMotion.enter,
            alignment: _tab == 0 ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: PharmacyColors.bg,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: PharmacyColors.shadowElevated,
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < 2; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _tab = i),
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: PharmacyMotion.medium,
                        style: PharmacyType.sans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _tab == i
                              ? PharmacyColors.textStrong
                              : PharmacyColors.textSecondary,
                        ),
                        child: Text(labels[i]),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _batchesTab(MedicineDetailData? detail) {
    final bool isBatchesLoading =
        detail == null || detail.isLoading || !detail.hasLoadedBatches;
    if (_batches.isEmpty) {
      if (isBatchesLoading) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: PharmacyListSkeleton(count: 2),
        );
      }
      return const PharmacyEmptyStateInline(
        icon: LucideIcons.package,
        text: 'No active batches found',
      );
    }
    return Column(
      children: List.generate(_batches.length, (index) {
        final b = _batches[index];
        // tryParse throughout: one malformed record used to throw inside
        // build and take the whole tab down with it.
        final expiryAt = DateTime.tryParse('${b['expiryDate'] ?? ''}');
        final expiry = expiryAt != null
            ? DateFormat('dd MMM yyyy').format(expiryAt.toLocal())
            : 'N/A';
        final expired = expiryAt != null && expiryAt.isBefore(DateTime.now());
        return PharmacyCard(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${b['batchNumber'] ?? ''}',
                    style: PharmacyType.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: PharmacyColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Exp: $expiry',
                    style: PharmacyType.sans(
                      fontSize: 11.5,
                      color: PharmacyColors.textSecondary,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Text(
                    'Qty: ${b['availableQuantity']}',
                    style: PharmacyType.sans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: PharmacyColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    expired ? 'Expired' : 'Active',
                    style: PharmacyType.sans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: expired
                          ? PharmacyColors.error
                          : PharmacyColors.greenDark,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _stockLogTab(MedicineDetailData? detail) {
    final bool isLogsLoading =
        detail == null || detail.isLoading || !detail.hasLoadedBatches;
    if (_adjustments.isEmpty) {
      if (isLogsLoading) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: PharmacyListSkeleton(count: 2),
        );
      }
      return const PharmacyEmptyStateInline(
        icon: LucideIcons.activity,
        text: 'No stock activity yet',
      );
    }
    return Column(
      children: List.generate(_adjustments.length, (index) {
        final a = _adjustments[index];
        final addition = a['adjustmentType'] == 'addition';
        final change = num.tryParse('${a['adjustmentQuantity'] ?? 0}') ?? 0;
        final at = DateTime.tryParse('${a['createdAt'] ?? ''}');
        return PharmacyCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                addition ? LucideIcons.arrowUp : LucideIcons.arrowDown,
                size: 16,
                color: addition ? PharmacyColors.success : PharmacyColors.error,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${a['reason'] ?? 'Adjustment'}',
                      style: PharmacyType.sans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: PharmacyColors.textPrimary,
                      ),
                    ),
                    Text(
                      at == null
                          ? ''
                          : DateFormat('dd MMM hh:mm a').format(at.toLocal()),
                      style: PharmacyType.sans(
                        fontSize: 11.5,
                        color: PharmacyColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${change > 0 ? '+' : ''}$change',
                style: PharmacyType.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: addition
                      ? PharmacyColors.success
                      : PharmacyColors.error,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
