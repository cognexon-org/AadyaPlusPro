import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/pharmacy_type.dart';
import '../theme/pharmacy_colors.dart';
import '../../../core/network/api_service.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../widgets/pharmacy_ui.dart';

class AddMedicine extends ConsumerStatefulWidget {
  const AddMedicine({super.key});

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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Medicine added successfully'),
            backgroundColor: PharmacyColors.success,
          ),
        );
        Navigator.pop(context);
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
          'Add Medicine',
          style: PharmacyType.sans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: PharmacyColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  PharmacyTextField(
                    label: 'Medicine Name',
                    controller: _nameController,
                    icon: Icons.medication_outlined,
                    required: true,
                    hint: 'Search medicine name...',
                  ),
                  if (_searchingCatalog)
                    const Positioned(
                      right: 12,
                      top: 30,
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
              if (_suggestions.isNotEmpty) _buildSuggestions(),
              PharmacyTextField(
                label: 'Generic Name',
                controller: _genericNameController,
                icon: CupertinoIcons.textformat,
                required: true,
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: PharmacyDropdownField<String>(
                      label: 'Category',
                      value: _category,
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
                          setState(() => _category = v ?? _category),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PharmacyTextField(
                      label: 'Strength',
                      controller: _strengthController,
                      icon: Icons.monitor_weight_outlined,
                      hint: 'e.g. 500mg',
                    ),
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: PharmacyTextField(
                      label: 'Selling Price (₹)',
                      controller: _priceController,
                      // icon: ,
                      hint: '₹',
                      isDecimal: true,
                      required: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PharmacyTextField(
                      label: 'Initial Stock',
                      controller: _stockController,
                      icon: CupertinoIcons.cube_box,
                      isNum: true,
                      hint: 'Optional',
                    ),
                  ),
                ],
              ),
              if (_hasInitialStock) ...[
                PharmacyCard(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  borderColor: PharmacyColors.info.withValues(alpha: 0.2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            CupertinoIcons.info_circle,
                            size: 16,
                            color: PharmacyColors.info,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Stock is tracked as a batch — batch number and expiry are required to add initial stock.',
                              style: PharmacyType.sans(
                                fontSize: 12,
                                color: PharmacyColors.info,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      PharmacyTextField(
                        label: 'Batch Number',
                        controller: _batchNumberController,
                        icon: CupertinoIcons.number,
                        required: true,
                      ),
                      PharmacyPickerField(
                        label: 'Expiry Date',
                        required: true,
                        valueText: _expiryDate == null
                            ? 'Select expiry date'
                            : '${_expiryDate!.day}/${_expiryDate!.month}/${_expiryDate!.year}',
                        onTap: _pickExpiryDate,
                      ),
                      PharmacyTextField(
                        label: 'Purchase Price (₹)',
                        controller: _purchasePriceController,
                        icon: Icons.receipt_long_outlined,
                        isDecimal: true,
                        hint: 'Defaults to selling price',
                        margin: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ],
              PharmacyTextField(
                label: 'Reorder Alert Level',
                controller: _reorderController,
                icon: CupertinoIcons.exclamationmark_triangle,
                isNum: true,
                hint: 'e.g. 10',
              ),
              PharmacySwitchRow(
                label: 'Requires Prescription',
                icon: CupertinoIcons.doc_text,
                value: _prescriptionRequired,
                onChanged: (val) => setState(() => _prescriptionRequired = val),
                margin: EdgeInsets.zero,
              ),
              const SizedBox(height: 28),
              PharmacyButton(
                label: 'Save Medicine',
                loading: _isLoading,
                onPressed: _submit,
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
        separatorBuilder: (_, __) =>
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
                fontSize: 13.5,
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
