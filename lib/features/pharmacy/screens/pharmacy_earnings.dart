import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/pharmacy_type.dart';
import '../../../core/network/api_service.dart';
import '../theme/pharmacy_colors.dart';
import '../providers/pharmacy_store_provider.dart';
import '../widgets/pharmacy_ui.dart';

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
        _loadedStoreId = ref.read(pharmacyStoreProvider).selectedStoreId;
        _pnl = Map<String, dynamic>.from(results[0].data as Map);
        _valuation = Map<String, dynamic>.from(results[1].data as Map);
        _settlement = results[3].data is Map
            ? Map<String, dynamic>.from(results[3].data as Map)
            : const {};
        _dailyReport = report
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pharmacyErrorMessage(
                e,
                fallback: 'Couldn\'t load your finances.',
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: PharmacyColors.error,
          ),
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static final _inr = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  /// Lakh grouping, the same as every other money figure in the module —
  /// `₹12,68,500`, not the ungrouped `₹1268500` this screen used to print.
  String _money(dynamic value) => _inr.format(num.tryParse('$value') ?? 0);
  double _num(dynamic value) => num.tryParse('$value')?.toDouble() ?? 0;

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(pharmacyStoreProvider);
    if (store.selectedStoreId != null &&
        store.selectedStoreId != _loadedStoreId &&
        !_loading)
      Future.microtask(_load);
    final totals = Map<String, dynamic>.from(
      (_valuation['totals'] as Map?) ?? const {},
    );
    return Scaffold(
      backgroundColor: PharmacyColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: PharmacyColors.green,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const PharmacyScreenHeader(
                title: 'Earnings',
                subtitle: 'Profit & loss and inventory valuation',
              ),
              const SizedBox(height: 16),
              if (_settlement.isNotEmpty) ...[
                _settlementCard(),
                _settlementLines(),
                const SizedBox(height: 16),
              ],
              if (_loading && _pnl.isEmpty)
                const PharmacyListSkeleton(count: 2),
              if (_pnl.isNotEmpty) ...[
                _heroCard()
                    .animate()
                    .fadeIn(duration: 300.ms)
                    .slideY(begin: 0.05, end: 0, curve: Curves.easeOutCubic),
                const SizedBox(height: 16),
                _revenueTrendCard(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: PharmacyMetricTile(
                        label: 'Gross Sales',
                        value: _money(_pnl['grossSales']),
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PharmacyMetricTile(
                        label: 'Returns',
                        value: _money(_pnl['returns']),
                        compact: true,
                        color: PharmacyColors.error,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: PharmacyMetricTile(
                        label: 'COGS',
                        value: _money(_pnl['costOfGoods']),
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PharmacyMetricTile(
                        label: 'Tax',
                        value: _money(_pnl['taxCollected']),
                        compact: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _breakdownCard(),
                const SizedBox(height: 20),
              ],
              Text(
                'Inventory Valuation',
                style: PharmacyType.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: PharmacyColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: PharmacyMetricTile(
                      label: 'Cost Value',
                      value: _money(totals['costValue']),
                      compact: true,
                      color: PharmacyColors.green,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PharmacyMetricTile(
                      label: 'Retail Value',
                      value: _money(totals['retailValue']),
                      compact: true,
                      color: PharmacyColors.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: PharmacyMetricTile(
                      label: 'Units',
                      value: '${totals['units'] ?? 0}',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PharmacyMetricTile(
                      label: 'Expired Cost',
                      value: _money(totals['expiredCostValue']),
                      compact: true,
                      color: PharmacyColors.error,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroCard() {
    final netSales = _num(_pnl['netSales']);
    final grossProfit = _num(_pnl['grossProfit']);
    final margin = netSales > 0 ? (grossProfit / netSales * 100) : 0;
    return PharmacyCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Net Sales',
                      style: PharmacyType.sans(
                        fontSize: 12,
                        color: PharmacyColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _money(_pnl['netSales']),
                      style: PharmacyType.number(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: PharmacyColors.textStrong,
                      ),
                    ),
                  ],
                ),
              ),
              PharmacyStatusPill(
                text: '${margin.toStringAsFixed(1)}% margin',
                color: PharmacyColors.green,
                background: PharmacyColors.greenLight,
                icon: CupertinoIcons.graph_square,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: PharmacyColors.border),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _statColumn('Gross Profit', _money(_pnl['grossProfit'])),
              ),
              Container(width: 1, height: 30, color: PharmacyColors.border),
              Expanded(
                child: _statColumn('Gross Sales', _money(_pnl['grossSales'])),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Platform settlement: what is owed, what has been paid, and the
  /// commission taken to get there.
  Widget _settlementCard() {
    final pending = _map(_settlement['pending']);
    final paid = _map(_settlement['paid']);
    final payable = _num(pending['payable']);
    final orders = _num(pending['orders']).toInt();

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
      decoration: BoxDecoration(
        color: PharmacyColors.greenVeryLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PharmacyColors.greenLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DUE FROM AADYA PLUS',
                      style: PharmacyType.sans(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                        color: PharmacyColors.greenDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _money(payable),
                        maxLines: 1,
                        style: PharmacyType.number(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          height: 1,
                          color: PharmacyColors.textStrong,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      orders == 0
                          ? 'No delivered orders awaiting settlement'
                          : 'across $orders delivered ${orders == 1 ? 'order' : 'orders'}',
                      style: PharmacyType.sans(
                        fontSize: 11.5,
                        color: PharmacyColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: PharmacyColors.greenLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.wallet,
                  size: 20,
                  color: PharmacyColors.greenDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: PharmacyColors.greenLight),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _settlementStat(
                  'Order value',
                  _money(_num(pending['gross'])),
                ),
              ),
              Expanded(
                child: _settlementStat(
                  'Platform fee ${_rateLabel()}',
                  '−${_money(_num(pending['commission']))}',
                ),
              ),
              Expanded(
                child: _settlementStat(
                  'Paid out',
                  _money(_num(paid['paidOut'])),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _rateLabel() {
    final rate = _num(_settlement['commissionRate']);
    if (rate <= 0) return '';
    return '(${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 1)}%)';
  }

  /// One row per settled order, so the aggregate above can be checked against
  /// the orders behind it rather than taken on trust.
  Widget _settlementLines() {
    final lines = (_settlement['lines'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (lines.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          'SETTLEMENT BY ORDER',
          style: PharmacyType.sans(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: PharmacyColors.textTertiary,
          ),
        ),
        const SizedBox(height: 9),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: PharmacyColors.borderStrong),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Column(
              children: [
                for (var i = 0; i < lines.length; i++) ...[
                  if (i > 0) Container(height: 1, color: PharmacyColors.border),
                  _settlementLine(lines[i]),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _settlementLine(Map<String, dynamic> line) {
    final order = _map(line['pharmacyOrderId']);
    final paid = '${line['payoutStatus']}' == 'paid';
    final rate = _num(line['commissionRate']);

    return Container(
      color: PharmacyColors.bg,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${order['orderNumber'] ?? 'Order'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PharmacyType.sans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: PharmacyColors.textStrong,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_money(_num(line['consultationFee']))} · fee ${_money(_num(line['platformCommission']))}'
                  '${rate > 0 ? ' (${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 1)}%)' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PharmacyType.sans(
                    fontSize: 10.5,
                    color: PharmacyColors.textTertiary,
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
                _money(_num(line['professionalEarning'])),
                style: PharmacyType.number(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: PharmacyColors.textStrong,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                paid ? 'Paid out' : 'Awaiting payout',
                style: PharmacyType.sans(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: paid
                      ? PharmacyColors.greenDark
                      : PharmacyColors.warning,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _settlementStat(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          value,
          maxLines: 1,
          style: PharmacyType.number(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: PharmacyColors.textStrong,
          ),
        ),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: PharmacyType.sans(
          fontSize: 10,
          color: PharmacyColors.textSecondary,
        ),
      ),
    ],
  );

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  Widget _statColumn(String label, String value) => Column(
    children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          maxLines: 1,
          style: PharmacyType.number(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: PharmacyColors.textStrong,
          ),
        ),
      ),
      const SizedBox(height: 3),
      Text(
        label,
        style: PharmacyType.sans(
          fontSize: 10.5,
          color: PharmacyColors.textSecondary,
        ),
      ),
    ],
  );

  Widget _revenueTrendCard() {
    final points = _buildDailyPoints();
    final values = points.map((p) => p.y).toList();
    final maxY = values.isEmpty
        ? 100.0
        : (values.reduce((a, b) => a > b ? a : b) * 1.3).clamp(
            10,
            double.infinity,
          );
    final total = values.fold<double>(0, (a, b) => a + b);

    // A single-hue-of-a-line-chart still needs to be built once so
    // showingTooltipIndicators can reference the exact same bar instance —
    // fl_chart identifies a spot by (bar, index), not just by value.
    final lineBar = LineChartBarData(
      spots: points,
      isCurved: true,
      curveSmoothness: 0.32,
      color: PharmacyColors.green,
      barWidth: 2,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
          radius: 3,
          color: PharmacyColors.green,
          strokeWidth: 2,
          strokeColor: Colors.white,
        ),
      ),
      belowBarData: BarAreaData(
        show: true,
        color: PharmacyColors.green.withValues(alpha: 0.06),
      ),
    );

    return PharmacyCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(16, 16, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Revenue Trend',
                  style: PharmacyType.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: PharmacyColors.textPrimary,
                  ),
                ),
                Text(
                  '₹${total.toStringAsFixed(0)} · 7 days',
                  style: PharmacyType.sans(
                    fontSize: 11,
                    color: PharmacyColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 160,
            child: points.isEmpty
                ? Center(
                    child: Text(
                      'No sales recorded yet',
                      style: PharmacyType.sans(
                        fontSize: 12.5,
                        color: PharmacyColors.textTertiary,
                      ),
                    ),
                  )
                : LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: (points.length - 1)
                          .clamp(0, double.infinity)
                          .toDouble(),
                      minY: 0,
                      maxY: maxY.toDouble(),
                      // Always-visible value labels, not just on touch — with
                      // few points (e.g. a single day of sales) there was
                      // otherwise nothing to see on the chart at all.
                      showingTooltipIndicators: List.generate(
                        points.length,
                        (i) => ShowingTooltipIndicators([
                          LineBarSpot(lineBar, 0, points[i]),
                        ]),
                      ),
                      lineTouchData: LineTouchData(
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (_) => PharmacyColors.textPrimary,
                          tooltipRoundedRadius: 8,
                          tooltipPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          getTooltipItems: (spots) => spots
                              .map(
                                (s) => LineTooltipItem(
                                  '₹${s.y.toStringAsFixed(0)}',
                                  PharmacyType.sans(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        getTouchedSpotIndicator: (barData, indexes) => indexes
                            .map(
                              (_) => TouchedSpotIndicatorData(
                                FlLine(
                                  color: PharmacyColors.green.withValues(
                                    alpha: 0.3,
                                  ),
                                  strokeWidth: 1.5,
                                  dashArray: [4, 4],
                                ),
                                FlDotData(
                                  getDotPainter: (spot, percent, bar, index) =>
                                      FlDotCirclePainter(
                                        radius: 4,
                                        color: PharmacyColors.green,
                                        strokeWidth: 2,
                                        strokeColor: Colors.white,
                                      ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: maxY / 3,
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: PharmacyColors.border,
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 24,
                            // Without an explicit interval, fl_chart picks its
                            // own tick spacing based on chart width; with a
                            // small x-range (e.g. a single day of data) that
                            // spacing can be fractional, so the same day index
                            // got rendered several times — "Mon Mon Mon".
                            interval: 1,
                            getTitlesWidget: (v, _) {
                              final i = v.round();
                              if ((v - i).abs() > 0.01 ||
                                  i < 0 ||
                                  i >= _dailyLabels.length)
                                return const SizedBox();
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  _dailyLabels[i],
                                  style: PharmacyType.sans(
                                    fontSize: 10,
                                    color: PharmacyColors.textTertiary,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 36,
                            interval: maxY / 3,
                            getTitlesWidget: (v, _) => Text(
                              v >= 1000
                                  ? '₹${(v / 1000).toStringAsFixed(1)}k'
                                  : '₹${v.toInt()}',
                              style: PharmacyType.sans(
                                fontSize: 9.5,
                                color: PharmacyColors.textTertiary,
                              ),
                            ),
                          ),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [lineBar],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  List<String> _dailyLabels = [];

  List<FlSpot> _buildDailyPoints() {
    if (_dailyReport.isEmpty) {
      _dailyLabels = [];
      return [];
    }
    const weekday = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final recent = _dailyReport.length > 7
        ? _dailyReport.sublist(_dailyReport.length - 7)
        : _dailyReport;
    _dailyLabels = recent.map((e) {
      final date = DateTime.tryParse('${e['_id']}');
      return date == null ? '${e['_id']}' : weekday[date.weekday - 1];
    }).toList();
    return List.generate(
      recent.length,
      (i) => FlSpot(i.toDouble(), _num(recent[i]['netSales'])),
    );
  }

  Widget _breakdownCard() {
    final cogs = _num(_pnl['costOfGoods']);
    final profit = _num(_pnl['grossProfit']).clamp(0, double.infinity);
    final tax = _num(_pnl['taxCollected']);
    final total = cogs + profit + tax;
    final slices = <_Slice>[
      _Slice('Cost of Goods', cogs, PharmacyColors.textTertiary),
      _Slice('Gross Profit', profit.toDouble(), PharmacyColors.success),
      _Slice('Tax Collected', tax, PharmacyColors.info),
    ].where((s) => s.value > 0).toList();

    return PharmacyCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sales Breakdown',
            style: PharmacyType.sans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: PharmacyColors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          if (slices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  'No sales recorded yet',
                  style: PharmacyType.sans(
                    fontSize: 12.5,
                    color: PharmacyColors.textTertiary,
                  ),
                ),
              ),
            )
          else
            Row(
              children: [
                SizedBox(
                  width: 110,
                  height: 110,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sections: slices
                              .map(
                                (s) => PieChartSectionData(
                                  value: s.value,
                                  color: s.color,
                                  radius: 18,
                                  showTitle: false,
                                ),
                              )
                              .toList(),
                          centerSpaceRadius: 34,
                          sectionsSpace: 3,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Total',
                            style: PharmacyType.sans(
                              fontSize: 10,
                              color: PharmacyColors.textTertiary,
                            ),
                          ),
                          Text(
                            total >= 1000
                                ? '₹${(total / 1000).toStringAsFixed(1)}k'
                                : '₹${total.toStringAsFixed(0)}',
                            style: PharmacyType.sans(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: PharmacyColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: slices
                        .map(
                          (s) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 9,
                                  height: 9,
                                  decoration: BoxDecoration(
                                    color: s.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    s.label,
                                    style: PharmacyType.sans(
                                      fontSize: 12.5,
                                      color: PharmacyColors.textSecondary,
                                    ),
                                  ),
                                ),
                                Text(
                                  total > 0
                                      ? '${(s.value / total * 100).toStringAsFixed(0)}%'
                                      : '0%',
                                  style: PharmacyType.sans(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: PharmacyColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Slice {
  final String label;
  final double value;
  final Color color;
  _Slice(this.label, this.value, this.color);
}
