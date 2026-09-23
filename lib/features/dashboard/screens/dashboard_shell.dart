import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../pharmacy/theme/pharmacy_colors.dart';
import '../../auth/models/user_model.dart';
import '../../auth/providers/auth_provider.dart';

// Tabs for each role
import '../../doctor/screens/doctor_home.dart';
import '../../doctor/screens/doctor_appointments.dart';
import '../../doctor/screens/doctor_patients.dart';
import '../../doctor/screens/doctor_earnings.dart';
import '../../doctor/screens/doctor_profile.dart';

import '../../physio/screens/physio_home.dart';
import '../../physio/screens/physio_appointments.dart';
import '../../physio/screens/physio_patients.dart';
import '../../physio/screens/physio_earnings.dart';
import '../../physio/screens/physio_profile.dart';

import '../../pathology/screens/pathology_home.dart';
import '../../pathology/screens/pathology_orders.dart';
import '../../pathology/screens/pathology_test_catalog.dart';
import '../../pathology/screens/pathology_earnings.dart';
import '../../pathology/screens/pathology_profile.dart';

import '../../pharmacy/screens/pharmacy_home.dart';
import '../../pharmacy/screens/pharmacy_orders.dart';
import '../../pharmacy/screens/pharmacy_medicines.dart';
import '../../pharmacy/screens/pharmacy_earnings.dart';
// Kept as a comment alongside the commented-out Sales tab below, so
// restoring the tab is a two-line change rather than a hunt for the import.
// import '../../pharmacy/screens/pharmacy_sales.dart';
import '../../pharmacy/screens/pharmacy_profile.dart';
import '../../pharmacy/providers/pharmacy_store_provider.dart';
import '../../mr/screens/mr_home.dart';
import '../../mr/screens/mr_calls.dart';
import '../../mr/screens/mr_work.dart';
import '../../mr/screens/mr_team.dart';
import '../../mr/screens/mr_profile.dart';
import '../../notifications/providers/notification_provider.dart';
import '../../notifications/widgets/notification_bell.dart';
import '../../../core/notifications/professional_notification_navigation_service.dart';
import '../../../core/notifications/onesignal_service.dart';
import '../../../core/notifications/professional_push_notification_service.dart';

class DashboardShell extends ConsumerStatefulWidget {
  const DashboardShell({super.key});

  @override
  ConsumerState<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends ConsumerState<DashboardShell> {
  int _currentIndex = 0;
  bool _bannerDismissed = false;
  Timer? _notificationTimer;
  StreamSubscription<int>? _pushNotificationSubscription;

  @override
  void initState() {
    super.initState();
    ProfessionalNotificationNavigationService.instance.setAuthenticatedReady(
      true,
    );
    Future.microtask(() async {
      // Binding happens here rather than at app start: the permission prompt
      // should land on someone who has already signed in, and the OneSignal
      // subscription is then attached to a known user from its first moment.
      final userId = ref.read(authProvider).user?.id;
      if (userId != null && userId.isNotEmpty) {
        await OneSignalService.instance.bindUser(userId);
      }
      await ProfessionalPushNotificationService.instance
          .syncAuthenticatedDevice();
      // Safe on every launch — the once-a-day rule lives on the server.
      unawaited(OneSignalService.instance.requestDailyWelcome());
      await ref
          .read(professionalNotificationProvider.notifier)
          .refresh(silent: true);
    });
    _pushNotificationSubscription = ProfessionalPushNotificationService
        .instance
        .notificationEvents
        .listen((_) {
          if (!mounted) return;
          ref
              .read(professionalNotificationProvider.notifier)
              .refresh(silent: true);
        });
    _notificationTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => ref
          .read(professionalNotificationProvider.notifier)
          .refresh(silent: true),
    );
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    _pushNotificationSubscription?.cancel();
    ProfessionalNotificationNavigationService.instance.setAuthenticatedReady(
      false,
    );
    super.dispose();
  }

