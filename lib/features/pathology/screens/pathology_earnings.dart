import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/earnings_widgets.dart';
import '../providers/lab_providers.dart';
import '../widgets/lab_ui.dart';
import 'pathology_order_detail.dart';

const _ranges = [
  ('7d', '7 days'),
  ('30d', '30 days'),
  ('month', 'This month'),
  ('year', '12 months'),
];

/// The lab's Earnings tab: what paid orders brought in over a range, after
/// the platform fee, as a chart, a few tiles, the best-selling tests and the
/// latest payments. Reads GET /diagnostics/merchant/earnings.
class PathologyEarnings extends ConsumerStatefulWidget {
  const PathologyEarnings({super.key});

  @override
  ConsumerState<PathologyEarnings> createState() => _PathologyEarningsState();
}

class _PathologyEarningsState extends ConsumerState<PathologyEarnings> {
  String _range = '30d';

  /// The last range that loaded, shown (dimmed) while a new range loads, so
  /// switching a chip never flashes an empty screen.
  Map<String, dynamic>? _last;

  Future<void> _refresh() async {
    ref.invalidate(labEarningsProvider(_range));
    try {
      await ref.read(labEarningsProvider(_range).future);
    } catch (_) {
      // Shown by the error banner.
    }
  }

  void _openOrder(Map<String, dynamic> row) {
    final id = '${row['_id'] ?? ''}';
    if (id.isEmpty) return;
    Navigator.of(
      context,
    ).push(AppPageRoute(builder: (_) => PathologyOrderDetail(orderId: id)));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(labEarningsProvider(_range));
    final accent = ModuleAccent.of(context).color;
    final data = async.valueOrNull;
    if (data != null) _last = data;
    final shown = data ?? _last;
    final switching = data == null && _last != null && async.isLoading;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: accent,
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              const AppScreenHeader(
                title: 'Earnings',
                subtitle: 'Paid orders and payouts',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (var i = 0; i < _ranges.length; i++) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: AppFilterChip(
                        label: _ranges[i].$2,
                        selected: _range == _ranges[i].$1,
                        block: true,
                        onTap: () => setState(() => _range = _ranges[i].$1),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              if (async.hasError && data == null)
                AppErrorBanner(
                  message: labError(
                    async.error!,
                    fallback: 'Couldn’t load your earnings.',
                  ),
                  onRetry: _refresh,
                )
              else if (shown == null)
                const AppDetailSkeleton(rows: 7)
              else
                AnimatedOpacity(
                  opacity: switching ? 0.45 : 1,
                  duration: AppMotion.fast,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _body(shown),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(Map<String, dynamic> d) {
    final totals = _m(d['totals']);
    final rate = num.tryParse('${d['commissionRate'] ?? ''}');
    final series = _l(d['series']);
    final top = _l(d['topTests']);
    final recent = _l(d['recent']);
    return [
      AppEntrance(child: _hero(totals, rate, series, '${d['by'] ?? 'day'}')),
      const SizedBox(height: 12),
      AppEntrance(index: 1, child: _tiles(totals)),
      const SizedBox(height: 12),
      Text(
        rate == null
            ? 'Aadya Plus keeps a platform fee on each paid order; the rest is paid out to you.'
            : 'Aadya Plus keeps ${formatRate(rate)} of each paid order; the rest is paid out to you.',
        style: AppType.sans(
          fontSize: AppType.caption,
          color: AppColors.textTertiary,
          height: 1.45,
        ),
      ),
      const SizedBox(height: 26),
      AppEntrance(index: 2, child: _topTests(top)),
      const SizedBox(height: 26),
      AppEntrance(index: 3, child: _recent(recent)),
    ];
  }

  // ─────────────────────────── Hero ───────────────────────────

  Widget _hero(
    Map<String, dynamic> totals,
    num? rate,
    List<Map<String, dynamic>> series,
    String by,
  ) {
    final net = _n(totals['net']);
    final gross = _n(totals['gross']);
    final fee = _n(totals['commission']);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your earnings',
            style: AppType.sans(
              fontSize: AppType.caption,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AppCountUp(
              value: net,
              format: appRupees,
              style: AppType.number(
                fontSize: AppType.display,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.2,
                height: 1.05,
                color: AppColors.textStrong,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${appRupees(gross)} collected · ${appRupees(fee)} platform fee'
            '${rate == null ? '' : ' (${formatRate(rate)})'}',
            style: AppType.sans(
              fontSize: AppType.caption,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          _chart(series, by),
        ],
      ),
    );
  }

  Widget _chart(List<Map<String, dynamic>> series, String by) {
    final accent = ModuleAccent.of(context);
    if (series.isEmpty) return const SizedBox.shrink();
    final maxV = series.fold<num>(0, (a, s) => math.max(a, _n(s['net'])));
    final top = maxV <= 0 ? 1.0 : maxV * 1.15;
    final n = series.length;
    final barWidth = n <= 7 ? 18.0 : (n <= 12 ? 14.0 : 5.0);
    // Label every bar when there are few, else about five evenly spaced.
    final step = n <= 12 ? 1 : (n / 5).ceil();

    String label(int i) {
      final key = '${series[i]['key'] ?? ''}';
      final d = DateTime.tryParse(by == 'month' ? '$key-01' : key);
      if (d == null) return '';
      if (by == 'month') return DateFormat('MMM').format(d);
      if (n <= 7) return DateFormat('E').format(d);
      return DateFormat('d MMM').format(d);
    }

    return SizedBox(
      height: 132,
      child: BarChart(
        BarChartData(
          maxY: top.toDouble(),
          alignment: BarChartAlignment.spaceAround,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppColors.textStrong,
              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 5,
              ),
              getTooltipItem: (group, _, rod, _) {
                final s = series[group.x];
                final orders = _n(s['orders']).toInt();
                return BarTooltipItem(
                  '${label(group.x)}\n${appRupees(_n(s['net']))} · $orders ${orders == 1 ? 'order' : 'orders'}',
                  AppType.sans(
                    fontSize: AppType.micro,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  final last = i == n - 1;
                  if (i < 0 || i >= n || (!last && i % step != 0)) {
                    return const SizedBox.shrink();
                  }
                  // Skip a label that would crowd the last one.
                  if (!last && n > 12 && n - 1 - i < step / 2) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      label(i),
                      style: AppType.sans(
                        fontSize: AppType.micro,
                        fontWeight: last ? FontWeight.w700 : FontWeight.w500,
                        color: last ? accent.color : AppColors.textTertiary,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var x = 0; x < n; x++)
              BarChartGroupData(
                x: x,
                barRods: [
                  BarChartRodData(
                    toY: _n(series[x]['net']).toDouble(),
                    width: barWidth,
                    color: x == n - 1 ? accent.color : accent.light,
                    borderRadius: BorderRadius.circular(n > 12 ? 2 : 5),
                    backDrawRodData: BackgroundBarChartRodData(
                      show: true,
                      toY: top.toDouble(),
                      color: AppColors.bg,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────── Tiles ───────────────────────────

  Widget _tiles(Map<String, dynamic> t) {
    final unpaid = _n(t['unpaidAmount']);
    final unpaidOrders = _n(t['unpaidOrders']).toInt();
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: EarningsTile(
                label: 'Paid orders',
                value: '${_n(t['orders']).toInt()}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: EarningsTile(
                label: 'Home collection fees',
                value: appRupees(_n(t['collectionCharges'])),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: EarningsTile(
                label: 'Paid online',
                value: appRupees(_n(t['online'])),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: EarningsTile(
                label: 'Paid at the lab',
                value: appRupees(_n(t['offline'])),
              ),
            ),
          ],
        ),
        if (unpaid > 0) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.wallet,
                  size: 17,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$unpaidOrders ${unpaidOrders == 1 ? 'order is' : 'orders are'} still unpaid',
                    style: AppType.sans(
                      fontSize: AppType.small,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  appRupees(unpaid),
                  style: AppType.number(
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w700,
                    color: AppColors.warning,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ─────────────────────────── Top tests ───────────────────────────

  Widget _topTests(List<Map<String, dynamic>> top) {
    final accent = ModuleAccent.of(context).color;
    final maxCount = top.fold<num>(0, (a, t) => math.max(a, _n(t['count'])));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionTitle('Top tests'),
        if (top.isEmpty)
          const AppEmptyState(
            icon: LucideIcons.flaskConical,
            text: 'Your most booked tests appear here.',
          )
        else
          AppGroup(
            children: [
              for (var i = 0; i < top.length; i++) ...[
                if (i > 0) const AppHairline(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${top[i]['name'] ?? 'Test'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.sans(
                                fontSize: AppType.body,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_n(top[i]['count']).toInt()} × · ${appRupees(_n(top[i]['revenue']))}',
                            style: AppType.sans(
                              fontSize: AppType.caption,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: maxCount > 0
                              ? (_n(top[i]['count']) / maxCount).toDouble()
                              : 0,
                          minHeight: 4,
                          color: accent,
                          backgroundColor: AppColors.bg,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }

  // ─────────────────────────── Recent ───────────────────────────

  Widget _recent(List<Map<String, dynamic>> rows) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final d = DateTime.tryParse('${r['paidAt'] ?? ''}')?.toLocal();
      groups.putIfAbsent(dayLabel(d), () => []).add(r);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionTitle('Recent payments'),
        if (rows.isEmpty)
          const AppEmptyState(
            icon: LucideIcons.wallet,
            text: 'Payments appear here once orders are paid.',
          )
        else
          for (final g in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 6, 0, 6),
              child: Text(
                g.key,
                style: AppType.sans(
                  fontSize: AppType.caption,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
            AppGroup(
              children: [
                for (var i = 0; i < g.value.length; i++) ...[
                  if (i > 0) const AppHairline(),
                  _paymentRow(g.value[i]),
                ],
              ],
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  Widget _paymentRow(Map<String, dynamic> r) {
    final method = '${r['method'] ?? 'online'}';
    final (icon, methodLabel) = switch (method) {
      'cash' => (LucideIcons.banknote, 'Cash'),
      'card' => (LucideIcons.creditCard, 'Card'),
      'upi' => (LucideIcons.smartphone, 'UPI'),
      _ => (LucideIcons.globe, 'Online'),
    };
    final home = r['type'] == 'home_collection';
    return AppPressable(
      scale: 0.985,
      onTap: () => _openOrder(r),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 16, color: AppColors.textHeading),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${r['patientName'] ?? 'Patient'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.sans(
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    [
                      '${r['labTestNumber'] ?? ''}',
                      methodLabel,
                      if (home) 'Home',
                    ].where((e) => e.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  appRupees(_n(r['net'])),
                  style: AppType.number(
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textStrong,
                  ),
                ),
                Text(
                  'of ${appRupees(_n(r['amount']))}',
                  style: AppType.sans(
                    fontSize: AppType.micro,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static num _n(dynamic v) => num.tryParse('${v ?? 0}') ?? 0;
  static Map<String, dynamic> _m(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : const {};
  static List<Map<String, dynamic>> _l(dynamic v) => (v is List ? v : const [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}
