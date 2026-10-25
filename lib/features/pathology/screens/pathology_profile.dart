import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/ui/app_ui.dart';
import '../../auth/providers/auth_provider.dart';
import '../../doctor/widgets/availability_save_bar.dart';
import '../../doctor/widgets/doctor_ui.dart' show DoctorAvatar;
import '../../notifications/screens/notification_screen.dart';
import '../../physio/widgets/physio_profile_widgets.dart';
import '../providers/lab_providers.dart';
import 'lab_collection_settings.dart';
import 'lab_edit_profile.dart';
import 'lab_schedule.dart';
import 'pathology_staff.dart';
import 'pathology_test_catalog.dart';

/// The lab's Profile tab: the lab as patients see it, the tools that run it
/// (slots, tests, team) and account actions. Same layout as the doctor's
/// and physio's.
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
      if (!mounted) return;
      ref.read(labProfileProvider.notifier).ensureLoaded();
      ref.read(labDashboardProvider.notifier).ensureLoaded();
    });
  }

  Future<void> _refresh() => Future.wait([
    ref.read(labProfileProvider.notifier).load(silent: true),
    ref.read(labDashboardProvider.notifier).load(silent: true),
  ]);

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push<bool>(AppPageRoute(builder: (_) => page));
    // Counts (tests, team, slots) may have changed on the way.
    if (mounted) _refresh();
  }

  Future<void> _help() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@aadyaplus.com',
      queryParameters: {'subject': 'Help with my lab account'},
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
          'You will stop receiving booking alerts on this phone until you log in again.',
      icon: LucideIcons.logOut,
      confirmLabel: 'Log out',
    );
    if (ok && mounted) ref.read(authProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final st = ref.watch(labProfileProvider);
    final dash = ref.watch(labDashboardProvider);
    final profile = st.data;
    final lab = dash.data['lab'] is Map
        ? Map<String, dynamic>.from(dash.data['lab'] as Map)
        : const <String, dynamic>{};
    final firstLoad = profile.isEmpty && st.error == null;
    int count(String k) => int.tryParse('${lab[k] ?? ''}') ?? 0;
    final tests = count('catalogCount');
    final packages = count('packageCount');
    final staff = count('staffCount');
    final slotDays = count('slotDaysThisWeek');
    final home = profile['homeCollectionAvailable'] == true;
    final pincodes = profile['homeCollectionPincodes'] is List
        ? (profile['homeCollectionPincodes'] as List).length
        : 0;

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
                subtitle: 'Your lab and account',
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
                    name: '${profile['labName'] ?? user?.name ?? ''}'.trim(),
                  ),
                ),
              if (profile.isNotEmpty) ...[
                const SizedBox(height: 14),
                AppEntrance(
                  index: 1,
                  child: Row(
                    children: [
                      _stat('Tests', '$tests'),
                      const SizedBox(width: 8),
                      _stat('Packages', '$packages'),
                      const SizedBox(width: 8),
                      _stat('Team', '$staff'),
                      const SizedBox(width: 8),
                      _stat(
                        'Reports',
                        '${int.tryParse('${profile['totalTestsConducted'] ?? ''}') ?? 0}',
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const AppSectionTitle('Your lab'),
              AppEntrance(
                index: 2,
                child: AppGroup(
                  children: [
                    PhysioProfileTile(
                      icon: LucideIcons.building2,
                      title: 'Edit lab details',
                      subtitle: 'Name, registration, address, accreditation',
                      onTap: () => _open(const LabEditProfile()),
                    ),
                    const AppHairline(),
                    PhysioProfileTile(
                      icon: LucideIcons.house,
                      title: 'Home collection & booking',
                      subtitle: home
                          ? 'On${pincodes > 0 ? ' · $pincodes ${pincodes == 1 ? 'pincode' : 'pincodes'}' : ''} · booking rules and hours'
                          : 'Off · booking rules and hours',
                      onTap: () => _open(const LabCollectionSettings()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const AppSectionTitle('Operations'),
              AppEntrance(
                index: 3,
                child: AppGroup(
                  children: [
                    PhysioProfileTile(
                      icon: LucideIcons.calendarClock,
                      title: 'Collection slots',
                      subtitle: lab.isEmpty
                          ? 'Your weekly timetable'
                          : slotDays == 0
                          ? 'No slots this week — patients can’t book'
                          : 'Open $slotDays of the next 7 days',
                      onTap: () => _open(const LabSchedule()),
                    ),
                    const AppHairline(),
                    PhysioProfileTile(
                      icon: LucideIcons.flaskConical,
                      title: 'Tests & packages',
                      subtitle: tests == 0
                          ? 'Add tests patients can book'
                          : '$tests ${tests == 1 ? 'test' : 'tests'}, $packages ${packages == 1 ? 'package' : 'packages'}',
                      onTap: () => _open(const PathologyTestCatalog()),
                    ),
                    const AppHairline(),
                    PhysioProfileTile(
                      icon: LucideIcons.usersRound,
                      title: 'Team',
                      subtitle: staff == 0
                          ? 'Add phlebotomists for home collection'
                          : '$staff ${staff == 1 ? 'phlebotomist' : 'phlebotomists'} and staff',
                      onTap: () => _open(const PathologyStaffScreen()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const AppSectionTitle('Account'),
              AppEntrance(
                index: 4,
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
                index: 5,
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

  Widget _stat(String label, String value) => Expanded(
    child: Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppType.number(
              fontSize: AppType.heading,
              fontWeight: FontWeight.w700,
              color: AppColors.textStrong,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.sans(
              fontSize: AppType.micro,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    ),
  );

  // ──────────────────────── Identity ──────────────────────────

  Widget _identity(Map<String, dynamic> p, {required String name}) {
    final accent = ModuleAccent.of(context).color;
    final address = p['address'] is Map
        ? Map<String, dynamic>.from(p['address'] as Map)
        : const <String, dynamic>{};
    final city = '${address['city'] ?? ''}'.trim();
    final accreditation =
        (p['accreditation'] is List ? p['accreditation'] as List : const [])
            .map((e) => '$e'.trim())
            .where((e) => e.isNotEmpty)
            .join(', ');
    final subtitle = [
      if (city.isNotEmpty) city,
      if (accreditation.isNotEmpty) accreditation,
    ].join(' · ');

    final (
      statusText,
      statusTone,
      statusIcon,
    ) = switch ('${p['verificationStatus'] ?? ''}') {
      'approved' => ('Verified', accent, LucideIcons.badgeCheck),
      'rejected' => ('Not verified', AppColors.error, LucideIcons.circleAlert),
      'suspended' => ('Suspended', AppColors.error, LucideIcons.circleAlert),
      'pending' => ('Under review', AppColors.warning, LucideIcons.hourglass),
      _ => ('', AppColors.textSecondary, LucideIcons.circle),
    };
    final rating = num.tryParse('${p['averageRating'] ?? ''}') ?? 0;
    final reviews = int.tryParse('${p['totalReviews'] ?? ''}') ?? 0;

    final street = [
      '${address['street'] ?? ''}'.trim(),
      city,
      '${address['pincode'] ?? ''}'.trim(),
    ].where((e) => e.isNotEmpty).join(', ');
    final registration = '${p['registrationNumber'] ?? ''}'.trim();
    final signatory = '${p['contactPerson'] ?? ''}'.trim();
    final phone = '${p['phone'] ?? ''}'.trim();

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
                    name.isEmpty ? 'Your lab' : name,
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
                      if (rating > 0)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.star,
                              size: 13,
                              color: AppColors.warning,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${rating.toStringAsFixed(1)}${reviews > 0 ? ' ($reviews)' : ''}',
                              style: AppType.sans(
                                fontSize: AppType.caption,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
            AppPressable(
              onTap: () => _open(const LabEditProfile()),
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
            _dataRow(LucideIcons.fileBadge, 'Registration no.', registration),
            const AppHairline(),
            _dataRow(LucideIcons.mapPin, 'Address', street),
            const AppHairline(),
            _dataRow(LucideIcons.phone, 'Phone', phone),
            const AppHairline(),
            _dataRow(
              LucideIcons.signature,
              'Reports signed by',
              signatory,
              optional: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget? _statusNote(Map<String, dynamic> p) {
    final text = switch ('${p['verificationStatus'] ?? ''}') {
      'pending' =>
        'Our team is checking your lab’s registration. Patients can book you '
            'once you’re verified — add your tests, slots and team in the '
            'meantime.',
      'rejected' =>
        'We couldn’t verify your lab. Check your registration details or '
            'contact support to resubmit.',
      'suspended' =>
        'Your lab is suspended and hidden from patients. Contact support to '
            'restore it.',
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
