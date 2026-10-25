import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../pharmacy/widgets/pharmacy_barcode_scanner.dart';
import '../providers/lab_providers.dart';
import '../widgets/lab_ui.dart';
import 'pathology_order_detail.dart';

/// The filters on Orders. Today's tiles set this before switching tabs, so
/// "3 ready to release" lands on exactly those three.
enum LabOrderFilter { open, collect, home, processing, reports, overdue, completed, cancelled }

final labOrderFilterProvider = StateProvider<LabOrderFilter>(
  (ref) => LabOrderFilter.open,
);

/// The Orders tab: every booking, filtered by where it is in the lab's day.
/// Filtering and search run on the loaded list, so a chip switches instantly.
class PathologyOrders extends ConsumerStatefulWidget {
  const PathologyOrders({super.key});

  @override
  ConsumerState<PathologyOrders> createState() => _PathologyOrdersState();
}

class _PathologyOrdersState extends ConsumerState<PathologyOrders> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(labOrdersProvider.notifier).ensureLoaded());
    _search.addListener(() {
      final q = _search.text.trim().toLowerCase();
      if (q != _q) setState(() => _q = q);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(LabOrderFilter f, Map<String, dynamic> o) {
    final stage = labStage(o);
    return switch (f) {
      LabOrderFilter.open =>
        stage != LabStage.completed && stage != LabStage.cancelled,
      LabOrderFilter.collect => stage == LabStage.collect,
      LabOrderFilter.home => stage == LabStage.collect && labIsHome(o),
      LabOrderFilter.processing => stage == LabStage.processing,
      LabOrderFilter.reports => stage == LabStage.reports,
      LabOrderFilter.overdue => labOverdue(o),
      LabOrderFilter.completed => stage == LabStage.completed,
      LabOrderFilter.cancelled => stage == LabStage.cancelled,
    };
  }

  bool _searchHit(Map<String, dynamic> o) {
    if (_q.isEmpty) return true;
    final p = labPatient(o);
    final barcode = o['sample'] is Map ? '${(o['sample'] as Map)['barcode'] ?? ''}' : '';
    return [
      labPatientName(o),
      '${p['phone'] ?? ''}',
      labNumber(o),
      barcode,
      labTestSummary(o, show: 99),
    ].any((s) => s.toLowerCase().contains(_q));
  }

  String _label(LabOrderFilter f) => switch (f) {
    LabOrderFilter.open => 'Open',
    LabOrderFilter.collect => 'To collect',
    LabOrderFilter.home => 'Home',
    LabOrderFilter.processing => 'In process',
    LabOrderFilter.reports => 'Ready to release',
    LabOrderFilter.overdue => 'Overdue',
    LabOrderFilter.completed => 'Completed',
    LabOrderFilter.cancelled => 'Cancelled',
  };

  /// Scan a tube label to find its order.
  Future<void> _scan() async {
    final code = await scanPharmacyBarcode(
      context,
      hint: 'Scan the label on the sample tube',
    );
    if (code == null || !mounted) return;
    ref.read(labOrderFilterProvider.notifier).state = LabOrderFilter.open;
    _search.text = code;
    final hits = ref
        .read(labOrdersProvider)
        .all
        .where((o) => o['sample'] is Map && '${(o['sample'] as Map)['barcode']}' == code)
        .toList();
    if (hits.length == 1) _open(hits.first);
  }

  void _open(Map<String, dynamic> o) => Navigator.of(context).push(
    AppPageRoute(
      builder: (_) => PathologyOrderDetail(orderId: '${o['_id']}', order: o),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(labOrdersProvider);
    final filter = ref.watch(labOrderFilterProvider);
    final accent = ModuleAccent.of(context).color;
    final counts = {
      for (final f in LabOrderFilter.values)
        f: state.all.where((o) => _matches(f, o)).length,
    };
    final shown = state.all
        .where((o) => _matches(filter, o) && _searchHit(o))
        .toList();
    final past = filter == LabOrderFilter.completed ||
        filter == LabOrderFilter.cancelled;
    // Open work soonest first; finished work newest first.
    shown.sort((a, b) {
      final da = labSlot(a) ?? DateTime(2000);
      final db = labSlot(b) ?? DateTime(2000);
      return past ? db.compareTo(da) : da.compareTo(db);
    });

    final chips = [
      for (final f in LabOrderFilter.values)
        if (f != LabOrderFilter.overdue || counts[f]! > 0) f,
    ];

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: AppScreenHeader(
                title: 'Orders',
                subtitle: state.hasLoaded
                    ? '${counts[LabOrderFilter.open]} open · ${counts[LabOrderFilter.reports]} ready to release'
                    : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppSearchField(
                controller: _search,
                hint: 'Patient, phone, report no. or barcode',
                onScan: _scan,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: chips.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final f = chips[i];
                  final n = counts[f]!;
                  final showCount = f != LabOrderFilter.completed &&
                      f != LabOrderFilter.cancelled &&
                      n > 0;
                  return AppFilterChip(
                    label: showCount ? '${_label(f)} · $n' : _label(f),
                    selected: filter == f,
                    onTap: () =>
                        ref.read(labOrderFilterProvider.notifier).state = f,
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: RefreshIndicator(
                color: accent,
                onRefresh: () =>
                    ref.read(labOrdersProvider.notifier).load(silent: true),
                child: _body(state, shown, filter, past),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(
    LabOrdersState state,
    List<Map<String, dynamic>> shown,
    LabOrderFilter filter,
    bool past,
  ) {
    if (state.error != null && !state.hasLoaded) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppErrorBanner(
            message: state.error!,
            onRetry: () => ref.read(labOrdersProvider.notifier).load(),
          ),
        ],
      );
    }
    if (!state.hasLoaded) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [AppListSkeleton(count: 6)],
      );
    }
    if (shown.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
        children: [
          AppEmptyState(
            icon: _q.isNotEmpty ? LucideIcons.searchX : LucideIcons.flaskConical,
            text: _q.isNotEmpty
                ? 'No orders match “${_search.text.trim()}”.'
                : switch (filter) {
                    LabOrderFilter.open => 'Nothing open. New bookings will show up here.',
                    LabOrderFilter.collect => 'No samples waiting to be collected.',
                    LabOrderFilter.home => 'No home collections waiting.',
                    LabOrderFilter.processing => 'Nothing in process.',
                    LabOrderFilter.reports => 'No reports waiting to be released.',
                    LabOrderFilter.overdue => 'Nothing overdue.',
                    LabOrderFilter.completed => 'No completed orders yet.',
                    LabOrderFilter.cancelled => 'No cancelled orders.',
                  },
          ),
        ],
      );
    }

    // Grouped by day, like a diary.
    final rows = <Widget>[];
    String? lastDay;
    var i = 0;
    for (final o in shown) {
      final day = dayLabel(labSlot(o));
      if (day != lastDay) {
        rows.add(
          Padding(
            padding: EdgeInsets.fromLTRB(2, rows.isEmpty ? 4 : 14, 2, 8),
            child: Text(
              day,
              style: AppType.sans(
                fontSize: AppType.small,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        );
        lastDay = day;
      }
      rows.add(
        AppEntrance(
          index: i++ < 10 ? i : 10,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: LabOrderCard(order: o, onTap: () => _open(o)),
          ),
        ),
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: rows,
    );
  }
}
