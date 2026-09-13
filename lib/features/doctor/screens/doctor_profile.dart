import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import 'doctor_availability.dart';
import 'doctor_prescriptions.dart';
import 'doctor_schedule.dart';

class DoctorProfile extends ConsumerStatefulWidget {
  const DoctorProfile({super.key});

  @override
  ConsumerState<DoctorProfile> createState() => _DoctorProfileState();
}

class _DoctorProfileState extends ConsumerState<DoctorProfile> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(doctorDashboardProvider.notifier).loadAll());
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final dashData = ref.watch(doctorDashboardProvider);
    final profile = dashData.profile;

    // Extract profile data with fallbacks from user model
    final name = profile['name'] ?? user?.name ?? 'Doctor';
    final specialization = (profile['specialization'] is List && (profile['specialization'] as List).isNotEmpty)
        ? (profile['specialization'] as List).join(', ')
        : profile['specialization']?.toString() ?? 'General Physician';
    final experience = profile['experienceYears']?.toString() ?? '0';
    final license = profile['licenseNumber'] ?? 'N/A';
    final consultFee = profile['consultationFee']?.toString() ?? '0';
    final homeVisitFee = profile['homeVisitFee']?.toString() ?? '0';
    final rating = profile['averageRating']?.toString() ?? '0.0';
    final totalConsultations = profile['totalConsultations']?.toString() ?? '0';
    final totalReviews = profile['totalReviews']?.toString() ?? '0';
    final totalEarnings = profile['totalEarnings'] ?? 0;
    final verificationStatus = profile['verificationStatus'] ?? 'pending';
    final phone = profile['contactNumber'] ?? user?.phone ?? '';
    final email = profile['email'] ?? user?.email ?? '';

    final clinicAddress = profile['clinicAddress'];
    final addressStr = clinicAddress is Map
        ? '${clinicAddress['address'] ?? ''}\n${clinicAddress['city'] ?? ''}, ${clinicAddress['state'] ?? ''} - ${clinicAddress['pincode'] ?? ''}'
        : 'Not set';

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Profile header with gradient
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(gradient: AppTheme.doctorGradient),
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20)],
                      ),
                      child: Center(
                        child: profile['profileImage'] != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: Image.network(profile['profileImage'], width: 90, height: 90, fit: BoxFit.cover,
                                  errorBuilder: (_, e, s) => Text(name.substring(0, 1), style: GoogleFonts.plusJakartaSans(fontSize: 36, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                                ),
                              )
                            : Text(name.substring(0, 1), style: GoogleFonts.plusJakartaSans(fontSize: 36, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text('$specialization • $experience+ years', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: Colors.white70)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            children: [
                              const Icon(Iconsax.star, size: 14, color: Colors.amber),
                              const SizedBox(width: 4),
                              Text(rating, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: verificationStatus == 'approved' ? AppTheme.success.withValues(alpha: 0.2) : AppTheme.warning.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(verificationStatus == 'approved' ? Iconsax.verify5 : Iconsax.clock, size: 14, color: verificationStatus == 'approved' ? AppTheme.success : AppTheme.warning),
                              const SizedBox(width: 4),
                              Text(
                                verificationStatus == 'approved' ? 'Verified' : 'Pending',
                                style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // Profile content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      _statBox('Consultations', totalConsultations),
                      const SizedBox(width: 12),
                      _statBox('Reviews', totalReviews),
                      const SizedBox(width: 12),
                      _statBox('Earnings', _formatEarnings(totalEarnings)),
                    ],
                  ),
                  const SizedBox(height: 20),

                  _infoSection('Contact', [
                    _infoRow(Iconsax.call, 'Phone', phone.isNotEmpty ? phone : 'Not set'),
                    _infoRow(Iconsax.sms, 'Email', email.isNotEmpty ? email : 'Not set'),
                  ]),
                  const SizedBox(height: 12),

                  _infoSection('Professional', [
                    _infoRow(Iconsax.document, 'License', license),
                    _infoRow(Iconsax.briefcase, 'Experience', '$experience years'),
                    _infoRow(Iconsax.medal_star, 'Specialization', specialization),
                    _infoRow(Iconsax.money_recive, 'Consultation Fee', '₹$consultFee'),
                    _infoRow(Iconsax.home, 'Home Visit Fee', '₹$homeVisitFee'),
                  ]),
                  const SizedBox(height: 12),

                  _infoSection('Clinic Address', [
                    _infoRow(Iconsax.location, 'Address', addressStr),
                  ]),
                  const SizedBox(height: 20),

                  _menuItem(Iconsax.calendar_tick, 'My Schedule', () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DoctorSchedule()));
                  }),
                  _menuItem(Iconsax.shield_tick, 'Set Availability', () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DoctorAvailability()));
                  }),
                  _menuItem(Iconsax.document_text, 'Prescriptions', () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DoctorPrescriptions()));
                  }),
                  _menuItem(Iconsax.message_question, 'Help & Support', () {}),
                  const SizedBox(height: 12),
                  _menuItem(
                    Iconsax.logout,
                    'Sign Out',
                    () async {
                      await ref.read(authProvider.notifier).logout();
                      if (mounted) {
                        Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
                      }
                    },
                    isDestructive: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatEarnings(dynamic value) {
    if (value is num) {
      if (value >= 100000) return '₹${(value / 100000).toStringAsFixed(1)}L';
      if (value >= 1000) return '₹${(value / 1000).toStringAsFixed(1)}K';
      return '₹$value';
    }
    return '₹0';
  }

  Widget _statBox(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
        child: Column(
          children: [
            Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            const SizedBox(height: 4),
            Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _infoSection(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 16, color: AppTheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textTertiary)),
                const SizedBox(height: 2),
                Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuItem(IconData icon, String title, VoidCallback onTap, {bool isDestructive = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isDestructive ? AppTheme.error.withValues(alpha: 0.2) : AppTheme.border),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: isDestructive ? AppTheme.error : AppTheme.textSecondary),
                const SizedBox(width: 14),
                Expanded(child: Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w500, color: isDestructive ? AppTheme.error : AppTheme.textPrimary))),
                Icon(Iconsax.arrow_right_3, size: 18, color: isDestructive ? AppTheme.error : AppTheme.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
