import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/pharmacy_type.dart';
import '../../../core/network/api_service.dart';
import '../theme/pharmacy_colors.dart';
import '../providers/pharmacy_store_provider.dart';
import '../widgets/order_action_sheets.dart';
import '../widgets/pharmacy_ui.dart';
import 'order_details_screen.dart';

const kOrderStatuses = <String?>[
  null,
  'prescription_review',
  'placed',
  'confirmed',
  'packing',
  'ready_to_ship',
  'shipped',
  'out_for_delivery',
  'delivered',
  'cancelled',
];

String orderStatusLabel(String s) => s
    .split('_')
    .map((x) => x.isEmpty ? x : '${x[0].toUpperCase()}${x.substring(1)}')
    .join(' ');

class PharmacyOrders extends ConsumerStatefulWidget {
  const PharmacyOrders({super.key});

  @override
  ConsumerState<PharmacyOrders> createState() => _PharmacyOrdersState();
}

class _PharmacyOrdersState extends ConsumerState<PharmacyOrders> {
  final _api = ApiService();
  final _search = TextEditingController();
  List<Map<String, dynamic>> _orders = const [];
  bool _loading = true;
  String? _filter;
  String? _error;
  String? _loadedStoreId;

  /// Ids currently being accepted or rejected, so a card can show its own
  /// spinner without freezing the whole list.
  final Set<String> _busy = {};

  /// Drives the elapsed-time counters on new orders. Only runs while at least
  /// one order is actually waiting — a list of delivered orders has nothing
  /// to count, and a timer ticking behind it would just burn battery.
  Timer? _ticker;

  static const _quickFilters = <String?>[
    null,
    'prescription_review',
    'placed',
    'confirmed',
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(pharmacyStoreProvider.notifier).initialize();
      if (mounted) await _load();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _syncTicker() {
    final waiting = _orders.any(_isAwaitingAction);
    if (waiting && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!waiting) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  /// An order the pharmacy has not yet accepted or turned down.
  static bool _isAwaitingAction(Map<String, dynamic> order) {
    final status = '${order['orderStatus'] ?? ''}';
    final rx = '${order['prescriptionStatus'] ?? ''}';
    return status == 'placed' ||
        (status == 'prescription_review' && rx != 'pending_review');
  }

  /// The one action that moves this order forward, or null when it is the
  /// customer's or the courier's turn.
  static ({String status, String label})? _nextStep(String status) {
    const ladder = {
      'confirmed': ('packing', 'Start packing'),
      'packing': ('ready_to_ship', 'Mark packed'),
      'ready_to_ship': ('shipped', 'Hand to courier'),
      'shipped': ('out_for_delivery', 'Out for delivery'),
      'out_for_delivery': ('delivered', 'Mark delivered'),
    };
    final step = ladder[status];
    return step == null ? null : (status: step.$1, label: step.$2);
  }

  Future<void> _load() async {
    final storeId = ref.read(pharmacyStoreProvider).selectedStoreId;
    if (storeId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.getMerchantOrders(
        queryParams: {
          'limit': 100,
          if (_filter != null) 'status': _filter,
          if (_search.text.trim().isNotEmpty) 'q': _search.text.trim(),
        },
      );
      final data = response.data;
      if (!mounted) return;
      setState(() {
        _orders = _maps(data is Map ? data['orders'] : data);
        _loadedStoreId = storeId;
        _loading = false;
      });
      _syncTicker();
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(e);
      });
    }
  }

