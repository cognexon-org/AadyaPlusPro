import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../dashboard/providers/dashboard_provider.dart';

class PharmacyProfile extends ConsumerStatefulWidget {
  const PharmacyProfile({super.key});

  @override
  ConsumerState<PharmacyProfile> createState() => _PharmacyProfileState();
}

class _PharmacyProfileState extends ConsumerState<PharmacyProfile> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(pharmacyDashboardProvider.notifier).loadProfile());
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final dashData = ref.watch(pharmacyDashboardProvider);
    final profile = dashData.profile;
    
    final isVerified = user?.isVerified ?? false;
    final drugLicense = profile['drugLicenseNumber'] ?? profile['licenseNumber'] ?? 'Not added';
    final addressMap = profile['address'] ?? {};
    final addressText = addressMap is Map 
      ? '${addressMap['address'] ?? ''}\n${addressMap['city'] ?? ''}, ${addressMap['state'] ?? ''}'.trim()
      : 'Address not added';
    
    final deliveryRadius = profile['deliveryRadius'] ?? '5';
    final isDelivery = profile['deliveryAvailable'] == true;

    final stats = dashData.stats;
    final totalSales = stats['salesCount'] ?? stats['totalOrders'] ?? profile['totalOrders'] ?? '--';
    final totalRevenue = stats['totalSales'] ?? '--';
    final rating = profile['averageRating'] ?? '0.0';

    return Scaffold(backgroundColor: AppTheme.surface, body: 
      dashData.isLoading && profile.isEmpty 
        ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
        : SingleChildScrollView(child: Column(children: [
      Container(width: double.infinity, decoration: const BoxDecoration(gradient: AppTheme.pharmacyGradient),
        child: SafeArea(bottom: false, child: Column(children: [
          const SizedBox(height: 16),
          Container(width: 90, height: 90, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20)]),
            child: const Center(child: Icon(Iconsax.building, size: 40, color: AppTheme.accent))),
          const SizedBox(height: 12),
          Text(profile['pharmacyName'] ?? user?.name ?? 'Pharmacy', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          Text('Medical Store', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: Colors.white70)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _badge(Iconsax.star, '$rating'), const SizedBox(width: 10), _badge2(isVerified ? Iconsax.verify5 : Iconsax.clock, isVerified ? 'Licensed' : 'Pending'),
          ]),
          const SizedBox(height: 20),
        ]))),
      Padding(padding: const EdgeInsets.all(20), child: Column(children: [
        Row(children: [
          _sb('Orders', '$totalSales'), 
          const SizedBox(width: 12), 
          _sb('Items', '${dashData.medicines.length}'), 
          const SizedBox(width: 12), 
          _sb('Revenue', '₹$totalRevenue')
        ]),
        const SizedBox(height: 20),
        _sec('Store Details', [
          _ir(Iconsax.document, 'Drug License', drugLicense),
          _ir(Iconsax.location, 'Address', addressText),
          _ir(Iconsax.clock, 'Hours', profile['operatingHours'] ?? '8:00 AM - 10:00 PM'),
          _ir(Iconsax.call, 'Phone', user?.phone ?? profile['phone'] ?? '+91 N/A'),
        ]),
        const SizedBox(height: 12),
        _sec('Services', [
          // _ir(Iconsax.box, 'Categories', 'Tablets, Capsules, Syrups, Injections, Ointments'),
          _ir(Iconsax.truck, 'Delivery', isDelivery ? 'Available within ${deliveryRadius}km' : 'Not Available'),
          _ir(Iconsax.document_text, 'Prescriptions', 'Accepted'),
        ]),
        const SizedBox(height: 20),
        _mi(Iconsax.setting_2, 'Settings', () {}),
        _mi(Iconsax.chart_2, 'Stock Management', () {}),
        _mi(Iconsax.truck, 'Suppliers', () {}),
        _mi(Iconsax.document_text, 'Prescriptions', () {}),
        _mi(Iconsax.star, 'Reviews', () {}),
        _mi(Iconsax.message_question, 'Help', () {}),
        const SizedBox(height: 12),
        _mi(Iconsax.logout, 'Sign Out', () {
          ref.read(authProvider.notifier).logout();
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
        }, d: true),
      ])),
    ])));
  }
  Widget _badge(IconData i, String t) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
    child: Row(children: [Icon(i, size: 14, color: Colors.amber), const SizedBox(width: 4), Text(t, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white))]));
  Widget _badge2(IconData i, String t) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
    child: Row(children: [Icon(i, size: 14, color: Colors.white), const SizedBox(width: 4), Text(t, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white))]));
  Widget _sb(String l, String v) => Expanded(child: Container(padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
    child: Column(children: [Text(v, style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)), const SizedBox(height: 4), Text(l, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textSecondary))])));
  Widget _sec(String t, List<Widget> c) => Container(padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)), const SizedBox(height: 12), ...c]));
  Widget _ir(IconData i, String l, String v) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppTheme.accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
      child: Icon(i, size: 16, color: AppTheme.accent)),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(l, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textTertiary)), const SizedBox(height: 2),
      Text(v, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
    ]))]));
  Widget _mi(IconData i, String t, VoidCallback f, {bool d = false}) => Container(margin: const EdgeInsets.only(bottom: 8),
    child: Material(color: Colors.white, borderRadius: BorderRadius.circular(14),
      child: InkWell(onTap: f, borderRadius: BorderRadius.circular(14),
        child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: d ? AppTheme.error.withValues(alpha: 0.2) : AppTheme.border)),
          child: Row(children: [Icon(i, size: 20, color: d ? AppTheme.error : AppTheme.textSecondary), const SizedBox(width: 14),
            Expanded(child: Text(t, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w500, color: d ? AppTheme.error : AppTheme.textPrimary))),
            Icon(Iconsax.arrow_right_3, size: 18, color: d ? AppTheme.error : AppTheme.textTertiary)])))));
}
