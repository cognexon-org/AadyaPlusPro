import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/network/api_service.dart';
import '../providers/pharmacy_store_provider.dart';
import '../theme/pharmacy_colors.dart';
import '../theme/pharmacy_type.dart';
import '../widgets/pharmacy_ui.dart';

/// Earnings, in the module's minimal style: one large figure (net sales),
/// a quiet seven-day line, then grouped rows — what Aadya Plus owes the
/// branch, the branch's own profit and loss, and what its stock is worth.
class PharmacyEarnings extends ConsumerStatefulWidget {
  const PharmacyEarnings({super.key});
  @override
  ConsumerState<PharmacyEarnings> createState() => _PharmacyEarningsState();
}

class _PharmacyEarningsState extends ConsumerState<PharmacyEarnings> {
  bool _loading = false;
  Map<String, dynamic> _pnl = {};
  Map<String, dynamic> _valuation = {};

  /// What Aadya Plus owes this branch for delivered online orders. Distinct
  /// from _pnl, which is the branch's own trading position — a pharmacy can
  /// be profitable and still be owed a month of settlements.
  Map<String, dynamic> _settlement = {};
  List<Map<String, dynamic>> _dailyReport = [];
  String? _loadedStoreId;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await ref.read(pharmacyStoreProvider.notifier).initialize();
      // Marked before the requests, not after: build() reloads whenever this
      // differs from the selected branch, so setting it only on success made
      // a failing endpoint retry (and toast) forever.
      _loadedStoreId = ref.read(pharmacyStoreProvider).selectedStoreId;
      final results = await Future.wait([
        ApiService().getPharmacyProfitLoss(),
        ApiService().getInventoryValuation(),
        ApiService().getPharmacySalesReport(queryParams: {'groupBy': 'day'}),
        ApiService().getMerchantSettlement(),
      ]);
      if (!mounted) return;
      final reportData = results[2].data;
      final report =
          (reportData is Map ? reportData['report'] : null) as List? ??
          const [];
      setState(() {
        _pnl = _map(results[0].data);
        _valuation = _map(results[1].data);
        _settlement = _map(results[3].data);
        _dailyReport = report
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (e) {
      if (mounted) {
        showPharmacyError(context, e, fallback: "Couldn't load your finances.");
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ───────────────────────────── Build ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(pharmacyStoreProvider);
    if (store.selectedStoreId != null &&
        store.selectedStoreId != _loadedStoreId &&
        !_loading) {
      Future.microtask(_load);
    }
    final pending = _loading && _pnl.isEmpty;

    return Scaffold(
      backgroundColor: PharmacyColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: PharmacyColors.green,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const PharmacyScreenHeader(
                title: 'Earnings',
                subtitle: 'Sales, settlement and stock value',
              ),
              const SizedBox(height: 22),
              PharmacyEntrance(index: 0, child: _headline(pending)),
              const SizedBox(height: 18),
              PharmacyEntrance(index: 1, child: _chart()),
              if (_settlement.isNotEmpty) ...[
                const SizedBox(height: 28),
                PharmacyEntrance(index: 2, child: _settlementSection()),
              ],
              if (_pnl.isNotEmpty) ...[
                const SizedBox(height: 28),
                PharmacyEntrance(index: 3, child: _profitSection()),
              ],
              const SizedBox(height: 28),
              PharmacyEntrance(index: 4, child: _stockSection()),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────── Headline ────────────────────────────

  Widget _headline(bool pending) {
    final net = _num(_pnl['netSales']);
    final profit = _num(_pnl['grossProfit']);
    final margin = net > 0 ? profit / net * 100 : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Net sales', style: _caption),
        const SizedBox(height: 4),
        pending
            ? const PharmacyShimmer(
                child: PharmacySkeletonBlock(width: 170, height: 36),
              )
            : FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: PharmacyCountUp(
                  value: net,
                  format: _money,
                  style: PharmacyType.number(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.2,
                    height: 1.05,
                    color: PharmacyColors.textStrong,
                  ),
                ),
              ),
        const SizedBox(height: 6),
        Text(
          pending
              ? ' '
              : '${_money(profit)} gross profit  ·  ${margin.toStringAsFixed(1)}% margin',
          style: _caption,
        ),
      ],
    );
  }

  // ──────────────────────────── Chart ──────────────────────────────

  /// Seven calendar days ending today, zero-filled — the report lists only
  /// days that had sales.
  List<({DateTime day, double value})> get _week {
    final byDay = <String, double>{};
    for (final e in _dailyReport) {
      final d = DateTime.tryParse('${e['_id']}');
      if (d != null) {
        byDay[DateFormat('yyyy-MM-dd').format(d)] = _num(e['netSales']);
      }
    }
    final t = DateTime.now();
    return [
      for (var i = 6; i >= 0; i--)
        () {
          final day = DateTime(t.year, t.month, t.day - i);
          return (
            day: day,
            value: byDay[DateFormat('yyyy-MM-dd').format(day)] ?? 0.0,
          );
        }(),
    ];
  }

  Widget _chart() {
    final week = _week;
    final values = [for (final d in week) d.value];
    final maxY = math.max(values.fold<double>(0, math.max) * 1.2, 10.0);
    final total = values.fold<double>(0, (a, b) => a + b);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: PharmacyColors.panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Last 7 days',
                  style: _body.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                _money(total),
                style: PharmacyType.number(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: PharmacyColors.textStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 120,
            child: total <= 0
                ? Center(child: Text('No sales this week', style: _caption))
                : LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: 6,
                      minY: 0,
                      maxY: maxY,
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (_) => PharmacyColors.textStrong,
                          tooltipRoundedRadius: 8,
                          getTooltipItems: (spots) => [
                            for (final s in spots)
                              LineTooltipItem(
                                _money(s.y),
                                PharmacyType.sans(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                          ],
                        ),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(),
                        rightTitles: const AxisTitles(),
                        topTitles: const AxisTitles(),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: 1,
                            reservedSize: 22,
                            getTitlesWidget: (v, _) {
                              final i = v.round();
                              if ((v - i).abs() > 0.01 || i < 0 || i > 6) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  DateFormat('E').format(week[i].day)[0],
                                  style: _caption.copyWith(
                                    fontSize: 11.5,
                                    fontWeight: i == 6
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: i == 6
                                        ? PharmacyColors.textStrong
                                        : PharmacyColors.textTertiary,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            for (var i = 0; i < values.length; i++)
                              FlSpot(i.toDouble(), values[i]),
                          ],
                          isCurved: true,
                          curveSmoothness: 0.3,
                          preventCurveOverShooting: true,
                          color: PharmacyColors.green,
                          barWidth: 2.5,
                          isStrokeCapRound: true,
                          // Only today's point is marked.
                          dotData: FlDotData(
                            show: true,
                            checkToShowDot: (spot, _) => spot.x == 6,
                            getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                              radius: 4,
                              color: PharmacyColors.green,
                              strokeWidth: 2,
                              strokeColor: PharmacyColors.panel,
                            ),
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                PharmacyColors.green.withValues(alpha: 0.14),
                                PharmacyColors.green.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    duration: PharmacyMotion.slow,
                    curve: PharmacyMotion.enter,
                  ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────── Settlement ───────────────────────────

  Widget _settlementSection() {
    final pending = _map(_settlement['pending']);
    final paid = _map(_settlement['paid']);
    final payable = _num(pending['payable']);
    final orders = _num(pending['orders']).toInt();
    final rate = _num(_settlement['commissionRate']);
    final lines = (_settlement['lines'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PharmacySectionTitle('From Aadya Plus'),
        PharmacyGroup(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Due to you', style: _caption),
                        const SizedBox(height: 2),
                        PharmacyCountUp(
                          value: payable,
                          format: _money,
                          style: PharmacyType.number(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            color: PharmacyColors.greenDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    orders == 0
                        ? 'Nothing pending'
                        : '$orders delivered ${orders == 1 ? 'order' : 'orders'}',
                    style: _caption,
                  ),
                ],
              ),
            ),
            const PharmacyHairline(),
            _row('Order value', _money(pending['gross'])),
            const PharmacyHairline(),
            _row(
              rate > 0
                  ? 'Platform fee (${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 1)}%)'
                  : 'Platform fee',
              '−${_money(pending['commission'])}',
            ),
            const PharmacyHairline(),
            _row('Paid out so far', _money(paid['paidOut'])),
          ],
        ),
        if (lines.isNotEmpty) ...[
          const SizedBox(height: 20),
          const PharmacySectionTitle('By order'),
          PharmacyGroup(
            children: [
              for (var i = 0; i < lines.length; i++) ...[
                if (i > 0) const PharmacyHairline(),
                _settlementLine(lines[i]),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _settlementLine(Map<String, dynamic> line) {
    final order = _map(line['pharmacyOrderId']);
    final paid = '${line['payoutStatus']}' == 'paid';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${order['orderNumber'] ?? 'Order'}', style: _body),
                const SizedBox(height: 1),
                Text(
                  '${_money(line['consultationFee'])} · fee ${_money(line['platformCommission'])}',
                  style: _caption.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _money(line['professionalEarning']),
                style: PharmacyType.number(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: PharmacyColors.textStrong,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                paid ? 'Paid out' : 'Awaiting payout',
                style: _caption.copyWith(
                  fontSize: 11.5,
                  color: paid
                      ? PharmacyColors.textSecondary
                      : PharmacyColors.warning,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── Profit ──────────────────────────────

  Widget _profitSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PharmacySectionTitle('Profit & loss'),
        PharmacyGroup(
          children: [
            _row('Gross sales', _money(_pnl['grossSales'])),
            const PharmacyHairline(),
            _row(
              'Returns',
              '−${_money(_pnl['returns'])}',
              valueColor: _num(_pnl['returns']) > 0
                  ? PharmacyColors.error
                  : null,
            ),
            const PharmacyHairline(),
            _row('Net sales', _money(_pnl['netSales']), strong: true),
            const PharmacyHairline(),
            _row('Cost of goods', '−${_money(_pnl['costOfGoods'])}'),
            const PharmacyHairline(),
            _row(
              'Gross profit',
              _money(_pnl['grossProfit']),
              strong: true,
              valueColor: PharmacyColors.greenDark,
            ),
            const PharmacyHairline(),
            _row('Tax collected', _money(_pnl['taxCollected'])),
          ],
        ),
      ],
    );
  }

  // ──────────────────────────── Stock ──────────────────────────────

  Widget _stockSection() {
    final totals = _map(_valuation['totals']);
    final expired = _num(totals['expiredCostValue']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PharmacySectionTitle('Stock value'),
        PharmacyGroup(
          children: [
            _row('At retail', _money(totals['retailValue']), strong: true),
            const PharmacyHairline(),
            _row('At cost', _money(totals['costValue'])),
            const PharmacyHairline(),
            _row(
              'Units on shelf',
              NumberFormat.decimalPattern(
                'en_IN',
              ).format(_num(totals['units']).round()),
            ),
            const PharmacyHairline(),
            _row(
              'Expired stock (at cost)',
              _money(expired),
              valueColor: expired > 0 ? PharmacyColors.error : null,
              icon: expired > 0 ? LucideIcons.circleAlert : null,
            ),
          ],
        ),
      ],
    );
  }

  // ─────────────────────────── Pieces ──────────────────────────────

  static final _caption = PharmacyType.sans(
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    color: PharmacyColors.textSecondary,
  );
  static final _body = PharmacyType.sans(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: PharmacyColors.textPrimary,
  );

  Widget _row(
    String label,
    String value, {
    bool strong = false,
    Color? valueColor,
    IconData? icon,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: _body.copyWith(
              fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
        if (icon != null) ...[
          Icon(icon, size: 14, color: valueColor),
          const SizedBox(width: 5),
        ],
        Text(
          value,
          style: PharmacyType.number(
            fontSize: 13,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
            color:
                valueColor ??
                (strong
                    ? PharmacyColors.textStrong
                    : PharmacyColors.textSecondary),
          ),
        ),
      ],
    ),
  );

  static final _inr = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  /// Lakh grouping, as everywhere in the module — `₹12,68,500`.
  static String _money(dynamic value) =>
      _inr.format(num.tryParse('${value ?? 0}') ?? 0);
  static double _num(dynamic value) =>
      num.tryParse('${value ?? 0}')?.toDouble() ?? 0;
  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
}
