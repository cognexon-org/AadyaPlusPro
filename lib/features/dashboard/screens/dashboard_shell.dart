import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/network/api_service.dart';
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
import '../../physio/screens/physio_appointment_details.dart';
import '../../physio/screens/physio_patients.dart';
import '../../physio/screens/physio_earnings.dart';
import '../../physio/screens/physio_profile.dart';

import '../../pathology/screens/pathology_home.dart';
import '../../pathology/screens/pathology_orders.dart';
import '../../pathology/screens/pathology_test_catalog.dart';
import '../../pathology/screens/pathology_earnings.dart';
import '../../pathology/screens/pathology_profile.dart';
import '../../pathology/screens/pathology_order_detail.dart';
import '../../pathology/providers/lab_providers.dart';
import '../../pathology/widgets/lab_ui.dart' as lab;

import '../../pharmacy/screens/pharmacy_home.dart';
import '../../pharmacy/screens/pharmacy_orders.dart';
import '../../pharmacy/screens/pharmacy_medicines.dart';
import '../../pharmacy/screens/pharmacy_earnings.dart';
// Kept as a comment alongside the commented-out Sales tab below, so
// restoring the tab is a two-line change rather than a hunt for the import.
// import '../../pharmacy/screens/pharmacy_sales.dart';
import '../../pharmacy/screens/pharmacy_profile.dart';
import '../../pharmacy/providers/pharmacy_store_provider.dart';
import '../../pharmacy/providers/pharmacy_orders_provider.dart';
import '../../pharmacy/providers/pharmacy_nav_provider.dart';
import '../../pharmacy/widgets/pharmacy_nav_bar.dart';
import '../../pharmacy/services/pharmacy_order_ringer.dart';
import '../../pharmacy/widgets/pharmacy_new_order_banner.dart';
import '../../doctor/providers/doctor_appointments_provider.dart';
import '../../doctor/widgets/doctor_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../pharmacy/widgets/pharmacy_ui.dart'
    show PharmacyScrollScope, PharmacyOfflineBanner;
