import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import 'add_medicine.dart';
import 'medicine_details.dart';

class PharmacyMedicines extends ConsumerStatefulWidget {
  const PharmacyMedicines({super.key});

  @override
  ConsumerState<PharmacyMedicines> createState() => _PharmacyMedicinesState();
}

class _PharmacyMedicinesState extends ConsumerState<PharmacyMedicines> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(pharmacyDashboardProvider.notifier).loadMedicines());
  }

  @override
  Widget build(BuildContext context) {
    final dashData = ref.watch(pharmacyDashboardProvider);
    final medicines = dashData.medicines;

    return Scaffold(backgroundColor: AppTheme.surface, body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 12), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Medicines', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
          Text('${medicines.length} items in inventory', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textSecondary)),
        ]),
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddMedicine())),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(gradient: AppTheme.pharmacyGradient, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [const Icon(Iconsax.add, size: 16, color: Colors.white), const SizedBox(width: 6),
              Text('Add', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white))])),
        ),
      ])),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: TextField(decoration: InputDecoration(
        hintText: 'Search medicines...', prefixIcon: const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Icon(Iconsax.search_normal, size: 18, color: AppTheme.textTertiary)),
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border)),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ))),
      const SizedBox(height: 12),
      dashData.isLoading && medicines.isEmpty
        ? const Expanded(child: Center(child: CircularProgressIndicator(color: AppTheme.accent)))
        : medicines.isEmpty
          ? Expanded(child: Center(child: Text('No medicines found in inventory', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppTheme.textSecondary))))
          : Expanded(child: ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 20), itemCount: medicines.length, itemBuilder: (_, i) {
              final m = medicines[i];
              final stock = int.tryParse(m['quantity']?.toString() ?? '0') ?? 0;
              final reorderLevel = int.tryParse(m['reorderLevel']?.toString() ?? '10') ?? 10;
              final lowStock = stock <= reorderLevel;
              final name = m['medicineName'] ?? m['name'] ?? 'Medicine';
              final brand = m['genericName'] ?? m['brand'] ?? 'Generic';
              final price = m['sellingPrice']?.toString() ?? m['price']?.toString() ?? '0';
              final category = m['category'] ?? 'Tablets';

              return GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MedicineDetails(medicineId: m['_id']))),
                child: Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: lowStock ? AppTheme.warning.withValues(alpha: 0.3) : AppTheme.border)),
                  child: Row(children: [
                    Container(width: 44, height: 44, decoration: BoxDecoration(color: AppTheme.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                      child: const Center(child: Icon(Iconsax.box, size: 22, color: AppTheme.accent))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                      Text(brand, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
                      const SizedBox(height: 4),
                      Row(children: [
                        Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppTheme.accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4)),
                          child: Text(category, style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w500, color: AppTheme.accent))),
                        const SizedBox(width: 8),
                        Icon(Iconsax.box, size: 12, color: lowStock ? AppTheme.warning : AppTheme.textTertiary),
                        const SizedBox(width: 4),
                        Text('$stock units', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w500, color: lowStock ? AppTheme.warning : AppTheme.textTertiary)),
                      ]),
                    ])),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('₹$price', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                      if (lowStock) ...[
                        const SizedBox(height: 4),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppTheme.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                          child: Text('Low Stock', style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.warning))),
                      ],
                    ]),
                  ])),
              );
            })),
    ])));
  }
}
