import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/pharmacy_type.dart';
import '../../../core/network/api_service.dart';
import '../theme/pharmacy_colors.dart';
import '../providers/pharmacy_store_provider.dart';
import '../providers/pharmacy_orders_provider.dart';
import '../widgets/delivery_sheets.dart';
import '../widgets/order_action_sheets.dart';
import '../widgets/pharmacy_ui.dart';
import 'order_details_screen.dart';

const kOrderStatuses = <String?>[
  null,
  PharmacyOrdersNotifier.awaitingFilter,
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

/// Sentence case ("Ready to ship"), the module's label style.
String orderStatusLabel(String s) {
  if (s == PharmacyOrdersNotifier.awaitingFilter) return 'Needs action';
  // Local delivery words, not courier ones.
  const named = {
    'ready_to_ship': 'Packed',
    'shipped': 'With courier',
    'out_for_delivery': 'Out for delivery',
  };
  if (named.containsKey(s)) return named[s]!;
  final words = s.replaceAll('_', ' ').trim();
  if (words.isEmpty) return words;
  return '${words[0].toUpperCase()}${words.substring(1)}';
}

class PharmacyOrders extends ConsumerStatefulWidget {
  const PharmacyOrders({super.key});

  @override
  ConsumerState<PharmacyOrders> createState() => _PharmacyOrdersState();
}

class _PharmacyOrdersState extends ConsumerState<PharmacyOrders> {
  final _api = ApiService();
  final _search = TextEditingController();

  /// Ids currently being accepted or rejected, so a card can show its own
  /// spinner without freezing the whole list.
  final Set<String> _busy = {};

  static const _quickFilters = <String?>[
    null,
    PharmacyOrdersNotifier.awaitingFilter,
    'prescription_review',
    'placed',
    'confirmed',
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(pharmacyStoreProvider.notifier).initialize();
      if (mounted) {
        ref.read(pharmacyOrdersProvider.notifier).initialize();
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// An order the pharmacy has not yet accepted or turned down.
  ///
  /// `prescription_review` always carries a `pending_review` prescription —
  /// the backend creates it that way and flips it to `placed` on approval —
  /// so it counts as waiting too; the card offers the review instead of Accept.
  static bool _isAwaitingAction(Map<String, dynamic> order) {
    final status = '${order['orderStatus'] ?? ''}';
    return status == 'placed' || status == 'prescription_review';
  }

  /// The one action that moves this order forward, or null when it is the
  /// customer's or the courier's turn.
  static ({String status, String label})? _nextStep(String status) {
    const ladder = {
      'confirmed': ('packing', 'Start packing'),
      'packing': ('ready_to_ship', 'Mark packed'),
      'ready_to_ship': ('out_for_delivery', 'Hand to driver'),
      'shipped': ('out_for_delivery', 'Out for delivery'),
      'out_for_delivery': ('delivered', 'Mark delivered'),
    };
    final step = ladder[status];
    return step == null ? null : (status: step.$1, label: step.$2);
  }

  /// Runs one card's action and refreshes silently, keeping the spinner on that card.
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
      ref.read(pharmacyOrdersProvider.notifier).loadOrders(silent: true);
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
      builder: (_) => OrderAvailabilitySheet(
        items: items,
        orderId: id,
        customerPhone: order['deliveryAddress'] is Map
            ? '${(order['deliveryAddress'] as Map)['phone'] ?? ''}'
            : null,
      ),
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
          style: PharmacyType.sans(fontSize: 11.5, color: Colors.white),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openFilterSheet(String? currentFilter) async {
    // The choice is wrapped in a record because a bare `null` means both
    // "All orders" and "sheet dismissed" — swiping the sheet away used to
    // clear the filter.
    final result = await showPharmacySheet<({String? status})>(
      context,
      builder: (ctx) => _OrderFilterSheet(initial: currentFilter),
    );
    if (result == null || !mounted) return;
    if (result.status != currentFilter) {
      ref.read(pharmacyOrdersProvider.notifier).setFilter(result.status);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordersState = ref.watch(pharmacyOrdersProvider);
    final currentFilter = ordersState.filter;

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
                      onPressed: () => _openFilterSheet(currentFilter),
                      icon: Icon(
                        LucideIcons.slidersHorizontal,
                        color: currentFilter != null
                            ? PharmacyColors.green
                            : PharmacyColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _summaryStrip(ordersState),
                  const SizedBox(height: 12),
                  PharmacySearchField(
                    controller: _search,
                    hint: 'Search by order number...',
                    onSubmitted: () {
                      ref
                          .read(pharmacyOrdersProvider.notifier)
                          .setSearch(_search.text.trim());
                    },
                    onRefresh: () {
                      ref
                          .read(pharmacyOrdersProvider.notifier)
                          .loadOrders(silent: true);
                    },
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final s in [
                          ..._quickFilters,
                          if (currentFilter != null &&
                              !_quickFilters.contains(currentFilter))
                            currentFilter,
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 7),
                            child: PharmacyFilterChip(
                              label: s == null ? 'All' : orderStatusLabel(s),
                              selected: currentFilter == s,
                              onTap: () {
                                ref
                                    .read(pharmacyOrdersProvider.notifier)
                                    .setFilter(s);
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Two pixels, only while a chip or search is being confirmed by
            // the server — so a list that may still change never reads as
            // the final answer.
            SizedBox(
              height: 2,
              child: AnimatedOpacity(
                opacity: ordersState.isSwitching ? 1 : 0,
                duration: PharmacyMotion.fast,
                child: const LinearProgressIndicator(
                  minHeight: 2,
                  color: PharmacyColors.green,
                  backgroundColor: Colors.transparent,
                ),
              ),
            ),
            Expanded(
              child: ordersState.isLoading && ordersState.orders.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: const [PharmacyListSkeleton(count: 5)],
                    )
                  : ordersState.error != null && ordersState.orders.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: PharmacyErrorBanner(
                        message: ordersState.error!,
                        onRetry: () {
                          ref
                              .read(pharmacyOrdersProvider.notifier)
                              .loadOrders();
                        },
                      ),
                    )
                  : RefreshIndicator(
                      color: PharmacyColors.green,
                      onRefresh: () => ref
                          .read(pharmacyOrdersProvider.notifier)
                          .loadOrders(silent: true),
                      child: ordersState.orders.isEmpty
                          ? ListView(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              children: [
                                const SizedBox(height: 40),
                                PharmacyEmptyStateInline(
                                  icon: LucideIcons.shoppingBag,
                                  text: _emptyText(ordersState),
                                ),
                              ],
                            )
                          : Builder(
                              builder: (_) {
                                final rows = _groupedByDay(ordersState.orders);
                                return ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    4,
                                    16,
                                    24,
                                  ),
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  itemCount: rows.length,
                                  itemBuilder: (_, i) => rows[i],
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _emptyText(PharmacyOrdersState s) {
    if (s.searchQuery.trim().isNotEmpty) {
      return 'No orders match "${s.searchQuery.trim()}"';
    }
    if (s.filter == null) return 'No online orders for this branch yet';
    if (s.filter == PharmacyOrdersNotifier.awaitingFilter) {
      return 'Nothing needs action right now';
    }
    return 'No ${orderStatusLabel(s.filter!).toLowerCase()} orders';
  }

  /// Three live counts across the top: what is waiting on the store, what is
  /// being worked on, and what was delivered today. Tapping one filters.
  Widget _summaryStrip(PharmacyOrdersState state) {
    final waiting = state.awaitingOrders.length;
    const active = {
      'confirmed',
      'packing',
      'ready_to_ship',
      'shipped',
      'out_for_delivery',
    };
    final inProgress = state.orders
        .where((o) => active.contains('${o['orderStatus']}'))
        .length;
    final today = DateTime.now();
    final deliveredToday = state.orders.where((o) {
      if ('${o['orderStatus']}' != 'delivered') return false;
      final d = DateTime.tryParse('${o['updatedAt'] ?? ''}')?.toLocal();
      return d != null &&
          d.year == today.year &&
          d.month == today.month &&
          d.day == today.day;
    }).length;

    Widget tile(
      String label,
      int value,
      Color tone,
      Color surface,
      String? filter, {
      bool live = false,
    }) => Expanded(
      child: PharmacyPressable(
        scale: 0.96,
        onTap: () =>
            ref.read(pharmacyOrdersProvider.notifier).setFilter(filter),
        child: AnimatedContainer(
          duration: PharmacyMotion.medium,
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            // Neutral panels; the selected one gains an ink outline. Colour
            // is left to the live dot alone.
            color: PharmacyColors.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              width: 1.5,
              color: state.filter == filter && filter != null
                  ? PharmacyColors.textStrong
                  : PharmacyColors.panel,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PharmacyCountUp(
                    value: value,
                    format: (v) => '${v.round()}',
                    duration: const Duration(milliseconds: 500),
                    style: PharmacyType.number(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      color: PharmacyColors.textStrong,
                    ),
                  ),
                  const Spacer(),
                  if (live && value > 0) PharmacyPulse(color: tone, size: 6),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PharmacyType.sans(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: PharmacyColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Row(
      children: [
        tile(
          'Waiting',
          waiting,
          PharmacyColors.greenDark,
          PharmacyColors.greenVeryLight,
          // Both kinds of waiting order — new ones and ones whose
          // prescription still needs checking — so the list matches the
          // number on the tile.
          PharmacyOrdersNotifier.awaitingFilter,
          live: true,
        ),
        const SizedBox(width: 8),
        tile(
          'In progress',
          inProgress,
          PharmacyColors.info,
          PharmacyTileStyle.blue.surface,
          'confirmed',
        ),
        const SizedBox(width: 8),
        tile(
          'Delivered',
          deliveredToday,
          PharmacyColors.textSecondary,
          PharmacyColors.bgSecondary,
          'delivered',
        ),
      ],
    );
  }

  /// Orders arrive across days, and a flat run of cards gives no sense of
  /// when. A day heading every time the date changes costs one text row and
  /// makes the list scannable.
  List<Widget> _groupedByDay(List<Map<String, dynamic>> orders) {
    final widgets = <Widget>[];
    String? lastBucket;
    var n = 0;
    for (final order in orders) {
      final bucket = _dayBucket(order['createdAt']?.toString());
      if (bucket != lastBucket) {
        widgets.add(
          Padding(
            key: ValueKey('day-$bucket'),
            padding: EdgeInsets.fromLTRB(2, widgets.isEmpty ? 2 : 14, 2, 8),
            child: Text(
              bucket,
              style: PharmacyType.sans(
                fontSize: PharmacyType.small,
                fontWeight: FontWeight.w600,
                color: PharmacyColors.textSecondary,
              ),
            ),
          ),
        );
        lastBucket = bucket;
      }
      // Keyed by id so a newly arrived order slides in at the top instead of
      // every card below it re-rendering in a shifted slot.
      widgets.add(
        KeyedSubtree(
          key: ValueKey('order-${order['_id']}'),
          child: PharmacyEntrance(index: n++, child: _orderCard(order)),
        ),
      );
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
    final rxPending =
        '${order['orderStatus']}' == 'prescription_review' ||
        '${order['prescriptionStatus']}' == 'pending_review';

    // Minimal style: the same grey panel as every other card. What marks a
    // waiting order is the live dot and clock on its first line and the
    // green primary button — not a banner, glow or coloured border.
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: PharmacyColors.panel,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const PharmacyPulse(size: 7),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    rxPending ? 'New · Rx to check' : 'New order',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PharmacyType.sans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: PharmacyColors.greenDark,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _WaitClock(
                  createdAt: order['createdAt']?.toString(),
                  acceptBy: order['acceptBy']?.toString(),
                ),
              ],
            ),
            const SizedBox(height: 10),
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
                          fontWeight: FontWeight.w700,
                          color: PharmacyColors.textStrong,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${order['orderNumber'] ?? 'Order'}  ·  ${items.length} ${items.length == 1 ? 'item' : 'items'}',
                        style: PharmacyType.sans(
                          fontSize: 11.5,
                          color: PharmacyColors.textSecondary,
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
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: PharmacyColors.textStrong,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cod && !paid
                          ? 'Cash on delivery'
                          : paid
                          ? 'Paid online'
                          : 'Payment pending',
                      style: PharmacyType.sans(
                        fontSize: 11.5,
                        color: PharmacyColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 12),
              _itemPreview(items),
            ],
            if (rxPending) ...[const SizedBox(height: 10), _rxBanner()],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _quietButton(
                    'Reject',
                    busy ? null : () => _reject(order),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: PharmacyButton(
                    compact: true,
                    // A prescription still under review blocks acceptance
                    // server-side, so the card offers the review instead.
                    label: rxPending ? 'Review prescription' : 'Accept order',
                    loading: busy,
                    onPressed: busy
                        ? null
                        : () =>
                              rxPending ? _openDetails(order) : _accept(order),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// White text-button on the grey panel — the secondary action, with no
  /// outline or tint competing with the primary one.
  Widget _quietButton(String label, VoidCallback? onTap) => PharmacyPressable(
    onTap: onTap,
    scale: 0.96,
    child: Container(
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: PharmacyColors.bg,
        borderRadius: BorderRadius.circular(PharmacyColors.radiusButton),
      ),
      child: Text(
        label,
        style: PharmacyType.sans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: onTap == null
              ? PharmacyColors.textDisabled
              : PharmacyColors.textPrimary,
        ),
      ),
    ),
  );

  /// First two lines of the basket — enough to judge whether the order can
  /// be filled without opening it.
  Widget _itemPreview(List<Map<String, dynamic>> items) {
    final shown = items.take(2).toList();
    final rest = items.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${item['medicineName'] ?? 'Medicine'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PharmacyType.sans(
                      fontSize: PharmacyType.small,
                      color: PharmacyColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '×${(num.tryParse('${item['quantity'] ?? 0}') ?? 0).toInt()}',
                  style: PharmacyType.number(
                    fontSize: PharmacyType.small,
                    fontWeight: FontWeight.w600,
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
              fontSize: 11.5,
              color: PharmacyColors.textSecondary,
            ),
          ),
      ],
    );
  }

  Widget _rxBanner() => Row(
    children: [
      const Icon(LucideIcons.fileText, size: 15, color: PharmacyColors.warning),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          'Check the prescription before accepting',
          style: PharmacyType.sans(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: PharmacyColors.warning,
          ),
        ),
      ),
    ],
  );

  /// Where an order sits on the fulfilment ladder, and its tone. `stage` is
  /// its position out of five; -1 marks a terminal state.
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
          tone: PharmacyColors.greenDark,
        );
      case 'ready_to_ship':
        return (
          stage: 3,
          icon: LucideIcons.packageCheck,
          tone: PharmacyColors.greenDark,
        );
      case 'shipped':
        return (
          stage: 4,
          icon: LucideIcons.truck,
          tone: PharmacyColors.greenDark,
        );
      case 'out_for_delivery':
        return (
          stage: 4,
          icon: LucideIcons.bike,
          tone: PharmacyColors.greenDark,
        );
      case 'delivered':
        return (
          stage: 5,
          icon: LucideIcons.circleCheckBig,
          tone: PharmacyColors.textSecondary,
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

  /// An order already accepted: stage as small coloured text, a thin rail
  /// for progress, and the one button that moves it on.
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
    final cod = '${order['paymentMethod']}' == 'cod';
    final paid = '${order['paymentStatus']}' == 'paid';
    final inStage = _inStageFor(order);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PharmacyPressable(
        scale: 0.985,
        onTap: () => _openDetails(order),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: PharmacyColors.panel,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(stage.icon, size: 14, color: stage.tone),
                  const SizedBox(width: 6),
                  Text(
                    orderStatusLabel(status),
                    style: PharmacyType.sans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: stage.tone,
                    ),
                  ),
                  const Spacer(),
                  if (!terminal && inStage != null)
                    Text(
                      '$inStage in stage',
                      style: PharmacyType.sans(
                        fontSize: 11.5,
                        color: PharmacyColors.textTertiary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
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
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: PharmacyColors.textStrong,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          items.isEmpty
                              ? '${order['orderNumber'] ?? 'Order'}'
                              : _itemSummary(items),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PharmacyType.sans(
                            fontSize: 11.5,
                            color: PharmacyColors.textSecondary,
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
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: PharmacyColors.textStrong,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        cod && !paid ? 'Collect cash' : 'Paid',
                        style: PharmacyType.sans(
                          fontSize: 11.5,
                          color: cod && !paid
                              ? PharmacyColors.warning
                              : PharmacyColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (!terminal) ...[
                const SizedBox(height: 12),
                _progressRail(stage.stage, PharmacyColors.green),
              ],
              if (step != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    _callButton(order),
                    const Spacer(),
                    SizedBox(
                      height: 40,
                      child: PharmacyButton(
                        compact: true,
                        label: step.label,
                        loading: busy,
                        fullWidth: false,
                        onPressed: busy
                            ? null
                            : () async {
                                final extra = await prepareDeliveryStep(
                                  context,
                                  order,
                                  step.status,
                                );
                                if (extra == null || !mounted) return;
                                await _act(
                                  id,
                                  () => _api.updateMerchantOrderStatus(
                                    id,
                                    step.status,
                                    extra: extra,
                                  ),
                                  step.status == 'out_for_delivery'
                                      ? 'Handed to driver — customer notified'
                                      : 'Moved to ${orderStatusLabel(step.status)}',
                                );
                              },
                      ),
                    ),
                  ],
                ),
              ],
            ],
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
              color: i <= stage ? tone : PharmacyColors.bg,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        if (i < 5) const SizedBox(width: 4),
      ],
    ],
  );

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
    ).push(PharmacyPageRoute(builder: (_) => OrderDetailsScreen(order: order)));
    if (mounted) {
      ref.read(pharmacyOrdersProvider.notifier).loadOrders(silent: true);
    }
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
                    fontSize: 13,
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
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: PharmacyColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Status',
          style: PharmacyType.sans(
            fontSize: 11.5,
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
                onPressed: () => Navigator.of(context).pop((status: null)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PharmacyButton(
                label: 'Apply',
                onPressed: () => Navigator.of(context).pop((status: _selected)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The live "waiting for" clock on a new-order card. Its own widget so it
/// is the only thing that rebuilds each second — the screen used to rebuild
/// every card once a second while any order was waiting.
class _WaitClock extends StatefulWidget {
  final String? createdAt;

  /// The server's auto-reject deadline. When present the clock counts down
  /// to it; older servers that do not send it get the elapsed-time clock.
  final String? acceptBy;
  const _WaitClock({required this.createdAt, this.acceptBy});

  @override
  State<_WaitClock> createState() => _WaitClockState();
}

class _WaitClockState extends State<_WaitClock> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deadline = DateTime.tryParse(widget.acceptBy ?? '')?.toLocal();
    if (deadline != null) return _countdown(deadline);

    final waited = _PharmacyOrdersState._waitedFor(widget.createdAt);
    if (waited == null) return const SizedBox.shrink();
    // After five minutes the clock turns amber — urgency as text colour,
    // not as a red card.
    final tone = waited.inMinutes >= 5
        ? PharmacyColors.warning
        : PharmacyColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.clock, size: 13, color: tone),
        const SizedBox(width: 4),
        Text(
          _PharmacyOrdersState._clock(waited),
          style: PharmacyType.number(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: tone,
          ),
        ),
      ],
    );
  }

  /// "Auto-cancels in 7:42" — the time left before the server rejects the
  /// order for not being answered. Amber under five minutes, red under two.
  Widget _countdown(DateTime deadline) {
    final left = deadline.difference(DateTime.now());
    final over = left.isNegative;
    final tone = over || left.inMinutes < 2
        ? PharmacyColors.error
        : left.inMinutes < 5
        ? PharmacyColors.warning
        : PharmacyColors.textSecondary;
    final mm = left.inMinutes.toString();
    final ss = (left.inSeconds % 60).toString().padLeft(2, '0');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.timer, size: 13, color: tone),
        const SizedBox(width: 4),
        Text(
          over ? 'Cancelling…' : 'Cancels in $mm:$ss',
          style: PharmacyType.number(
            fontSize: PharmacyType.caption,
            fontWeight: FontWeight.w600,
            color: tone,
          ),
        ),
      ],
    );
  }
}
