import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/pharmacy_type.dart';
import '../theme/pharmacy_colors.dart';
import '../../../core/network/api_service.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../providers/pharmacy_medicines_provider.dart';
import '../widgets/pharmacy_barcode_scanner.dart';
import '../widgets/pharmacy_ui.dart';

class AddMedicine extends ConsumerStatefulWidget {
  /// Pre-fills the barcode — set when a scan found no matching medicine.
  final String? initialBarcode;
  const AddMedicine({super.key, this.initialBarcode});

  @override
  ConsumerState<AddMedicine> createState() => _AddMedicineState();
}

class _AddMedicineState extends ConsumerState<AddMedicine> {
  final _nameController = TextEditingController();
  final _genericNameController = TextEditingController();
  final _strengthController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();
  final _reorderController = TextEditingController();
  final _batchNumberController = TextEditingController();
  final _purchasePriceController = TextEditingController();
  late final _barcodeController = TextEditingController(
    text: widget.initialBarcode ?? '',
  );
  final _nameFocus = FocusNode();

  bool _isLoading = false;
  bool _prescriptionRequired = false;
  DateTime? _expiryDate;
  String _category = 'tablet';

  Timer? _catalogDebounce;
  bool _searchingCatalog = false;
  List<Map<String, dynamic>> _suggestions = [];

