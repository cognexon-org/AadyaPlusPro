import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../notifications/widgets/notification_bell.dart';
import '../../pharmacy/providers/pharmacy_nav_provider.dart';
import '../providers/mr_provider.dart';
import '../widgets/mr_claims.dart';
import '../widgets/mr_sheets.dart';
import '../widgets/mr_ui.dart';
import 'mr_accounts.dart';
import 'mr_visit_screen.dart';

/// Today, for a field rep or manager: start and end the workday, today's
/// tour-plan stop, the month against target, today's calls, and the
/// shortcuts used most in the field.
class MrHome extends ConsumerStatefulWidget {
  const MrHome({super.key});

  @override
  ConsumerState<MrHome> createState() => _MrHomeState();
}

class _MrHomeState extends ConsumerState<MrHome> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(mrProvider.notifier).ensureLoaded());
  }

  Future<void> _refresh() => ref.read(mrProvider.notifier).loadAll();

  void _open(Widget page) => Navigator.of(context).push(AppPageRoute(builder: (_) => page));

  void _goTab(int tab) => ref.read(pharmacyTabRequestProvider.notifier).state = tab;

  Future<void> _startDay() async {
    final type = await showAppSheet<String>(context, builder: (_) => const _WorkTypeSheet());
    if (type == null || !mounted) return;
    if (type == 'leave') {
      await applyLeave(context, from: DateTime.now());
      return;
    }
    setState(() => _busy = true);
    await mrRun(context, () => ref.read(mrProvider.notifier).punchIn(workType: type), done: 'Day started — have a good one');
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _endDay() async {
    setState(() => _busy = true);
    await mrRun(context, () => ref.read(mrProvider.notifier).punchOut(), done: 'Day ended');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(mrProvider);
    final accent = ModuleAccent.of(context);
    final now = DateTime.now();
    final todayKey = dateKey(now);
    final todaysCalls = s.visits.where((v) => s.isMine(v['profileId']) && mrDate(v['visitDate']) != null && dateKey(mrDate(v['visitDate'])!) == todayKey).toList()
      ..sort((a, b) => mrDate(a['visitDate'])!.compareTo(mrDate(b['visitDate'])!));
    final toReport = s.visits.where((v) => s.isMine(v['profileId']) && const {'completed', 'rejected'}.contains(v['status'])).length;
    final plan = s.tourPlans.where((p) => s.isMine(p['profileId']) && p['month'] == monthKey(now)).firstOrNull;
    final planDay = listOf(plan?['days']).where((d) => mrDate(d['date']) != null && dateKey(mrDate(d['date'])!) == todayKey).firstOrNull;
    final pending = (s.metrics['pendingApprovals'] as num?)?.toInt() ?? 0;
    final hq = '${s.profile['headquarters'] ?? mapOf(s.dashboard['profile'])['headquarters'] ?? ''}';

    var i = 0;
    Widget enter(Widget c) => AppEntrance(index: i++, child: c);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            MrHeader(
              title: s.name.isEmpty ? 'Field force' : s.name,
              subtitle: [s.designation, if (hq.isNotEmpty) hq, DateFormat('EEE d MMM').format(now)].join(' · '),
              actions: [NotificationBell(color: accent.color)],
            ),
            Expanded(
              child: RefreshIndicator(
                color: accent.color,
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: [
                    if (s.error != null && !s.hasLoaded)
                      AppErrorBanner(message: s.error!, onRetry: _refresh)
                    else if (s.isLoading && !s.hasLoaded)
                      const AppListSkeleton(count: 3)
                    else ...[
                      enter(_WorkdayCard(today: s.today, leave: s.leaveOn(DateTime.now()), busy: _busy, onStart: _startDay, onEnd: _endDay)),
                      if (planDay != null) ...[
                        const SizedBox(height: 12),
                        enter(_PlanStop(day: planDay, approved: plan?['status'] == 'approved')),
                      ],
                      if (toReport > 0) ...[
                        const SizedBox(height: 12),
                        enter(_Nudge(
                          icon: LucideIcons.filePen,
                          color: AppColors.warning,
                          text: toReport == 1 ? '1 call report to write' : '$toReport call reports to write',
                          onTap: () => _goTab(MrTab.calls),
                        )),
                      ],
                      if (s.isManager && pending > 0) ...[
                        const SizedBox(height: 12),
                        enter(_Nudge(
                          icon: LucideIcons.inbox,
                          color: accent.color,
                          text: pending == 1 ? '1 item waiting for your approval' : '$pending items waiting for your approval',
                          onTap: () => _goTab(MrTab.team),
                        )),
                      ],
                      const SizedBox(height: 22),
                      enter(AppSectionTitle('This month · ${DateFormat('MMMM').format(now)}')),
                      enter(_MonthRings(state: s)),
                      const SizedBox(height: 22),
                      enter(AppSectionTitle(
                        todaysCalls.isEmpty ? 'Today’s calls' : 'Today’s calls · ${todaysCalls.length}',
                        action: 'All calls',
                        onAction: () => _goTab(MrTab.calls),
                      )),
                      if (todaysCalls.isEmpty)
                        enter(AppEmptyState(
                          icon: LucideIcons.calendarPlus,
                          text: 'No calls planned for today.',
                          action: AppButton(
                            label: 'Plan a call',
                            icon: LucideIcons.plus,
                            compact: true,
                            fullWidth: false,
                            onPressed: () => planCall(context, ref),
                          ),
                        ))
                      else
                        for (final v in todaysCalls)
                          enter(Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: MrVisitCard(visit: v, showRep: false, onTap: () => _open(MrVisitScreen(visitId: idOf(v)))),
                          )),
                      const SizedBox(height: 22),
                      enter(const AppSectionTitle('Quick actions')),
                      enter(Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _Quick(LucideIcons.calendarPlus, 'Plan call', () => planCall(context, ref)),
                          _Quick(LucideIcons.receiptIndianRupee, 'Expense', () => newExpense(context, ref)),
                          _Quick(LucideIcons.shoppingCart, 'Book order', () => newOrder(context, ref)),
                          _Quick(LucideIcons.contact, 'Customers', () => _open(const MrAccountsScreen())),
                        ],
                      )),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The workday: not started → choose the day's work and start; started →
/// a live clock since punch-in; ended → the day's length.
class _WorkdayCard extends StatefulWidget {
  final Map<String, dynamic>? today;
  final Map<String, dynamic>? leave;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onEnd;
  const _WorkdayCard({required this.today, this.leave, required this.busy, required this.onStart, required this.onEnd});

  @override
  State<_WorkdayCard> createState() => _WorkdayCardState();
}

class _WorkdayCardState extends State<_WorkdayCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    final t = widget.today;
    final inAt = mrDate(mapOf(t?['punchIn'])['at']);
    final outAt = mrDate(mapOf(t?['punchOut'])['at']);
    final type = '${t?['workType'] ?? 'field'}';
    final leave = widget.leave;
    final fullLeave = leave?['status'] == 'approved' && leave?['halfDay'] != true;
    final onLeave = inAt == null && (t?['status'] == 'leave' || fullLeave);
    final (title, line) = onLeave
        ? ('On leave today', 'Enjoy the day off.')
        : inAt == null
        ? (
            'Ready to start?',
            leave?['status'] == 'pending'
                ? 'Your leave for today is awaiting approval.'
                : leave?['halfDay'] == true
                ? 'Half-day leave approved. Start when you’re in.'
                : 'Start your day to log attendance with your location.',
          )
        : outAt == null
        ? (durationLabel(DateTime.now().difference(inAt)), '${workTypes[type]?.$1 ?? 'Field work'} · started ${timeLabel(inAt)}')
        : ('Day complete', '${durationLabel(outAt.difference(inAt))} · ${timeLabel(inAt)} – ${timeLabel(outAt)}');
    final live = inAt != null && outAt == null && !onLeave;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(accent.color, Colors.white, 0.18)!, accent.color],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(right: -30, top: -40, child: _ring(120, 0.10)),
          Positioned(right: 30, bottom: -50, child: _ring(80, 0.08)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (live) ...[
                    const AppPulse(color: Colors.white),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    live ? 'In the field' : 'Your workday',
                    style: AppType.sans(fontSize: AppType.small, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.85)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(title, style: AppType.sans(fontSize: live ? 28 : 21, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: Colors.white)),
              const SizedBox(height: 3),
              Text(line, style: AppType.sans(fontSize: AppType.small, color: Colors.white.withValues(alpha: 0.88))),
              if (!onLeave && outAt == null) ...[
                const SizedBox(height: 14),
                AppPressable(
                  onTap: widget.busy ? null : (inAt == null ? widget.onStart : widget.onEnd),
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: inAt == null ? Colors.white : Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                      border: inAt == null ? null : Border.all(color: Colors.white.withValues(alpha: 0.6)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.busy)
                          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: inAt == null ? accent.color : Colors.white))
                        else
                          Icon(inAt == null ? LucideIcons.play : LucideIcons.square, size: 15, color: inAt == null ? accent.color : Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          inAt == null ? 'Start my day' : 'End my day',
                          style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w800, color: inAt == null ? accent.color : Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static Widget _ring(double size, double alpha) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: alpha)),
  );
}

class _WorkTypeSheet extends StatefulWidget {
  const _WorkTypeSheet();

  @override
  State<_WorkTypeSheet> createState() => _WorkTypeSheetState();
}

class _WorkTypeSheetState extends State<_WorkTypeSheet> {
  String _type = 'field';

  @override
  Widget build(BuildContext context) => MrSheetBody(
    children: [
      const MrSheetTitle('Start your day', subtitle: 'Your location is saved with the time.'),
      for (final e in workTypes.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppPressable(
            onTap: () => setState(() => _type = e.key),
            child: AnimatedContainer(
              duration: AppMotion.fast,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _type == e.key ? ModuleAccent.of(context).veryLight : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _type == e.key ? ModuleAccent.of(context).color : AppColors.borderStrong, width: _type == e.key ? 1.5 : 1),
              ),
              child: Row(
                children: [
                  Icon(e.value.$2, size: 19, color: _type == e.key ? ModuleAccent.of(context).color : AppColors.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(child: Text(e.value.$1, style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w700, color: AppColors.textStrong))),
                  if (_type == e.key) Icon(LucideIcons.circleCheck, size: 19, color: ModuleAccent.of(context).color),
                ],
              ),
            ),
          ),
        ),
      const SizedBox(height: 8),
      AppButton(label: 'Start my day', icon: LucideIcons.play, onPressed: () => Navigator.pop(context, _type)),
      const SizedBox(height: 4),
      Center(
        child: TextButton.icon(
          onPressed: () => Navigator.pop(context, 'leave'),
          icon: const Icon(LucideIcons.palmtree, size: 16),
          label: const Text('Taking leave? Apply instead'),
          style: TextButton.styleFrom(foregroundColor: ModuleAccent.of(context).color),
        ),
      ),
    ],
  );
}

