import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_service.dart';
import '../../dashboard/providers/dashboard_provider.dart';

class AddMedicine extends ConsumerStatefulWidget {
  const AddMedicine({super.key});

  @override
  ConsumerState<AddMedicine> createState() => _AddMedicineState();
}

class _AddMedicineState extends ConsumerState<AddMedicine> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _genericNameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();
  final _reorderController = TextEditingController();

  bool _isLoading = false;
  bool _prescriptionRequired = false;

  @override
  void dispose() {
    _nameController.dispose();
    _genericNameController.dispose();
    _categoryController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _reorderController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    
    try {
      final payload = {
        'medicineName': _nameController.text.trim(),
        'genericName': _genericNameController.text.trim(),
        'category': _categoryController.text.trim().isEmpty ? 'General' : _categoryController.text.trim(),
        'sellingPrice': double.tryParse(_priceController.text) ?? 0,
        'quantity': int.tryParse(_stockController.text) ?? 0,
        'reorderLevel': int.tryParse(_reorderController.text) ?? 10,
        'prescriptionRequired': _prescriptionRequired,
        'isActive': true,
      };

      await ApiService().createMedicine(payload);
      
      // Refresh inventory
      ref.read(pharmacyDashboardProvider.notifier).loadMedicines();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Medicine added successfully'), backgroundColor: AppTheme.success));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error));
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
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        title: Text('Add New Medicine', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildField('Medicine Name *', _nameController, Iconsax.box),
                _buildField('Generic Name (Brand) *', _genericNameController, Iconsax.text),
                _buildField('Category (e.g. Tablets, Syrups)', _categoryController, Iconsax.category),
                
                Row(
                  children: [
                    Expanded(child: _buildField('Selling Price (₹) *', _priceController, Iconsax.money, isNum: true)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildField('Initial Stock *', _stockController, Iconsax.box_add, isNum: true)),
                  ],
                ),
                
                _buildField('Reorder Alert Level', _reorderController, Iconsax.warning_2, isNum: true, hint: 'e.g. 10'),
                
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Iconsax.document_text, color: AppTheme.textSecondary, size: 20),
                          const SizedBox(width: 12),
                          Text('Prescription Required', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppTheme.textPrimary)),
                        ],
                      ),
                      Switch(
                        value: _prescriptionRequired,
                        activeColor: AppTheme.accent,
                        onChanged: (val) => setState(() => _prescriptionRequired = val),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _isLoading 
                      ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Add Medicine', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, IconData icon, {bool isNum = false, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            keyboardType: isNum ? TextInputType.number : TextInputType.text,
            validator: (v) => label.contains('*') && (v == null || v.isEmpty) ? 'Required field' : null,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: Icon(icon, size: 20, color: AppTheme.textTertiary),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.accent)),
            ),
          ),
        ],
      ),
    );
  }
}