  List<Widget> _getPages(UserRole role) {
    switch (role) {
      case UserRole.doctor:
        return const [
          DoctorHome(),
          DoctorAppointments(),
          DoctorPatients(),
          DoctorEarnings(),
          DoctorProfile(),
        ];
      case UserRole.physiotherapist:
        return const [
          PhysioHome(),
          PhysioAppointments(),
          PhysioPatients(),
          PhysioEarnings(),
          PhysioProfile(),
        ];
      case UserRole.pathology:
        return const [
          PathologyHome(),
          PathologyOrders(),
          PathologyTestCatalog(),
          PathologyEarnings(),
          PathologyProfile(),
        ];
      case UserRole.pharmacy:
        return const [
          PharmacyHome(),
          PharmacyOrders(),
          // Counter sales (walk-in POS) is pharmacy-management functionality,
          // not merchant functionality: this app's job is receiving and
          // fulfilling orders sent from the Aadya Plus consumer app. The
          // screen still exists and still works — it is only off the nav.
          // Restore by re-adding PharmacySales() here and its nav item below.
          // PharmacySales(),
          PharmacyMedicines(),
          PharmacyEarnings(),
          PharmacyProfile(),
        ];
      case UserRole.mr:
        return const [MrHome(), MrCalls(), MrWork(), MrTeam(), MrProfile()];
    }
  }