class _PlanStop extends ConsumerWidget {
  final Map<String, dynamic> day;
  final bool approved;
  const _PlanStop({required this.day, required this.approved});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ModuleAccent.of(context);
    final s = ref.watch(mrProvider);
    final today = dateKey(DateTime.now());
    final called = {
      for (final v in s.visits)
        if (s.isMine(v['profileId']) && mrDate(v['visitDate']) != null && dateKey(mrDate(v['visitDate'])!) == today) idOf(v['accountId']),
    };
    final planned = (day['accountIds'] is List ? day['accountIds'] as List : const []).map(idOf).where((id) => id.isNotEmpty).toList();
    final toPlan = planned.where((id) => !called.contains(id)).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: accent.veryLight, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.route, size: 20, color: accent.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Today’s plan · ${day['area'] ?? ''}', style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
                    if ('${day['objective'] ?? ''}'.isNotEmpty)
                      Text('${day['objective']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.sans(fontSize: AppType.small, color: AppColors.textSecondary)),
                    if (planned.isNotEmpty)
                      Text(
                        toPlan.isEmpty ? 'All ${planned.length} planned customers are on today’s calls' : '${planned.length - toPlan.length} of ${planned.length} customers on today’s calls',
                        style: AppType.sans(fontSize: AppType.caption, fontWeight: FontWeight.w600, color: toPlan.isEmpty ? AppColors.success : accent.color),
                      ),
                  ],
                ),
              ),
              if (!approved) const MrStatusPill('draft'),
            ],
          ),
          if (toPlan.isNotEmpty) ...[
            const SizedBox(height: 10),
            AppButton(
              label: 'Plan ${toPlan.length} call${toPlan.length == 1 ? '' : 's'} for today',
              icon: LucideIcons.calendarPlus,
              compact: true,
              onPressed: () => mrRun(context, () async {
                // Space the calls 45 minutes apart from now so the day reads in order.
                var at = DateTime.now().add(const Duration(minutes: 15));
                for (final id in toPlan) {
                  await ref.read(mrProvider.notifier).createVisit(id, when: at);
                  at = at.add(const Duration(minutes: 45));
                }
              }, done: 'Today’s calls are planned'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Nudge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final VoidCallback onTap;
  const _Nudge({required this.icon, required this.color, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) => AppPressable(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: Color.alphaBlend(color.withValues(alpha: 0.09), Colors.white), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w700, color: AppColors.textStrong))),
          Icon(LucideIcons.chevronRight, size: 18, color: color),
        ],
      ),
    ),
  );
}

