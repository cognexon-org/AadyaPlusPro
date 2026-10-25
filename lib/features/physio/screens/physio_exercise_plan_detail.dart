import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/doctor_ui.dart'
    show doctorError, dayLabel, timeLabel;
import '../../doctor/widgets/prescription_ui.dart' show rxAppBar, RxBottomBar;
import '../providers/physio_exercise_provider.dart';
import '../widgets/exercise_charts.dart';
import '../widgets/exercise_log_sheet.dart';
import '../widgets/exercise_ui.dart';
import 'physio_exercise_plan_editor.dart';

/// One exercise plan: how well the patient is keeping to it, how their
/// pain is moving, every logged session, and the plan's actions.
class PhysioExercisePlanDetail extends ConsumerStatefulWidget {
  final String planId;
  const PhysioExercisePlanDetail({super.key, required this.planId});

  @override
  ConsumerState<PhysioExercisePlanDetail> createState() =>
      _PhysioExercisePlanDetailState();
}

class _PhysioExercisePlanDetailState
    extends ConsumerState<PhysioExercisePlanDetail> {
  bool _allLogs = false;
  String? _busy; // 'complete' | 'cancel'

  PhysioAdherenceQuery get _adherenceQuery =>
      (planId: widget.planId, lastDays: null);

  Future<void> _refresh() async {
    ref.invalidate(physioPlanAdherenceProvider(_adherenceQuery));
    try {
      ref.invalidate(physioPlanDetailProvider(widget.planId));
      await ref.read(physioPlanDetailProvider(widget.planId).future);
    } catch (_) {
      // Shown by the error banner.
    }
  }

  Future<void> _edit(PhysioPlanDetail d) => Navigator.of(context).push<bool>(
    AppPageRoute(
      builder: (_) => PhysioExercisePlanEditor(
        patientId: d.patientId,
        patientName: '${d.patient['name'] ?? ''}',
        planId: widget.planId,
      ),
    ),
  );

  Future<void> _log(PhysioPlanDetail d) async {
    final n = await showExerciseLogSheet(
      context,
      planId: widget.planId,
      items: d.items,
    );
    if (n != null && n > 0 && mounted) {
      _toast('Logged $n exercise${n == 1 ? '' : 's'} from today’s session.');
    }
  }

  Future<void> _complete() async {
    final ok = await AppModal.confirm(
      context,
      title: 'Mark this plan completed?',
      message:
          'The patient keeps it in their history but stops logging against it.',
      icon: LucideIcons.circleCheck,
      confirmLabel: 'Mark completed',
      destructive: false,
    );
    if (!ok || !mounted) return;
    await _run('complete', () async {
      await ref.read(physioExercisePlanActionsProvider).complete(widget.planId);
      if (mounted) _toast('Plan marked completed.');
    });
  }

  Future<void> _cancel() async {
    final ok = await AppModal.confirm(
      context,
      title: 'Cancel this plan?',
      message:
          'The patient will no longer see it as an active programme. Logged sessions stay on record.',
      icon: LucideIcons.ban,
      confirmLabel: 'Cancel plan',
      cancelLabel: 'Keep plan',
    );
    if (!ok || !mounted) return;
    await _run('cancel', () async {
      await ref.read(physioExercisePlanActionsProvider).cancel(widget.planId);
      if (mounted) _toast('Plan cancelled.');
    });
  }

  Future<void> _run(String what, Future<void> Function() action) async {
    setState(() => _busy = what);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        showAppError(
          context,
          null,
          fallback: doctorError(e, fallback: 'Couldn’t update the plan.'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.textStrong,
      content: Text(
        text,
        style: AppType.sans(fontSize: AppType.caption, color: Colors.white),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(physioPlanDetailProvider(widget.planId));
    final adherence = ref.watch(physioPlanAdherenceProvider(_adherenceQuery));
    final d = async.valueOrNull;
    final name = '${d?.patient['name'] ?? ''}'.trim();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: rxAppBar(
        context,
        title: 'Exercise plan',
        subtitle: name.isEmpty ? null : name,
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              color: ModuleAccent.of(context).color,
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                children: [
                  if (async.hasError && d == null)
                    AppErrorBanner(message: '${async.error}', onRetry: _refresh)
                  else if (d == null)
                    const AppDetailSkeleton(rows: 7)
                  else
                    ..._content(d, adherence),
                ],
              ),
            ),
          ),
          if (d != null && d.isActive)
            RxBottomBar(
              child: Row(
                children: [
                  Expanded(
                    child: AppSecondaryButton(
                      label: 'Edit plan',
                      icon: LucideIcons.squarePen,
                      onPressed: _busy != null ? null : () => _edit(d),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppButton(
                      label: 'Log session',
                      icon: LucideIcons.clipboardCheck,
                      onPressed: _busy != null || d.items.isEmpty
                          ? null
                          : () => _log(d),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _content(
    PhysioPlanDetail d,
    AsyncValue<Map<String, dynamic>> adherence,
  ) {
    const gap = SizedBox(height: 24);
    final adh = adherence.valueOrNull ?? const <String, dynamic>{};
    final itemStats = {
      for (final i in exMaps(adh['items'])) '${i['planItemId'] ?? ''}': i,
    };
    final pain = painTrend(d.progress);
    final logs = d.progress;
    final shown = _allLogs ? logs : logs.take(6).toList();
    var i = 0;
    Widget enter(Widget child) => AppEntrance(index: i++, child: child);
    return [
      enter(_Header(detail: d)),
      gap,
      enter(const AppSectionTitle('Adherence')),
      enter(
        _AdherenceCard(
          detail: d,
          adherence: adherence,
          onRetry: () =>
              ref.invalidate(physioPlanAdherenceProvider(_adherenceQuery)),
        ),
      ),
      gap,
      enter(AppSectionTitle('Exercises (${d.items.length})')),
      enter(
        AppGroup(
          children: [
            for (final (n, item) in d.items.indexed) ...[
              if (n > 0) const AppHairline(),
              _ItemRow(
                key: ValueKey('item-${item['_id']}'),
                item: item,
                stats: itemStats['${item['_id'] ?? ''}'],
              ),
            ],
          ],
        ),
      ),
      gap,
      enter(const AppSectionTitle('Pain')),
      enter(_PainCard(points: pain)),
      gap,
      enter(
        AppSectionTitle(
          logs.isEmpty ? 'Logged sessions' : 'Logged sessions (${logs.length})',
          action: logs.length > 6
              ? (_allLogs ? 'Show fewer' : 'Show all')
              : null,
          onAction: () => setState(() => _allLogs = !_allLogs),
        ),
      ),
      if (logs.isEmpty)
        enter(
          AppEmptyState(
            icon: LucideIcons.clipboardList,
            text: d.isActive
                ? 'Nothing logged yet.\nThe patient logs from their app; log in-clinic work with Log session.'
                : 'Nothing was logged against this plan.',
          ),
        )
      else
        enter(
          AppGroup(
            children: [
              for (final (n, log) in shown.indexed) ...[
                if (n > 0) const AppHairline(),
                _LogRow(key: ValueKey('log-${log['_id'] ?? n}'), log: log),
              ],
            ],
          ),
        ),
      if (d.isActive) ...[
        gap,
        enter(const AppSectionTitle('Plan')),
        enter(
          AppGroup(
            children: [
              _ActionRow(
                icon: LucideIcons.circleCheck,
                label: 'Mark completed',
                subtitle: 'The programme has done its job',
                busy: _busy == 'complete',
                onTap: _busy != null ? null : _complete,
              ),
              const AppHairline(),
              _ActionRow(
                icon: LucideIcons.ban,
                label: 'Cancel plan',
                subtitle: 'Stop it without marking it done',
                destructive: true,
                busy: _busy == 'cancel',
                onTap: _busy != null ? null : _cancel,
              ),
            ],
          ),
        ),
      ],
    ];
  }
}

// ════════════════════════════════ Header ════════════════════════════════

class _Header extends StatelessWidget {
  final PhysioPlanDetail detail;
  const _Header({required this.detail});

  @override
  Widget build(BuildContext context) {
    final p = detail.plan;
    final title = '${p['title'] ?? ''}'.trim();
    final start = exDate(p['startDate']);
    final end = exDate(p['endDate']);
    final goals = exStrings(p['goals']);
    final instructions = '${p['instructions'] ?? ''}'.trim();
    final fmt = DateFormat('d MMM');
    String? week;
    if (start != null && detail.isActive) {
      final now = DateTime.now();
      final w = now.difference(start).inDays ~/ 7 + 1;
      if (!now.isBefore(start)) {
        week = end == null
            ? 'Week $w'
            : 'Week $w of ${(end.difference(start).inDays / 7).ceil().clamp(1, 520)}';
      }
    }
    final dates = [
      if (start != null)
        end == null
            ? 'From ${fmt.format(start)}'
            : '${fmt.format(start)} – ${fmt.format(end)}',
      ?week,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title.isEmpty ? 'Exercise plan' : title,
                  style: AppType.sans(
                    fontSize: AppType.heading,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textStrong,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: PlanStatusTag(detail.status),
              ),
            ],
          ),
          if (dates.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  LucideIcons.calendarDays,
                  size: 13,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    dates,
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (goals.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final g in goals)
                  ExerciseTag(g, icon: LucideIcons.target, accent: true),
              ],
            ),
          ],
          if (instructions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              instructions,
              style: AppType.sans(
                fontSize: AppType.small,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════ Adherence ══════════════════════════════

class _AdherenceCard extends StatelessWidget {
  final PhysioPlanDetail detail;
  final AsyncValue<Map<String, dynamic>> adherence;
  final VoidCallback onRetry;
  const _AdherenceCard({
    required this.detail,
    required this.adherence,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final adh = adherence.valueOrNull;
    final overall = exMap(adh?['overall']);
    final percent = exInt(overall['compliancePercent']) ?? 0;
    final done = exInt(overall['completedSessions']) ?? 0;
    final due = exInt(overall['prescribedSessions']) ?? 0;
    final before = overall['averagePainBefore'];
    final after = overall['averagePainAfter'];
    final last = exDate(overall['lastLoggedAt']);
    final week = ExerciseWeekBars.fromLogs(detail.progress);
    final weekTotal = week.fold<int>(0, (s, v) => s + v);
    final target = planWeeklyTarget(detail.plan);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (adh == null && adherence.hasError)
            AppErrorBanner(message: '${adherence.error}', onRetry: onRetry)
          else if (adh == null)
            const SizedBox(
              height: 92,
              child: Center(child: AppSkeletonBlock(width: 92, height: 92)),
            )
          else
            Row(
              children: [
                ExerciseAdherenceRing(percent: percent),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Stat(
                        label: 'Sessions done',
                        value: due == 0 ? '—' : '$done of $due',
                      ),
                      const SizedBox(height: 8),
                      _Stat(
                        label: 'Average pain',
                        value: before is num || after is num
                            ? '${before is num ? before : '–'} → ${after is num ? after : '–'}'
                            : 'Not recorded',
                        warn: after is num && after >= 7,
                      ),
                      const SizedBox(height: 8),
                      _Stat(
                        label: 'Last logged',
                        value: last == null
                            ? 'Never'
                            : '${dayLabel(last)}, ${timeLabel(last)}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'Last 7 days',
                style: AppType.sans(
                  fontSize: AppType.caption,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                target > 0
                    ? '$weekTotal of ${target.round()} this week'
                    : '$weekTotal logged',
                style: AppType.sans(
                  fontSize: AppType.caption,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ExerciseWeekBars(days: week, dailyTarget: target / 7),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final bool warn;
  const _Stat({required this.label, required this.value, this.warn = false});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: AppType.sans(
          fontSize: AppType.micro,
          color: AppColors.textTertiary,
        ),
      ),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppType.sans(
          fontSize: AppType.body,
          fontWeight: FontWeight.w700,
          color: warn ? AppColors.warning : AppColors.textStrong,
        ),
      ),
    ],
  );
}

// ═══════════════════════════════ Exercises ═══════════════════════════════

class _ItemRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final Map<String, dynamic>? stats;
  const _ItemRow({super.key, required this.item, this.stats});

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    final ex = planItemExercise(item);
    final notes = '${item['notes'] ?? ''}'.trim();
    final pct = exInt(stats?['compliancePercent']);
    final done = exInt(stats?['completedSessions']) ?? 0;
    final due = exInt(stats?['prescribedSessions']) ?? 0;
    final low = pct != null && pct < 50;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExerciseThumb(exercise: ex, size: 44, radius: 10),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ex.isEmpty ? 'Archived exercise' : exName(ex),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.sans(
                          fontSize: AppType.body,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textStrong,
                        ),
                      ),
                    ),
                    if (pct != null)
                      Text(
                        '$pct%',
                        style: AppType.number(
                          fontSize: AppType.body,
                          fontWeight: FontWeight.w700,
                          color: low ? AppColors.warning : accent.color,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  planItemDosing(item),
                  style: AppType.sans(
                    fontSize: AppType.caption,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    notes,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
                if (pct != null) ...[
                  const SizedBox(height: 8),
                  ExerciseProgressBar(
                    fraction: pct / 100,
                    color: low ? AppColors.warning : accent.color,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$done of $due sessions',
                    style: AppType.sans(
                      fontSize: AppType.micro,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════ Pain ═════════════════════════════════

class _PainCard extends StatelessWidget {
  final List<PainPoint> points;
  const _PainCard({required this.points});

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    if (points.length < 2) {
      return AppEmptyState(
        icon: LucideIcons.activity,
        text: points.isEmpty
            ? 'No pain scores yet.\nThe trend appears once sessions are logged with pain before and after.'
            : 'One day of pain scores so far. The trend appears after the next.',
      );
    }
    Widget key(Color c, String label, {bool dashed = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: dashed ? 2 : 3,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: AppType.sans(
            fontSize: AppType.micro,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
    final first = points.firstWhere(
      (p) => p.after != null,
      orElse: () => points.first,
    );
    final latest = points.lastWhere(
      (p) => p.after != null,
      orElse: () => points.last,
    );
    final change = first.after != null && latest.after != null
        ? latest.after! - first.after!
        : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Row(
              children: [
                key(accent.color, 'After'),
                const SizedBox(width: 14),
                key(AppColors.textTertiary, 'Before', dashed: true),
                const Spacer(),
                if (change != null)
                  Text(
                    change == 0
                        ? 'No change'
                        : '${change < 0 ? 'Down' : 'Up'} ${change.abs().toStringAsFixed(1)} since ${DateFormat('d MMM').format(first.day)}',
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      fontWeight: FontWeight.w600,
                      color: change > 0
                          ? AppColors.warning
                          : AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ExercisePainChart(points: points),
        ],
      ),
    );
  }
}

// ═════════════════════════════════ Logs ═════════════════════════════════

class _LogRow extends StatelessWidget {
  final Map<String, dynamic> log;
  const _LogRow({super.key, required this.log});

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    final ex = exMap(log['exerciseId']);
    final at = exDate(log['performedAt']);
    final done = log['completed'] != false;
    final byPhysio = '${log['loggedBy']}' == 'physio';
    final sets = exInt(log['setsCompleted']) ?? 0;
    final reps = exInt(log['repsCompleted']) ?? 0;
    final dur = exInt(log['durationSec']) ?? 0;
    final b = log['painBefore'];
    final a = log['painAfter'];
    final notes = '${log['notes'] ?? ''}'.trim();
    final line = [
      if (sets > 0 && reps > 0) '$sets × $reps' else if (reps > 0) '$reps reps',
      if (dur > 0) exSeconds(dur),
      if (b is num || a is num)
        'pain ${b is num ? b : '–'} → ${a is num ? a : '–'}',
      switch ('${log['perceivedDifficulty'] ?? ''}') {
        'easy' => 'felt easy',
        'about_right' => 'felt about right',
        'hard' => 'felt hard',
        _ => '',
      },
    ].where((e) => e.isNotEmpty).join(' · ');
    final highPain = a is num && a >= 8;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: done ? accent.veryLight : AppColors.bg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              done ? LucideIcons.check : LucideIcons.x,
              size: 14,
              color: done ? accent.color : AppColors.textTertiary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        ex.isEmpty ? 'Exercise' : exName(ex),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.sans(
                          fontSize: AppType.body,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textStrong,
                        ),
                      ),
                    ),
                    Text(
                      at == null ? '' : '${dayLabel(at)}, ${timeLabel(at)}',
                      style: AppType.sans(
                        fontSize: AppType.micro,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    byPhysio ? 'In clinic' : 'At home',
                    if (!done) 'skipped',
                    if (line.isNotEmpty) line,
                  ].join(' · '),
                  style: AppType.sans(
                    fontSize: AppType.caption,
                    color: highPain ? AppColors.error : AppColors.textSecondary,
                  ),
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    notes,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool destructive;
  final bool busy;
  final VoidCallback? onTap;
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.destructive = false,
    this.busy = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? AppColors.error
        : ModuleAccent.of(context).color;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppType.sans(
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w600,
                      color: destructive
                          ? AppColors.error
                          : AppColors.textStrong,
                    ),
                  ),
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
            if (busy)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              const Icon(
                LucideIcons.chevronRight,
                size: 16,
                color: AppColors.textTertiary,
              ),
          ],
        ),
      ),
    );
  }
}
