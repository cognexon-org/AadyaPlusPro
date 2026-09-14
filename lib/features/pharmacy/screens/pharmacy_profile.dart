import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/pharmacy_store_provider.dart';
import 'pharmacy_inventory_ops.dart';
import 'pharmacy_online_settings.dart';
import 'pharmacy_procurement.dart';
import 'prescription_queue.dart';

class PharmacyProfile extends ConsumerWidget {
  const PharmacyProfile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final storeState = ref.watch(pharmacyStoreProvider);
    final store = storeState.selectedStore ?? const <String, dynamic>{};
    final address = Map<String, dynamic>.from((store['address'] as Map?) ?? const {});
    final addressText = [address['street'], address['city'], address['state'], address['pincode']].where((v) => v != null && '$v'.trim().isNotEmpty).join(', ');
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text('Pharmacy Operations', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          const PharmacyStoreSelector(),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(gradient: AppTheme.pharmacyGradient, borderRadius: BorderRadius.circular(18)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${store['name'] ?? user?.name ?? 'Pharmacy'}', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 6),
              Text('${store['code'] ?? ''}', style: GoogleFonts.plusJakartaSans(color: Colors.white70)),
              if (addressText.isNotEmpty) ...[const SizedBox(height: 6), Text(addressText, style: GoogleFonts.plusJakartaSans(color: Colors.white70))],
              const SizedBox(height: 10),
              Text('Drug license: ${store['drugLicenseNumber'] ?? store['licenseNumber'] ?? 'Not configured'}', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.white)),
            ]),
          ),
          const SizedBox(height: 18),
          _tile(context, 'Procurement & GRN', 'Suppliers, purchase orders, receiving and damaged stock', Icons.local_shipping_outlined, const PharmacyProcurement()),
          _tile(context, 'Transfers & Returns', 'Inter-store transfers, sales returns and stock visibility', Icons.swap_horiz, const PharmacyInventoryOps()),
          _tile(context, 'Prescription Queue', 'Review prescription-required online orders', Icons.medication_outlined, const PrescriptionQueue()),
          _tile(context, 'Online Store', 'Serviceability, delivery settings and coupons', Icons.storefront_outlined, const PharmacyOnlineSettings()),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => ref.read(authProvider.notifier).logout(),
            icon: const Icon(Icons.logout), label: const Text('Logout'),
          ),
        ]),
      ),
    );
  }

  Widget _tile(BuildContext context, String title, String subtitle, IconData icon, Widget page) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
    child: ListTile(
      leading: Icon(icon, color: AppTheme.pharmacyAccent),
      title: Text(title, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)),
    ),
  );
}
