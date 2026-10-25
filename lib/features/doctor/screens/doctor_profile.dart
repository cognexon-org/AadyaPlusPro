import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/ui/app_ui.dart';
import '../../auth/providers/auth_provider.dart';
import '../../notifications/screens/notification_screen.dart';
import '../providers/doctor_profile_provider.dart';
import '../widgets/availability_save_bar.dart';
import '../widgets/doctor_ui.dart';
import 'doctor_availability.dart';
import 'doctor_edit_profile.dart';
import 'doctor_practice_settings.dart';
import 'doctor_prescriptions.dart';

/// The doctor's Profile tab: who they are as patients see them, the
/// practice tools, and account actions.
class DoctorProfile extends ConsumerStatefulWidget {
  const DoctorProfile({super.key});

  @override
  ConsumerState<DoctorProfile> createState() => _DoctorProfileState();
}

class _DoctorProfileState extends ConsumerState<DoctorProfile> {
  /// Only read from build helpers, so watching here is safe.
  Map<String, dynamic> get _profile =>
      ref.watch(doctorProfileProvider.select((s) => s.profile));

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(doctorProfileProvider.notifier).ensureLoaded();
    });
  }

  Future<void> _refresh() =>
      ref.read(doctorProfileProvider.notifier).load(silent: true);

  Future<void> _open(Widget page) async {
    final changed = await Navigator.of(
      context,
    ).push<bool>(AppPageRoute(builder: (_) => page));
    // Saves already update the provider; this just picks up anything the
    // server derived from them.
    if (changed == true && mounted) _refresh();
  }

  Future<void> _help() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@aadyaplus.com',
      queryParameters: {'subject': 'Help with my doctor account'},
    );
    var ok = false;
    try {
      ok = await launchUrl(uri);
    } catch (_) {}
    if (!ok && mounted) {
      doctorToast(context, 'Email us at support@aadyaplus.com');
    }
  }

  Future<void> _logout() async {
    final ok = await AppModal.confirm(
      context,
      title: 'Log out?',
      message:
          'You will stop receiving appointment alerts on this phone until you log in again.',
      icon: LucideIcons.logOut,
      confirmLabel: 'Log out',
    );
    if (ok) ref.read(authProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final st = ref.watch(doctorProfileProvider);
    final profile = st.profile;
    final firstLoad = profile.isEmpty && st.error == null;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: ModuleAccent.of(context).color,
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              const AppScreenHeader(
                title: 'Profile',
                subtitle: 'Your practice and account',
              ),
              const SizedBox(height: 18),
              if (st.error != null)
                AppErrorBanner(message: st.error!, onRetry: _refresh),
              if (firstLoad)
                const AppDetailSkeleton(rows: 4)
              else
                AppEntrance(
                  child: _identity(
                    name: '${profile['name'] ?? user?.name ?? ''}'.trim(),
                  ),
                ),
              const SizedBox(height: 24),
              const AppSectionTitle('Practice'),
              AppEntrance(
                index: 2,
                child: AppGroup(
                  children: [
                    _tile(
                      LucideIcons.userPen,
                      'Edit profile',
                      'Name, specialisations, clinic and languages',
                      () => _open(const DoctorEditProfile()),
                    ),
                    const AppHairline(),
                    _tile(
                      LucideIcons.slidersHorizontal,
                      'Practice settings',
                      'Visit types, fees and booking rules',
                      () => _open(const DoctorPracticeSettings()),
                    ),
                    const AppHairline(),
                    _tile(
                      LucideIcons.calendarClock,
                      'Availability',
                      'Your weekly hours',
                      () => _open(const DoctorAvailability()),
                    ),
                    const AppHairline(),
                    _tile(
                      LucideIcons.fileText,
                      'Prescriptions',
                      'Prescriptions you have written',
                      () => _open(const DoctorPrescriptions()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const AppSectionTitle('Account'),
              AppEntrance(
                index: 3,
                child: AppGroup(
                  children: [
                    _tile(
                      LucideIcons.bell,
                      'Notifications',
                      'Bookings, cancellations and updates',
                      () => _open(
                        ProfessionalNotificationScreen(
                          accent: ModuleAccent.of(context).color,
                        ),
                      ),
                    ),
                    const AppHairline(),
                    _tile(
                      LucideIcons.lifeBuoy,
                      'Help & support',
                      'support@aadyaplus.com',
                      _help,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              AppEntrance(
                index: 4,
                child: AppSecondaryButton(
                  label: 'Log out',
                  icon: LucideIcons.logOut,
                  color: AppColors.error,
                  onPressed: _logout,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────── Identity ──────────────────────────

  Widget _identity({required String name}) {
    final p = _profile;
    final specs = p['specialization'] is List
        ? (p['specialization'] as List)
              .map((e) => '$e'.trim())
              .where((e) => e.isNotEmpty)
              .join(', ')
        : '${p['specialization'] ?? ''}'.trim();
    final years = int.tryParse('${p['experienceYears'] ?? ''}') ?? 0;
    final subtitle = [
      if (specs.isNotEmpty) specs,
      if (years > 0) '$years ${years == 1 ? 'yr' : 'yrs'} experience',
    ].join(' · ');

    final accent = ModuleAccent.of(context).color;
    final (
      statusText,
      statusTone,
      statusIcon,
    ) = switch ('${p['verificationStatus'] ?? ''}') {
      'approved' => ('Verified', accent, LucideIcons.badgeCheck),
      'rejected' || 'suspended' => (
        'Action needed',
        AppColors.error,
        LucideIcons.circleAlert,
      ),
      'pending' => ('Under review', AppColors.warning, LucideIcons.hourglass),
      _ => ('', AppColors.textSecondary, LucideIcons.circle),
    };

    final rating = num.tryParse('${p['averageRating'] ?? ''}') ?? 0;
    final reviews = int.tryParse('${p['totalReviews'] ?? ''}') ?? 0;
    final consults = int.tryParse('${p['totalConsultations'] ?? ''}') ?? 0;
    final stats = [
      if (rating > 0)
        '${rating.toStringAsFixed(1)} rating${reviews > 0 ? ' ($reviews)' : ''}',
      if (consults > 0)
        '$consults ${consults == 1 ? 'consultation' : 'consultations'}',
    ].join('  ·  ');

    final address = p['clinicAddress'] is Map
        ? Map<String, dynamic>.from(p['clinicAddress'] as Map)
        : const <String, dynamic>{};
    final clinic = [
      '${p['clinicName'] ?? ''}'.trim(),
      '${address['city'] ?? ''}'.trim(),
    ].where((e) => e.isNotEmpty).join(', ');
    final licence = '${p['licenseNumber'] ?? ''}'.trim();
    final languages = p['languages'] is List
        ? (p['languages'] as List)
              .map((e) => '$e'.trim())
              .where((e) => e.isNotEmpty)
              .join(', ')
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DoctorAvatar(name: name, size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Your name' : name,
                    style: AppType.sans(
                      fontSize: AppType.heading,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: AppColors.textStrong,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppType.sans(
                        fontSize: AppType.caption,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  if (statusText.isNotEmpty || stats.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        if (statusText.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(statusIcon, size: 14, color: statusTone),
                              const SizedBox(width: 5),
                              Text(
                                statusText,
                                style: AppType.sans(
                                  fontSize: AppType.caption,
                                  fontWeight: FontWeight.w600,
                                  color: statusTone,
                                ),
                              ),
                            ],
                          ),
                        if (stats.isNotEmpty)
                          Text(
                            stats,
                            style: AppType.sans(
                              fontSize: AppType.caption,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            AppPressable(
              onTap: () => _open(const DoctorEditProfile()),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
                child: Text(
                  'Edit',
                  style: AppType.sans(
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_statusNote() case final note?) ...[
          const SizedBox(height: 14),
          note,
        ],
        const SizedBox(height: 18),
        AppGroup(
          children: [
            _dataRow(LucideIcons.fileBadge, 'Registration no.', licence),
            const AppHairline(),
            _dataRow(LucideIcons.building2, 'Clinic', clinic),
            if (languages.isNotEmpty) ...[
              const AppHairline(),
              _dataRow(LucideIcons.languages, 'Languages', languages),
            ],
          ],
        ),
      ],
    );
  }

  /// One line on what verification means for bookings, only when it is not
  /// yet done — a verified doctor doesn't need telling.
  Widget? _statusNote() {
    final status = '${_profile['verificationStatus'] ?? ''}';
    final text = switch (status) {
      'pending' =>
        'Our team is checking your registration. Patients can book you once '
            'you’re verified — set up your hours and fees in the meantime.',
      'rejected' =>
        'We couldn’t verify your registration. Check your details or contact '
            'support to resubmit.',
      'suspended' =>
        'Your profile is suspended and hidden from patients. Contact support '
            'to restore it.',
      _ => null,
    };
    if (text == null) return null;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: AppType.sans(
          fontSize: AppType.caption,
          height: 1.45,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  /// A missing registration number or clinic says "Not set" in amber —
  /// patients can't book a doctor without them.
  Widget _dataRow(IconData icon, String label, String value) {
    final missing = value.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textHeading),
          const SizedBox(width: 12),
          Text(
            label,
            style: AppType.sans(
              fontSize: AppType.body,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              missing ? 'Not set' : value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: AppType.sans(
                fontSize: AppType.body,
                fontWeight: FontWeight.w600,
                color: missing ? AppColors.warning : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) => AppPressable(
    scale: 0.985,
    onTap: onTap,
    child: Container(
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(14, 12, 11, 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: AppColors.textHeading),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppType.sans(
                    fontWeight: FontWeight.w600,
                    fontSize: AppType.small,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: AppType.sans(
                    fontSize: AppType.caption,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            LucideIcons.chevronRight,
            size: 15,
            color: AppColors.textDisabled,
          ),
        ],
      ),
    ),
  );
}