import '../../mr/providers/mr_provider.dart';
import '../../pharmacy/widgets/module_accent.dart';
import '../../mr/screens/mr_accounts.dart';
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
  bool _pharmacyBooted = false;
  bool _mrBooted = false;
  bool _doctorBooted = false;
  bool _labBooted = false;
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
          final role = ref.read(authProvider).user?.role;
          if (role == UserRole.pharmacy) {
            ref.read(pharmacyOrdersProvider.notifier).pollNow();
          } else if (_isClinician(role)) {
            ref.read(doctorAppointmentsProvider.notifier).load(silent: true);
          } else if (role == UserRole.pathology) {
            ref.read(labOrdersProvider.notifier).load(silent: true);
            ref.read(labDashboardProvider.notifier).load(silent: true);
          }
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
    ProfessionalNotificationNavigationService.appointmentScreen = null;
    ProfessionalNotificationNavigationService.labOrderScreen = null;
    super.dispose();
  }

  static bool _isClinician(UserRole? role) =>
      role == UserRole.doctor || role == UserRole.physiotherapist;

  /// The details screen for one appointment, for this role. Starts from the
  /// copy already in the list when there is one (so it paints filled in);
  /// the screen fetches the latest itself either way.
  Widget _appointmentScreen(String id) {
    final known = ref
        .read(doctorAppointmentsProvider)
        .all
        .where((a) => '${a['_id']}' == id);
    final appointment = known.isEmpty
        ? <String, dynamic>{'_id': id}
        : known.first;
    return ref.read(authProvider).user?.role == UserRole.physiotherapist
        ? PhysioAppointmentDetails(appointment: appointment)
        : AppointmentDetailsScreen(appointment: appointment);
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
        return [
          const MrHome(),
          const MrCalls(),
          const MrWork(),
          ref.read(mrProvider).isManager ? const MrTeam() : const MrAccountsScreen(asTab: true),
          const MrProfile(),
        ];
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
        return ModuleAccent.mr.color;
    }
  }

  /// Rings and shows a banner for an order that just arrived. A pharmacy
  /// works with the phone on the counter; the haptic and sound are what
  /// stop an order sitting unseen.
  /// A patient asked for an appointment. Treated like a pharmacy's new
  /// order: it rings until someone looks (an unanswered request is declined
  /// automatically) and joins the app-wide banner stack until dismissed or
  /// answered.
  void _announceNewRequest() {
    final state = ref.read(doctorAppointmentsProvider);
    final fresh = state.lastArrivals;
    if (fresh.isEmpty || !mounted) return;
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    final noun = ref.read(authProvider).user?.role == UserRole.physiotherapist
        ? 'session'
        : 'appointment';
    String when(Map<String, dynamic> a) =>
        '${dayLabel(apptStart(a))}, ${timeLabel(apptStart(a))}';

    final first = fresh.first;
    PharmacyOrderRinger.instance.ringAppointments(
      latest: first,
      waiting: state.requests.length,
      who: patientName(first),
      when: when(first),
      noun: noun,
    );

    // Oldest first, so the newest ends on top of the stack.
    final banner = ref.read(pharmacyOrderBannerProvider.notifier);
    for (final a in fresh.reversed) {
      banner.addAppointment(
        a,
        title: 'New $noun request',
        subtitle: [
          patientName(a),
          when(a),
          capitalised(apptType(a) == 'home' ? 'home visit' : apptType(a)),
        ].where((v) => v.trim().isNotEmpty).join(' · '),
      );
    }
  }

  /// A new lab booking: buzz, chime and add it to the app-wide banner
  /// stack. Bookings are confirmed automatically, so there's nothing to
  /// accept — no repeating alarm, just make sure it's seen.
  void _announceLabBooking() {
    final fresh = ref.read(labOrdersProvider).lastArrivals;
    if (fresh.isEmpty || !mounted) return;
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    final banner = ref.read(pharmacyOrderBannerProvider.notifier);
    for (final o in fresh.reversed) {
      banner.addAppointment(
        o,
        kind: 'labtest',
        title: lab.labIsHome(o) ? 'New home collection' : 'New lab booking',
        subtitle: [
          lab.labPatientName(o),
          lab.labTestSummary(o),
          '${lab.dayLabel(lab.labSlot(o))}, ${lab.timeLabel(lab.labSlot(o))}',
        ].join(' · '),
      );
    }
    ref.read(labDashboardProvider.notifier).load(silent: true);
  }

  void _announceNewOrder() {
    final state = ref.read(pharmacyOrdersProvider);
    final order = state.lastArrival;
    if (order == null || !mounted) return;
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    // Repeats until someone opens Orders or taps the alert (see
    // [_acknowledgeOrders]); a single chime is easy to miss at a counter.
    PharmacyOrderRinger.instance.ring(
      latest: order,
      waiting: state.awaitingOrders.length,
    );

    // App-wide banner. Oldest first, so the newest ends on top of the stack.
    final banner = ref.read(pharmacyOrderBannerProvider.notifier);
    final arrivals = state.lastArrivals.isEmpty ? [order] : state.lastArrivals;
    for (final o in arrivals.reversed) {
      banner.add(o);
    }
  }

  /// Someone has looked at the orders: stop ringing. The banner is left
  /// alone — only the user clears it (see PharmacyOrderBannerNotifier).
  void _acknowledgeOrders() {
    PharmacyOrderRinger.instance.stop();
  }

  void _selectTab(int index) {
    setState(() => _currentIndex = index);
    // Orders (pharmacy) and Appointments/Sessions (doctor, physio) are both
    // the second tab: opening it is someone looking, so the ringing stops.
    if (index == PharmacyTab.orders) _acknowledgeOrders();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final role = authState.user?.role ?? UserRole.doctor;
    final pages = _getPages(role);
    final navItems = _getNavItems(role);
    final roleColor = _getRoleColor(role);

    if (role == UserRole.pharmacy) {
      // Once per shell, not once per build: this used to re-run the branch
      // initialiser on every rebuild of the dashboard.
      if (!_pharmacyBooted) {
        _pharmacyBooted = true;
        Future.microtask(() async {
          await ref.read(pharmacyStoreProvider.notifier).initialize();
          if (mounted) {
            ref.read(pharmacyOrdersProvider.notifier).startLiveUpdates();
          }
        });
      }
      ref.listen<int>(pharmacyOrdersProvider.select((s) => s.arrivalTick), (
        previous,
        next,
      ) {
        if (previous != null && next > previous) _announceNewOrder();
      });
      ref.listen<int>(
        pharmacyOrdersProvider.select((s) => s.awaitingOrders.length),
        (_, next) {
          if (next == 0) _acknowledgeOrders();
        },
      );
      // An order accepted, rejected or cancelled leaves the banner.
      ref.listen<String>(
        pharmacyOrdersProvider.select(
          (s) => s.awaitingOrders.map((o) => '${o['_id']}').join(','),
        ),
        (_, next) => ref
            .read(pharmacyOrderBannerProvider.notifier)
            .retainOnly(next.isEmpty ? const {} : next.split(',').toSet()),
      );
      ref.listen<int?>(pharmacyTabRequestProvider, (_, next) {
        if (next == null) return;
        _selectTab(next);
        ref.read(pharmacyTabRequestProvider.notifier).state = null;
      });
    }
    // Doctors and physios share the appointments data layer (the server
    // scopes /appointment by role), so they boot and alert the same way.
    if (role == UserRole.doctor || role == UserRole.physiotherapist) {
      if (!_doctorBooted) {
        _doctorBooted = true;
        ProfessionalNotificationNavigationService.appointmentScreen =
            _appointmentScreen;
        Future.microtask(
          () =>
              ref.read(doctorAppointmentsProvider.notifier).startLiveUpdates(),
        );
      }
      ref.listen<int>(doctorAppointmentsProvider.select((s) => s.arrivalTick), (
        previous,
        next,
      ) {
        if (previous != null && next > previous) _announceNewRequest();
      });
      // Nothing left to answer: stop ringing. A request accepted, declined,
      // cancelled or expired leaves the banner.
      ref.listen<String>(
        doctorAppointmentsProvider.select(
          (s) => s.requests.map((a) => '${a['_id']}').join(','),
        ),
        (_, next) {
          if (next.isEmpty) _acknowledgeOrders();
          ref
              .read(pharmacyOrderBannerProvider.notifier)
              .retainOnly(next.isEmpty ? const {} : next.split(',').toSet());
        },
      );
      ref.listen<int?>(pharmacyTabRequestProvider, (_, next) {
        if (next == null) return;
        _selectTab(next);
        ref.read(pharmacyTabRequestProvider.notifier).state = null;
      });
    }
    if (role == UserRole.mr) {
      if (!_mrBooted) {
        _mrBooted = true;
        Future.microtask(() => ref.read(mrProvider.notifier).ensureLoaded());
      }
      // Rebuild the tabs once the profile says whether this is a manager.
      ref.watch(mrProvider.select((s) => s.isManager));
      ref.listen<int?>(pharmacyTabRequestProvider, (_, next) {
        if (next == null) return;
        _selectTab(next);
        ref.read(pharmacyTabRequestProvider.notifier).state = null;
      });
    }
    if (role == UserRole.pathology) {
      if (!_labBooted) {
        _labBooted = true;
        ProfessionalNotificationNavigationService.labOrderScreen = (id) =>
            PathologyOrderDetail(orderId: id);
        Future.microtask(() {
          ref.read(labOrdersProvider.notifier).startLiveUpdates();
          ref.read(labDashboardProvider.notifier).load();
        });
      }
      ref.listen<int>(labOrdersProvider.select((s) => s.arrivalTick), (
        previous,
        next,
      ) {
        if (previous != null && next > previous) _announceLabBooking();
      });
      // A booking leaves the banner once its sample is collected (or it's
      // cancelled) — the lab has clearly dealt with it.
      ref.listen<String>(
        labOrdersProvider.select(
          (s) => s
              .inStage(lab.LabStage.collect)
              .map((o) => '${o['_id']}')
              .join(','),
        ),
        (_, next) => ref
            .read(pharmacyOrderBannerProvider.notifier)
            .retainOnly(next.isEmpty ? const {} : next.split(',').toSet()),
      );
      ref.listen<int?>(pharmacyTabRequestProvider, (_, next) {
        if (next == null) return;
        _selectTab(next);
        ref.read(pharmacyTabRequestProvider.notifier).state = null;
      });
    }
    // Modules on the minimal kit: pill nav, faded tabs, clamped scrolling,
    // bell and verification notice inside their own Home.
    final minimal =
        role == UserRole.pharmacy ||
        role == UserRole.doctor ||
        role == UserRole.physiotherapist ||
        role == UserRole.pathology ||
        role == UserRole.mr;
    final labWaiting = role == UserRole.pathology
        ? ref.watch(
            labOrdersProvider.select(
              (s) =>
                  s.inStage(lab.LabStage.collect).length +
                  s.inStage(lab.LabStage.reports).length,
            ),
          )
        : 0;
    final doctorRequests =
        role == UserRole.doctor || role == UserRole.physiotherapist
        ? ref.watch(doctorAppointmentsProvider.select((s) => s.requests.length))
        : 0;
    final awaitingOrders = role == UserRole.pharmacy
        ? ref.watch(
            pharmacyOrdersProvider.select((s) => s.awaitingOrders.length),
          )
        : 0;

    // Pharmacy renders this notice inside its Home screen instead, below the
    // hero and above the actions group, where it sits in that page's own
    // rhythm. A differently-styled strip shoved above the hero broke the top
    // of the screen. Keeping `showBanner` false for pharmacy (rather than
    // just skipping the widget) also leaves the notification bell's own
    // SafeArea handling below intact.
    final showBanner =
        authState.user?.verificationStatus != VerificationStatus.approved &&
        !_bannerDismissed &&
        !minimal;

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
                IndexedStack(
                  index: _currentIndex,
                  children: [
                    for (var i = 0; i < pages.length; i++)
                      // The tab coming into view fades up instead of
                      // snapping; IndexedStack keeps each tab's state.
                      minimal
                          ? AnimatedOpacity(
                              opacity: i == _currentIndex ? 1 : 0,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                              child: PharmacyScrollScope(child: pages[i]),
                            )
                          : pages[i],
                  ],
                ),
                // Pharmacy carries its bell inside Home's pinned header
                // instead of floating it over the tabs.
                if (!minimal)
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
      bottomNavigationBar:
          role == UserRole.doctor || role == UserRole.physiotherapist
          ? PharmacyBottomBarReporter(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: ApiService.reachable,
                    builder: (_, online, _) => AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      child: online
                          ? const SizedBox(width: double.infinity)
                          : PharmacyOfflineBanner(
                              onRetry: () => ref
                                  .read(doctorAppointmentsProvider.notifier)
                                  .load(silent: true),
                            ),
                    ),
                  ),
                  PharmacyNavBar(
                    currentIndex: _currentIndex,
                    onTap: _selectTab,
                    items: [
                      const PharmacyNavItem(LucideIcons.house, 'Today'),
                      PharmacyNavItem(
                        LucideIcons.calendarDays,
                        role == UserRole.physiotherapist
                            ? 'Sessions'
                            : 'Appointments',
                        badge: doctorRequests,
                      ),
                      const PharmacyNavItem(LucideIcons.users, 'Patients'),
                      const PharmacyNavItem(LucideIcons.wallet, 'Earnings'),
                      const PharmacyNavItem(
                        LucideIcons.circleUserRound,
                        'Profile',
                      ),
                    ],
                  ),
                ],
              ),
            )
          : role == UserRole.mr
          ? PharmacyBottomBarReporter(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: ApiService.reachable,
                    builder: (_, online, _) => AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      child: online
                          ? const SizedBox(width: double.infinity)
                          : PharmacyOfflineBanner(
                              onRetry: () => ref.read(mrProvider.notifier).loadAll(),
                            ),
                    ),
                  ),
                  Builder(
                    builder: (_) {
                      final mr = ref.watch(mrProvider);
                      final toReport = mr.visits
                          .where((v) => mr.isMine(v['profileId']) && const {'completed', 'rejected'}.contains(v['status']))
                          .length;
                      final pending = (mr.metrics['pendingApprovals'] as num?)?.toInt() ?? 0;
                      return PharmacyNavBar(
                        currentIndex: _currentIndex,
                        onTap: _selectTab,
                        items: [
                          const PharmacyNavItem(LucideIcons.house, 'Today'),
                          PharmacyNavItem(LucideIcons.stethoscope, 'Calls', badge: toReport),
                          const PharmacyNavItem(LucideIcons.route, 'Plan'),
                          mr.isManager
                              ? PharmacyNavItem(LucideIcons.users, 'Team', badge: pending)
                              : const PharmacyNavItem(LucideIcons.contact, 'Customers'),
                          const PharmacyNavItem(LucideIcons.circleUserRound, 'Profile'),
                        ],
                      );
                    },
                  ),
                ],
              ),
            )
          : role == UserRole.pathology
          ? PharmacyBottomBarReporter(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: ApiService.reachable,
                    builder: (_, online, _) => AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      child: online
                          ? const SizedBox(width: double.infinity)
                          : PharmacyOfflineBanner(
                              onRetry: () => ref
                                  .read(labOrdersProvider.notifier)
                                  .load(silent: true),
                            ),
                    ),
                  ),
                  PharmacyNavBar(
                    currentIndex: _currentIndex,
                    onTap: _selectTab,
                    items: [
                      const PharmacyNavItem(LucideIcons.house, 'Today'),
                      PharmacyNavItem(
                        LucideIcons.clipboardList,
                        'Orders',
                        badge: labWaiting,
                      ),
                      const PharmacyNavItem(LucideIcons.flaskConical, 'Tests'),
                      const PharmacyNavItem(LucideIcons.wallet, 'Earnings'),
                      const PharmacyNavItem(
                        LucideIcons.circleUserRound,
                        'Profile',
                      ),
                    ],
                  ),
                ],
              ),
            )
          : role == UserRole.pharmacy
          ? PharmacyBottomBarReporter(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Above the nav bar rather than at the top: pages own their
                  // safe-area insets, and a top strip would double them.
                  ValueListenableBuilder<bool>(
                    valueListenable: ApiService.reachable,
                    builder: (_, online, _) => AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      child: online
                          ? const SizedBox(width: double.infinity)
                          : PharmacyOfflineBanner(
                              onRetry: () {
                                ref
                                    .read(pharmacyOrdersProvider.notifier)
                                    .pollNow();
                                ref
                                    .read(pharmacyStoreProvider.notifier)
                                    .refresh();
                              },
                            ),
                    ),
                  ),
                  PharmacyNavBar(
                    currentIndex: _currentIndex,
                    awaitingOrders: awaitingOrders,
                    onTap: _selectTab,
                  ),
                ],
              ),
            )
          : Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
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
