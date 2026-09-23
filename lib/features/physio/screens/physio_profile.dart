import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import 'physio_availability.dart';
import 'physio_exercises.dart';
import 'physio_service_areas.dart';

class PhysioProfile extends ConsumerStatefulWidget {
  const PhysioProfile({super.key});

  @override
  ConsumerState<PhysioProfile> createState() => _PhysioProfileState();
}

class _PhysioProfileState extends ConsumerState<PhysioProfile> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(physioDashboardProvider.notifier).loadAll());
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final dashData = ref.watch(physioDashboardProvider);
    final profile = dashData.profile;

    final stats = dashData.stats;
    final rating = profile['averageRating'] ?? stats['averageRating'] ?? '0.0';
    final isVerified = profile['verificationStatus'] == 'approved' || user?.isVerified == true;
    
    final exp = profile['experienceYears'] ?? profile['experience'] ?? '--';
    final spec = (profile['specialization'] as List?)?.join(', ') ?? 'Physiotherapist';
    final totalConsultations = profile['totalConsultations'] ?? stats['totalConsultations'] ?? '--';
    final totalEarnings = profile['totalEarnings'] ?? stats['totalEarnings'] ?? '--';
    
    final earningsInfo = dashData.earnings;
    final commissionRate = earningsInfo['commissionRate'] ?? earningsInfo['totals']?['commissionRate'] ?? 20;
    final physioSplit = 100 - commissionRate;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SingleChildScrollView(child: Column(children: [
        Container(width: double.infinity, decoration: const BoxDecoration(gradient: AppTheme.physioGradient),
          child: SafeArea(bottom: false, child: Column(children: [
            const SizedBox(height: 16),
            Container(width: 90, height: 90, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20)]),
              child: Center(child: Text(user?.name.substring(0, 1) ?? 'P', style: GoogleFonts.manrope(fontSize: 36, fontWeight: FontWeight.w700, color: AppTheme.physioAccent)))),
            const SizedBox(height: 12),
            Text(user?.name ?? 'Physiotherapist', style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
            Text('$spec • $exp years', style: GoogleFonts.manrope(fontSize: 13, color: Colors.white70)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(CupertinoIcons.star, size: 14, color: Colors.amber), const SizedBox(width: 4),
                  Text('$rating', style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                ])),
              const SizedBox(width: 10),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: (isVerified ? AppTheme.success : AppTheme.warning).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  Icon(isVerified ? CupertinoIcons.checkmark_seal_fill : CupertinoIcons.clock, size: 14, color: Colors.white), const SizedBox(width: 4),
                  Text(isVerified ? 'Verified' : 'Pending', style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                ])),
            ]),
            const SizedBox(height: 20),
          ]))),
        Padding(padding: const EdgeInsets.all(20), child: Column(children: [
          Row(children: [
            _statBox('Sessions', '$totalConsultations'), const SizedBox(width: 12),
            _statBox('Reviews', profile['totalReviews']?.toString() ?? '--'), const SizedBox(width: 12),
            _statBox('Earnings', '₹$totalEarnings'),
          ]),
          const SizedBox(height: 20),
          _infoSection('Professional', [
            _infoRow(CupertinoIcons.doc, 'License', profile['licenseNumber'] ?? 'PT-XXXXXXXX'),
            _infoRow(CupertinoIcons.briefcase, 'Experience', '$exp years'),
            _infoRow(Icons.workspace_premium_outlined, 'Current Split', '$physioSplit% Earning ($commissionRate% platform fee)'),
            _infoRow(CupertinoIcons.money_dollar_circle, 'Clinic Fee', '₹${profile['consultationFee'] ?? '0'}'),
            _infoRow(CupertinoIcons.house, 'Home Visit', '₹${profile['homeVisitFee'] ?? '0'}'),
          ]),
          const SizedBox(height: 12),
          _infoSection('Service Areas', [
            _infoRow(CupertinoIcons.location, 'Areas', (profile['servesAreas'] as List?)?.join(', ') ?? 'No areas added'),
          ]),
          const SizedBox(height: 20),
          _menuItem(CupertinoIcons.settings, 'Settings', () {}),
          _menuItem(CupertinoIcons.checkmark_shield, 'My Availability', () {
             Navigator.push(context, MaterialPageRoute(builder: (c) => const PhysioAvailability()));
          }),
          _menuItem(CupertinoIcons.waveform_path, 'Exercises Library', () {
             Navigator.push(context, MaterialPageRoute(builder: (c) => const PhysioExercises()));
          }),
          _menuItem(CupertinoIcons.map, 'Service Areas', () {
             Navigator.push(context, MaterialPageRoute(builder: (c) => const PhysioServiceAreas()));
          }),
          _menuItem(CupertinoIcons.chat_bubble_text, 'Help & Support', () {}),
          const SizedBox(height: 12),
          _menuItem(Icons.logout_outlined, 'Sign Out', () {
            ref.read(authProvider.notifier).logout();
            Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
          }, isDestructive: true),
        ])),
      ])),
    );
  }

  Widget _statBox(String l, String v) => Expanded(child: Container(padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
    child: Column(children: [
      Text(v, style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
      const SizedBox(height: 4),
      Text(l, style: GoogleFonts.manrope(fontSize: 11, color: AppTheme.textSecondary)),
    ])));

  Widget _infoSection(String t, List<Widget> c) => Container(padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
      const SizedBox(height: 12), ...c,
    ]));

  Widget _infoRow(IconData i, String l, String v) => Padding(padding: const EdgeInsets.only(bottom: 12),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppTheme.physioAccent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
        child: Icon(i, size: 16, color: AppTheme.physioAccent)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l, style: GoogleFonts.manrope(fontSize: 12, color: AppTheme.textTertiary)),
        const SizedBox(height: 2),
        Text(v, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
      ])),
    ]));

  Widget _menuItem(IconData i, String t, VoidCallback onTap, {bool isDestructive = false}) => Container(margin: const EdgeInsets.only(bottom: 8),
    child: Material(color: Colors.white, borderRadius: BorderRadius.circular(14),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14),
        child: Container(padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: isDestructive ? AppTheme.error.withValues(alpha: 0.2) : AppTheme.border)),
          child: Row(children: [
            Icon(i, size: 20, color: isDestructive ? AppTheme.error : AppTheme.textSecondary),
            const SizedBox(width: 14),
            Expanded(child: Text(t, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w500, color: isDestructive ? AppTheme.error : AppTheme.textPrimary))),
            Icon(CupertinoIcons.chevron_right, size: 18, color: isDestructive ? AppTheme.error : AppTheme.textTertiary),
          ])))));
}