  bool get _hasInitialStock => (int.tryParse(_stockController.text) ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    _stockController.addListener(_onStockChanged);
    _nameController.addListener(_onNameChanged);
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus) setState(() => _suggestions = []);
    });
  }

  void _onStockChanged() => setState(() {});

  void _onNameChanged() {
    _catalogDebounce?.cancel();
    final query = _nameController.text.trim();
    if (query.length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    _catalogDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _searchCatalog(query),
    );
  }

  Future<void> _searchCatalog(String query) async {
    setState(() => _searchingCatalog = true);
    try {
      final response = await ApiService().searchMedicineCatalog(query);
      final results =
          (response.data?['results'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [];
      if (!mounted || _nameController.text.trim() != query) return;
      setState(() => _suggestions = results);
    } catch (_) {
      // Reference-catalog lookup is a convenience only — never block manual entry.
      if (mounted) setState(() => _suggestions = []);
    } finally {
      if (mounted) setState(() => _searchingCatalog = false);
    }
  }

  void _applySuggestion(Map<String, dynamic> suggestion) {
    _nameController.removeListener(_onNameChanged);
    _nameController.text =
        suggestion['name']?.toString() ?? _nameController.text;
    _nameController.addListener(_onNameChanged);
    _genericNameController.text =
        suggestion['genericName']?.toString() ?? _genericNameController.text;
    _strengthController.text =
        suggestion['strength']?.toString() ?? _strengthController.text;
    final suggestedCategory = suggestion['category']?.toString();
    setState(() {
      if (suggestedCategory != null &&
          kMedicineCategories.containsKey(suggestedCategory)) {
        _category = suggestedCategory;
      }
      _suggestions = [];
    });
    _nameFocus.unfocus();
  }

  @override
  void dispose() {
    _catalogDebounce?.cancel();
    _stockController.removeListener(_onStockChanged);
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _genericNameController.dispose();
    _strengthController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _reorderController.dispose();
    _batchNumberController.dispose();
    _purchasePriceController.dispose();
    _barcodeController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _pickExpiryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now().add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) setState(() => _expiryDate = picked);
  }

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty ||
        _genericNameController.text.trim().isEmpty ||
        _priceController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Medicine name, generic name and selling price are required',
          ),
          backgroundColor: PharmacyColors.warning,
        ),
      );
      return;
    }

    final stockQty = int.tryParse(_stockController.text) ?? 0;
    if (stockQty > 0) {
      if (_batchNumberController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Batch number is required to add initial stock'),
            backgroundColor: PharmacyColors.warning,
          ),
        );
        return;
      }
      if (_expiryDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Expiry date is required to add initial stock'),
            backgroundColor: PharmacyColors.warning,
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      // Medicine CRUD deliberately can't set quantity directly (stock is
      // ledger-controlled server-side) — the actual stock intake happens via
      // a separate call below. Without that second call, "Initial Stock"
      // typed here was silently discarded and every new medicine started at
      // zero units with no way to fix it from this screen.
      final payload = {
        'medicineName': _nameController.text.trim(),
        'genericName': _genericNameController.text.trim(),
        'category': _category,
        'strength': _strengthController.text.trim(),
        'sellingPrice': double.tryParse(_priceController.text) ?? 0,
        'reorderLevel': int.tryParse(_reorderController.text) ?? 10,
        'prescriptionRequired': _prescriptionRequired,
        'isActive': true,
        if (_barcodeController.text.trim().isNotEmpty)
          'barcode': _barcodeController.text.trim(),
      };

      final createResponse = await ApiService().createMedicine(payload);
      final medicineId = createResponse.data?['medicine']?['_id'];

      if (stockQty > 0 && medicineId != null) {
        try {
          await ApiService().addMedicineStock(medicineId, {
            'batchNumber': _batchNumberController.text.trim(),
            'quantity': stockQty,
            'purchasePrice':
                double.tryParse(_purchasePriceController.text) ??
                double.tryParse(_priceController.text) ??
                0,
            'sellingPrice': double.tryParse(_priceController.text) ?? 0,
            'expiryDate': _expiryDate!.toIso8601String(),
          });
        } catch (stockError) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Medicine created, but adding stock failed: $stockError. Add stock from the medicine\'s details screen.',
                ),
                backgroundColor: PharmacyColors.warning,
              ),
            );
          }
        }
      }

      // Refresh inventory
      ref.read(pharmacyDashboardProvider.notifier).loadMedicines();
      ref.read(pharmacyMedicinesProvider.notifier).loadMedicines(silent: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Medicine added successfully'),
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
                fallback: 'Something went wrong. Please try again.',
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: PharmacyColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PharmacyColors.bg,
      appBar: AppBar(
        backgroundColor: PharmacyColors.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: PharmacyColors.textPrimary),
        title: Text(
          'Add medicine',
          style: PharmacyType.sans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: PharmacyColors.textPrimary,
          ),
        ),
      ),
      // Save stays reachable at the foot of the form instead of scrolling
      // away below the last field.
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        decoration: const BoxDecoration(
          color: PharmacyColors.bg,
          border: Border(top: BorderSide(color: PharmacyColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: PharmacyButton(
            label: 'Save medicine',
            loading: _isLoading,
            onPressed: _submit,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PharmacySectionTitle('Medicine'),
              Stack(
                children: [
                  PharmacyTextField(
                    label: 'Medicine name',
                    controller: _nameController,
                    icon: LucideIcons.search,
                    required: true,
                    hint: 'Start typing to search the catalogue',
                  ),
                  if (_searchingCatalog)
                    const Positioned(
                      right: 14,
                      top: 36,
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: PharmacyColors.green,
                        ),
                      ),
                    ),
                ],
              ),
              if (_suggestions.isNotEmpty) _buildSuggestions(),
              PharmacyTextField(
                label: 'Barcode',
                controller: _barcodeController,
                icon: LucideIcons.barcode,
                hint: 'Scan or type the code on the pack',
                trailing: IconButton(
                  tooltip: 'Scan barcode',
                  icon: const Icon(
                    LucideIcons.scanBarcode,
                    size: 20,
                    color: PharmacyColors.green,
                  ),
                  onPressed: () async {
                    final code = await scanPharmacyBarcode(context);
                    if (code != null) {
                      setState(() => _barcodeController.text = code);
                    }
                  },
                ),
              ),
              PharmacyTextField(
                label: 'Generic name',
                controller: _genericNameController,
                icon: LucideIcons.type,
                required: true,
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: PharmacyDropdownField<String>(
                      label: 'Category',
                      value: _category,
                      items: kMedicineCategories.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Row(
                                children: [
                                  Icon(
                                    medicineCategoryIcon(e.key),
                                    size: 16,
                                    color: PharmacyColors.textHeading,
                                  ),
                                  const SizedBox(width: 9),
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
                          setState(() => _category = v ?? _category),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PharmacyTextField(
                      label: 'Strength',
                      controller: _strengthController,
                      hint: 'e.g. 500mg',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const PharmacySectionTitle('Price & stock'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: PharmacyTextField(
                      label: 'Selling price (₹)',
                      controller: _priceController,
                      icon: LucideIcons.indianRupee,
                      hint: '0',
                      isDecimal: true,
                      required: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PharmacyTextField(
                      label: 'Opening stock',
                      controller: _stockController,
                      icon: LucideIcons.package,
                      isNum: true,
                      hint: 'Optional',
                    ),
                  ),
                ],
              ),
              // Batch details slide open only once there is stock to record.
              AnimatedSize(
                duration: PharmacyMotion.medium,
                curve: PharmacyMotion.enter,
                alignment: Alignment.topCenter,
                child: !_hasInitialStock
                    ? const SizedBox(width: double.infinity)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 1),
                                  child: Icon(
                                    LucideIcons.info,
                                    size: 14,
                                    color: PharmacyColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    'Stock is tracked by batch, so the batch number and expiry printed on the pack are needed.',
                                    style: PharmacyType.sans(
                                      fontSize: 11.5,
                                      height: 1.45,
                                      color: PharmacyColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: PharmacyTextField(
                                  label: 'Batch number',
                                  controller: _batchNumberController,
                                  icon: LucideIcons.hash,
                                  required: true,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: PharmacyPickerField(
                                  label: 'Expiry',
                                  required: true,
                                  valueText: _expiryDate == null
                                      ? 'Select'
                                      : '${_expiryDate!.day}/${_expiryDate!.month}/${_expiryDate!.year}',
                                  onTap: _pickExpiryDate,
                                ),
                              ),
                            ],
                          ),
                          PharmacyTextField(
                            label: 'Purchase price (₹)',
                            controller: _purchasePriceController,
                            icon: LucideIcons.receiptText,
                            isDecimal: true,
                            hint: 'Defaults to the selling price',
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 8),
              const PharmacySectionTitle('Alerts & rules'),
              PharmacyTextField(
                label: 'Reorder alert at',
                controller: _reorderController,
                icon: LucideIcons.bellRing,
                isNum: true,
                hint: 'e.g. 10 units',
              ),
              PharmacyGroup(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 10, 4),
                    child: PharmacySwitchRow(
                      label: 'Prescription required',
                      subtitle: 'Customers must attach a valid prescription',
                      value: _prescriptionRequired,
                      onChanged: (val) =>
                          setState(() => _prescriptionRequired = val),
                      margin: EdgeInsets.zero,
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

  Widget _buildSuggestions() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16, top: 0),
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: PharmacyColors.card,
        borderRadius: BorderRadius.circular(PharmacyColors.radiusCard),
        border: Border.all(color: PharmacyColors.border),
        boxShadow: PharmacyColors.shadowElevated,
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: _suggestions.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: PharmacyColors.border),
        itemBuilder: (context, index) {
          final s = _suggestions[index];
          final name = s['name']?.toString() ?? '';
          final generic = s['genericName']?.toString() ?? '';
          final strength = s['strength']?.toString() ?? '';
          final categoryKey = s['category']?.toString();
          final category = kMedicineCategories[categoryKey] ?? '';
          return ListTile(
            dense: true,
            leading: Icon(
              medicineCategoryIcon(categoryKey),
              size: 20,
              color: PharmacyColors.green,
            ),
            title: Text(
              name,
              style: PharmacyType.sans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              [
                generic,
                strength,
                category,
              ].where((v) => v.isNotEmpty).join(' · '),
              style: PharmacyType.sans(
                fontSize: 11.5,
                color: PharmacyColors.textSecondary,
              ),
            ),
            onTap: () => _applySuggestion(s),
          );
        },
      ),
    );
  }
}
