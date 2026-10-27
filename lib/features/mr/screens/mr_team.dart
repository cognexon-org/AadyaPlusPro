import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/ui/app_ui.dart';
import '../providers/mr_provider.dart';
import '../widgets/mr_claims.dart';
import '../widgets/mr_manage.dart';
import '../widgets/mr_sheets.dart';
import '../widgets/mr_ui.dart';
import 'mr_visit_screen.dart';

/// For a manager (ABM, RBM, ZSM): everything the team sent for approval in
/// one inbox, and each member's month against target — with targets and
/// sample stock set from here.
class MrTeam extends ConsumerStatefulWidget {
  const MrTeam({super.key});

  @override
  ConsumerState<MrTeam> createState() => _MrTeamState();
}

class _MrTeamState extends ConsumerState<MrTeam> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(mrProvider.notifier).ensureLoaded());
  }

  Future<void> _refresh() async {
    final n = ref.read(mrProvider.notifier);
    await Future.wait([n.loadDashboard(), n.loadVisits(), n.loadPlans(), n.loadExpenses(), n.loadLeaves(), n.loadTeam(), n.loadAnalytics(), n.loadTargets()]);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(mrProvider);
    final accent = ModuleAccent.of(context);
    final visits = s.visits.where((v) => !s.isMine(v['profileId']) && v['status'] == 'submitted').toList();
    final plans = s.tourPlans.where((p) => !s.isMine(p['profileId']) && p['status'] == 'submitted').toList();
    final expenses = s.expenses.where((e) => !s.isMine(e['profileId']) && e['status'] == 'submitted').toList();
    final leaves = s.leaves.where((l) => !s.isMine(l['profileId']) && l['status'] == 'pending').toList()
      ..sort((a, b) => '${a['fromDate']}'.compareTo('${b['fromDate']}'));
    final toPay = s.expenses.where((e) => !s.isMine(e['profileId']) && e['status'] == 'approved').toList();
    final waiting = visits.length + plans.length + expenses.length + leaves.length;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            MrHeader(title: 'Team', subtitle: '${s.team.where((p) => idOf(p) != s.ownProfileId && p['isActive'] != false).length} people report to you'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: MrSegments(labels: ['Approvals${waiting > 0 ? ' · $waiting' : ''}', 'People'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
            ),
            Expanded(
              child: RefreshIndicator(
                color: accent.color,
                onRefresh: _refresh,
                child: _tab == 0 ? _Approvals(visits: visits, plans: plans, expenses: expenses, leaves: leaves, toPay: toPay) : const _People(),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _tab == 1 && directReport[s.designation] != null
          ? AppFab(label: 'Add ${directReport[s.designation]}', icon: LucideIcons.userPlus, onPressed: () => addTeamMember(context))
          : null,
    );
  }
}

class _Approvals extends ConsumerWidget {
  final List<Map<String, dynamic>> visits;
  final List<Map<String, dynamic>> plans;
  final List<Map<String, dynamic>> expenses;
  final List<Map<String, dynamic>> leaves;
  final List<Map<String, dynamic>> toPay;
  const _Approvals({required this.visits, required this.plans, required this.expenses, required this.leaves, required this.toPay});

  Future<void> _review(BuildContext context, String title, String subtitle, Future<void> Function(String, String) act) async {
    final r = await reviewSheet(context, title: title, subtitle: subtitle);
    if (r == null || !context.mounted) return;
    await mrRun(context, () => act(r.$1, r.$2), done: r.$1 == 'approve' ? 'Approved' : 'Sent back');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(mrProvider.notifier);
    final accent = ModuleAccent.of(context);
    if (visits.isEmpty && plans.isEmpty && expenses.isEmpty && leaves.isEmpty && toPay.isEmpty) {
      return ListView(padding: const EdgeInsets.all(16), children: const [AppEmptyState(icon: LucideIcons.inbox, text: 'Nothing waiting. Your team is all caught up.')]);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        if (leaves.isNotEmpty) ...[
          AppSectionTitle('Leave · ${leaves.length}'),
          for (final l in leaves)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: MrLeaveCard(
                leave: l,
                showRep: true,
                trailing: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AppButton(
                      label: 'Approve',
                      compact: true,
                      fullWidth: false,
                      icon: LucideIcons.check,
                      onPressed: () => mrRun(context, () => n.reviewLeave(idOf(l), 'approve'), done: 'Leave approved'),
                    ),
                    TextButton(
                      onPressed: () async {
                        final r = await reviewSheet(context, title: 'Decline leave', subtitle: '${repName(l['profileId'])} · ${leaveDates(l)}', rejectLabel: 'Decline');
                        if (r == null || !context.mounted) return;
                        await mrRun(context, () => n.reviewLeave(idOf(l), r.$1, comment: r.$2), done: r.$1 == 'approve' ? 'Leave approved' : 'Leave declined');
                      },
                      style: TextButton.styleFrom(foregroundColor: AppColors.error),
                      child: const Text('Decline'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],
        if (plans.isNotEmpty) ...[
          AppSectionTitle('Tour plans · ${plans.length}'),
          for (final p in plans)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        MrAvatar(name: repName(p['profileId']), size: 38),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(repName(p['profileId']), style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
                              Text(
                                '${_monthName(p['month'])} · ${listOf(p['days']).length} days planned',
                                style: AppType.sans(fontSize: AppType.caption, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    for (final d in (listOf(p['days'])..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'))).take(4))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          '${mrDate(d['date']) == null ? '' : DateFormat('EEE d').format(mrDate(d['date'])!)} — ${d['area'] ?? ''}${'${d['objective'] ?? ''}'.isEmpty ? '' : ': ${d['objective']}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.sans(fontSize: AppType.small, color: AppColors.textPrimary),
                        ),
                      ),
                    if (listOf(p['days']).length > 4)
                      Text('+${listOf(p['days']).length - 4} more days', style: AppType.sans(fontSize: AppType.caption, color: AppColors.textTertiary)),
                    const SizedBox(height: 10),
                    AppButton(
                      label: 'Review plan',
                      compact: true,
                      icon: LucideIcons.clipboardCheck,
                      onPressed: () => _review(context, 'Review tour plan', '${repName(p['profileId'])} · ${_monthName(p['month'])}', (d, c) => n.reviewTourPlan(idOf(p), d, comment: c)),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],
        if (visits.isNotEmpty) ...[
          AppSectionTitle('Call reports · ${visits.length}'),
          for (final v in visits)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: MrVisitCard(
                visit: v,
                showRep: true,
                showDay: true,
                onTap: () => Navigator.of(context).push(AppPageRoute(builder: (_) => MrVisitScreen(visitId: idOf(v)))),
                trailing: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AppButton(
                      label: 'Approve',
                      compact: true,
                      fullWidth: false,
                      icon: LucideIcons.check,
                      onPressed: () => mrRun(context, () => n.reviewVisit(idOf(v), 'approve'), done: 'Approved'),
                    ),
                    TextButton(
                      onPressed: () => _review(context, 'Send back report', repName(v['profileId']), (d, c) => n.reviewVisit(idOf(v), d, comment: c)),
                      style: TextButton.styleFrom(foregroundColor: AppColors.error),
                      child: const Text('Send back'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],
        if (expenses.isNotEmpty) ...[
          AppSectionTitle('Expenses · ${expenses.length}'),
          for (final e in expenses)
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
                              Flexible(child: Text('${repName(e['profileId'])} · ${expenseCategories[e['category']]?.$1 ?? e['category']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w700, color: AppColors.textStrong))),
                              if (hasReceipt(e)) ...[const SizedBox(width: 6), Icon(LucideIcons.paperclip, size: 13, color: AppColors.textTertiary)],
                            ],
                          ),
                          Text(
                            [if (mrDate(e['expenseDate']) != null) DateFormat('d MMM').format(mrDate(e['expenseDate'])!), if ('${e['description'] ?? ''}'.isNotEmpty) '${e['description']}'].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.sans(fontSize: AppType.caption, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(appRupees(e['amount']), style: AppType.sans(fontSize: AppType.title, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
                        GestureDetector(
                          onTap: () => expenseDetail(context, idOf(e)),
                          child: Text('Review', style: AppType.sans(fontSize: AppType.small, fontWeight: FontWeight.w800, color: accent.color)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
        if (toPay.isNotEmpty) ...[
          const SizedBox(height: 12),
          AppSectionTitle('Approved, to pay · ${appRupees(toPay.fold<num>(0, (a, e) => a + ((e['amount'] as num?) ?? 0)))}'),
          for (final e in toPay)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.all(14),
                onTap: () => expenseDetail(context, idOf(e)),
                child: Row(
                  children: [
                    AppIconBadge(icon: expenseCategories[e['category']]?.$2 ?? LucideIcons.receipt, color: AppColors.success),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${repName(e['profileId'])} · ${expenseCategories[e['category']]?.$1 ?? e['category']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w700, color: AppColors.textStrong)),
                          Text(appRupees(e['amount']), style: AppType.sans(fontSize: AppType.caption, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => markPaid(context, ref, e),
                      child: Text('Mark paid', style: AppType.sans(fontSize: AppType.small, fontWeight: FontWeight.w800, color: accent.color)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  static String _monthName(dynamic month) {
    final d = DateTime.tryParse('$month-01');
    return d == null ? '$month' : DateFormat('MMMM y').format(d);
  }
}

class _People extends ConsumerWidget {
  const _People();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(mrProvider);
    final perf = {
      for (final r in [...listOf(s.analytics['performance']), ...listOf(s.dashboard['teamPerformance'])]) idOf(r['profile']): r,
    };
    final inactive = s.team.where((p) => idOf(p) != s.ownProfileId && p['isActive'] == false).toList();
    final people = s.team.where((p) => idOf(p) != s.ownProfileId && p['isActive'] != false).toList()
      ..sort((a, b) => ((perf[idOf(b)]?['achievementPercent'] as num?) ?? -1).compareTo((perf[idOf(a)]?['achievementPercent'] as num?) ?? -1));
    final totals = mapOf(s.analytics['totals']);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
      children: [
        if (totals.isNotEmpty) ...[
          Row(
            children: [
              Expanded(child: AppMetricTile(label: 'Team calls', value: '${totals['calls'] ?? 0}', icon: LucideIcons.stethoscope, color: ModuleAccent.of(context).color, compact: true)),
              const SizedBox(width: 10),
              Expanded(child: AppMetricTile(label: 'Team orders', value: appRupees(totals['pobAmount'] ?? 0), icon: LucideIcons.shoppingCart, color: AppColors.success, compact: true)),
            ],
          ),
          const SizedBox(height: 14),
        ],
        if (people.isEmpty)
          const AppEmptyState(icon: LucideIcons.users, text: 'No one reports to you yet. Add your team to see their calls and approve their work.')
        else
          for (final p in people)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PersonCard(person: p, perf: perf[idOf(p)] ?? const {}),
            ),
        if (inactive.isNotEmpty) ...[
          const SizedBox(height: 12),
          AppSectionTitle('Inactive · ${inactive.length}'),
          for (final p in inactive)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.all(12),
                onTap: () => editTeamMember(context, p),
                child: Row(
                  children: [
                    MrAvatar(name: '${p['name'] ?? repName(p)}', size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${p['name'] ?? repName(p)} · ${p['employeeCode'] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                      ),
                    ),
                    Text('Reactivate', style: AppType.sans(fontSize: AppType.small, fontWeight: FontWeight.w800, color: ModuleAccent.of(context).color)),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _PersonCard extends ConsumerWidget {
  final Map<String, dynamic> person;
  final Map<String, dynamic> perf;
  const _PersonCard({required this.person, required this.perf});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ModuleAccent.of(context);
    final p = person;
    final name = '${p['name'] ?? repName(p)}';
    final pct = (perf['achievementPercent'] as num?)?.toDouble();
    final target = mapOf(perf['target']);
    return AppCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      onTap: () => showAppSheet<void>(context, builder: (_) => _PersonSheet(person: p, perf: perf)),
      child: Column(
        children: [
          Row(
            children: [
              MrAvatar(name: name, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppType.sans(fontSize: AppType.body + 1, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
                    Text(
                      ['${p['designation'] ?? ''}', '${p['employeeCode'] ?? ''}', '${p['headquarters'] ?? ''}'].where((e) => e.isNotEmpty).join(' · '),
                      style: AppType.sans(fontSize: AppType.caption, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (pct != null)
                Text('${pct.round()}%', style: AppType.sans(fontSize: AppType.figure, fontWeight: FontWeight.w800, color: pct >= 100 ? AppColors.success : pct >= 60 ? accent.color : AppColors.warning)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Fig('Calls', '${perf['calls'] ?? 0}${(target['callTarget'] as num? ?? 0) > 0 ? '/${target['callTarget']}' : ''}'),
              _Fig('Doctors', '${perf['doctorCalls'] ?? 0}'),
              _Fig('Orders', appRupees(perf['pobAmount'] ?? 0)),
              _Fig('Days', '${perf['workingDays'] ?? 0}'),
            ],
          ),
          if (pct != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: (pct / 100).clamp(0, 1), minHeight: 5, backgroundColor: accent.veryLight, color: pct >= 100 ? AppColors.success : accent.color),
            ),
          ],
        ],
      ),
    );
  }
}

class _Fig extends StatelessWidget {
  final String label;
  final String value;
  const _Fig(this.label, this.value);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
        Text(label, style: AppType.sans(fontSize: AppType.micro, color: AppColors.textSecondary)),
      ],
    ),
  );
}

/// A team member: set this month's targets, or hand over samples.
class _PersonSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> person;
  final Map<String, dynamic> perf;
  const _PersonSheet({required this.person, required this.perf});

  @override
  ConsumerState<_PersonSheet> createState() => _PersonSheetState();
}

class _PersonSheetState extends ConsumerState<_PersonSheet> {
  late final target = mapOf(widget.perf['target']);
  late final _calls = TextEditingController(text: _v(target['callTarget']));
  late final _doctors = TextEditingController(text: _v(target['doctorCallTarget']));
  late final _pob = TextEditingController(text: _v(target['pobTarget']));
  late final _days = TextEditingController(text: _v(target['workingDaysTarget']));
  final _product = TextEditingController();
  final _qty = TextEditingController();
  String _itemType = 'sample';
  bool _busy = false;

  static String _v(dynamic n) => n is num && n > 0 ? '${n.toInt()}' : '';

  @override
  void dispose() {
    for (final c in [_calls, _doctors, _pob, _days, _product, _qty]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveTarget() async {
    setState(() => _busy = true);
    final ok = await mrRun(
      context,
      () => ref.read(mrProvider.notifier).setTarget(
        profileId: idOf(widget.person),
        month: monthKey(DateTime.now()),
        callTarget: num.tryParse(_calls.text) ?? 0,
        doctorCallTarget: num.tryParse(_doctors.text) ?? 0,
        pobTarget: num.tryParse(_pob.text) ?? 0,
        workingDaysTarget: num.tryParse(_days.text) ?? 0,
      ),
      done: 'Targets saved',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context);
  }

  Future<void> _issue() async {
    final qty = int.tryParse(_qty.text.trim()) ?? 0;
    if (_product.text.trim().isEmpty || qty <= 0) {
      mrToast(context, 'Enter the product and quantity', error: true);
      return;
    }
    setState(() => _busy = true);
    final ok = await mrRun(
      context,
      () => ref.read(mrProvider.notifier).issueSamples(profileId: idOf(widget.person), productName: _product.text.trim(), quantity: qty, itemType: _itemType),
      done: '${_itemType == 'gift' ? 'Gifts' : 'Samples'} issued',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _product.clear();
      _qty.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = '${widget.person['name'] ?? repName(widget.person)}';
    final phone = '${widget.person['phone'] ?? ''}';
    return MrSheetBody(
      children: [
        MrSheetTitle(name, subtitle: [designationNames['${widget.person['designation']}'] ?? '${widget.person['designation'] ?? ''}', '${widget.person['headquarters'] ?? ''}'].where((e) => e.isNotEmpty).join(' · ')),
        Row(
          children: [
            if (phone.isNotEmpty) ...[
              Expanded(child: AppSecondaryButton(label: 'Call', icon: LucideIcons.phone, onPressed: () => launchUrl(Uri.parse('tel:$phone')))),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: AppSecondaryButton(
                label: 'Work details',
                icon: LucideIcons.pencil,
                onPressed: () {
                  Navigator.pop(context);
                  editTeamMember(context, widget.person);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text('Targets for ${DateFormat('MMMM').format(DateTime.now())}', style: AppType.sans(fontSize: AppType.title, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: AppTextField(label: 'Calls', controller: _calls, isNum: true, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
            const SizedBox(width: 10),
            Expanded(child: AppTextField(label: 'Doctor calls', controller: _doctors, isNum: true, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
          ],
        ),
        Row(
          children: [
            Expanded(child: AppTextField(label: 'Orders ₹', controller: _pob, isNum: true, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
            const SizedBox(width: 10),
            Expanded(child: AppTextField(label: 'Working days', controller: _days, isNum: true, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
          ],
        ),
        AppButton(label: 'Save targets', icon: LucideIcons.target, loading: _busy, onPressed: _saveTarget),
        const SizedBox(height: 22),
        Text('Hand over stock', style: AppType.sans(fontSize: AppType.title, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
        const SizedBox(height: 10),
        Row(
          children: [
            AppFilterChip(label: 'Samples', selected: _itemType == 'sample', onTap: () => setState(() => _itemType = 'sample')),
            const SizedBox(width: 8),
            AppFilterChip(label: 'Gifts', selected: _itemType == 'gift', onTap: () => setState(() => _itemType = 'gift')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(flex: 3, child: AppTextField(label: 'Product', controller: _product, textCapitalization: TextCapitalization.words)),
            const SizedBox(width: 10),
            Expanded(flex: 1, child: AppTextField(label: 'Qty', controller: _qty, isNum: true, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
          ],
        ),
        AppSecondaryButton(label: 'Issue to $name', icon: LucideIcons.packagePlus, onPressed: _busy ? null : _issue),
      ],
    );
  }
}
