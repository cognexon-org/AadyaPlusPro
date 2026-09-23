import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../auth/providers/auth_provider.dart';
import '../../dashboard/providers/dashboard_provider.dart';

class PathologyProfile extends ConsumerStatefulWidget {
  const PathologyProfile({super.key});

  @override
  ConsumerState<PathologyProfile> createState() => _PathologyProfileState();
}

class _PathologyProfileState extends ConsumerState<PathologyProfile> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(pathologyDashboardProvider.notifier).loadProfile();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final dashData = ref.watch(pathologyDashboardProvider);
    final profile = dashData.profile;

    final isVerified = user?.isVerified ?? false;
    final licenseNumber = profile['licenseNumber'] ?? 'Not added';
    final addressMap = profile['labAddress'] ?? profile['address'] ?? {};
    final addressText = addressMap is Map 
      ? '${addressMap['address'] ?? ''}, ${addressMap['city'] ?? ''}, ${addressMap['state'] ?? ''}' 
      : 'Address not added';
    
    final services = profile['services'] ?? [];
    final servicesText = services is List && services.isNotEmpty ? services.join(', ') : 'No specific services added';

    final totalTests = dashData.stats['totalTests'] ?? dashData.stats['tests'] ?? '--';
    final revenue = dashData.stats['totalEarnings'] ?? dashData.stats['earnings'] ?? '--';

    return Scaffold(backgroundColor: AppTheme.surface, body: 
      dashData.isLoading && profile.isEmpty 
        ? const Center(child: CircularProgressIndicator(color: AppTheme.pathologyAccent))
        : SingleChildScrollView(child: Column(children: [
      Container(width: double.infinity, decoration: const BoxDecoration(gradient: AppTheme.pathologyGradient),
        child: SafeArea(bottom: false, child: Column(children: [
          const SizedBox(height: 16),
          Container(width: 90, height: 90, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20)]),
            child: const Center(child: Icon(Icons.biotech_outlined, size: 40, color: AppTheme.pathologyAccent))),
          const SizedBox(height: 12),
          Text(profile['labName'] ?? user?.name ?? 'Lab', style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          Text('Diagnostic Center', style: GoogleFonts.manrope(fontSize: 13, color: Colors.white70)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _badge(CupertinoIcons.star, '${profile['averageRating'] ?? '0.0'}', Colors.amber),
            const SizedBox(width: 10),
            _badge(
              isVerified ? CupertinoIcons.checkmark_seal_fill : CupertinoIcons.clock, 
              isVerified ? 'Verified' : 'Pending', 
              isVerified ? AppTheme.success : AppTheme.warning
            ),
          ]),
          const SizedBox(height: 20),
        ]))),
      Padding(padding: const EdgeInsets.all(20), child: Column(children: [
        Row(children: [
          _sb('Tests', '$totalTests'), 
          const SizedBox(width: 12), 
          _sb('Reviews', '${profile['totalReviews'] ?? '0'}'), 
          const SizedBox(width: 12), 
          _sb('Revenue', '₹$revenue')
        ]),
        const SizedBox(height: 20),
        _sec('Lab Details', [
          _ir(CupertinoIcons.doc, 'License', licenseNumber),
          _ir(CupertinoIcons.location, 'Address', addressText),
          _ir(CupertinoIcons.clock, 'Hours', '7:00 AM - 9:00 PM'), // Can be customized later
        ]),
        const SizedBox(height: 12),
        _sec('Services', [
          _ir(Icons.local_hospital_outlined, 'Lab Tests', servicesText),
          _ir(CupertinoIcons.house, 'Home Collection', profile['homeSampleCollection'] == true ? 'Available' : 'Not Available'),
        ]),
        const SizedBox(height: 20),
        _mi(CupertinoIcons.settings, 'Settings', () {}),
        _mi(CupertinoIcons.calendar, 'Schedule', () {}),
        _mi(CupertinoIcons.chart_bar_alt_fill, 'Inventory', () {}),
        _mi(CupertinoIcons.star, 'Reviews', () {}),
        _mi(CupertinoIcons.chat_bubble_text, 'Help', () {}),
        const SizedBox(height: 12),
        _mi(Icons.logout_outlined, 'Sign Out', () {
          ref.read(authProvider.notifier).logout();
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
        }, d: true),
      ])),
    ])));
  }
  Widget _badge(IconData i, String t, Color c) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: c.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
    child: Row(children: [Icon(i, size: 14, color: Colors.white), const SizedBox(width: 4), Text(t, style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white))]));
  Widget _sb(String l, String v) => Expanded(child: Container(padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
    child: Column(children: [Text(v, style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)), const SizedBox(height: 4), Text(l, style: GoogleFonts.manrope(fontSize: 11, color: AppTheme.textSecondary))])));
  Widget _sec(String t, List<Widget> c) => Container(padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)), const SizedBox(height: 12), ...c]));
  Widget _ir(IconData i, String l, String v) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppTheme.pathologyAccent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
      child: Icon(i, size: 16, color: AppTheme.pathologyAccent)),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(l, style: GoogleFonts.manrope(fontSize: 12, color: AppTheme.textTertiary)), const SizedBox(height: 2),
      Text(v, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
    ]))]));
  Widget _mi(IconData i, String t, VoidCallback f, {bool d = false}) => Container(margin: const EdgeInsets.only(bottom: 8),
    child: Material(color: Colors.white, borderRadius: BorderRadius.circular(14),
      child: InkWell(onTap: f, borderRadius: BorderRadius.circular(14),
        child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: d ? AppTheme.error.withValues(alpha: 0.2) : AppTheme.border)),
          child: Row(children: [Icon(i, size: 20, color: d ? AppTheme.error : AppTheme.textSecondary), const SizedBox(width: 14),
            Expanded(child: Text(t, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w500, color: d ? AppTheme.error : AppTheme.textPrimary))),
            Icon(CupertinoIcons.chevron_right, size: 18, color: d ? AppTheme.error : AppTheme.textTertiary)])))));
}
