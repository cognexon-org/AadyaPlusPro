import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/pharmacy_type.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/network/api_service.dart';
import '../../auth/models/user_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/pharmacy_store_provider.dart';
import '../theme/pharmacy_colors.dart';
import '../widgets/pharmacy_ui.dart';
import 'add_medicine.dart';
import 'new_sale.dart';
import 'pharmacy_coupons.dart';
import 'pharmacy_inventory_ops.dart';
import 'pharmacy_online_settings.dart';
import 'pharmacy_orders.dart';
import 'pharmacy_procurement.dart';
import 'prescription_queue.dart';
import 'pharmacy_sales.dart';
import 'sale_details_screen.dart';
import 'stock_alert.dart';

/// Pharmacy Home.
///
/// One dominant block, then dense content — deliberately not a page of
/// equal-weight cards floating on grey. The day's takings own the screen at
/// 38pt; everything below is grouped by hairline rules on white, at the
/// density a counter operator actually reads. Colour is reserved for meaning
/// (money is green, alerts are amber/rose); nothing is tinted for decoration.
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

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(pharmacyStoreProvider.notifier).initialize();
      if (mounted) await _load();
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
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(e);
      });
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) await _load();
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

    return Scaffold(
      // Tints the status-bar strip so the hero reads as running to the top.
      backgroundColor: PharmacyColors.heroGradient.first,
      body: SafeArea(
        bottom: false,
        child: Container(
          color: PharmacyColors.bg,
          child: RefreshIndicator(
            color: PharmacyColors.green,
            onRefresh: _load,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _hero(store),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: PharmacyErrorBanner(
                      message: _error!,
                      onRetry: _load,
                    ),
                  ),
                _alertsGroup(),
                _verificationNotice(),
                const SizedBox(height: 20),
                _label('ACTIONS'),
                _actionsGroup(),
                const SizedBox(height: 20),
                _banner(),
                _inventoryGroup(),
                _billsGroup(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ────────────────────────────── Hero ─────────────────────────────

  Widget _hero(PharmacyStoreState store) {
    final revenue =
        num.tryParse('${_stats['todayRevenue'] ?? 0}')?.toDouble() ?? 0;
    final bills = _int(_stats['todayTransactions']);
    final profit =
        num.tryParse('${_stats['todayGrossProfit'] ?? 0}')?.toDouble() ?? 0;

    final parts = <String>[
      if (bills > 0) '$bills ${bills == 1 ? 'bill' : 'bills'}',
      if (profit != 0) '${_rupees(profit)} profit',
      if (bills > 0) '${_rupees(revenue / bills)} avg',
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: PharmacyColors.heroGradient,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _storeRow(store),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TODAY',
                      style: PharmacyType.sans(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 3),
                    if (_loading)
                      // The hero sits on green, so this placeholder is a white
                      // wash rather than the slate PharmacySkeletonBlock — but
                      // it takes the same shimmer as every other skeleton.
                      PharmacyShimmer(
                        child: Container(
                          width: 150,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      )
                    else
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _rupees(revenue),
                          maxLines: 1,
                          style: PharmacyType.number(
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.4,
                            height: 1,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  DateFormat('EEE, d MMM').format(DateTime.now()),
                  style: PharmacyType.sans(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
          if (!_loading) ...[
            const SizedBox(height: 7),
            Text(
              parts.isEmpty ? 'No bills yet today' : parts.join('  ·  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PharmacyType.sans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.78),
              ),
            ),
          ],
          if (!_loading && _dailyReport.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.14)),
            const SizedBox(height: 12),
            _trendStrip(),
          ],
        ],
      ),
    );
  }

  /// The location shown in the hero is the one captured when the pharmacy was
  /// registered — `PharmacyProfile.address` — not the store record's copy.
  /// The backend seeds a store's address from the profile when it provisions
  /// the tenant and re-syncs it on every profile save, but a store created
  /// before the profile carried an address keeps whatever it was given, so the
  /// registration record is the one to trust.
  ///
  /// The selected store's address is only a fallback, and it is the right
  /// answer for an additional branch: a second branch has its own address,
  /// entered for that branch, which the registration record knows nothing
  /// about.
  String _registeredLocation(PharmacyStoreState store) {
    String from(Map<String, dynamic> address) => [
      address['city'],
      address['state'],
    ].where((v) => v != null && '$v'.trim().isNotEmpty).join(', ');

    final registered = from(_map(_profile['address']));
    if (registered.isNotEmpty) return registered;
    return from(_map(store.selectedStore?['address']));
  }

  Widget _storeRow(PharmacyStoreState store) {
    final storeName = store.selectedStore?['name']?.toString() ?? 'Pharmacy';
    final city = _registeredLocation(store);
    final multiBranch = store.stores.length > 1;
    final user = ref.watch(authProvider).user;
    final owner = (user?.name ?? '').trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: multiBranch ? () => _switchBranch(store) : null,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        storeName.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PharmacyType.sans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.9,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (multiBranch) ...[
                      const SizedBox(width: 3),
                      Icon(
                        LucideIcons.chevronDown,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 1),
              Text(
                [
                  if (city.isNotEmpty) city,
                  if (owner.isNotEmpty) owner,
                ].join('  ·  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PharmacyType.sans(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              if (store.error != null) ...[
                const SizedBox(height: 6),
                Text(
                  store.error!,
                  style: PharmacyType.sans(fontSize: 11, color: Colors.white),
                ),
              ],
            ],
          ),
        ),
        // The dashboard shell floats a 46px notification bell at
        // (top: 12, right: 12) over every tab screen; without this reserved
        // gap the branch name runs underneath it.
        const SizedBox(width: 52),
      ],
    );
  }

  /// Seven days of takings as bars inside the hero — the trend belongs next
  /// to the number it explains, not in a chart card of its own.
  Widget _trendStrip() {
    const weekday = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final recent = _dailyReport.length > 7
        ? _dailyReport.sublist(_dailyReport.length - 7)
        : _dailyReport;
    final values = recent
        .map((e) => num.tryParse('${e['netSales']}')?.toDouble() ?? 0)
        .toList();
    final labels = recent.map((e) {
      final d = DateTime.tryParse('${e['_id']}');
      return d == null ? '' : weekday[d.weekday - 1];
    }).toList();
    final maxValue = values.fold<double>(0, (a, b) => b > a ? b : a);
    final total = values.fold<double>(0, (a, b) => a + b);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < values.length; i++) ...[
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: maxValue <= 0
                    ? 4
                    : (4 + (values[i] / maxValue) * 30).clamp(4.0, 34.0),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(
                    alpha: maxValue <= 0
                        ? 0.3
                        : (0.3 + (values[i] / maxValue) * 0.7),
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                labels[i],
                style: PharmacyType.sans(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
          const SizedBox(width: 7),
        ],
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'LAST ${values.length} DAYS',
                style: PharmacyType.sans(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _rupees(total),
                style: PharmacyType.number(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _switchBranch(PharmacyStoreState storeState) {
    if (storeState.stores.length <= 1) return;
    showPharmacySheet<void>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Switch branch',
            style: PharmacyType.sans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: PharmacyColors.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          ...storeState.stores.map((s) {
            final id = s['_id']?.toString() ?? '';
            final selected = id == storeState.selectedStoreId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: selected
                    ? PharmacyColors.greenVeryLight
                    : PharmacyColors.bgSecondary,
                borderRadius: BorderRadius.circular(PharmacyColors.radiusInput),
                child: InkWell(
                  borderRadius: BorderRadius.circular(
                    PharmacyColors.radiusInput,
                  ),
                  onTap: () {
                    ref.read(pharmacyStoreProvider.notifier).selectStore(id);
                    Navigator.pop(ctx);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.store,
                          size: 17,
                          color: selected
                              ? PharmacyColors.green
                              : PharmacyColors.textSecondary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            s['name']?.toString() ?? 'Pharmacy branch',
                            style: PharmacyType.sans(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: PharmacyColors.textPrimary,
                            ),
                          ),
                        ),
                        if (selected)
                          const Icon(
                            LucideIcons.check,
                            size: 16,
                            color: PharmacyColors.green,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ───────────────────────── Section chrome ────────────────────────

  Widget _label(String text, {String? action, VoidCallback? onAction}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 9),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: PharmacyType.sans(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: PharmacyColors.textTertiary,
                ),
              ),
            ),
            if (action != null)
              InkWell(
                onTap: onAction,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 2,
                  ),
                  child: Text(
                    action,
                    style: PharmacyType.sans(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: PharmacyColors.green,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  /// A bordered group with hairline-separated rows. Every list on this screen
  /// uses it, so the page has one grouping idiom instead of five card styles.
  Widget _group(List<Widget> children) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: PharmacyColors.borderStrong),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Column(children: children),
    ),
  );

  static Widget get _hairline =>
      Container(height: 1, color: PharmacyColors.border);

  // ───────────────────────────── Alerts ────────────────────────────

  Widget _alertsGroup() {
    if (_loading || _error != null) return const SizedBox.shrink();
    final rows = <Widget>[];

    void add(
      IconData icon,
      Color tone,
      int count,
      String one,
      String many,
      VoidCallback onTap,
    ) {
      if (count <= 0) return;
      if (rows.isNotEmpty) rows.add(_hairline);
      rows.add(_alertRow(icon, tone, count, count == 1 ? one : many, onTap));
    }

    add(
      LucideIcons.packageSearch,
      PharmacyColors.warning,
      _int(_stats['lowStock']),
      'medicine is low on stock',
      'medicines are low on stock',
      () => _open(const StockAlertScreen(initialTab: 0)),
    );
    add(
      LucideIcons.calendarClock,
      PharmacyColors.info,
      _int(_stats['expiringBatches']),
      'batch expires soon',
      'batches expire soon',
      () => _open(const StockAlertScreen(initialTab: 1)),
    );
    add(
      LucideIcons.circleAlert,
      PharmacyColors.error,
      _int(_stats['expiredBatches']),
      'batch has expired',
      'batches have expired',
      () => _open(const StockAlertScreen(initialTab: 2)),
    );
    add(
      LucideIcons.truck,
      PharmacyColors.textSecondary,
      _int(_stats['pendingOrders']),
      'purchase order is open',
      'purchase orders are open',
      () => _open(const PharmacyProcurement()),
    );

    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: _group(rows),
    );
  }

  Widget _alertRow(
    IconData icon,
    Color tone,
    int count,
    String label,
    VoidCallback onTap,
  ) {
    return Material(
      color: PharmacyColors.bg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 11, 11, 11),
          child: Row(
            children: [
              Icon(icon, size: 16, color: tone),
              const SizedBox(width: 11),
              Expanded(
                child: RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '$count ',
                        style: PharmacyType.sans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: PharmacyColors.textStrong,
                        ),
                      ),
                      TextSpan(
                        text: label,
                        style: PharmacyType.sans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: PharmacyColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Icon(
                LucideIcons.chevronRight,
                size: 15,
                color: PharmacyColors.textDisabled,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ────────────────────── Verification ──────────────────────

  /// The "verification pending" notice, shown here rather than as a strip
  /// above the hero. It sits directly above the actions it qualifies, because
  /// the point of the message is which actions still work while you wait.
  ///
  /// Only an explicitly non-approved status renders it. A null status means
  /// the user record has not loaded yet, and warning someone about a state you
  /// have not actually read is worse than staying quiet for a moment.
  Widget _verificationNotice() {
    final status = ref.watch(authProvider).user?.verificationStatus;
    if (_verificationDismissed ||
        status == null ||
        status == VerificationStatus.approved) {
      return const SizedBox.shrink();
    }

    final rejected = status == VerificationStatus.rejected;
    final suspended = status == VerificationStatus.suspended;
    final bad = rejected || suspended;
    final tone = bad ? PharmacyColors.error : PharmacyColors.warning;
    final surface = bad
        ? PharmacyColors.errorBg
        : PharmacyTileStyle.amber.surface;
    final edge = bad ? PharmacyColors.errorBg : PharmacyTileStyle.amber.border;

    final title = rejected
        ? 'Verification rejected'
        : suspended
        ? 'Store suspended'
        : 'Verification pending';
    final body = rejected
        ? 'Your documents were not accepted. Re-submit them from your profile — inventory and billing keep working in the meantime.'
        : suspended
        ? 'Your store is hidden from online orders. Contact support to restore it; counter billing and stock still work.'
        : "Your store isn't listed for online orders yet. Everything below still works — add medicines, take counter sales and manage stock while you wait.";

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 11, 9, 12),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: edge),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  bad ? LucideIcons.circleAlert : LucideIcons.hourglass,
                  size: 15,
                  color: tone,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: PharmacyType.sans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: PharmacyColors.textStrong,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _verificationDismissed = true),
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      LucideIcons.x,
                      size: 14,
                      color: PharmacyColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 23, right: 6),
              child: Text(
                body,
                style: PharmacyType.sans(
                  fontSize: 11.5,
                  height: 1.45,
                  color: PharmacyColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 9),
            Padding(
              padding: const EdgeInsets.only(left: 21),
              child: InkWell(
                onTap: _recheckVerification,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 2,
                  ),
                  child: _recheckingVerification
                      ? SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: tone,
                          ),
                        )
                      : Text(
                          'CHECK AGAIN',
                          style: PharmacyType.sans(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                            color: tone,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _recheckVerification() async {
    if (_recheckingVerification) return;
    setState(() => _recheckingVerification = true);
    await ref.read(authProvider.notifier).refreshUser();
    if (mounted) setState(() => _recheckingVerification = false);
  }

  // ───────────────────────────── Actions ───────────────────────────

  Widget _actionsGroup() {
    // Three actions are commented out rather than deleted — New sale (walk-in
    // POS), Transfers (multi-branch stock ops) and Coupons (merchant-funded
    // promos, which in a marketplace the platform owns). Their screens are
    // untouched and reachable again by restoring these entries.
    final actions = <_HomeAction>[
      // _HomeAction(
      //   'New sale',
      //   LucideIcons.shoppingCart,
      //   () => _open(const NewSaleScreen()),
      // ),
      _HomeAction(
        'Prescriptions',
        LucideIcons.fileText,
        () => _open(const PrescriptionQueue()),
      ),
      _HomeAction(
        'Procurement',
        LucideIcons.truck,
        () => _open(const PharmacyProcurement()),
      ),
      _HomeAction(
        'Stock alerts',
        LucideIcons.triangleAlert,
        () => _open(const StockAlertScreen()),
      ),
      // _HomeAction(
      //   'Transfers',
      //   LucideIcons.repeat2,
      //   () => _open(const PharmacyInventoryOps()),
      // ),
      _HomeAction(
        'Add medicine',
        LucideIcons.packagePlus,
        () => _open(const AddMedicine()),
      ),
      _HomeAction(
        'Online store',
        LucideIcons.store,
        () => _open(const PharmacyOnlineSettings()),
      ),
      // _HomeAction(
      //   'Coupons',
      //   LucideIcons.ticketPercent,
      //   () => _open(const PharmacyCoupons()),
      // ),
      _HomeAction(
        'Orders',
        LucideIcons.clipboardList,
        () => _open(const PharmacyOrders()),
      ),
    ];
    return _group([
      _actionRow(actions.sublist(0, 3)),
      _hairline,
      _actionRow(actions.sublist(3, 6)),
    ]);
  }

  Widget _actionRow(List<_HomeAction> row) => IntrinsicHeight(
    child: Row(
      children: [
        for (var i = 0; i < row.length; i++)
          Expanded(
            child: Container(
              decoration: i == row.length - 1
                  ? null
                  : const BoxDecoration(
                      border: Border(
                        right: BorderSide(color: PharmacyColors.border),
                      ),
                    ),
              child: Material(
                color: PharmacyColors.bg,
                child: InkWell(
                  onTap: row[i].onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 13,
                      horizontal: 4,
                    ),
                    child: Column(
                      children: [
                        Icon(
                          row[i].icon,
                          size: 19,
                          color: PharmacyColors.greenDark,
                        ),
                        const SizedBox(height: 7),
                        Text(
                          row[i].label,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: PharmacyType.sans(
                            fontSize: 10.5,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: PharmacyColors.textHeading,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  // ───────────────────────── Banner ──────────────────────

  /// Brand artwork, sat between the action chrome and the data tables so it
  /// breaks the page rather than pushing the day's numbers below the fold.
  /// Inset and radiused to the same 16/13 as every group on this screen, and
  /// carried at the asset's own 2.625 aspect so nothing is cropped or
  /// stretched. If the asset ever goes missing the slot collapses instead of
  /// leaving a grey hole.
  Widget _banner() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: AspectRatio(
        aspectRatio: 2032 / 774,
        child: Image.asset(
          'assets/banner.png',
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    ),
  );

  // ──────────────────────────── Inventory ──────────────────────────

  Widget _inventoryGroup() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: PharmacyListSkeleton(count: 2),
      );
    }
    if (_error != null) return const SizedBox.shrink();

    final retail =
        num.tryParse('${_stats['inventoryRetailValue'] ?? 0}')?.toDouble() ?? 0;
    final cost =
        num.tryParse('${_stats['inventoryCostValue'] ?? 0}')?.toDouble() ?? 0;
    final margin = retail - cost;
    final marginPct = cost > 0 ? (margin / cost) * 100 : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(
          'INVENTORY',
          action: '+ ADD',
          onAction: () => _open(const AddMedicine()),
        ),
        _group([
          _dataRow(
            'Medicines listed',
            _decimal(_int(_stats['totalMedicines'])),
          ),
          _hairline,
          _dataRow('Units on shelf', _decimal(_int(_stats['inventoryUnits']))),
          _hairline,
          _dataRow('Stock value at retail', _rupees(retail)),
          _hairline,
          _dataRow('Stock value at cost', _rupees(cost)),
          _hairline,
          _dataRow(
            'Potential margin',
            _rupees(margin),
            valueColor: PharmacyColors.greenDark,
            trailing: marginPct == null
                ? null
                : '${marginPct >= 0 ? '+' : ''}${marginPct.toStringAsFixed(1)}%',
          ),
          _hairline,
          _dataRow(
            'Active suppliers',
            _decimal(_int(_stats['activeSuppliers'])),
          ),
        ]),
        const SizedBox(height: 22),
      ],
    );
  }

  Widget _dataRow(
    String label,
    String value, {
    Color? valueColor,
    String? trailing,
  }) => Container(
    color: PharmacyColors.bg,
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PharmacyType.sans(
              fontSize: 12.5,
              color: PharmacyColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          value,
          style: PharmacyType.number(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: valueColor ?? PharmacyColors.textStrong,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: PharmacyColors.greenVeryLight,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              trailing,
              style: PharmacyType.sans(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: PharmacyColors.greenDark,
              ),
            ),
          ),
        ],
      ],
    ),
  );

  // ────────────────────────────── Bills ────────────────────────────

  Widget _billsGroup() {
    if (_loading || _error != null) return const SizedBox.shrink();
    if (_sales.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('RECENT BILLS'),
          _group([
            Container(
              color: PharmacyColors.bg,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
              child: const PharmacyEmptyStateInline(
                icon: LucideIcons.receiptText,
                text: 'No bills raised at this branch yet',
              ),
            ),
          ]),
        ],
      );
    }

    final rows = <Widget>[];
    for (final sale in _sales.take(6)) {
      if (rows.isNotEmpty) rows.add(_hairline);
      rows.add(_billRow(sale));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(
          'RECENT BILLS',
          action: 'ALL SALES',
          onAction: () => _open(const PharmacySales()),
        ),
        _group(rows),
      ],
    );
  }

  Widget _billRow(Map<String, dynamic> sale) {
    final customer = sale['customerName']?.toString().trim();
    final name = (customer == null || customer.isEmpty) ? 'Walk-in' : customer;
    final invoice =
        sale['invoiceNumber']?.toString() ??
        sale['saleNumber']?.toString() ??
        '';
    final amount =
        (num.tryParse('${sale['totalAmount'] ?? 0}') ?? 0) -
        (num.tryParse('${sale['returnedAmount'] ?? 0}') ?? 0);
    final meta = [
      if (invoice.isNotEmpty) invoice,
      _time(sale['createdAt']?.toString()),
    ].where((v) => v.isNotEmpty).join('  ·  ');

    return Material(
      color: PharmacyColors.bg,
      child: InkWell(
        onTap: () => _open(SaleDetailsScreen(sale: sale)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: PharmacyColors.bgSecondary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  name[0].toUpperCase(),
                  style: PharmacyType.sans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: PharmacyColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PharmacyType.sans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: PharmacyColors.textPrimary,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PharmacyType.sans(
                          fontSize: 10.5,
                          color: PharmacyColors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _rupees(amount),
                style: PharmacyType.number(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: PharmacyColors.textStrong,
                ),
              ),
              const SizedBox(width: 3),
              const Icon(
                LucideIcons.chevronRight,
                size: 14,
                color: PharmacyColors.textDisabled,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────────── Helpers ───────────────────────────

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  static int _int(dynamic value) => num.tryParse('${value ?? 0}')?.toInt() ?? 0;

  static final _decimalFormat = NumberFormat.decimalPattern('en_IN');
  static String _decimal(int value) => _decimalFormat.format(value);

  /// Indian digit grouping — pharmacy figures read as ₹12,68,500 (lakh
  /// grouping), not ₹1,268,500.
  static final _inr = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  static String _rupees(dynamic value) =>
      _inr.format(num.tryParse(value?.toString() ?? '') ?? 0);

  static String _time(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso);
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

class _HomeAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _HomeAction(this.label, this.icon, this.onTap);
}
