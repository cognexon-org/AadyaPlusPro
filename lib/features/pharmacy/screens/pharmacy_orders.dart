import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../dashboard/providers/dashboard_provider.dart';

class PharmacyOrders extends ConsumerStatefulWidget {
  const PharmacyOrders({super.key});

  @override
  ConsumerState<PharmacyOrders> createState() => _PharmacyOrdersState();
}

class _PharmacyOrdersState extends ConsumerState<PharmacyOrders> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(pharmacyDashboardProvider.notifier).loadSales());
  }

  @override
  Widget build(BuildContext context) {
    final dashData = ref.watch(pharmacyDashboardProvider);
    final sales = dashData.recentTransactions;

    return Scaffold(backgroundColor: AppTheme.surface, body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Orders', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
        Text('Manage incoming orders', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textSecondary)),
      ])),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: TextField(decoration: InputDecoration(
        hintText: 'Search orders...', prefixIcon: const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Icon(Iconsax.search_normal, size: 18, color: AppTheme.textTertiary)),
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border)),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ))),
      const SizedBox(height: 12),
      dashData.isLoading && sales.isEmpty
        ? const Expanded(child: Center(child: CircularProgressIndicator(color: AppTheme.accent)))
        : sales.isEmpty
          ? Expanded(child: Center(child: Text('No orders found', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppTheme.textSecondary))))
          : Expanded(child: ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 20), itemCount: sales.length, itemBuilder: (_, i) {
              final sale = sales[i];
              final customerName = sale['customerName'] ?? sale['patientId']?['name'] ?? 'Walk-in Customer';
              
              final itemsList = (sale['items'] as List?) ?? [];
              final itemsDesc = itemsList.isEmpty ? 'Items' : itemsList.map((i) => i['medicineName']?.toString() ?? 'Med').take(2).join(', ') + (itemsList.length > 2 ? ' ...' : '');
              
              final amountStr = sale['totalAmount']?.toString() ?? '0';
              final status = sale['status']?.toString().toLowerCase() ?? 'pending';

              return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
                child: Column(children: [
                  Row(children: [
                    Container(width: 44, height: 44, decoration: BoxDecoration(color: AppTheme.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                      child: const Center(child: Icon(Iconsax.bag_2, size: 22, color: AppTheme.accent))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(customerName, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(itemsDesc, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ])),
                    Text('₹$amountStr', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Text('ORD-${sale['_id']?.toString().substring(0, 6).toUpperCase() ?? '1000'}', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textTertiary)),
                    const Spacer(),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: status == 'completed' || status == 'dispensed' ? AppTheme.success.withValues(alpha: 0.1) : status == 'processing' ? AppTheme.info.withValues(alpha: 0.1) : AppTheme.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8)),
                      child: Text(status.toUpperCase(), style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600,
                        color: status == 'completed' || status == 'dispensed' ? AppTheme.success : status == 'processing' ? AppTheme.info : AppTheme.warning))),
                  ]),
                ]));
            })),
    ])));
  }
}
