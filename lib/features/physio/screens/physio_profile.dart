import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/ui/app_ui.dart';
import '../../auth/providers/auth_provider.dart';
import '../../doctor/widgets/availability_save_bar.dart';
import '../../doctor/widgets/doctor_ui.dart';
import '../../notifications/screens/notification_screen.dart';
import '../providers/physio_profile_provider.dart';
import '../widgets/physio_profile_widgets.dart';
import 'physio_availability.dart';
import 'physio_edit_profile.dart';
import 'physio_exercises.dart';
import 'physio_packages.dart';
import 'physio_practice_settings.dart';
import 'physio_service_areas.dart';

/// The physiotherapist's Profile tab: who they are as patients see them,
/// the practice tools, and account actions. Same layout as the doctor's.
class PhysioProfile extends ConsumerStatefulWidget {
  const PhysioProfile({super.key});

  @override
  ConsumerState<PhysioProfile> createState() => _PhysioProfileState();
}

class _PhysioProfileState extends ConsumerState<PhysioProfile> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(physioProfileProvider.notifier).ensureLoaded();
    });
  }

  Future<void> _refresh() =>
      ref.read(physioProfileProvider.notifier).load(silent: true);

  Future<void> _open(Widget page) async {
    final changed = await Navigator.of(
      context,
    ).push<bool>(AppPageRoute(builder: (_) => page));
    if (changed == true && mounted) _refresh();
  }

  Future<void> _help() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@aadyaplus.com',
      queryParameters: {'subject': 'Help with my physiotherapist account'},
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
          'You will stop receiving session alerts on this phone until you log in again.',
      icon: LucideIcons.logOut,
      confirmLabel: 'Log out',
    );
    if (ok && mounted) ref.read(authProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final st = ref.watch(physioProfileProvider);
    final profile = st.profile;
    final firstLoad = profile.isEmpty && st.error == null;
    final areas = physioStrings(profile['servesAreas']);

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
              else if (profile.isNotEmpty)
                AppEntrance(
                  child: _identity(
                    profile,
                    name: '${profile['name'] ?? user?.name ?? ''}'.trim(),
                  ),
                ),
              const SizedBox(height: 24),
              const AppSectionTitle('Practice'),
              AppEntrance(
                index: 2,
                child: AppGroup(
                  children: [
                    PhysioProfileTile(
                      icon: LucideIcons.userPen,
                      title: 'Edit profile',
                      subtitle: 'Name, specialisations, clinic and services',
                      onTap: () => _open(const PhysioEditProfile()),
                    ),
                    const AppHairline(),
                    PhysioProfileTile(
                      icon: LucideIcons.slidersHorizontal,
                      title: 'Practice settings',
                      subtitle: 'Visit types, fees and booking rules',
                      onTap: () => _open(const PhysioPracticeSettings()),
                    ),
                    const AppHairline(),
                    PhysioProfileTile(
                      icon: LucideIcons.calendarClock,
                      title: 'Availability',
                      subtitle: 'Your weekly hours',
                      onTap: () => _open(const PhysioAvailability()),
                    ),
                    const AppHairline(),
                    PhysioProfileTile(
                      icon: LucideIcons.mapPinned,
                      title: 'Service areas',
                      subtitle: areas.isEmpty
                          ? 'Where you make home visits'
                          : '${areas.length} ${areas.length == 1 ? 'area' : 'areas'} for home visits',
                      onTap: () => _open(const PhysioServiceAreas()),
                    ),
                    const AppHairline(),
                    PhysioProfileTile(
                      icon: LucideIcons.packageOpen,
                      title: 'Treatment packages',
                      subtitle: 'Multi-session plans patients pay for once',
                      onTap: () => _open(const PhysioPackages()),
                    ),
                    const AppHairline(),
                    PhysioProfileTile(
                      icon: LucideIcons.dumbbell,
                      title: 'Exercise library',
                      subtitle: 'Exercises you prescribe to patients',
                      onTap: () => _open(const PhysioExercises()),
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
                    PhysioProfileTile(
                      icon: LucideIcons.bell,
                      title: 'Notifications',
                      subtitle: 'Bookings, cancellations and updates',
                      onTap: () => _open(
                        ProfessionalNotificationScreen(
                          accent: ModuleAccent.of(context).color,
                        ),
                      ),
                    ),
                    const AppHairline(),
                    PhysioProfileTile(
                      icon: LucideIcons.lifeBuoy,
                      title: 'Help & support',
                      subtitle: 'support@aadyaplus.com',
                      onTap: _help,
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

  Widget _identity(Map<String, dynamic> p, {required String name}) {
    final specs = physioStrings(p['specialization']).join(', ');
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
    final sessions = int.tryParse('${p['totalConsultations'] ?? ''}') ?? 0;
    final stats = [
      if (rating > 0)
        '${rating.toStringAsFixed(1)} rating${reviews > 0 ? ' ($reviews)' : ''}',
      if (sessions > 0) '$sessions ${sessions == 1 ? 'session' : 'sessions'}',
    ].join('  ·  ');

    final address = p['clinicAddress'] is Map
        ? Map<String, dynamic>.from(p['clinicAddress'] as Map)
        : const <String, dynamic>{};
    final clinic = [
      '${address['address'] ?? ''}'.trim(),
      '${address['city'] ?? ''}'.trim(),
    ].where((e) => e.isNotEmpty).join(', ');
    final licence = '${p['licenseNumber'] ?? ''}'.trim();
    final languages = physioStrings(p['languages']).join(', ');
    final areas = physioStrings(p['servesAreas']).join(', ');

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
              onTap: () => _open(const PhysioEditProfile()),
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
        if (_statusNote(p) case final note?) ...[
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
            const AppHairline(),
            _dataRow(
              LucideIcons.mapPin,
              'Service areas',
              areas,
              optional: true,
            ),
          ],
        ),
      ],
    );
  }

  /// One line on what verification means for bookings, only when it is not
  /// yet done.
  Widget? _statusNote(Map<String, dynamic> p) {
    final text = switch ('${p['verificationStatus'] ?? ''}') {
      'pending' =>
        'Our team is checking your registration. Patients can book you once '
            'you’re verified — set up your hours, fees and packages in the '
            'meantime.',
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

  /// A missing registration or clinic says "Not set" in amber; service
  /// areas are optional, so missing ones are just grey.
  Widget _dataRow(
    IconData icon,
    String label,
    String value, {
    bool optional = false,
  }) {
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
                color: missing && !optional
                    ? AppColors.warning
                    : (missing
                          ? AppColors.textTertiary
                          : AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