/// Calls, doctor calls, orders and working days — each as a ring filling
/// toward the month's target (or just the count when none is set).
class _MonthRings extends StatelessWidget {
  final MrState state;
  const _MonthRings({required this.state});

  @override
  Widget build(BuildContext context) {
    final m = state.metrics;
    final target = mapOf(state.selfPerformance['target']);
    num n(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
    final rings = [
      ('Calls', n(m['calls']), n(target['callTarget']), false),
      ('Doctors', n(m['doctorCalls']), n(target['doctorCallTarget']), false),
      ('Orders', n(m['pobAmount']), n(target['pobTarget']), true),
      ('Days', n(m['workingDays']), n(target['workingDaysTarget']), false),
    ];
    return AppCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Row(
        children: [
          for (final (label, value, goal, money) in rings)
            Expanded(child: _Ring(label: label, value: value, goal: goal, money: money)),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  final String label;
  final num value;
  final num goal;
  final bool money;
  const _Ring({required this.label, required this.value, required this.goal, required this.money});

  String _short(num v) {
    if (!money) return v % 1 == 0 ? '${v.toInt()}' : v.toStringAsFixed(1);
    if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
    if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}k';
    return '₹${v.toInt()}';
  }

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    final progress = goal > 0 ? math.min(1.0, value / goal) : 0.0;
    final done = goal > 0 && value >= goal;
    return Column(
      children: [
        SizedBox(
          width: 64,
          height: 64,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress.toDouble()),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: goal > 0 ? v : 0,
                    strokeWidth: 5.5,
                    strokeCap: StrokeCap.round,
                    backgroundColor: accent.veryLight,
                    color: done ? AppColors.success : accent.color,
                  ),
                ),
                Text(_short(value), style: AppType.sans(fontSize: money ? AppType.small : AppType.title, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: AppType.sans(fontSize: AppType.caption, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        Text(
          goal > 0 ? 'of ${_short(goal)}' : 'no target',
          style: AppType.sans(fontSize: AppType.micro, color: AppColors.textTertiary),
        ),
      ],
    );
  }
}

class _Quick extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Quick(this.icon, this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    return AppPressable(
      onTap: onTap,
      semanticLabel: label,
      child: SizedBox(
        width: 76,
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(color: accent.veryLight, shape: BoxShape.circle),
              child: Icon(icon, size: 22, color: accent.color),
            ),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center, style: AppType.sans(fontSize: AppType.caption, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}
