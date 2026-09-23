import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/pharmacy_type.dart';
import 'package:intl/intl.dart';
import '../theme/pharmacy_colors.dart';
import '../../../core/network/api_service.dart';
import '../widgets/pharmacy_ui.dart';

class MedicineDetails extends ConsumerStatefulWidget {
  final String medicineId;
  const MedicineDetails({super.key, required this.medicineId});

  @override
  ConsumerState<MedicineDetails> createState() => _MedicineDetailsState();
}

class _MedicineDetailsState extends ConsumerState<MedicineDetails>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  bool _isLoading = true;
  Map<String, dynamic>? _medicine;
  List<dynamic> _batches = [];
  List<dynamic> _adjustments = [];

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().getMedicineById(widget.medicineId);
      final data = response.data;
      setState(() {
        _medicine = data['medicine'];
        _batches = data['batches'] ?? [];
        _adjustments = data['adjustments'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pharmacyErrorMessage(
                e,
                fallback: 'Couldn\'t load this medicine.',
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: PharmacyColors.error,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
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
    bool prescriptionRequired = m['prescriptionRequired'] == true;

    final result = await showPharmacySheet<bool>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Edit Medicine',
              style: PharmacyType.sans(
                fontSize: 16,
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
                      icon: Icons.medication_outlined,
                      required: true,
                    ),
                    PharmacyTextField(
                      label: 'Generic Name',
                      controller: genericCtrl,
                      icon: CupertinoIcons.textformat,
                    ),
                    PharmacyDropdownField<String>(
                      label: 'Category',
                      value: category,
                      icon: CupertinoIcons.square_grid_2x2,
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
                                  Text(e.value),
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
                            icon: CupertinoIcons.money_dollar,
                            isDecimal: true,
                            required: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PharmacyTextField(
                            label: 'Reorder Level',
                            controller: reorderCtrl,
                            icon: CupertinoIcons.exclamationmark_triangle,
                            isNum: true,
                          ),
                        ),
                      ],
                    ),
                    PharmacySwitchRow(
                      label: 'Prescription Required',
                      subtitle: 'Buyers must attach a valid prescription',
                      icon: CupertinoIcons.doc_text,
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
                    label: 'Save Changes',
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
      if (mounted)
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
              'Add Stock',
              style: PharmacyType.sans(
                fontSize: 16,
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
                      icon: CupertinoIcons.number,
                      required: true,
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: PharmacyTextField(
                            label: 'Quantity',
                            controller: qtyCtrl,
                            icon: CupertinoIcons.cube_box,
                            isNum: true,
                            required: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PharmacyTextField(
                            label: 'Purchase Price (₹)',
                            controller: purchaseCtrl,
                            icon: CupertinoIcons.money_dollar,
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
                        if (picked != null)
                          setSheetState(() => expiryDate = picked);
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
                    label: 'Add Stock',
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
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Batch number, quantity and expiry date are required',
            ),
            backgroundColor: PharmacyColors.warning,
          ),
        );
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
      if (mounted)
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Medicine deactivated'),
            backgroundColor: PharmacyColors.success,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted)
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

  @override
  Widget build(BuildContext context) {
    // The loading and not-found states keep the same app bar as the loaded
    // screen. Without it the page had no back button while it loaded, and it
    // jumped by the app bar's height the moment data arrived.
    if (_isLoading || _medicine == null) {
      return Scaffold(
        backgroundColor: PharmacyColors.bg,
        appBar: _appBar(showEdit: false),
        body: SafeArea(
          top: false,
          child: _isLoading
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

    final name = _medicine!['medicineName'] ?? 'Medicine';
    final qty = _medicine!['quantity'] ?? 0;
    final category =
        kMedicineCategories[_medicine!['category']] ??
        _medicine!['category'] ??
        'General';
    final categoryKey = _medicine!['category']?.toString();
    final requiresRx = _medicine!['prescriptionRequired'] == true;

    return Scaffold(
      backgroundColor: PharmacyColors.bg,
      appBar: _appBar(),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                PharmacyCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          PharmacyIconBadge(
                            icon: medicineCategoryIcon(categoryKey),
                            color: PharmacyColors.green,
                            size: 44,
                            iconSize: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: PharmacyType.sans(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: PharmacyColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$category · ${_medicine!['genericName'] ?? ''}',
                                  style: PharmacyType.sans(
                                    fontSize: 12,
                                    color: PharmacyColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      PharmacyStatusPill(
                        text: requiresRx
                            ? 'Prescription Required'
                            : 'Prescription Not Required',
                        color: requiresRx
                            ? PharmacyColors.warning
                            : PharmacyColors.textSecondary,
                        background: requiresRx
                            ? PharmacyColors.warningBg
                            : PharmacyColors.bgSecondary,
                      ),
                      const SizedBox(height: 16),
                      Container(height: 1, color: PharmacyColors.border),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(child: _metric('Total Stock', '$qty')),
                          Container(
                            width: 1,
                            height: 30,
                            color: PharmacyColors.border,
                          ),
                          Expanded(
                            child: _metric(
                              'Reorder Level',
                              '${_medicine!['reorderLevel'] ?? 0}',
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 30,
                            color: PharmacyColors.border,
                          ),
                          Expanded(
                            child: _metric(
                              'Selling Price',
                              '₹${_medicine!['sellingPrice'] ?? 0}',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                TabBar(
                  controller: _tabs,
                  labelColor: PharmacyColors.green,
                  unselectedLabelColor: PharmacyColors.textSecondary,
                  indicatorColor: PharmacyColors.green,
                  labelStyle: PharmacyType.sans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: PharmacyType.sans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                  tabs: const [
                    Tab(text: 'Batches'),
                    Tab(text: 'Stock Log'),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 420,
                  child: TabBarView(
                    controller: _tabs,
                    children: [_batchesTab(), _stockLogTab()],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              color: PharmacyColors.bg,
              border: Border(
                top: BorderSide(color: PharmacyColors.borderStrong),
              ),
            ),
            // Without this the buttons sit under the device gesture bar.
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: PharmacySecondaryButton(
                      label: 'Add Stock',
                      icon: CupertinoIcons.add,
                      onPressed: _showAddStockSheet,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PharmacySecondaryButton(
                      label: 'Deactivate',
                      color: PharmacyColors.error,
                      onPressed: _confirmDeactivate,
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
      'Medicine Details',
      style: PharmacyType.sans(
        fontSize: 16,
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
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: PharmacyColors.green,
            ),
          ),
        ),
    ],
  );

  Widget _metric(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Text(
        value,
        style: PharmacyType.sans(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: PharmacyColors.textPrimary,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        label,
        textAlign: TextAlign.center,
        style: PharmacyType.sans(
          fontSize: 10.5,
          color: PharmacyColors.textSecondary,
        ),
      ),
    ],
  );

  Widget _batchesTab() {
    if (_batches.isEmpty) {
      return const PharmacyEmptyStateInline(
        icon: CupertinoIcons.cube_box,
        text: 'No active batches found',
      );
    }
    return ListView.builder(
      itemCount: _batches.length,
      itemBuilder: (context, index) {
        final b = _batches[index];
        final expiry = b['expiryDate'] != null
            ? DateFormat('dd MMM yyyy').format(DateTime.parse(b['expiryDate']))
            : 'N/A';
        return PharmacyCard(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    b['batchNumber'] ?? '',
                    style: PharmacyType.sans(
                      fontSize: 13.5,
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
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: PharmacyColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  PharmacyStatusPill(
                    text: 'Active',
                    color: PharmacyColors.success,
                    background: PharmacyColors.greenLight,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _stockLogTab() {
    if (_adjustments.isEmpty) {
      return const PharmacyEmptyStateInline(
        icon: CupertinoIcons.waveform_path,
        text: 'No stock activity yet',
      );
    }
    return ListView.builder(
      itemCount: _adjustments.length,
      itemBuilder: (context, index) {
        final a = _adjustments[index];
        final addition = a['adjustmentType'] == 'addition';
        return PharmacyCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                addition ? CupertinoIcons.arrow_up : CupertinoIcons.arrow_down,
                size: 16,
                color: addition ? PharmacyColors.success : PharmacyColors.error,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a['reason'] ?? 'Adjustment',
                      style: PharmacyType.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: PharmacyColors.textPrimary,
                      ),
                    ),
                    Text(
                      DateFormat(
                        'dd MMM hh:mm a',
                      ).format(DateTime.parse(a['createdAt'])),
                      style: PharmacyType.sans(
                        fontSize: 11,
                        color: PharmacyColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${a['adjustmentQuantity'] > 0 ? '+' : ''}${a['adjustmentQuantity']}',
                style: PharmacyType.sans(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: addition
                      ? PharmacyColors.success
                      : PharmacyColors.error,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
