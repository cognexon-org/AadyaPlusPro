import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/network/api_service.dart';
import '../../auth/models/user_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../doctor/widgets/home_carousel.dart';
import '../../notifications/widgets/notification_bell.dart';
import '../providers/pharmacy_nav_provider.dart';
import '../providers/pharmacy_orders_provider.dart';
import '../providers/pharmacy_profile_provider.dart';
import '../providers/pharmacy_store_provider.dart';
import '../theme/pharmacy_colors.dart';
import '../theme/pharmacy_type.dart';
import '../widgets/pharmacy_ui.dart';
import 'add_medicine.dart';
import 'pharmacy_online_settings.dart';
import 'pharmacy_procurement.dart';
import 'pharmacy_sales.dart';
import 'pharmacy_coupons.dart';
import 'prescription_queue.dart';
import 'sale_details_screen.dart';
import 'stock_alert.dart';

// New sale (walk-in POS), Transfers and Coupons are deliberately off Home —
// their screens still exist: new_sale.dart, pharmacy_inventory_ops.dart and
// pharmacy_coupons.dart. Restore by importing them and adding an action.

/// Pharmacy Home, in the module's minimal style.
///
/// White page; content in soft grey grouped panels with no shadow or border;
/// hierarchy from type size and weight rather than boxes. Green is reserved
/// for money and the primary action; amber/red appear only as small text,
/// never as fills. One large number on the screen (today's sales) and one
/// live signal (orders waiting) — everything else is quiet rows.
class PharmacyHome extends ConsumerStatefulWidget {
  const PharmacyHome({super.key});

  @override
  ConsumerState<PharmacyHome> createState() => _PharmacyHomeState();
}

class _PharmacyHomeState extends ConsumerState<PharmacyHome> {
  final ApiService _api = ApiService();
  Map<String, dynamic> _stats = const {};
  Map<String, dynamic> _profile = const {};
  List<Map<String, dynamic>> _sales = const [];
  List<Map<String, dynamic>> _dailyReport = const [];
  bool _loading = true;
  bool _verificationDismissed = false;
  bool _recheckingVerification = false;
  String? _error;
  String? _loadedStoreId;

