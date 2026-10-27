import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../providers/mr_provider.dart';
import '../widgets/mr_claims.dart';
import '../widgets/mr_sheets.dart';
import '../widgets/mr_ui.dart';

/// The Plan tab: the monthly tour plan (submitted to the manager), expense
/// claims and booked orders.
class MrWork extends ConsumerStatefulWidget {
  const MrWork({super.key});

  @override
  ConsumerState<MrWork> createState() => _MrWorkState();
}

class _MrWorkState extends ConsumerState<MrWork> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _tab = ref.read(mrPlanSectionProvider) ?? 0;
    Future.microtask(() {
      ref.read(mrPlanSectionProvider.notifier).state = null;
      ref.read(mrProvider.notifier).ensureLoaded();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(mrProvider);
    ref.listen<int?>(mrPlanSectionProvider, (_, next) {
      if (next == null) return;
      setState(() => _tab = next);
      ref.read(mrPlanSectionProvider.notifier).state = null;
    });
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            const MrHeader(title: 'Plan', subtitle: 'Tour plan, leave, expenses and orders'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: MrSegments(labels: const ['Tour', 'Leave', 'Expenses', 'Orders'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: AppMotion.medium,
                child: switch (_tab) {
                  0 => const _TourPlan(key: ValueKey('tour')),
                  1 => const _Leave(key: ValueKey('leave')),
                  2 => const _Expenses(key: ValueKey('exp')),
                  _ => const _Orders(key: ValueKey('pob')),
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: switch (_tab) {
        1 => AppFab(label: 'Apply for leave', icon: LucideIcons.plus, onPressed: () => applyLeave(context)),
        2 => AppFab(label: 'New expense', icon: LucideIcons.plus, onPressed: () => newExpense(context, ref)),
        3 => AppFab(label: 'Book order', icon: LucideIcons.plus, onPressed: () => newOrder(context, ref)),
        _ => null,
      },
    );
  }
}

// ─────────────────────────── Tour plan ───────────────────────────

class _TourPlan extends ConsumerStatefulWidget {
  const _TourPlan({super.key});

  @override
  ConsumerState<_TourPlan> createState() => _TourPlanState();
}

class _TourPlanState extends ConsumerState<_TourPlan> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _busy = false;

  Map<String, dynamic>? _plan(MrState s) =>
      s.tourPlans.where((p) => s.isMine(p['profileId']) && p['month'] == monthKey(_month)).firstOrNull;

  Future<void> _editDay(DateTime day, Map<String, dynamic>? plan) async {
    final days = listOf(plan?['days']);
    final existing = days.where((d) => mrDate(d['date']) != null && dateKey(mrDate(d['date'])!) == dateKey(day)).firstOrNull;
    final result = await showAppSheet<Map<String, dynamic>>(context, builder: (_) => _DaySheet(day: day, existing: existing));
    if (result == null || !mounted) return;
    final next = days.where((d) => mrDate(d['date']) == null || dateKey(mrDate(d['date'])!) != dateKey(day)).toList();
    if (result['remove'] != true) {
      // Midday UTC keeps the day the same in every timezone.
      next.add({...result, 'date': '${dateKey(day)}T12:00:00.000Z'});
    }
    setState(() => _busy = true);
    await mrRun(context, () => ref.read(mrProvider.notifier).saveTourPlan(monthKey(_month), next));
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(mrProvider);
    final accent = ModuleAccent.of(context);
    final plan = _plan(s);
    final status = '${plan?['status'] ?? 'draft'}';
    final locked = status == 'submitted' || status == 'approved';
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final byKey = {
      for (final d in listOf(plan?['days']))
        if (mrDate(d['date']) != null) dateKey(mrDate(d['date'])!): d,
    };
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    return RefreshIndicator(
      color: accent.color,
      onRefresh: () => ref.read(mrProvider.notifier).loadPlans(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          Row(
            children: [
              for (final (i, m) in [DateTime(today.year, today.month), DateTime(today.year, today.month + 1)].indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                AppFilterChip(label: DateFormat('MMMM').format(m), selected: _month == m, onTap: () => setState(() => _month = m)),
              ],
              const Spacer(),
              if (plan != null) MrStatusPill(status, icon: true),
            ],
          ),
          const SizedBox(height: 12),
          if (status == 'rejected' && '${plan?['managerComment'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.errorBg, borderRadius: BorderRadius.circular(14)),
                child: Text('Sent back: ${plan!['managerComment']}', style: AppType.sans(fontSize: AppType.small, color: AppColors.textPrimary)),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: accent.veryLight, borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                Icon(LucideIcons.route, size: 20, color: accent.color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    locked
                        ? (status == 'approved' ? 'Approved — follow this plan in the field.' : 'With your manager for approval.')
                        : '${byKey.length} of $daysInMonth days planned. Tap a day to set the area and who you’ll meet.',
                    style: AppType.sans(fontSize: AppType.small, height: 1.4, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (var d = 1; d <= daysInMonth; d++)
            Builder(
              builder: (_) {
                final day = DateTime(_month.year, _month.month, d);
                final entry = byKey[dateKey(day)];
                final sunday = day.weekday == DateTime.sunday;
                final past = day.isBefore(today);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: AppPressable(
                    onTap: locked || past ? null : () => _editDay(day, plan),
                    scale: 0.99,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: entry != null ? Colors.white : (sunday ? AppColors.panel : Colors.white),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: day == today ? accent.color : AppColors.borderStrong, width: day == today ? 1.5 : 1),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 44,
                            child: Column(
                              children: [
                                Text(DateFormat('EEE').format(day), style: AppType.sans(fontSize: AppType.micro, color: AppColors.textSecondary)),
                                Text('$d', style: AppType.sans(fontSize: AppType.title, fontWeight: FontWeight.w800, color: past ? AppColors.textTertiary : AppColors.textStrong)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: entry == null
                                ? Text(sunday ? 'Sunday' : (locked || past ? '—' : 'Add plan'), style: AppType.sans(fontSize: AppType.small, color: AppColors.textTertiary))
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${entry['area'] ?? ''}', style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w700, color: AppColors.textStrong)),
                                      if ('${entry['objective'] ?? ''}'.isNotEmpty || listOf(entry['accountIds']).isNotEmpty || (entry['accountIds'] is List && (entry['accountIds'] as List).isNotEmpty))
                                        Text(
                                          [
                                            if ('${entry['objective'] ?? ''}'.isNotEmpty) '${entry['objective']}',
                                            if (entry['accountIds'] is List && (entry['accountIds'] as List).isNotEmpty) '${(entry['accountIds'] as List).length} customers',
                                          ].join(' · '),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppType.sans(fontSize: AppType.caption, color: AppColors.textSecondary),
                                        ),
                                    ],
                                  ),
                          ),
                          if (!locked && !past) Icon(entry == null ? LucideIcons.plus : LucideIcons.pencil, size: 16, color: AppColors.textTertiary),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          if (plan != null && !locked && byKey.isNotEmpty) ...[
            const SizedBox(height: 10),
            AppButton(
              label: 'Send plan for approval',
              icon: LucideIcons.send,
              loading: _busy,
              onPressed: () async {
                setState(() => _busy = true);
                await mrRun(context, () => ref.read(mrProvider.notifier).submitTourPlan(idOf(plan)), done: 'Plan sent to your manager');
                if (mounted) setState(() => _busy = false);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _DaySheet extends ConsumerStatefulWidget {
  final DateTime day;
  final Map<String, dynamic>? existing;
  const _DaySheet({required this.day, this.existing});

  @override
  ConsumerState<_DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends ConsumerState<_DaySheet> {
  late final _area = TextEditingController(text: '${widget.existing?['area'] ?? ''}');
  late final _objective = TextEditingController(text: '${widget.existing?['objective'] ?? ''}');
  late final Set<String> _accounts = {
    for (final a in (widget.existing?['accountIds'] is List ? widget.existing!['accountIds'] as List : const [])) idOf(a),
  };
  String? _error;

  @override
  void dispose() {
    _area.dispose();
    _objective.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(mrProvider).accounts.where((a) => a['isActive'] != false).toList();
    return MrSheetBody(
      children: [
        MrSheetTitle(DateFormat('EEEE, d MMMM').format(widget.day)),
        AppTextField(label: 'Area', controller: _area, required: true, hint: 'e.g. Indiranagar, HAL 2nd stage', textCapitalization: TextCapitalization.words),
        AppTextField(label: 'Objective', controller: _objective, hint: 'e.g. Launch Cardio-X with A-class doctors', textCapitalization: TextCapitalization.sentences),
        if (accounts.isNotEmpty) ...[
          Text('Customers to meet', style: AppType.sans(fontSize: AppType.small, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in accounts.take(30))
                AppFilterChip(
                  label: '${a['name']}',
                  selected: _accounts.contains(idOf(a)),
                  onTap: () => setState(() => _accounts.contains(idOf(a)) ? _accounts.remove(idOf(a)) : _accounts.add(idOf(a))),
                ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        if (_error != null)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: AppType.sans(fontSize: AppType.small, color: AppColors.error))),
        AppButton(
          label: 'Save day',
          icon: LucideIcons.check,
          onPressed: () {
            if (_area.text.trim().isEmpty) {
              setState(() => _error = 'Add the area you’ll cover');
              return;
            }
            Navigator.pop(context, {'area': _area.text.trim(), 'objective': _objective.text.trim(), 'accountIds': _accounts.toList()});
          },
        ),
        if (widget.existing != null) ...[
          const SizedBox(height: 8),
          AppSecondaryButton(label: 'Clear this day', color: AppColors.error, onPressed: () => Navigator.pop(context, {'remove': true})),
        ],
      ],
    );
  }
}

// ─────────────────────────── Expenses ───────────────────────────

class _Expenses extends ConsumerWidget {
  const _Expenses({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(mrProvider);
    final accent = ModuleAccent.of(context);
    final mine = s.expenses.where((e) => s.isMine(e['profileId'])).toList()
      ..sort((a, b) => (mrDate(b['expenseDate']) ?? DateTime(0)).compareTo(mrDate(a['expenseDate']) ?? DateTime(0)));
    final month = monthKey(DateTime.now());
    final thisMonth = mine.where((e) => mrDate(e['expenseDate']) != null && monthKey(mrDate(e['expenseDate'])!) == month);
    num sum(Iterable<Map<String, dynamic>> l) => l.fold<num>(0, (a, e) => a + ((e['amount'] as num?) ?? 0));
    final claimed = sum(thisMonth.where((e) => e['status'] != 'draft'));
    final approved = sum(thisMonth.where((e) => e['status'] == 'approved' || e['status'] == 'paid'));
    return RefreshIndicator(
      color: accent.color,
      onRefresh: () => ref.read(mrProvider.notifier).loadExpenses(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
        children: [
          Row(
            children: [
              Expanded(child: AppMetricTile(label: 'Claimed this month', value: appRupees(claimed), icon: LucideIcons.receiptIndianRupee, color: accent.color)),
              const SizedBox(width: 10),
              Expanded(child: AppMetricTile(label: 'Approved', value: appRupees(approved), icon: LucideIcons.circleCheck, color: AppColors.success)),
            ],
          ),
          const SizedBox(height: 14),
          if (mine.isEmpty)
            const AppEmptyState(icon: LucideIcons.receipt, text: 'No expenses yet. Add travel, allowances and other claims here.')
          else
            for (final e in mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.all(14),
                  onTap: () => expenseDetail(context, idOf(e)),
                  child: Row(
                    children: [
                      AppIconBadge(icon: expenseCategories[e['category']]?.$2 ?? LucideIcons.receipt, color: accent.color),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(child: Text(expenseCategories[e['category']]?.$1 ?? '${e['category']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w700, color: AppColors.textStrong))),
                                if (hasReceipt(e)) ...[const SizedBox(width: 6), Icon(LucideIcons.paperclip, size: 13, color: AppColors.textTertiary)],
                              ],
                            ),
                            Text(
                              [if (mrDate(e['expenseDate']) != null) DateFormat('d MMM').format(mrDate(e['expenseDate'])!), if ('${e['description'] ?? ''}'.isNotEmpty) '${e['description']}'].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.sans(fontSize: AppType.caption, color: AppColors.textSecondary),
                            ),
                            if (e['status'] == 'rejected' && '${e['managerComment'] ?? ''}'.isNotEmpty)
                              Text('Sent back: ${e['managerComment']}', style: AppType.sans(fontSize: AppType.caption, color: AppColors.error)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(appRupees(e['amount']), style: AppType.sans(fontSize: AppType.title, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
                          const SizedBox(height: 4),
                          if (e['status'] == 'draft' || e['status'] == 'rejected')
                            GestureDetector(
                              onTap: () => mrRun(context, () => ref.read(mrProvider.notifier).submitExpense(idOf(e)), done: 'Sent for approval'),
                              child: Text('Submit', style: AppType.sans(fontSize: AppType.small, fontWeight: FontWeight.w800, color: accent.color)),
                            )
                          else
                            MrStatusPill(e['status']?.toString()),
                        ],
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

// ─────────────────────────── Leave ───────────────────────────

class _Leave extends ConsumerWidget {
  const _Leave({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(mrProvider);
    final accent = ModuleAccent.of(context);
    final n = ref.read(mrProvider.notifier);
    final mine = s.leaves.where((l) => s.isMine(l['profileId'])).toList()
      ..sort((a, b) => '${b['fromDate']}'.compareTo('${a['fromDate']}'));
    final year = '${DateTime.now().year}';
    final taken = mine
        .where((l) => l['status'] == 'approved' && '${l['fromDate']}'.startsWith(year))
        .fold<num>(0, (a, l) => a + ((l['days'] as num?) ?? 0));
    final pending = mine.where((l) => l['status'] == 'pending').length;
    final today = dateKey(DateTime.now());
    return RefreshIndicator(
      color: accent.color,
      onRefresh: () => Future.wait([n.loadLeaves(), n.loadAttendance()]),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
        children: [
          Row(
            children: [
              Expanded(child: AppMetricTile(label: 'Taken in $year', value: taken == 0.5 ? 'Half day' : '${taken == taken.roundToDouble() ? taken.toInt() : taken} day${taken == 1 ? '' : 's'}', icon: LucideIcons.palmtree, color: accent.color)),
              const SizedBox(width: 10),
              Expanded(child: AppMetricTile(label: 'Awaiting approval', value: '$pending', icon: LucideIcons.hourglass, color: AppColors.warning)),
            ],
          ),
          const SizedBox(height: 14),
          if (mine.isEmpty)
            const AppEmptyState(icon: LucideIcons.palmtree, text: 'No leave yet. Apply here and your manager approves it.')
          else
            for (final l in mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: MrLeaveCard(
                  leave: l,
                  trailing: l['status'] == 'pending' || (l['status'] == 'approved' && '${l['fromDate']}'.compareTo(today) > 0)
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: GestureDetector(
                            onTap: () async {
                              final ok = await AppModal.show<bool>(
                                context,
                                title: 'Cancel this leave?',
                                icon: LucideIcons.calendarX,
                                content: Text(leaveDates(l), style: AppType.sans(fontSize: AppType.body, color: AppColors.textPrimary)),
                                actions: [
                                  AppSecondaryButton(label: 'Keep it', onPressed: () => Navigator.pop(context, false)),
                                  AppButton(label: 'Cancel leave', onPressed: () => Navigator.pop(context, true)),
                                ],
                              );
                              if (ok == true && context.mounted) await mrRun(context, () => n.cancelLeave(idOf(l)), done: 'Leave cancelled');
                            },
                            child: Text('Cancel request', style: AppType.sans(fontSize: AppType.small, fontWeight: FontWeight.w800, color: AppColors.error)),
                          ),
                        )
                      : null,
                ),
              ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Orders ───────────────────────────

class _Orders extends ConsumerWidget {
  const _Orders({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(mrProvider);
    final accent = ModuleAccent.of(context);
    final orders = [...s.pobOrders]..sort((a, b) => (mrDate(b['createdAt']) ?? DateTime(0)).compareTo(mrDate(a['createdAt']) ?? DateTime(0)));
    final value = orders.where((o) => o['status'] != 'cancelled').fold<num>(0, (a, o) => a + ((o['totalAmount'] as num?) ?? 0));
    final names = {for (final a in s.accounts) idOf(a): '${a['name']}'};
    return RefreshIndicator(
      color: accent.color,
      onRefresh: () => ref.read(mrProvider.notifier).loadPob(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
        children: [
          AppMetricTile(label: 'Orders booked · ${orders.length}', value: appRupees(value), icon: LucideIcons.shoppingCart, color: accent.color),
          const SizedBox(height: 14),
          if (orders.isEmpty)
            const AppEmptyState(icon: LucideIcons.shoppingCart, text: 'No orders yet. Book them at chemists, stockists and hospitals.')
          else
            for (final o in orders)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _OrderCard(order: o, accountName: names[idOf(o['accountId'])] ?? '${mapOf(o['accountId'])['name'] ?? 'Customer'}'),
              ),
        ],
      ),
    );
  }
}

class _OrderCard extends ConsumerWidget {
  final Map<String, dynamic> order;
  final String accountName;
  const _OrderCard({required this.order, required this.accountName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(mrProvider);
    final o = order;
    final mine = s.isMine(o['profileId']);
    final status = '${o['status']}';
    final items = listOf(o['items']);
    final notifier = ref.read(mrProvider.notifier);
    final actions = <Widget>[
      if (mine && status == 'placed')
        TextButton(onPressed: () => mrRun(context, () => notifier.setPobStatus(idOf(o), 'cancelled'), done: 'Order cancelled'), style: TextButton.styleFrom(foregroundColor: AppColors.error), child: const Text('Cancel')),
      if (!mine && s.isManager && status == 'placed')
        AppButton(label: 'Accept', compact: true, fullWidth: false, onPressed: () => mrRun(context, () => notifier.setPobStatus(idOf(o), 'accepted'), done: 'Accepted')),
      if (!mine && s.isManager && status == 'accepted')
        AppButton(label: 'Mark fulfilled', compact: true, fullWidth: false, onPressed: () => mrRun(context, () => notifier.setPobStatus(idOf(o), 'fulfilled'), done: 'Marked fulfilled')),
    ];
    return AppCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(accountName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.sans(fontSize: AppType.body + 1, fontWeight: FontWeight.w800, color: AppColors.textStrong))),
              Text(appRupees(o['totalAmount']), style: AppType.sans(fontSize: AppType.title, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [
              '${o['orderNumber'] ?? ''}',
              if (mrDate(o['createdAt']) != null) dayLabel(mrDate(o['createdAt'])!),
              if (!mine) repName(o['profileId']),
            ].where((e) => e.isNotEmpty).join(' · '),
            style: AppType.sans(fontSize: AppType.caption, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(items.map((i) => '${i['productName']} × ${i['quantity']}').join(', '), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.sans(fontSize: AppType.small, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          Row(
            children: [
              MrStatusPill(status, icon: true),
              const Spacer(),
              ...actions,
            ],
          ),
        ],
      ),
    );
  }
}
