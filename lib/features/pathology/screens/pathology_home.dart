import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../auth/models/user_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../doctor/widgets/home_carousel.dart';
import '../../notifications/widgets/notification_bell.dart';
import '../../pharmacy/providers/pharmacy_nav_provider.dart';
import '../providers/lab_providers.dart';
import '../widgets/lab_ui.dart';
import 'lab_schedule.dart';
import 'lab_test_library.dart';
import 'pathology_order_detail.dart';
import 'pathology_orders.dart';
import 'pathology_staff.dart';

/// The lab's Today: where the day's samples are (to collect, in process,
/// ready to release, overdue), what needs a person now, today's slots in
/// time order, and — for a new lab — the three things to set up first.
class PathologyHome extends ConsumerStatefulWidget {
  const PathologyHome({super.key});

  @override
  ConsumerState<PathologyHome> createState() => _PathologyHomeState();
}

class _PathologyHomeState extends ConsumerState<PathologyHome> {
  bool _scrolled = false;
  Timer? _tick;

  static const _ordersTab = 1;
  static const _earningsTab = 3;

  static const List<HomeSlide> _slides = [
    (
      title: 'Add tests in one tap',
      body: 'CBC, LFT, lipid profile and more — with reference ranges.',
      cta: 'Test library',
      art: HomeSlideArt.tubes,
      page: LabTestLibrary(),
      tab: null,
    ),
    (
      title: 'Open collection slots',
      body: 'Set your week once; slots roll forward on their own.',
      cta: 'Set slots',
      art: HomeSlideArt.schedule,
      page: LabSchedule(),
      tab: null,
    ),
    (
      title: 'Reports without paperwork',
      body: 'Type results, values flag themselves, release a PDF.',
      cta: 'Orders',
      art: HomeSlideArt.labReport,
      page: null,
      tab: _ordersTab,
    ),
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(labDashboardProvider.notifier).load(silent: true);
      ref.read(labOrdersProvider.notifier).ensureLoaded();
    });
    // Keeps "overdue" and today's list honest without a reload.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _refresh() => Future.wait([
    ref.read(labDashboardProvider.notifier).load(silent: true),
    ref.read(labOrdersProvider.notifier).load(silent: true),
  ]);

  void _push(Widget page) =>
      Navigator.of(context).push(AppPageRoute(builder: (_) => page));

  void _openOrder(Map<String, dynamic> o) => _push(
    PathologyOrderDetail(orderId: '${o['_id']}', order: o),
  );

  void _goToOrders(LabOrderFilter filter) {
    ref.read(labOrderFilterProvider.notifier).state = filter;
    ref.read(pharmacyTabRequestProvider.notifier).state = _ordersTab;
  }

  void _openSlide(HomeSlide s) {
    if (s.page != null) {
      _push(s.page!);
    } else if (s.tab != null) {
      _goToOrders(LabOrderFilter.open);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders = ref.watch(labOrdersProvider);
    final dash = ref.watch(labDashboardProvider);
    final user = ref.watch(authProvider.select((s) => s.user));
    final accent = ModuleAccent.of(context);
    final lab = dash.data['lab'] is Map
        ? Map<String, dynamic>.from(dash.data['lab'] as Map)
        : const <String, dynamic>{};
    final stats = dash.data['stats'] is Map
        ? Map<String, dynamic>.from(dash.data['stats'] as Map)
        : const <String, dynamic>{};

    final collect = orders.inStage(LabStage.collect).length;
    final processing = orders.inStage(LabStage.processing).length;
    final reports = orders.inStage(LabStage.reports).length;
    final overdue = orders.overdue;
    final unassigned = orders.unassigned;
    final today = orders.today;
    final attention = [
      ...overdue,
      ...unassigned.where((o) => !overdue.contains(o)),
    ];

    var i = 0;
    Widget enter(Widget c) => AppEntrance(index: i++, child: c);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _header(lab, user, collect, reports, accent),
            AnimatedContainer(
              duration: AppMotion.fast,
              height: 1,
              color: _scrolled ? AppColors.border : Colors.transparent,
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  final s = n.metrics.pixels > 4;
                  if (s != _scrolled) setState(() => _scrolled = s);
                  return false;
                },
                child: RefreshIndicator(
                  color: accent.color,
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    children: [
                      if (user != null &&
                          user.verificationStatus !=
                              VerificationStatus.approved)
                        enter(_VerificationNote(status: user.verificationStatus)),
                      if (dash.hasLoaded) ...[
                        if (_setupSteps(lab).any((s) => !s.done))
                          enter(_SetupCard(steps: _setupSteps(lab), onOpen: _push)),
                      ],
                      if (orders.error != null && !orders.hasLoaded)
                        AppErrorBanner(
                          message: orders.error!,
                          onRetry: _refresh,
                        )
                      else if (!orders.hasLoaded)
                        const AppListSkeleton(count: 3)
                      else ...[
                        enter(
                          _Pipeline(
                            collect: collect,
                            processing: processing,
                            reports: reports,
                            overdue: overdue.length,
                            onTap: _goToOrders,
                          ),
                        ),
                        if (attention.isNotEmpty) ...[
                          const SizedBox(height: 22),
                          enter(
                            AppSectionTitle(
                              'Needs attention',
                              action: attention.length > 3 ? 'See all' : null,
                              onAction: () => _goToOrders(
                                overdue.isNotEmpty
                                    ? LabOrderFilter.overdue
                                    : LabOrderFilter.home,
                              ),
                            ),
                          ),
                          for (final o in attention.take(3))
                            enter(
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: LabOrderCard(
                                  order: o,
                                  showDay: true,
                                  onTap: () => _openOrder(o),
                                ),
                              ),
                            ),
                        ],
                        const SizedBox(height: 22),
                        enter(
                          AppSectionTitle(
                            today.isEmpty
                                ? 'Today'
                                : 'Today · ${today.length} booking${today.length == 1 ? '' : 's'}',
                            action: 'All orders',
                            onAction: () => _goToOrders(LabOrderFilter.open),
                          ),
                        ),
                        if (today.isEmpty)
                          enter(
                            const AppEmptyState(
                              icon: LucideIcons.calendarCheck,
                              text: 'No collections booked for today.',
                            ),
                          )
                        else
                          for (final o in today)
                            enter(
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: LabOrderCard(
                                  order: o,
                                  onTap: () => _openOrder(o),
                                ),
                              ),
                            ),
                        const SizedBox(height: 22),
                        enter(
                          HomeCarousel(slides: _slides, onOpen: _openSlide),
                        ),
                        if (dash.hasLoaded) ...[
                          const SizedBox(height: 22),
                          enter(
                            _MoneyStrip(
                              today: stats['revenueToday'] ?? 0,
                              month: stats['monthlyPaidRevenue'] ?? 0,
                              released: stats['completedToday'] ?? 0,
                              onTap: () => ref
                                  .read(pharmacyTabRequestProvider.notifier)
                                  .state = _earningsTab,
                            ),
                          ),
                        ],
                        const SizedBox(height: 22),
                        enter(const AppSectionTitle('Quick actions')),
                        enter(
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _QuickAction(
                                icon: LucideIcons.clock,
                                label: 'Slots',
                                onTap: () => _push(const LabSchedule()),
                              ),
                              _QuickAction(
                                icon: LucideIcons.flaskConical,
                                label: 'Library',
                                onTap: () => _push(const LabTestLibrary()),
                              ),
                              _QuickAction(
                                icon: LucideIcons.users,
                                label: 'Team',
                                onTap: () =>
                                    _push(const PathologyStaffScreen()),
                              ),
                              _QuickAction(
                                icon: LucideIcons.fileCheck2,
                                label: 'Release',
                                onTap: () =>
                                    _goToOrders(LabOrderFilter.reports),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_Step> _setupSteps(Map<String, dynamic> lab) {
    int n(String k) => int.tryParse('${lab[k] ?? 0}') ?? 0;
    return [
      _Step(
        done: n('catalogCount') > 0,
        title: 'Add your tests',
        body: 'Pick from 20 common tests with reference ranges',
        page: const LabTestLibrary(),
      ),
      _Step(
        done: n('slotDaysThisWeek') > 0,
        title: 'Open collection slots',
        body: 'Patients can only book times you’ve opened',
        page: const LabSchedule(),
      ),
      if (lab['homeCollectionAvailable'] == true)
        _Step(
          done: n('staffCount') > 0,
          title: 'Add a phlebotomist',
          body: 'Someone to send for home collections',
          page: const PathologyStaffScreen(),
        ),
    ];
  }

  Widget _header(
    Map<String, dynamic> lab,
    UserModel? user,
    int collect,
    int reports,
    ModuleAccent accent,
  ) {
    final name = '${lab['labName'] ?? ''}'.trim().isNotEmpty
        ? '${lab['labName']}'
        : (user?.name ?? '').trim().isNotEmpty
        ? user!.name
        : 'Your lab';
    final parts = [
      if (collect > 0) '$collect to collect',
      if (reports > 0) '$reports to release',
    ];
    final line = parts.isEmpty ? 'All caught up' : parts.join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.sans(
                    fontSize: AppType.heading,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textStrong,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$line · ${DateFormat('EEE d MMM').format(DateTime.now())}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.sans(
                    fontSize: AppType.caption,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          NotificationBell(color: accent.color),
        ],
      ),
    );
  }
}

// ─────────────────────────── Pieces ───────────────────────────

/// Four tiles: where every open sample is. Each opens Orders filtered.
class _Pipeline extends StatelessWidget {
  final int collect;
  final int processing;
  final int reports;
  final int overdue;
  final ValueChanged<LabOrderFilter> onTap;
  const _Pipeline({
    required this.collect,
    required this.processing,
    required this.reports,
    required this.overdue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    Widget tile(
      String label,
      int value,
      IconData icon,
      Color color,
      LabOrderFilter filter, {
      bool loud = false,
    }) => Expanded(
      child: AppPressable(
        onTap: () => onTap(filter),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: loud ? color.withValues(alpha: 0.08) : AppColors.panel,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppCountUp(
                      value: value,
                      format: (v) => '${v.round()}',
                      style: AppType.sans(
                        fontSize: AppType.figure,
                        fontWeight: FontWeight.w800,
                        color: loud ? color : AppColors.textStrong,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.sans(
                        fontSize: AppType.caption,
                        fontWeight: FontWeight.w600,
                        color: loud ? color : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(icon, size: 18, color: color),
            ],
          ),
        ),
      ),
    );
    return Column(
      children: [
        Row(
          children: [
            tile(
              'To collect',
              collect,
              LucideIcons.testTube,
              AppColors.warning,
              LabOrderFilter.collect,
            ),
            const SizedBox(width: 10),
            tile(
              'In process',
              processing,
              LucideIcons.microscope,
              accent.color,
              LabOrderFilter.processing,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            tile(
              'Ready to release',
              reports,
              LucideIcons.fileCheck2,
              AppColors.success,
              LabOrderFilter.reports,
              loud: reports > 0,
            ),
            const SizedBox(width: 10),
            tile(
              'Overdue',
              overdue,
              LucideIcons.timer,
              overdue > 0 ? AppColors.error : AppColors.textTertiary,
              LabOrderFilter.overdue,
              loud: overdue > 0,
            ),
          ],
        ),
      ],
    );
  }
}

class _Step {
  final bool done;
  final String title;
  final String body;
  final Widget page;
  const _Step({
    required this.done,
    required this.title,
    required this.body,
    required this.page,
  });
}

/// "Get your lab ready": the setup a new lab needs before its first booking.
class _SetupCard extends StatelessWidget {
  final List<_Step> steps;
  final ValueChanged<Widget> onOpen;
  const _SetupCard({required this.steps, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    final done = steps.where((s) => s.done).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: accent.veryLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Get your lab ready',
                  style: AppType.sans(
                    fontSize: AppType.title,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textStrong,
                  ),
                ),
              ),
              Text(
                '$done of ${steps.length}',
                style: AppType.sans(
                  fontSize: AppType.caption,
                  fontWeight: FontWeight.w700,
                  color: accent.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: done / steps.length,
              minHeight: 5,
              color: accent.color,
              backgroundColor: accent.light,
            ),
          ),
          const SizedBox(height: 6),
          for (final s in steps)
            InkWell(
              onTap: s.done ? null : () => onOpen(s.page),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      s.done ? LucideIcons.circleCheck : LucideIcons.circle,
                      size: 20,
                      color: s.done ? AppColors.success : accent.color,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.title,
                            style: AppType.sans(
                              fontSize: AppType.body,
                              fontWeight: FontWeight.w700,
                              color: s.done
                                  ? AppColors.textTertiary
                                  : AppColors.textStrong,
                              decoration: s.done
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          if (!s.done)
                            Text(
                              s.body,
                              style: AppType.sans(
                                fontSize: AppType.caption,
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (!s.done)
                      Icon(
                        LucideIcons.chevronRight,
                        size: 16,
                        color: accent.color,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MoneyStrip extends StatelessWidget {
  final dynamic today;
  final dynamic month;
  final dynamic released;
  final VoidCallback onTap;
  const _MoneyStrip({
    required this.today,
    required this.month,
    required this.released,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget figure(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppType.sans(
              fontSize: AppType.title,
              fontWeight: FontWeight.w800,
              color: AppColors.textStrong,
            ),
          ),
          Text(
            label,
            style: AppType.sans(
              fontSize: AppType.caption,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
    return AppPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            figure('Collected today', appRupees(today)),
            figure('This month', appRupees(month)),
            figure('Reports today', '$released'),
            const Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: AppColors.textDisabled,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    return AppPressable(
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: accent.veryLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 21, color: accent.color),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.sans(
                fontSize: AppType.caption,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerificationNote extends StatelessWidget {
  final VerificationStatus status;
  const _VerificationNote({required this.status});

  @override
  Widget build(BuildContext context) {
    final rejected = status == VerificationStatus.rejected;
    final color = rejected ? AppColors.error : AppColors.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            rejected ? LucideIcons.circleX : LucideIcons.hourglass,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              rejected
                  ? 'Your lab wasn’t approved. Check your details and documents in Profile.'
                  : 'Your lab is being verified. Patients can book you once it’s approved — set up tests and slots meanwhile.',
              style: AppType.sans(
                fontSize: AppType.small,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