  /// True once the list has scrolled under the pinned header, which then
  /// shows a hairline so its edge reads.
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(pharmacyStoreProvider.notifier).initialize();
      if (!mounted) return;
      // The header's "accepting orders" line reads the online-store settings.
      ref.read(pharmacyProfileProvider.notifier).initialize();
      await _load();
    });
  }

  Future<void> _load() async {
    final storeId = ref.read(pharmacyStoreProvider).selectedStoreId;
    if (storeId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.getPharmacyInventoryDashboard(),
        _api.getPharmacySalesReport(queryParams: {'groupBy': 'day'}),
        _api.getPharmacyProfile(),
      ]);
      final data = _map(results[0].data);
      final reportData = results[1].data;
      final report =
          (reportData is Map ? reportData['report'] : null) as List? ??
          const [];
      final profileBody = _map(results[2].data);
      if (!mounted) return;
      setState(() {
        _stats = _map(data['stats']);
        _profile = _map(
          profileBody['pharmacy'] ??
              profileBody['profile'] ??
              profileBody['data'] ??
              profileBody,
        );
        _sales = _maps(data['recentSales']);
        _dailyReport = report
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loadedStoreId = storeId;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Recorded on failure too: build() reloads whenever this differs from
        // the selected branch, so leaving it unset turned one failed request
        // into an endless retry loop.
        _loadedStoreId = storeId;
        _loading = false;
        _error = e is DioException
            ? _message(e)
            : pharmacyErrorMessage(e, fallback: "Couldn't load this branch.");
      });
    }
  }

  Future<void> _refresh() async {
    ref.read(pharmacyOrdersProvider.notifier).loadOrders(silent: true);
    await _load();
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(PharmacyPageRoute(builder: (_) => page));
    if (!mounted) return;
    // Coming back from Online store may have paused or reopened the store.
    ref
        .read(pharmacyProfileProvider.notifier)
        .loadOnlineSettings(silent: true, force: true);
    await _load();
  }

  void _goToTab(int tab) =>
      ref.read(pharmacyTabRequestProvider.notifier).state = tab;

  // ───────────────────────────── Build ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(pharmacyStoreProvider);
    if (store.selectedStoreId != null &&
        store.selectedStoreId != _loadedStoreId &&
        !_loading) {
      Future.microtask(_load);
    }
    final awaiting = ref.watch(
      pharmacyOrdersProvider.select((s) => s.awaitingOrders),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: PharmacyColors.bg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Pinned: the store, its live status and the bell stay put while
              // the content scrolls beneath — the bell used to float over a
              // scrolling page and looked detached from it.
              AnimatedContainer(
                duration: PharmacyMotion.fast,
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                decoration: BoxDecoration(
                  color: PharmacyColors.bg,
                  border: Border(
                    bottom: BorderSide(
                      color: _scrolled
                          ? PharmacyColors.border
                          : PharmacyColors.bg,
                    ),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: _header(store)),
                    const SizedBox(width: 12),
                    const NotificationBell(color: PharmacyColors.green),
                  ],
                ),
              ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.depth != 0) return false;
                    final scrolled = n.metrics.pixels > 2;
                    if (scrolled != _scrolled) {
                      setState(() => _scrolled = scrolled);
                    }
                    return false;
                  },
                  child: RefreshIndicator(
                    color: PharmacyColors.green,
                    onRefresh: _refresh,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        _Section(index: 1, child: _today()),
                        const SizedBox(height: 16),
                        _Section(index: 2, child: _banner()),
                        const SizedBox(height: 16),
                        _Section(
                          index: 3,
                          child: _LiveOrdersRow(
                            awaiting: awaiting,
                            onOpen: () => _goToTab(PharmacyTab.orders),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          PharmacyErrorBanner(message: _error!, onRetry: _load),
                        ],
                        ..._verificationNotice(),
                        const SizedBox(height: 28),
                        _Section(index: 4, child: _actions(awaiting)),
                        const SizedBox(height: 28),
                        _Section(index: 5, child: _inventory()),
                        const SizedBox(height: 28),
                        _Section(index: 6, child: _attention()),
                        const SizedBox(height: 28),
                        _Section(index: 7, child: _bills()),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────────── Header ────────────────────────────

  /// The location captured at registration (`PharmacyProfile.address`), with
  /// the selected store's address as the fallback for additional branches.
  String _location(PharmacyStoreState store) {
    String from(Map<String, dynamic> a) => [
      a['city'],
      a['state'],
    ].where((v) => v != null && '$v'.trim().isNotEmpty).join(', ');
    final registered = from(_map(_profile['address']));
    return registered.isNotEmpty
        ? registered
        : from(_map(store.selectedStore?['address']));
  }

  /// Store name, then the one thing a pharmacist wants to know on opening
  /// the app: is the store taking online orders right now. Tapping the status
  /// opens Online store, where it is changed.
  Widget _header(PharmacyStoreState store) {
    final name = store.selectedStore?['name']?.toString() ?? 'Pharmacy';
    final multiBranch = store.stores.length > 1;
    final city = _location(store).split(',').first.trim();
    final settings = ref.watch(
      pharmacyProfileProvider.select((s) => s.onlineSettings),
    );

    final enabled = settings['enabled'] != false;
    final pausedUntil = DateTime.tryParse(
      '${settings['pausedUntil'] ?? ''}',
    )?.toLocal();
    final paused = pausedUntil != null && pausedUntil.isAfter(DateTime.now());
    final (statusText, tone) = settings.isEmpty
        ? (null, PharmacyColors.textTertiary)
        : !enabled
        ? ('Online store is off', PharmacyColors.textTertiary)
        : paused
        ? (
            'Paused until ${DateFormat('h:mm a').format(pausedUntil)}',
            PharmacyColors.warning,
          )
        : ('Accepting online orders', PharmacyColors.green);

    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PharmacyPressable(
            onTap: multiBranch ? () => _switchBranch(store) : null,
            haptic: multiBranch,
            scale: 0.99,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _Type.title.copyWith(
                      fontSize: PharmacyType.figure,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                if (multiBranch) ...[
                  const SizedBox(width: 3),
                  const Icon(
                    LucideIcons.chevronDown,
                    size: 18,
                    color: PharmacyColors.textSecondary,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (store.error != null)
            Text(
              store.error!,
              style: _Type.caption.copyWith(color: PharmacyColors.error),
            )
          else
            PharmacyPressable(
              onTap: statusText == null
                  ? null
                  : () => _open(const PharmacyOnlineSettings()),
              scale: 0.98,
              child: Row(
                children: [
                  if (statusText != null) ...[
                    // Live only while orders can actually arrive.
                    !enabled || paused
                        ? Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: tone,
                              shape: BoxShape.circle,
                            ),
                          )
                        : const PharmacyPulse(size: 7),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(
                        statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _Type.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: tone == PharmacyColors.green
                              ? PharmacyColors.greenDark
                              : tone,
                        ),
                      ),
                    ),
                  ],
                  Text(
                    [
                      if (statusText != null) '',
                      if (city.isNotEmpty) city,
                      DateFormat('EEE, d MMM').format(DateTime.now()),
                    ].join('  ·  '),
                    style: _Type.caption,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ───────────────────────────── Today ─────────────────────────────

  /// The focal card: today's takings, how they compare with yesterday, and
  /// the week as a soft area chart along the card's lower edge.
  Widget _today() {
    final revenue = _num(_stats['todayRevenue']);
    final bills = _int(_stats['todayTransactions']);
    final profit = _num(_stats['todayGrossProfit']);
    final week = _week;
    final values = [for (final d in week) d.value];
    final weekTotal = values.fold<double>(0, (a, b) => a + b);
    final yesterday = values.length > 1 ? values[values.length - 2] : 0.0;
    final today = values.isEmpty ? revenue : math.max(values.last, revenue);
    final delta = yesterday > 0 ? (today - yesterday) / yesterday * 100 : null;
    final pending = _loading && _stats.isEmpty;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [PharmacyColors.greenVeryLight, PharmacyColors.panel],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      "Today's sales",
                      style: _Type.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: PharmacyColors.textHeading,
                      ),
                    ),
                    const Spacer(),
                    if (!pending && delta != null) _deltaChip(delta),
                  ],
                ),
                const SizedBox(height: 6),
                pending
                    ? const PharmacyShimmer(
                        child: PharmacySkeletonBlock(width: 150, height: 30),
                      )
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: PharmacyCountUp(
                          value: revenue,
                          format: _rupees,
                          style: _Type.display,
                        ),
                      ),
                const SizedBox(height: 4),
                Text(
                  pending
                      ? ' '
                      : bills == 0
                      ? 'No bills yet today'
                      : [
                          '$bills ${bills == 1 ? 'bill' : 'bills'}',
                          '${_rupees(profit)} profit',
                          '${_rupees(revenue / bills)} avg',
                        ].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _Type.caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(height: 64, child: _sparkline(values)),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: Row(
              children: [
                for (var i = 0; i < week.length; i++)
                  Expanded(
                    child: Text(
                      DateFormat('E').format(week[i].day)[0],
                      textAlign: TextAlign.center,
                      style: _Type.caption.copyWith(
                        fontSize: PharmacyType.micro,
                        fontWeight: i == week.length - 1
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: i == week.length - 1
                            ? PharmacyColors.greenDark
                            : PharmacyColors.textTertiary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(height: 1, color: Colors.white),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
            child: Row(
              children: [
                Text('This week', style: _Type.caption),
                const Spacer(),
                Text(
                  _rupees(weekTotal),
                  style: PharmacyType.number(
                    fontSize: PharmacyType.body,
                    fontWeight: FontWeight.w700,
                    color: PharmacyColors.textStrong,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _deltaChip(double delta) {
    final up = delta >= 0;
    final tone = up ? PharmacyColors.greenDark : PharmacyColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? LucideIcons.trendingUp : LucideIcons.trendingDown,
            size: 13,
            color: tone,
          ),
          const SizedBox(width: 4),
          Text(
            '${up ? '+' : ''}${delta.toStringAsFixed(0)}% vs yesterday',
            style: PharmacyType.sans(
              fontSize: PharmacyType.micro,
              fontWeight: FontWeight.w700,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }

  /// Seven days as a smooth filled line, edge to edge, no axes — context for
  /// the number above it, not a chart to be read value by value.
  Widget _sparkline(List<double> values) {
    final maxV = values.fold<double>(0, math.max);
    if (maxV <= 0) {
      return Center(child: Text('No sales this week', style: _Type.caption));
    }
    // Inset so the line's ends line up with the weekday letters below.
    return LayoutBuilder(
      builder: (context, c) {
        final step = (c.maxWidth - 36) / 7;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: 18 + step / 2),
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: values.length - 1.0,
              minY: 0,
              maxY: maxV * 1.15,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              clipData: const FlClipData.none(),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < values.length; i++)
                      FlSpot(i.toDouble(), values[i]),
                  ],
                  isCurved: true,
                  curveSmoothness: 0.35,
                  preventCurveOverShooting: true,
                  color: PharmacyColors.green,
                  barWidth: 2.5,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    checkToShowDot: (spot, _) => spot.x == values.length - 1,
                    getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                      radius: 4,
                      color: PharmacyColors.green,
                      strokeWidth: 2.5,
                      strokeColor: Colors.white,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        PharmacyColors.green.withValues(alpha: 0.22),
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
        );
      },
    );
  }

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

  // ──────────────────────────── Actions ────────────────────────────

  /// Five small icon buttons in one row. Neutral icons on a light disc — the
  /// labels carry the meaning, so the buttons do not each need a colour.
  Widget _actions(List<Map<String, dynamic>> awaiting) {
    final rx = awaiting
        .where((o) => '${o['orderStatus']}' == 'prescription_review')
        .length;
    final items = [
      (
        'Rx queue',
        LucideIcons.fileText,
        () => _open(const PrescriptionQueue()),
        rx,
      ),
      (
        'Add stock',
        LucideIcons.packagePlus,
        () => _open(const AddMedicine()),
        0,
      ),
      (
        'Alerts',
        LucideIcons.triangleAlert,
        () => _open(const StockAlertScreen()),
        0,
      ),
      (
        'Purchase',
        LucideIcons.truck,
        () => _open(const PharmacyProcurement()),
        0,
      ),
      (
        'Store',
        LucideIcons.store,
        () => _open(const PharmacyOnlineSettings()),
        0,
      ),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final (label, icon, onTap, badge) in items)
          _ActionButton(label: label, icon: icon, onTap: onTap, badge: badge),
      ],
    );
  }

  // ─────────────────────────── Attention ───────────────────────────

  Widget _attention() {
    if (_loading && _stats.isEmpty) {
      return const PharmacyShimmer(
        child: PharmacySkeletonBlock(height: 104, radius: 14),
      );
    }
    if (_error != null) return const SizedBox.shrink();

    final rows = [
      (
        LucideIcons.packageSearch,
        'Low on stock',
        _int(_stats['lowStock']),
        PharmacyColors.warning,
        0,
      ),
      (
        LucideIcons.calendarClock,
        'Expiring in 30 days',
        _int(_stats['expiringBatches']),
        PharmacyColors.warning,
        1,
      ),
      (
        LucideIcons.circleAlert,
        'Expired batches',
        _int(_stats['expiredBatches']),
        PharmacyColors.error,
        2,
      ),
    ].where((r) => r.$3 > 0).toList();
    final openPos = _int(_stats['pendingOrders']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Stock'),
        _Group(
          children: [
            if (rows.isEmpty)
              const _Row(
                icon: LucideIcons.circleCheck,
                label: 'Nothing low, expiring or expired',
                iconColor: PharmacyColors.greenDark,
              ),
            for (final r in rows)
              _Row(
                icon: r.$1,
                label: r.$2,
                value: '${r.$3}',
                valueColor: r.$4,
                onTap: () => _open(StockAlertScreen(initialTab: r.$5)),
              ),
            if (openPos > 0)
              _Row(
                icon: LucideIcons.truck,
                label: 'Open purchase orders',
                value: '$openPos',
                onTap: () => _open(const PharmacyProcurement()),
              ),
          ],
        ),
      ],
    );
  }

  // ─────────────────────────── Inventory ───────────────────────────

  Widget _inventory() {
    if (_loading && _stats.isEmpty) return const SizedBox.shrink();
    if (_error != null) return const SizedBox.shrink();

    final retail = _num(_stats['inventoryRetailValue']);
    final cost = _num(_stats['inventoryCostValue']);
    final margin = retail - cost;
    final share = retail > 0 ? (margin / retail).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          'Inventory',
          action: 'Add',
          onAction: () => _open(const AddMedicine()),
        ),
        // Equal-height tiles: the margin tile carries a bar the other does not.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _statTile(
                  'Stock value',
                  _rupees(retail),
                  'at retail · ${_rupees(cost)} at cost',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statTile(
                  'Potential margin',
                  '${(share * 100).round()}%',
                  _rupees(margin),
                  tone: PharmacyColors.greenDark,
                  bar: share.toDouble(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _Group(
          children: [
            _Row(
              icon: LucideIcons.pill,
              label: 'Medicines listed',
              value: _decimal(_int(_stats['totalMedicines'])),
            ),
            _Row(
              icon: LucideIcons.boxes,
              label: 'Units on shelf',
              value: _decimal(_int(_stats['inventoryUnits'])),
            ),
            _Row(
              icon: LucideIcons.users,
              label: 'Active suppliers',
              value: _decimal(_int(_stats['activeSuppliers'])),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statTile(
    String label,
    String value,
    String caption, {
    Color? tone,
    double? bar,
  }) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _Type.caption),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: _Type.figure.copyWith(
              color: tone ?? PharmacyColors.textStrong,
            ),
          ),
        ),
        const Spacer(),
        if (bar != null) ...[
          _MarginBar(fraction: bar),
          const SizedBox(height: 6),
        ],
        Text(
          caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _Type.caption.copyWith(fontSize: PharmacyType.micro),
        ),
      ],
    ),
  );

  // ───────────────────────────── Bills ─────────────────────────────

  Widget _bills() {
    if (_loading || _error != null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          'Recent bills',
          action: _sales.isEmpty ? null : 'See all',
          onAction: () => _open(const PharmacySales()),
        ),
        _Group(
          children: [
            if (_sales.isEmpty)
              const _Row(
                icon: LucideIcons.receiptText,
                label: 'No bills at this branch yet',
              ),
            for (final sale in _sales.take(5)) _billRow(sale),
          ],
        ),
      ],
    );
  }

  Widget _billRow(Map<String, dynamic> sale) {
    final customer = sale['customerName']?.toString().trim();
    final name = (customer == null || customer.isEmpty) ? 'Walk-in' : customer;
    final amount = _num(sale['totalAmount']) - _num(sale['returnedAmount']);
    final invoice =
        sale['invoiceNumber']?.toString() ??
        sale['saleNumber']?.toString() ??
        '';
    return _Row(
      leading: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Text(
          name[0].toUpperCase(),
          style: PharmacyType.sans(
            fontSize: PharmacyType.body,
            fontWeight: FontWeight.w700,
            color: PharmacyColors.greenDark,
          ),
        ),
      ),
      label: name,
      subtitle: [
        if (invoice.isNotEmpty) invoice,
        _time(sale['createdAt']?.toString()),
      ].where((v) => v.isNotEmpty).join('  ·  '),
      value: _rupees(amount),
      valueColor: PharmacyColors.textStrong,
      onTap: () => _open(SaleDetailsScreen(sale: sale)),
    );
  }

  // ─────────────────────────── Banner ──────────────────────────────

  /// Feature slides with animated scenes, in place of the old static
  /// banner image.
  static const List<HomeSlide> _slides = [
    (
      title: 'Never miss an order',
      body: 'New orders ring until someone accepts — even on a locked phone.',
      cta: 'Orders',
      art: HomeSlideArt.orders,
      page: null,
      tab: PharmacyTab.orders,
    ),
    (
      title: 'Stay ahead of stock',
      body: 'Low stock and expiring batches flagged before they cost you.',
      cta: 'Stock alerts',
      art: HomeSlideArt.stock,
      page: StockAlertScreen(),
      tab: null,
    ),
    (
      title: 'Bring customers back',
      body: 'Create coupons for online orders in under a minute.',
      cta: 'Coupons',
      art: HomeSlideArt.coupon,
      page: PharmacyCoupons(),
      tab: null,
    ),
  ];

  Widget _banner() => HomeCarousel(
    slides: _slides,
    onOpen: (s) {
      if (s.page != null) {
        Navigator.of(context).push(PharmacyPageRoute(builder: (_) => s.page!));
      } else if (s.tab != null) {
        _goToTab(s.tab!);
      }
    },
  );

  // ───────────────────────── Verification ──────────────────────────

  /// Shown only for an explicitly non-approved status; a null status means
  /// the user record has not loaded yet.
  List<Widget> _verificationNotice() {
    final status = ref.watch(authProvider).user?.verificationStatus;
    if (_verificationDismissed ||
        status == null ||
        status == VerificationStatus.approved) {
      return const [];
    }
    final bad =
        status == VerificationStatus.rejected ||
        status == VerificationStatus.suspended;
    final title = status == VerificationStatus.rejected
        ? 'Verification rejected'
        : status == VerificationStatus.suspended
        ? 'Store suspended'
        : 'Verification pending';
    final body = status == VerificationStatus.rejected
        ? 'Re-submit your documents from Profile. Inventory keeps working meanwhile.'
        : status == VerificationStatus.suspended
        ? 'Hidden from online orders. Contact support to restore it.'
        : "Not listed for online orders yet. You can set up stock meanwhile.";
    final tone = bad ? PharmacyColors.error : PharmacyColors.warning;

    return [
      const SizedBox(height: 12),
      _Group(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: tone,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: _Type.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(body, style: _Type.caption.copyWith(height: 1.4)),
                      const SizedBox(height: 6),
                      PharmacyPressable(
                        onTap: _recheckVerification,
                        child: _recheckingVerification
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.8,
                                ),
                              )
                            : Text(
                                'Check again',
                                style: _Type.caption.copyWith(
                                  color: PharmacyColors.greenDark,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  visualDensity: VisualDensity.compact,
                  onPressed: () =>
                      setState(() => _verificationDismissed = true),
                  icon: const Icon(
                    LucideIcons.x,
                    size: 16,
                    color: PharmacyColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  Future<void> _recheckVerification() async {
    if (_recheckingVerification) return;
    setState(() => _recheckingVerification = true);
    await ref.read(authProvider.notifier).refreshUser();
    if (mounted) setState(() => _recheckingVerification = false);
  }

  // ─────────────────────────── Branches ────────────────────────────

  void _switchBranch(PharmacyStoreState storeState) {
    if (storeState.stores.length <= 1) return;
    showPharmacySheet<void>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Switch branch', style: _Type.title),
          const SizedBox(height: 14),
          _Group(
            children: [
              for (final s in storeState.stores)
                _Row(
                  icon: LucideIcons.store,
                  label: s['name']?.toString() ?? 'Pharmacy branch',
                  trailing: s['_id']?.toString() == storeState.selectedStoreId
                      ? const Icon(
                          LucideIcons.check,
                          size: 18,
                          color: PharmacyColors.green,
                        )
                      : const SizedBox.shrink(),
                  onTap: () {
                    ref
                        .read(pharmacyStoreProvider.notifier)
                        .selectStore('${s['_id']}');
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── Helpers ─────────────────────────────

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  static int _int(dynamic value) => num.tryParse('${value ?? 0}')?.toInt() ?? 0;
  static double _num(dynamic value) =>
      num.tryParse('${value ?? 0}')?.toDouble() ?? 0;

  static final _decimalFormat = NumberFormat.decimalPattern('en_IN');
  static String _decimal(int value) => _decimalFormat.format(value);

  static final _inr = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  static String _rupees(num value) => _inr.format(value);

  static String _time(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    final now = DateTime.now();
    final sameDay =
        d.year == now.year && d.month == now.month && d.day == now.day;
    return sameDay
        ? DateFormat('h:mm a').format(d)
        : DateFormat('d MMM, h:mm a').format(d);
  }

  static String _message(DioException e) {
    final d = e.response?.data;
    if (d is Map) {
      return d['message']?.toString() ??
          d['error']?.toString() ??
          'Request failed';
    }
    return e.message ?? 'Request failed';
  }
}

// ═════════════════════════ Minimal building blocks ═════════════════════════

/// The type scale for this screen. Five styles, nothing else.
class _Type {
  _Type._();

  static final display = PharmacyType.number(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.2,
    height: 1.05,
    color: PharmacyColors.textStrong,
  );
  static final figure = PharmacyType.number(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: PharmacyColors.textStrong,
  );
  static final title = PharmacyType.sans(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: PharmacyColors.textStrong,
  );
  static final body = PharmacyType.sans(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: PharmacyColors.textPrimary,
  );
  static final caption = PharmacyType.sans(
    fontSize: 11.5,
    fontWeight: FontWeight.w500,
    color: PharmacyColors.textSecondary,
  );
}

/// Grey panel fill — the only surface below the header.
const _panel = PharmacyColors.panel;

/// One fade-and-rise per section, not per item: motion marks the arrival
/// of the page, then gets out of the way.
class _Section extends StatelessWidget {
  final int index;
  final Widget child;
  const _Section({required this.index, required this.child});

  @override
  Widget build(BuildContext context) =>
      PharmacyEntrance(index: index, offsetY: 8, child: child);
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final String? action;
  final VoidCallback? onAction;
  const _SectionTitle(this.text, {this.action, this.onAction});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: _Type.body.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: PharmacyColors.textStrong,
            ),
          ),
        ),
        if (action != null)
          GestureDetector(
            onTap: onAction,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                action!,
                style: _Type.caption.copyWith(
                  color: PharmacyColors.greenDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// A grouped panel: rows separated by inset hairlines, no border, no shadow.
class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          Container(
            height: 1,
            margin: const EdgeInsets.only(left: 16),
            color: Colors.white,
          ),
        );
      }
      rows.add(children[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

/// A list row: optional neutral icon, label (+ subtitle), right-aligned
/// value, chevron when tappable.
class _Row extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final Color iconColor;
  final String label;
  final String? subtitle;
  final String? value;
  final Color? valueColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _Row({
    this.icon,
    this.leading,
    this.iconColor = PharmacyColors.textHeading,
    required this.label,
    this.subtitle,
    this.value,
    this.valueColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 12),
          ] else if (icon != null) ...[
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _Type.body,
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _Type.caption.copyWith(fontSize: 11.5),
                  ),
                ],
              ],
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: 10),
            Text(
              value!,
              style: PharmacyType.number(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? PharmacyColors.textSecondary,
              ),
            ),
          ],
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (onTap != null && trailing == null) ...[
            const SizedBox(width: 6),
            const Icon(
              LucideIcons.chevronRight,
              size: 17,
              color: PharmacyColors.textDisabled,
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return PharmacyPressable(scale: 0.99, onTap: onTap, child: row);
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final int badge;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return PharmacyPressable(
      onTap: onTap,
      scale: 0.92,
      semanticLabel: badge > 0 ? '$label, $badge waiting' : label,
      child: SizedBox(
        width: 62,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: PharmacyColors.greenVeryLight,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 19, color: PharmacyColors.greenDark),
                ),
                if (badge > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: PharmacyColors.warning,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: _Type.caption.copyWith(
                fontSize: 11.5,
                color: PharmacyColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarginBar extends StatelessWidget {
  final double fraction;
  const _MarginBar({required this.fraction});

  @override
  Widget build(BuildContext context) {
    final reduced = PharmacyMotion.reduced(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Container(
        height: 6,
        color: Colors.white,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: reduced ? fraction : 0, end: fraction),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutCubic,
          builder: (_, f, _) => Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: f,
              child: Container(color: PharmacyColors.green),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Live orders row ───────────────────────────

/// The one live element on Home. A quiet row when nothing is waiting; a
/// green-tinted row with a pulsing dot when something is. Its own widget so
/// the wait time can refresh without rebuilding the page.
class _LiveOrdersRow extends StatefulWidget {
  final List<Map<String, dynamic>> awaiting;
  final VoidCallback onOpen;
  const _LiveOrdersRow({required this.awaiting, required this.onOpen});

  @override
  State<_LiveOrdersRow> createState() => _LiveOrdersRowState();
}

class _LiveOrdersRowState extends State<_LiveOrdersRow> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && widget.awaiting.isNotEmpty) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String? get _oldest {
    DateTime? oldest;
    for (final o in widget.awaiting) {
      final d = DateTime.tryParse('${o['createdAt'] ?? ''}')?.toLocal();
      if (d != null && (oldest == null || d.isBefore(oldest))) oldest = d;
    }
    if (oldest == null) return null;
    final w = DateTime.now().difference(oldest);
    if (w.inMinutes < 1) return 'just now';
    if (w.inMinutes < 60) return '${w.inMinutes} min';
    if (w.inHours < 24) return '${w.inHours} hr';
    return '${w.inDays} d';
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.awaiting.length;
    final waiting = count > 0;
    final oldest = _oldest;

    return PharmacyPressable(
      onTap: widget.onOpen,
      scale: 0.985,
      semanticLabel: waiting ? '$count orders waiting' : 'No orders waiting',
      child: AnimatedContainer(
        duration: PharmacyMotion.medium,
        padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
        decoration: BoxDecoration(
          color: waiting ? PharmacyColors.greenVeryLight : _panel,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            waiting
                ? const PharmacyPulse(size: 8)
                : Container(
                    width: 20.8,
                    alignment: Alignment.center,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: PharmacyColors.textDisabled,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                waiting
                    ? '$count ${count == 1 ? 'order' : 'orders'} waiting'
                    : 'No orders waiting',
                style: _Type.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: waiting
                      ? PharmacyColors.textStrong
                      : PharmacyColors.textSecondary,
                ),
              ),
            ),
            if (waiting && oldest != null)
              Text(
                'oldest $oldest',
                style: _Type.caption.copyWith(color: PharmacyColors.greenDark),
              ),
            const SizedBox(width: 6),
            Icon(
              LucideIcons.chevronRight,
              size: 17,
              color: waiting
                  ? PharmacyColors.greenDark
                  : PharmacyColors.textDisabled,
            ),
          ],
        ),
      ),
    );
  }
}