  List<BottomNavigationBarItem> _getNavItems(UserRole role) {
    switch (role) {
      case UserRole.doctor:
        return const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.house_fill),
            activeIcon: Icon(CupertinoIcons.house_fill),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.calendar),
            activeIcon: Icon(CupertinoIcons.calendar_circle_fill),
            label: 'Appointments',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.person_2),
            activeIcon: Icon(CupertinoIcons.person_2_fill),
            label: 'Patients',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            activeIcon: Icon(Icons.account_balance_wallet_outlined),
            label: 'Earnings',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.profile_circled),
            activeIcon: Icon(CupertinoIcons.profile_circled),
            label: 'Profile',
          ),
        ];
      case UserRole.physiotherapist:
        return const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.house),
            activeIcon: Icon(CupertinoIcons.house_fill),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.calendar),
            activeIcon: Icon(CupertinoIcons.calendar_circle_fill),
            label: 'Appointments',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.person_2),
            activeIcon: Icon(CupertinoIcons.person_2_fill),
            label: 'Patients',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            activeIcon: Icon(Icons.account_balance_wallet_outlined),
            label: 'Earnings',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.profile_circled),
            activeIcon: Icon(CupertinoIcons.profile_circled),
            label: 'Profile',
          ),
        ];
      case UserRole.pathology:
        return const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.house),
            activeIcon: Icon(CupertinoIcons.house_fill),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.doc_on_clipboard),
            activeIcon: Icon(CupertinoIcons.doc_on_clipboard),
            label: 'Orders',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.biotech_outlined),
            activeIcon: Icon(Icons.biotech_outlined),
            label: 'Tests',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            activeIcon: Icon(Icons.account_balance_wallet_outlined),
            label: 'Earnings',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.profile_circled),
            activeIcon: Icon(CupertinoIcons.profile_circled),
            label: 'Profile',
          ),
        ];
      case UserRole.pharmacy:
        return const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.house_fill),
            activeIcon: Icon(CupertinoIcons.house_fill),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.doc_on_clipboard),
            activeIcon: Icon(CupertinoIcons.doc_on_clipboard),
            label: 'Orders',
          ),
          // Sales tab removed — see _getPages above.
          // BottomNavigationBarItem(
          //   icon: Icon(Icons.receipt_long_outlined),
          //   activeIcon: Icon(Icons.receipt_long),
          //   label: 'Sales',
          // ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.cube_box),
            activeIcon: Icon(CupertinoIcons.cube_box_fill),
            label: 'Medicines',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            activeIcon: Icon(Icons.account_balance_wallet),
            label: 'Earnings',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.profile_circled),
            activeIcon: Icon(CupertinoIcons.profile_circled),
            label: 'Profile',
          ),
        ];
      case UserRole.mr:
        return const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.fact_check_outlined),
            activeIcon: Icon(Icons.fact_check),
            label: 'DCR',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.route_outlined),
            activeIcon: Icon(Icons.route),
            label: 'Work',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.groups_outlined),
            activeIcon: Icon(Icons.groups),
            label: 'Team',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.badge_outlined),
            activeIcon: Icon(Icons.badge),
            label: 'Profile',
          ),
        ];
    }
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.doctor:
        return AppTheme.doctorAccent;
      case UserRole.physiotherapist:
        return AppTheme.physioAccent;
      case UserRole.pathology:
        return AppTheme.pathologyAccent;
      case UserRole.pharmacy:
        return PharmacyColors.green;
      case UserRole.mr:
        return AppTheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final role = authState.user?.role ?? UserRole.doctor;
    final pages = _getPages(role);
    final navItems = _getNavItems(role);
    final roleColor = _getRoleColor(role);

    if (role == UserRole.pharmacy) {
      Future.microtask(
        () => ref.read(pharmacyStoreProvider.notifier).initialize(),
      );
    }

    // Pharmacy renders this notice inside its Home screen instead, below the
    // hero and above the actions group, where it sits in that page's own
    // rhythm. A differently-styled strip shoved above the hero broke the top
    // of the screen. Keeping `showBanner` false for pharmacy (rather than
    // just skipping the widget) also leaves the notification bell's own
    // SafeArea handling below intact.
    final showBanner =
        authState.user?.verificationStatus != VerificationStatus.approved &&
        !_bannerDismissed &&
        role != UserRole.pharmacy;

    return Scaffold(
      body: Column(
        children: [
          // In normal document flow (not a Positioned overlay) so it pushes
          // the page content down instead of painting over it — it used to
          // float on top of each screen's own header and overlap the text.
          // The whole SafeArea slot is only added while the banner is
          // actually shown; once dismissed it must disappear completely; a
          // dismissed-but-still-present SafeArea keeps reserving the status
          // bar inset as its own row, leaving a dead gap above the page.
          if (showBanner)
            SafeArea(
              bottom: false,
              child: _VerificationBanner(
                role: role,
                onDismiss: () => setState(() => _bannerDismissed = true),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                IndexedStack(index: _currentIndex, children: pages),
                Positioned(
                  top: 12,
                  right: 12,
                  // The banner (when shown) already consumes the status-bar
                  // safe area above this Stack, so only apply it here when
                  // there's no banner and this Stack starts at the very top.
                  child: SafeArea(
                    bottom: false,
                    top: !showBanner,
                    // The bell takes the role accent so it belongs to the
                    // module it floats over.
                    child: NotificationBell(color: roleColor),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ]
        ),
        child: SafeArea(
          child: Padding(
            // Pharmacy carries six items; the side padding that suits five
            // squeezes their labels, so it is dropped for that role only.
            padding: EdgeInsets.symmetric(
              horizontal: navItems.length > 5 ? 0 : 8,
              vertical: 4,
            ),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (i) => setState(() => _currentIndex = i),
              items: navItems,
              selectedItemColor: roleColor,
              unselectedItemColor: AppTheme.textTertiary,
              selectedLabelStyle: GoogleFonts.manrope(
                fontSize: navItems.length > 5 ? 10 : 11,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: GoogleFonts.manrope(
                fontSize: navItems.length > 5 ? 10 : 11,
                fontWeight: FontWeight.w500,
              ),
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
          ),
        ),
      ),
    );
  }
}

// Verification only affects public discoverability (patients booking a
// doctor/physio, orders reaching a pharmacy) — it never blocks the
// professional's own dashboard/inventory access (see splash/login/register
// screens for the matching routing fix). This banner keeps that status
// visible without gating anything.
class _VerificationBanner extends ConsumerStatefulWidget {
  final UserRole role;
  final VoidCallback onDismiss;
  const _VerificationBanner({required this.role, required this.onDismiss});

  @override
  ConsumerState<_VerificationBanner> createState() =>
      _VerificationBannerState();
}

class _VerificationBannerState extends ConsumerState<_VerificationBanner> {
  bool _checking = false;

  String get _message {
    switch (widget.role) {
      case UserRole.pharmacy:
        return 'Verification pending — your store isn\'t visible for online orders yet, but you can add medicines and manage inventory now.';
      case UserRole.doctor:
      case UserRole.physiotherapist:
        return 'Verification pending — patients can\'t book you publicly yet, but you can set up your profile and availability now.';
      case UserRole.pathology:
        return 'Verification pending — your lab isn\'t visible for online orders yet, but you can set up your test catalog now.';
      case UserRole.mr:
        return 'Verification pending review by your admin team.';
    }
  }

  Future<void> _refresh() async {
    setState(() => _checking = true);
    await ref.read(authProvider.notifier).refreshUser();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            CupertinoIcons.info_circle,
            size: 18,
            color: AppTheme.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _message,
              style: GoogleFonts.manrope(
                fontSize: 12,
                color: AppTheme.textPrimary,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _checking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : InkWell(
                  onTap: _refresh,
                  child: const Icon(
                    Icons.refresh,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                ),
          const SizedBox(width: 8),
          InkWell(
            onTap: widget.onDismiss,
            child: const Icon(
              Icons.close,
              size: 18,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