  /// Runs one card's action and refreshes, keeping the spinner on that card.
  Future<void> _act(
    String id,
    Future<Response> Function() action,
    String success,
  ) async {
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      await action();
      if (!mounted) return;
      _toast(success, PharmacyColors.success);
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      _toast(_message(e), PharmacyColors.error);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  /// Accept straight from the card. The availability sheet opens first so a
  /// short line can be handled here too — the commonest reason a pharmacist
  /// would otherwise have to open the order.
  Future<void> _accept(Map<String, dynamic> order) async {
    final id = '${order['_id'] ?? ''}';
    final items = _maps(order['items']);
    final availability = await showPharmacySheet<Map<String, int>>(
      context,
      builder: (_) => OrderAvailabilitySheet(items: items),
    );
    if (availability == null || !mounted) return;

    final short = <String>[];
    for (final item in items) {
      final itemId = '${item['_id'] ?? ''}';
      final ordered = (num.tryParse('${item['quantity'] ?? 0}') ?? 0).toInt();
      final supplied = availability[itemId] ?? ordered;
      if (supplied < ordered) {
        short.add('${item['medicineName'] ?? 'Item'} — $supplied of $ordered');
      }
    }

    if (short.isNotEmpty) {
      final paidOnline =
          '${order['paymentMethod']}' == 'online' &&
          '${order['paymentStatus']}' == 'paid';
      final proceed = await PharmacyDialog.confirm(
        context,
        title: 'Accept with changes?',
        message:
            '${short.join('\n')}\n\nThe order total is reduced'
            '${paidOnline ? ' and the difference refunded to the customer' : ''}.',
        confirmLabel: 'Accept',
        cancelLabel: 'Back',
        destructive: false,
      );
      if (!proceed || !mounted) return;
    }

    await _act(
      id,
      () => _api.confirmMerchantOrder(
        id,
        availability: short.isEmpty ? null : availability,
      ),
      short.isEmpty ? 'Order accepted' : 'Order accepted with changes',
    );
  }

  Future<void> _reject(Map<String, dynamic> order) async {
    final id = '${order['_id'] ?? ''}';
    final choice = await showPharmacySheet<Map<String, String>>(
      context,
      builder: (_) =>
          const OrderRejectReasonSheet(reasons: kOrderRejectionReasons),
    );
    if (choice == null || !mounted) return;

    final paidOnline =
        '${order['paymentMethod']}' == 'online' &&
        '${order['paymentStatus']}' == 'paid';
    final proceed = await PharmacyDialog.confirm(
      context,
      title: 'Reject this order?',
      message: paidOnline
          ? 'The customer is told the pharmacy could not take the order, and their online payment is refunded. This cannot be undone.'
          : 'The customer is told the pharmacy could not take the order. This cannot be undone.',
      confirmLabel: 'Reject order',
      cancelLabel: 'Keep order',
    );
    if (!proceed || !mounted) return;

    await _act(
      id,
      () => _api.rejectMerchantOrder(
        id,
        reason: choice['reason']!,
        note: choice['note'],
      ),
      'Order rejected',
    );
  }

  void _toast(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: PharmacyType.sans(fontSize: 12.5, color: Colors.white),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openFilterSheet() async {
    final selected = await showPharmacySheet<String?>(
      context,
      builder: (ctx) => _OrderFilterSheet(initial: _filter),
    );
    if (selected != _filter) {
      setState(() => _filter = selected);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(pharmacyStoreProvider);
    if (store.selectedStoreId != null &&
        store.selectedStoreId != _loadedStoreId &&
        !_loading) {
      Future.microtask(_load);
    }
    return Scaffold(
      backgroundColor: PharmacyColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PharmacyScreenHeader(
                    title: 'Orders',
                    subtitle: 'Online orders for this branch',
                    trailing: IconButton(
                      onPressed: _openFilterSheet,
                      icon: Icon(
                        CupertinoIcons.slider_horizontal_3,
                        color: _filter != null
                            ? PharmacyColors.green
                            : PharmacyColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  PharmacySearchField(
                    controller: _search,
                    hint: 'Search by order number...',
                    onSubmitted: _load,
                    onRefresh: _load,
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // A status picked from the sheet that is not one of
                        // the four quick chips used to leave every chip
                        // unselected, so the list looked filtered by nothing.
                        // Show it as its own selected chip instead.
                        for (final s in [
                          ..._quickFilters,
                          if (_filter != null &&
                              !_quickFilters.contains(_filter))
                            _filter,
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 7),
                            child: PharmacyFilterChip(
                              label: s == null ? 'All' : orderStatusLabel(s),
                              selected: _filter == s,
                              onTap: () {
                                setState(() => _filter = s);
                                _load();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: const [PharmacyListSkeleton(count: 5)],
                    )
                  : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: PharmacyErrorBanner(
                        message: _error!,
                        onRetry: _load,
                      ),
                    )
                  : RefreshIndicator(
                      color: PharmacyColors.green,
                      onRefresh: _load,
                      child: _orders.isEmpty
                          ? ListView(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              children: const [
                                SizedBox(height: 40),
                                PharmacyEmptyStateInline(
                                  icon: CupertinoIcons.bag,
                                  text: 'No online orders for this branch',
                                ),
                              ],
                            )
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              children: _groupedByDay(),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Orders arrive across days, and a flat run of cards gives no sense of
  /// when. A day heading every time the date changes costs one text row and
  /// makes the list scannable.
  List<Widget> _groupedByDay() {
    final widgets = <Widget>[];
    String? lastBucket;
    for (final order in _orders) {
      final bucket = _dayBucket(order['createdAt']?.toString());
      if (bucket != lastBucket) {
        widgets.add(
          Padding(
            padding: EdgeInsets.fromLTRB(2, widgets.isEmpty ? 2 : 14, 2, 8),
            child: Text(
              bucket.toUpperCase(),
              style: PharmacyType.sans(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: PharmacyColors.textTertiary,
              ),
            ),
          ),
        );
        lastBucket = bucket;
      }
      widgets.add(_orderCard(order));
    }
    return widgets;
  }

  Widget _orderCard(Map<String, dynamic> order) {
    // A waiting order is a different object from one already in flight: it
    // demands a decision, and burying that decision behind a tap is how
    // partner apps lose orders. Two card shapes, not one with a flag.
    return _isAwaitingAction(order)
        ? _newOrderCard(order)
        : _activeOrderCard(order);
  }

  /// The card for an order nobody has responded to yet.
  ///
  /// Carries the live wait time, an item preview and both decisions, so the
  /// common case — glance, accept — never leaves the list.
  Widget _newOrderCard(Map<String, dynamic> order) {
    final id = '${order['_id'] ?? ''}';
    final busy = _busy.contains(id);
    final patient = _map(order['patientId']);
    final name = patient['name']?.toString().trim();
    final display = (name == null || name.isEmpty) ? 'Customer' : name;
    final items = _maps(order['items']);
    final cod = '${order['paymentMethod']}' == 'cod';
    final paid = '${order['paymentStatus']}' == 'paid';
    final rxPending = '${order['prescriptionStatus']}' == 'pending_review';
    final waited = _waitedFor(order['createdAt']?.toString());
    // Waiting longer no longer turns the card red. The clock is the urgency
    // cue on its own; a red card in a list of green ones reads as an error,
    // not as "hurry up".
    final urgent = waited != null && waited.inMinutes >= 5;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: PharmacyColors.bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: PharmacyColors.green, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: PharmacyColors.green.withValues(alpha: 0.16),
              blurRadius: 16,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Column(
            children: [
              // The banner does the shouting: a waiting order should be
              // visible from across a counter.
              Container(
                width: double.infinity,
                color: PharmacyColors.green,
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(
                      LucideIcons.bellRing,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'NEW ORDER',
                      style: PharmacyType.sans(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    if (waited != null)
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: urgent ? 8 : 0,
                          vertical: urgent ? 3 : 0,
                        ),
                        decoration: urgent
                            ? BoxDecoration(
                                // Still green — just brighter and boxed, so a
                                // long wait reads as emphasis rather than
                                // alarm.
                                color: Colors.white.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(20),
                              )
                            : null,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.clock,
                              size: 13,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _clock(waited),
                              style: PharmacyType.number(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
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
                                display,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PharmacyType.sans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: PharmacyColors.textStrong,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${order['orderNumber'] ?? 'Order'}  ·  ${items.length} ${items.length == 1 ? 'item' : 'items'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PharmacyType.sans(
                                  fontSize: 11.5,
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
                              _rupees(order['totalAmount']),
                              style: PharmacyType.number(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                color: PharmacyColors.textStrong,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              cod
                                  ? 'Collect on delivery'
                                  : paid
                                  ? 'Paid online'
                                  : 'Payment pending',
                              style: PharmacyType.sans(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: cod && !paid
                                    ? PharmacyColors.warning
                                    : PharmacyColors.greenDark,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (items.isNotEmpty) ...[
                      const SizedBox(height: 11),
                      _itemPreview(items),
                    ],
                    if (rxPending) ...[const SizedBox(height: 10), _rxBanner()],
                  ],
                ),
              ),
              Container(height: 1, color: PharmacyColors.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
                child: Row(
                  children: [
                    Expanded(
                      child: PharmacySecondaryButton(
                        label: 'Reject',
                        color: PharmacyColors.error,
                        onPressed: busy ? null : () => _reject(order),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      flex: 2,
                      child: PharmacyButton(
                        // A prescription still under review blocks acceptance
                        // server-side, so the card sends them to review it
                        // rather than offering a button that will fail.
                        label: rxPending ? 'Review prescription' : 'Accept',
                        icon: rxPending
                            ? LucideIcons.fileText
                            : LucideIcons.check,
                        loading: busy,
                        onPressed: busy
                            ? null
                            : () => rxPending
                                  ? _openDetails(order)
                                  : _accept(order),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// First two lines of the basket. Enough to judge whether the order can be
  /// filled without opening it, which is the point.
  Widget _itemPreview(List<Map<String, dynamic>> items) {
    final shown = items.take(2).toList();
    final rest = items.length - shown.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: PharmacyColors.bgSecondary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item['medicineName'] ?? 'Medicine'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PharmacyType.sans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: PharmacyColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '×${(num.tryParse('${item['quantity'] ?? 0}') ?? 0).toInt()}',
                    style: PharmacyType.number(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: PharmacyColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          if (rest > 0)
            Text(
              '+$rest more',
              style: PharmacyType.sans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: PharmacyColors.greenDark,
              ),
            ),
        ],
      ),
    );
  }

  Widget _rxBanner() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: PharmacyColors.warningBg,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      children: [
        const Icon(
          LucideIcons.fileText,
          size: 13,
          color: PharmacyColors.warning,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Prescription needs review before this can be accepted',
            style: PharmacyType.sans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: PharmacyColors.warning,
            ),
          ),
        ),
      ],
    ),
  );

  /// Where an order sits on the fulfilment ladder, and what it looks like.
  ///
  /// `stage` is its position out of five; -1 marks a terminal state, which
  /// gets a flat treatment because there is no progress left to show.
  static ({int stage, IconData icon, Color tone}) _stageOf(String status) {
    switch (status) {
      case 'confirmed':
        return (
          stage: 1,
          icon: LucideIcons.clipboardCheck,
          tone: PharmacyColors.greenDark,
        );
      case 'packing':
        return (
          stage: 2,
          icon: LucideIcons.package,
          tone: PharmacyColors.warning,
        );
      case 'ready_to_ship':
        return (
          stage: 3,
          icon: LucideIcons.packageCheck,
          tone: PharmacyColors.info,
        );
      case 'shipped':
        return (stage: 4, icon: LucideIcons.truck, tone: PharmacyColors.info);
      case 'out_for_delivery':
        return (stage: 4, icon: LucideIcons.bike, tone: PharmacyColors.warning);
      case 'delivered':
        return (
          stage: 5,
          icon: LucideIcons.circleCheckBig,
          tone: PharmacyColors.greenDark,
        );
      case 'cancelled':
        return (stage: -1, icon: LucideIcons.ban, tone: PharmacyColors.error);
      case 'returned':
        return (stage: -1, icon: LucideIcons.undo2, tone: PharmacyColors.error);
      default:
        return (
          stage: 0,
          icon: LucideIcons.clipboardList,
          tone: PharmacyColors.textSecondary,
        );
    }
  }

  /// An order already accepted.
  ///
  /// Built to be actioned without opening: a stage header that says how long
  /// it has been sitting there, where it is going, what is in it, and the one
  /// button that moves it on.
  Widget _activeOrderCard(Map<String, dynamic> order) {
    final id = '${order['_id'] ?? ''}';
    final busy = _busy.contains(id);
    final status = order['orderStatus']?.toString() ?? 'placed';
    final patient = _map(order['patientId']);
    final name = patient['name']?.toString().trim();
    final display = (name == null || name.isEmpty) ? 'Customer' : name;
    final items = _maps(order['items']);
    final step = _nextStep(status);
    final stage = _stageOf(status);
    final terminal = stage.stage < 0;
    final done = status == 'delivered';
    final cod = '${order['paymentMethod']}' == 'cod';
    final paid = '${order['paymentStatus']}' == 'paid';

    final address = _map(order['deliveryAddress']);
    final area = [
      address['city'],
      address['pincode'],
    ].map((v) => '${v ?? ''}'.trim()).where((v) => v.isNotEmpty).join(' ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: PharmacyColors.bg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openDetails(order),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: terminal
                    ? PharmacyColors.border
                    : stage.tone.withValues(alpha: 0.3),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Column(
                children: [
                  // Stage header. Tinted rather than solid so the card still
                  // reads as calm next to the green NEW ORDER banner — an
                  // accepted order is work in hand, not an alarm.
                  Container(
                    width: double.infinity,
                    color: stage.tone.withValues(alpha: 0.1),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Row(
                      children: [
                        Icon(stage.icon, size: 14, color: stage.tone),
                        const SizedBox(width: 7),
                        Text(
                          orderStatusLabel(status).toUpperCase(),
                          style: PharmacyType.sans(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.9,
                            color: stage.tone,
                          ),
                        ),
                        const Spacer(),
                        if (!terminal && _inStageFor(order) != null)
                          Text(
                            '${_inStageFor(order)} in this stage',
                            style: PharmacyType.sans(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: stage.tone.withValues(alpha: 0.85),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
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
                                    display,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: PharmacyType.sans(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w800,
                                      color: PharmacyColors.textStrong,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${order['orderNumber'] ?? 'Order'}  ·  ${items.length} ${items.length == 1 ? 'item' : 'items'}  ·  ${_timeAgo(order['createdAt']?.toString())}',
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
                                  _rupees(order['totalAmount']),
                                  style: PharmacyType.number(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.4,
                                    color: PharmacyColors.textStrong,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  cod && !paid ? 'COD' : 'Paid',
                                  style: PharmacyType.sans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: cod && !paid
                                        ? PharmacyColors.warning
                                        : PharmacyColors.greenDark,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (area.isNotEmpty) ...[
                          const SizedBox(height: 9),
                          Row(
                            children: [
                              const Icon(
                                LucideIcons.mapPin,
                                size: 12,
                                color: PharmacyColors.textTertiary,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  area,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: PharmacyType.sans(
                                    fontSize: 11.5,
                                    color: PharmacyColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (items.isNotEmpty) ...[
                          const SizedBox(height: 9),
                          // One line, not a list: on an accepted order the
                          // contents are a reminder, not a decision.
                          Text(
                            _itemSummary(items),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PharmacyType.sans(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: PharmacyColors.textPrimary,
                            ),
                          ),
                        ],
                        if (!terminal) ...[
                          const SizedBox(height: 11),
                          _progressRail(stage.stage, stage.tone),
                        ],
                      ],
                    ),
                  ),
                  if (step != null)
                    Container(
                      color: stage.tone.withValues(alpha: 0.07),
                      padding: const EdgeInsets.fromLTRB(8, 8, 11, 9),
                      child: Row(
                        children: [
                          // The customer is one tap away at every stage —
                          // "where is my order" is the call a pharmacy gets.
                          _callButton(order),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _stepPrompt(status),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: PharmacyType.sans(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: PharmacyColors.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 36,
                            child: PharmacyButton(
                              label: step.label,
                              icon: LucideIcons.arrowRight,
                              loading: busy,
                              fullWidth: false,
                              onPressed: busy
                                  ? null
                                  : () => _act(
                                      id,
                                      () => _api.updateMerchantOrderStatus(
                                        id,
                                        step.status,
                                      ),
                                      'Moved to ${orderStatusLabel(step.status)}',
                                    ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (done)
                    Container(
                      width: double.infinity,
                      color: PharmacyColors.greenVeryLight,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            LucideIcons.circleCheckBig,
                            size: 13,
                            color: PharmacyColors.greenDark,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Delivered — settlement recorded',
                              style: PharmacyType.sans(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: PharmacyColors.greenDark,
                              ),
                            ),
                          ),
                          const Icon(
                            LucideIcons.chevronRight,
                            size: 14,
                            color: PharmacyColors.greenDark,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Calls the delivery contact. Falls back to the patient's own number when
  /// the address carries none.
  Widget _callButton(Map<String, dynamic> order) {
    final address = _map(order['deliveryAddress']);
    final patient = _map(order['patientId']);
    final phone = [
      '${address['phone'] ?? ''}',
      '${patient['phone'] ?? ''}',
    ].map((v) => v.trim()).firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (phone.isEmpty) return const SizedBox.shrink();

    return Material(
      color: PharmacyColors.bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () async {
          final uri = Uri(
            scheme: 'tel',
            path: phone.replaceAll(RegExp(r'\s'), ''),
          );
          if (!await launchUrl(uri) && mounted) {
            _toast('No dialler available', PharmacyColors.error);
          }
        },
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            LucideIcons.phone,
            size: 16,
            color: PharmacyColors.greenDark,
          ),
        ),
      ),
    );
  }

  /// "Paracetamol ×2 · Azithromycin ×1 · +2 more"
  static String _itemSummary(List<Map<String, dynamic>> items) {
    final parts = items
        .take(2)
        .map(
          (i) =>
              '${i['medicineName'] ?? 'Item'} ×${(num.tryParse('${i['quantity'] ?? 0}') ?? 0).toInt()}',
        )
        .toList();
    final rest = items.length - parts.length;
    if (rest > 0) parts.add('+$rest more');
    return parts.join('  ·  ');
  }

  /// How long the order has sat in its current stage, read from the last
  /// status-history entry. Null when there is nothing to measure.
  static String? _inStageFor(Map<String, dynamic> order) {
    final history = (order['statusHistory'] as List?)
        ?.whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (history == null || history.isEmpty) return null;
    final at = DateTime.tryParse('${history.last['at'] ?? ''}');
    if (at == null) return null;
    final d = DateTime.now().difference(at.toLocal());
    if (d.isNegative) return null;
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  /// Five segments, filled up to the current stage. Cheaper to read than a
  /// status word, and it shows what is still to come as well as what is done.
  Widget _progressRail(int stage, Color tone) => Row(
    children: [
      for (var i = 1; i <= 5; i++) ...[
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: i <= stage ? tone : PharmacyColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        if (i < 5) const SizedBox(width: 4),
      ],
    ],
  );

  /// What the pharmacy is being asked to do, phrased as the state it is in
  /// rather than repeating the button label back.
  static String _stepPrompt(String status) {
    switch (status) {
      case 'confirmed':
        return 'Accepted — ready to pick and pack';
      case 'packing':
        return 'Being packed';
      case 'ready_to_ship':
        return 'Packed and waiting for pickup';
      case 'shipped':
        return 'With the courier';
      case 'out_for_delivery':
        return 'On its way to the customer';
      default:
        return '';
    }
  }

  /// How long an order has been waiting, or null if it has no timestamp.
  static Duration? _waitedFor(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return null;
    final waited = DateTime.now().difference(d.toLocal());
    return waited.isNegative ? Duration.zero : waited;
  }

  /// mm:ss while that still means something, then whole minutes — a counter
  /// reading 184:12 is just noise.
  static String _clock(Duration d) {
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
    final m = d.inMinutes.toString().padLeft(2, '0');
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  Future<void> _openDetails(Map<String, dynamic> order) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => OrderDetailsScreen(order: order)));
    if (mounted) await _load();
  }

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  static List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];
  static final _inr = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  static String _rupees(dynamic value) =>
      _inr.format(num.tryParse(value?.toString() ?? '') ?? 0);

  static String _dayBucket(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return 'Earlier';
    final now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (days == 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 7) return DateFormat('EEEE').format(d);
    return DateFormat('d MMMM').format(d);
  }

  static String _timeAgo(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
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

/// Full status filter, presented as a bottom sheet with a single-select
/// radio list plus Clear All / Apply — the module's standard filter pattern.
class _OrderFilterSheet extends StatefulWidget {
  final String? initial;
  const _OrderFilterSheet({required this.initial});

  @override
  State<_OrderFilterSheet> createState() => _OrderFilterSheetState();
}

class _OrderFilterSheetState extends State<_OrderFilterSheet> {
  late String? _selected = widget.initial;

  Widget _statusOption(String? status) {
    final selected = _selected == status;
    final label = status == null ? 'All orders' : orderStatusLabel(status);
    return Material(
      color: selected ? PharmacyColors.greenVeryLight : PharmacyColors.bg,
      borderRadius: BorderRadius.circular(PharmacyColors.radiusInput),
      child: InkWell(
        borderRadius: BorderRadius.circular(PharmacyColors.radiusInput),
        onTap: () => setState(() => _selected = status),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PharmacyColors.radiusInput),
            border: Border.all(
              color: selected
                  ? PharmacyColors.green
                  : PharmacyColors.borderStrong,
            ),
          ),
          child: Row(
            children: [
              if (status != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: PharmacyColors.statusColors(status).$1,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  label,
                  style: PharmacyType.sans(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? PharmacyColors.greenDark
                        : PharmacyColors.textPrimary,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Filter Orders',
          style: PharmacyType.sans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: PharmacyColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Status',
          style: PharmacyType.sans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: PharmacyColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        const SizedBox(height: 8),
        // Selectable rows rather than RadioListTile: Flutter deprecated its
        // groupValue/onChanged pair, and a tinted row with a check reads the
        // same as the selected chips on the screen behind this sheet.
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final s in kOrderStatuses)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _statusOption(s),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: PharmacySecondaryButton(
                label: 'Clear All',
                onPressed: () => Navigator.of(context).pop(null),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PharmacyButton(
                label: 'Apply',
                onPressed: () => Navigator.of(context).pop(_selected),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
