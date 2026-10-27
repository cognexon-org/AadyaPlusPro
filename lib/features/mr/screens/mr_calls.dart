import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../providers/mr_provider.dart';
import '../widgets/mr_sheets.dart';
import '../widgets/mr_ui.dart';
import 'mr_visit_screen.dart';

/// The month's calls (daily call reports), by day — with the ones that
/// need something from you first: reports to write, and for a manager,
/// reports to review.
class MrCalls extends ConsumerStatefulWidget {
  const MrCalls({super.key});

  @override
  ConsumerState<MrCalls> createState() => _MrCallsState();
}

class _MrCallsState extends ConsumerState<MrCalls> {
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(mrProvider.notifier).ensureLoaded());
  }

  void _open(Map<String, dynamic> v) => Navigator.of(context).push(AppPageRoute(builder: (_) => MrVisitScreen(visitId: idOf(v))));

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(mrProvider);
    final accent = ModuleAccent.of(context);
    final mine = s.visits.where((v) => s.isMine(v['profileId'])).toList();
    final toReport = mine.where((v) => const {'checked_in', 'completed', 'rejected'}.contains(v['status'])).toList();
    final toReview = s.visits.where((v) => !s.isMine(v['profileId']) && v['status'] == 'submitted').toList();
    final filters = [
      ('all', 'All · ${mine.length}'),
      if (toReport.isNotEmpty) ('report', 'To report · ${toReport.length}'),
      if (s.isManager) ('review', 'To review · ${toReview.length}'),
      ('planned', 'Planned'),
      ('approved', 'Approved'),
    ];
    if (!filters.any((f) => f.$1 == _filter)) _filter = 'all';
    final list = switch (_filter) {
      'report' => toReport,
      'review' => toReview,
      'planned' => mine.where((v) => v['status'] == 'planned').toList(),
      'approved' => mine.where((v) => v['status'] == 'approved').toList(),
      _ => mine,
    }..sort((a, b) => (mrDate(b['visitDate']) ?? DateTime(0)).compareTo(mrDate(a['visitDate']) ?? DateTime(0)));
    final byDay = <String, List<Map<String, dynamic>>>{};
    for (final v in list) {
      final d = mrDate(v['visitDate']);
      byDay.putIfAbsent(d == null ? '' : dayLabel(d), () => []).add(v);
    }
    final completed = (s.metrics['calls'] as num?)?.toInt() ?? 0;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            MrHeader(
              title: 'Calls',
              subtitle: '$completed reported this month${(s.metrics['geofenceExceptions'] as num? ?? 0) > 0 ? ' · ${s.metrics['geofenceExceptions']} away from clinic' : ''}',
              actions: [
                IconButton(tooltip: 'Plan a call', icon: Icon(LucideIcons.calendarPlus, color: accent.color), onPressed: () => planCall(context, ref)),
              ],
            ),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => AppFilterChip(label: filters[i].$2, selected: _filter == filters[i].$1, onTap: () => setState(() => _filter = filters[i].$1)),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                color: accent.color,
                onRefresh: () => ref.read(mrProvider.notifier).loadVisits(),
                child: s.isLoading && !s.hasLoaded
                    ? const AppListSkeleton(count: 5)
                    : list.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          AppEmptyState(
                            icon: _filter == 'review' ? LucideIcons.inbox : LucideIcons.calendarCheck,
                            text: switch (_filter) {
                              'review' => 'No reports waiting for you.',
                              'report' => 'All your calls are reported.',
                              _ => 'No calls this month yet.',
                            },
                            action: _filter == 'all'
                                ? AppButton(label: 'Plan a call', icon: LucideIcons.plus, compact: true, fullWidth: false, onPressed: () => planCall(context, ref))
                                : null,
                          ),
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                        children: [
                          for (final e in byDay.entries) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
                              child: Text('${e.key} · ${e.value.length}', style: AppType.sans(fontSize: AppType.small, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                            ),
                            for (final (i, v) in e.value.indexed)
                              AppEntrance(
                                index: i.clamp(0, 6),
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: MrVisitCard(
                                    visit: v,
                                    showRep: _filter == 'review',
                                    onTap: () => _open(v),
                                    trailing: _filter == 'review'
                                        ? Align(
                                            alignment: Alignment.centerLeft,
                                            child: AppButton(label: 'Review', icon: LucideIcons.clipboardCheck, compact: true, fullWidth: false, onPressed: () => _open(v)),
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: AppFab(label: 'Plan call', icon: LucideIcons.plus, onPressed: () => planCall(context, ref)),
    );
  }
}
