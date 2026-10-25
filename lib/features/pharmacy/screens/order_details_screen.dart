import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_service.dart';
import '../theme/pharmacy_colors.dart';
import '../theme/pharmacy_type.dart';
import '../widgets/pharmacy_ui.dart';
import 'pharmacy_orders.dart' show orderStatusLabel;
import '../providers/pharmacy_orders_provider.dart';
import '../widgets/collect_payment_sheet.dart';
import '../widgets/delivery_sheets.dart';
import '../widgets/order_action_sheets.dart';
import '../widgets/prescription_review.dart';
import 'prescription_details_screen.dart';

/// Full order-detail screen, reached by tapping a row in the Orders list.
///
/// Laid out as labelled hairline groups, the same idiom as Home and the
/// settings screens, so a pharmacist reads it the way they read the rest of
/// the module: a section label, then rows.
class OrderDetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;
  const OrderDetailsScreen({super.key, required this.order});

  @override
  ConsumerState<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends ConsumerState<OrderDetailsScreen> {
  final _api = ApiService();
  final _noteController = TextEditingController();
  late Map<String, dynamic> _order = widget.order;

  /// What this order is worth to the pharmacy after the platform's cut.
  /// Returned alongside the order by GET /merchant/orders/:id.
  Map<String, dynamic> _settlement = const {};
  bool _busy = false;

  /// Opened from a notification with only an id: nothing real to paint
  /// until the fetch lands, so a skeleton shows instead of a ₹0 order.
  late bool _waiting = !_hasBody(_order);
  String? _loadError;

  static bool _hasBody(Map<String, dynamic> o) => o['items'] is List;

  /// The app usually already holds this order — from the Orders list, the
  /// live poll or an earlier visit — so use that and paint at once.
  Map<String, dynamic>? _fromMemory() {
    final s = ref.read(pharmacyOrdersProvider);
    final cached = s.orderDetailsCache[_id];
    if (cached != null && _hasBody(cached)) return cached;
    for (final list in [s.orders, s.awaitingOrders, s.allOrders]) {
      for (final o in list) {
        if ('${o['_id']}' == _id && _hasBody(o)) return o;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    if (_waiting) {
      final known = _fromMemory();
      if (known != null) {
        _order = known;
        _waiting = false;
      }
    }
    // The list hands over a summary row: no populated prescription, no
    // settlement preview, and on some endpoints no batch allocations. Without
    // this fetch the screen silently renders whatever the list happened to
    // carry, which is why the earning breakdown never appeared.
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  /// Refreshes from `GET /merchant/orders/:id`, which is the only endpoint
  /// that returns the settlement preview and the populated prescription.
  ///
  /// The screen keeps painting the row it was given while this runs, so there
  /// is no blank state — the detail simply fills in.
  Future<void> _load() async {
    if (_id.isEmpty) return;
    try {
      final res = await _api.getMerchantOrder(_id);
      final data = res.data;
      if (!mounted) return;
      setState(() {
        if (data is Map && data['order'] is Map) {
          _order = Map<String, dynamic>.from(data['order'] as Map);
        }
        if (data is Map && data['settlement'] is Map) {
          _settlement = Map<String, dynamic>.from(data['settlement'] as Map);
        }
        _waiting = !_hasBody(_order);
        _loadError = _waiting ? "Couldn't load this order." : null;
      });
      if (mounted && !_waiting) {
        ref.read(pharmacyOrdersProvider.notifier).upsertOrder(_order);
      }
    } catch (e) {
      // With a summary row on screen, keep it: everything the list gave us
      // is still valid and actionable. With nothing yet, say what failed.
      if (mounted && _waiting) {
        setState(
          () => _loadError = e is DioException
              ? _message(e)
              : "Couldn't load this order.",
        );
      }
    }
  }

  Widget _waitingBody() => SafeArea(
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      children: [
        if (_loadError == null)
          const PharmacyDetailSkeleton(rows: 7)
        else
          PharmacyErrorBanner(
            message: _loadError!,
            onRetry: () {
              setState(() => _loadError = null);
              _load();
            },
          ),
      ],
    ),
  );

  Map<String, dynamic> get _patient => _map(_order['patientId']);
  Map<String, dynamic> get _address => _map(_order['deliveryAddress']);
  Map<String, dynamic> get _tracking => _map(_order['tracking']);
  String get _status => _order['orderStatus']?.toString() ?? 'placed';
  String get _rx => _order['prescriptionStatus']?.toString() ?? 'not_required';
  String get _id => _order['_id']?.toString() ?? '';

  /// An order still awaiting the store's first verdict. `prescription_review`
  /// is included: a store can decline on sight without reviewing the
  /// prescription first, e.g. when it simply has none of the items.
  bool get _isNewOrder =>
      _status == 'placed' ||
      (_status == 'prescription_review' && _rx != 'pending_review');

  static String? _nextStatus(String status) {
    const map = {
      'confirmed': 'packing',
      'packing': 'ready_to_ship',
      'ready_to_ship': 'out_for_delivery',
      'shipped': 'out_for_delivery',
      'out_for_delivery': 'delivered',
    };
    return map[status];
  }

  // ───────────────────────────── Actions ───────────────────────────

  Future<void> _reviewRx(bool approved) async {
    final note = _noteController.text.trim();
    if (!approved) {
      if (note.isEmpty) {
        _toast(
          'A reason is required to reject a prescription',
          PharmacyColors.error,
        );
        return;
      }
      // The server cancels the order and refunds an online payment when a
      // prescription is rejected. Confirm before doing something undoable.
      final paidOnline =
          '${_order['paymentMethod']}' == 'online' &&
          '${_order['paymentStatus']}' == 'paid';
      final proceed = await PharmacyDialog.confirm(
        context,
        title: 'Reject and cancel this order?',
        message: paidOnline
            ? 'Rejecting the prescription cancels the order and refunds the customer’s online payment. This cannot be undone.'
            : 'Rejecting the prescription cancels the whole order. This cannot be undone.',
        confirmLabel: 'Reject & cancel',
        cancelLabel: 'Keep reviewing',
      );
      if (!proceed || !mounted) return;
    }
    Map<String, dynamic>? checklist;
    if (approved) {
      final rx = _map(_order['prescriptionId']);
      final doctor = _map(rx['doctorId']);
      final prescriber = doctor.isNotEmpty ? doctor : _map(rx['physioId']);
      checklist = await showPrescriptionChecklist(
        context,
        prescriberName: prescriber['name']?.toString(),
        registration: prescriber['licenseNumber']?.toString(),
        issuedOn: DateTime.tryParse('${rx['issuedAt'] ?? ''}')?.toLocal(),
      );
      if (checklist == null || !mounted) return;
    }
    await _run(
      () => _api.reviewMerchantPrescription(
        _id,
        approved: approved,
        reason: note,
        checklist: checklist,
      ),
      approved
          ? 'Prescription approved — the order can now be confirmed'
          : 'Prescription rejected. Order cancelled.',
    );
  }

  /// Asks why, then declines. The customer outcome is the same as a
  /// cancellation — the order ends and an online payment is refunded — so the
  /// consequence is spelled out before it happens.
  Future<void> _rejectOrder() async {
    final choice = await showPharmacySheet<Map<String, String>>(
      context,
      builder: (ctx) => OrderRejectReasonSheet(reasons: kOrderRejectionReasons),
    );
    if (choice == null || !mounted) return;

    final paidOnline =
        '${_order['paymentMethod']}' == 'online' &&
        '${_order['paymentStatus']}' == 'paid';
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

    await _run(
      () => _api.rejectMerchantOrder(
        _id,
        reason: choice['reason']!,
        note: choice['note'],
      ),
      'Order rejected',
    );
  }

  /// Accepting asks what can actually be supplied before allocating stock.
  ///
  /// The sheet starts with every line at the ordered quantity, so accepting in
  /// full is one tap; reducing a line shrinks the order and refunds the
  /// difference to a prepaid customer.
  Future<void> _confirmOrder() async {
    final items = _maps(_order['items']);
    final availability = await showPharmacySheet<Map<String, int>>(
      context,
      builder: (_) => OrderAvailabilitySheet(
        items: items,
        orderId: _id,
        customerPhone: '${_address['phone'] ?? _patient['phone'] ?? ''}',
      ),
    );
    if (availability == null || !mounted) return;

    final short = <String>[];
    for (final item in items) {
      final id = '${item['_id'] ?? ''}';
      final ordered = _num(item['quantity']).toInt();
      final supplied = availability[id] ?? ordered;
      if (supplied < ordered) {
        short.add('${item['medicineName'] ?? 'Item'} — $supplied of $ordered');
      }
    }

    if (short.isNotEmpty) {
      final paidOnline =
          '${_order['paymentMethod']}' == 'online' &&
          '${_order['paymentStatus']}' == 'paid';
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

    await _run(
      () => _api.confirmMerchantOrder(
        _id,
        availability: short.isEmpty ? null : availability,
      ),
      short.isEmpty
          ? 'Order confirmed and stock allocated'
          : 'Order accepted with changes',
    );
  }

  Map<String, dynamic> get _delivery => _map(_order['delivery']);

  /// Packed → hand to driver (asks who), out for delivery → delivered
  /// (confirms cash on a COD order); other steps go straight through.
  Future<void> _advance(String status) async {
    final extra = await prepareDeliveryStep(context, _order, status);
    if (extra == null || !mounted) return;
    await _run(
      () => _api.updateMerchantOrderStatus(_id, status, extra: extra),
      status == 'out_for_delivery'
          ? 'Handed to driver — customer notified'
          : status == 'delivered'
          ? 'Delivered — customer notified'
          : 'Order moved to ${orderStatusLabel(status)}',
    );
  }

  /// The driver couldn't deliver: back to packed, ready to hand over again.
  Future<void> _deliveryFailed() async {
    final reason = await askDeliveryFailure(context);
    if (reason == null || !mounted) return;
    await _run(
      () =>
          _api.updateMerchantOrderStatus(_id, 'ready_to_ship', reason: reason),
      'Back at the store — hand it over again when ready',
    );
  }

  Future<void> _run(Future<Response> Function() action, String success) async {
    if (_id.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final res = await action();
      if (!mounted) return;
      final updated = res.data;
      setState(() {
        if (updated is Map && updated['order'] is Map) {
          _order = Map<String, dynamic>.from(updated['order']);
        }
        if (updated is Map && updated['settlement'] is Map) {
          _settlement = Map<String, dynamic>.from(updated['settlement'] as Map);
        }
        _busy = false;
      });
      ref.read(pharmacyOrdersProvider.notifier).upsertOrder(_order);
      _toast(success, PharmacyColors.success);
    } catch (e) {
      // Any failure, not only a network one, must release the buttons — a
      // parsing error used to leave the screen stuck with every action off.
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(
        e is DioException
            ? _message(e)
            : pharmacyErrorMessage(e, fallback: 'Something went wrong.'),
        PharmacyColors.error,
      );
    }
  }

  /// A COD order can be settled by QR at handover instead of cash.
  Future<void> _collect() async {
    final paid = await showCollectPaymentSheet(
      context,
      orderId: _id,
      amount: _num(_order['totalAmount']),
      reference: '${_order['orderNumber'] ?? 'Order'}',
    );
    if (!paid || !mounted) return;
    try {
      final res = await _api.getMerchantOrder(_id);
      final data = res.data;
      if (!mounted) return;
      if (data is Map && data['order'] is Map) {
        setState(() {
          _order = Map<String, dynamic>.from(data['order'] as Map);
          if (data['settlement'] is Map) {
            _settlement = Map<String, dynamic>.from(data['settlement'] as Map);
          }
        });
        ref.read(pharmacyOrdersProvider.notifier).upsertOrder(_order);
      }
    } on DioException {
      // The payment landed; a failed refresh is cosmetic.
    }
  }

  /// Downloads the bill or packing slip and hands it to the share sheet,
  /// where the phone's print service, WhatsApp or a Bluetooth printer app
  /// can take it.
  bool _printing = false;
  Future<void> _sharePdf({required bool packingSlip}) async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      final res = await _api.downloadMerchantOrderPdf(
        _id,
        packingSlip: packingSlip,
      );
      final bytes = res.data;
      if (bytes == null || bytes.isEmpty) throw Exception('Empty file');
      final dir = await getTemporaryDirectory();
      final number = '${_order['orderNumber'] ?? _id}';
      final file = File(
        '${dir.path}/$number-${packingSlip ? 'packing-slip' : 'bill'}.pdf',
      );
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: packingSlip ? 'Packing slip $number' : 'Bill $number',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _toast(
        e is DioException
            ? _message(e)
            : "Couldn't prepare the ${packingSlip ? 'packing slip' : 'bill'}.",
        PharmacyColors.error,
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'\s'), ''));
    if (!await launchUrl(uri)) {
      if (mounted) _toast('No dialler available', PharmacyColors.error);
    }
  }

  void _copy(String value, String what) {
    Clipboard.setData(ClipboardData(text: value));
    _toast('$what copied', PharmacyColors.textPrimary);
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

  // ───────────────────────────── Build ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    final items = _maps(_order['items']);
    final next = _nextStatus(_status);

    return Scaffold(
      backgroundColor: PharmacyColors.bg,
      appBar: AppBar(
        backgroundColor: PharmacyColors.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: PharmacyColors.textPrimary),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _order['orderNumber']?.toString() ?? 'Order',
              style: PharmacyType.sans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: PharmacyColors.textStrong,
              ),
            ),
            Text(
              _placedAt(),
              style: PharmacyType.sans(
                fontSize: 10.5,
                color: PharmacyColors.textTertiary,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: AnimatedSwitcher(
                duration: PharmacyMotion.medium,
                transitionBuilder: (child, a) => ScaleTransition(
                  scale: Tween(begin: 0.8, end: 1.0).animate(a),
                  child: FadeTransition(opacity: a, child: child),
                ),
                // Hidden until loaded: the default would read "placed" for
                // an order that may already be packed.
                child: _waiting
                    ? const SizedBox.shrink()
                    : PharmacyStatusPill.status(
                        _status,
                        key: ValueKey(_status),
                      ),
              ),
            ),
          ),
        ],
      ),
      body: _waiting
          ? _waitingBody()
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    // Pull to refresh re-reads the order, which matters when the
                    // customer cancels or pays while this screen is open.
                    child: RefreshIndicator(
                      color: PharmacyColors.green,
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: _staggered([
                          _totalStrip(),
                          if (_stageIndex(_status) >= 0) ...[
                            const SizedBox(height: 12),
                            _progress(),
                          ],
                          const SizedBox(height: 22),
                          _label('CUSTOMER'),
                          _customerGroup(),
                          const SizedBox(height: 22),
                          _label('DELIVERY ADDRESS'),
                          _addressGroup(),
                          const SizedBox(height: 22),
                          _label('PAYMENT'),
                          _paymentGroup(),
                          // Not before acceptance: collecting money for an order the
                          // store may still reject only creates a refund.
                          if ('${_order['paymentStatus']}' != 'paid' &&
                              !_isNewOrder &&
                              _rx != 'pending_review' &&
                              ![
                                'cancelled',
                                'returned',
                                'payment_pending',
                              ].contains(_status)) ...[
                            const SizedBox(height: 10),
                            PharmacyButton(
                              label:
                                  'Collect ${_rupees(_num(_order['totalAmount']))} by UPI',
                              icon: LucideIcons.qrCode,
                              onPressed: _collect,
                            ),
                          ],
                          if ('${_delivery['driverName'] ?? ''}'
                              .isNotEmpty) ...[
                            const SizedBox(height: 22),
                            _label('DELIVERY'),
                            _deliveryGroup(),
                          ],
                          if (_tracking['trackingNumber'] != null ||
                              _tracking['carrier'] != null) ...[
                            const SizedBox(height: 22),
                            _label('SHIPMENT'),
                            _shipmentGroup(),
                          ],
                          const SizedBox(height: 22),
                          _label('ITEMS (${items.length})'),
                          _itemsGroup(items),
                          const SizedBox(height: 22),
                          _label('BILL'),
                          _billGroup(),
                          // Once accepted there is something to pack; once stock is
                          // allocated (fulfillmentSaleId) the bill is final.
                          if (!_isNewOrder &&
                              _rx != 'pending_review' &&
                              ![
                                'cancelled',
                                'payment_pending',
                              ].contains(_status)) ...[
                            const SizedBox(height: 22),
                            _label('PRINT'),
                            _printGroup(),
                          ],
                          // Nothing is earned on an order that was
                          // cancelled or sent back, so no breakdown for it.
                          if (_settlement.isNotEmpty &&
                              !['cancelled', 'returned'].contains(_status)) ...[
                            const SizedBox(height: 22),
                            _label('YOUR EARNING'),
                            _settlementGroup(),
                          ],
                          if (_order['prescriptionRequired'] == true) ...[
                            const SizedBox(height: 22),
                            _label('PRESCRIPTION'),
                            _prescriptionGroup(),
                          ],
                          if (_maps(_order['statusHistory']).isNotEmpty) ...[
                            const SizedBox(height: 22),
                            _label('TIMELINE'),
                            _timelineGroup(),
                          ],
                        ]),
                      ),
                    ),
                  ),
                  if (_rx == 'pending_review')
                    _bottomBar(
                      child: Row(
                        children: [
                          Expanded(
                            child: PharmacySecondaryButton(
                              label: 'Reject',
                              color: PharmacyColors.error,
                              onPressed: _busy ? null : () => _reviewRx(false),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: PharmacyButton(
                              label: 'Approve',
                              onPressed: _busy ? null : () => _reviewRx(true),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_isNewOrder)
                    _bottomBar(
                      // A store has to be able to say no. Before this the only
                      // options were accept, or "cancel" — which reads to the
                      // customer as backing out of an order already agreed.
                      child: Row(
                        children: [
                          Expanded(
                            child: PharmacySecondaryButton(
                              label: 'Reject',
                              color: PharmacyColors.error,
                              onPressed: _busy ? null : _rejectOrder,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: PharmacyButton(
                              label: 'Accept order',
                              icon: LucideIcons.circleCheckBig,
                              loading: _busy,
                              onPressed: _busy ? null : _confirmOrder,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_status == 'out_for_delivery')
                    _bottomBar(
                      child: Row(
                        children: [
                          Expanded(
                            child: PharmacySecondaryButton(
                              label: 'Delivery failed',
                              color: PharmacyColors.error,
                              onPressed: _busy ? null : _deliveryFailed,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: PharmacyButton(
                              label: 'Mark delivered',
                              icon: LucideIcons.circleCheckBig,
                              loading: _busy,
                              onPressed: _busy
                                  ? null
                                  : () => _advance('delivered'),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (next != null)
                    _bottomBar(
                      child: PharmacyButton(
                        label:
                            next == 'out_for_delivery' &&
                                _status == 'ready_to_ship'
                            ? 'Hand over to driver'
                            : next == 'packing'
                            ? 'Start packing'
                            : next == 'ready_to_ship'
                            ? 'Mark packed'
                            : 'Move to ${orderStatusLabel(next)}',
                        icon: next == 'out_for_delivery'
                            ? LucideIcons.bike
                            : LucideIcons.arrowRight,
                        loading: _busy,
                        onPressed: _busy ? null : () => _advance(next),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  /// Fades each top-level row in, one after another. Spacers are passed
  /// through unwrapped so they do not use up stagger slots.
  List<Widget> _staggered(List<Widget> children) {
    var i = 0;
    return [
      for (final c in children)
        c is SizedBox ? c : PharmacyEntrance(index: i++, child: c),
    ];
  }

  static const _stages = [
    ('confirmed', 'Accepted', LucideIcons.clipboardCheck),
    ('packing', 'Packing', LucideIcons.package),
    ('ready_to_ship', 'Packed', LucideIcons.packageCheck),
    ('out_for_delivery', 'On the way', LucideIcons.bike),
    ('delivered', 'Delivered', LucideIcons.circleCheckBig),
  ];

  /// Position on the fulfilment ladder; -1 for states that are not on it
  /// (waiting for acceptance, cancelled, returned).
  static int _stageIndex(String status) {
    if (status == 'shipped') return 3;
    return _stages.indexWhere((s) => s.$1 == status);
  }

  /// Five steps with a bar that fills to the current one. Rebuilt with the
  /// order, so moving it forward animates the fill to the next step.
  Widget _progress() {
    final current = _stageIndex(_status);
    final reduced = PharmacyMotion.reduced(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: PharmacyColors.panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final fraction = current / (_stages.length - 1);
              return Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: PharmacyColors.bg,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: reduced ? fraction : 0, end: fraction),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (_, f, _) => Container(
                      height: 4,
                      width: (c.maxWidth - 28) * f,
                      margin: const EdgeInsets.only(left: 14),
                      decoration: BoxDecoration(
                        color: PharmacyColors.green,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (var i = 0; i < _stages.length; i++)
                        _stageDot(i, current),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < _stages.length; i++)
                Expanded(
                  child: Text(
                    _stages[i].$2,
                    textAlign: i == 0
                        ? TextAlign.left
                        : i == _stages.length - 1
                        ? TextAlign.right
                        : TextAlign.center,
                    style: PharmacyType.sans(
                      fontSize: 10.5,
                      fontWeight: i == current
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: i <= current
                          ? PharmacyColors.textStrong
                          : PharmacyColors.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stageDot(int i, int current) {
    final done = i < current;
    final active = i == current;
    // The bounce lives on the scale only. On the decoration, `settle`
    // overshoots past 1, and lerping the glow from active to done then asks
    // for a negative blur radius — which crashed on "Delivered".
    return AnimatedScale(
      scale: active ? 1.08 : 1,
      duration: PharmacyMotion.medium,
      curve: PharmacyMotion.settle,
      child: _stageDotBody(i, done, active),
    );
  }

  Widget _stageDotBody(int i, bool done, bool active) {
    return AnimatedContainer(
      duration: PharmacyMotion.medium,
      curve: PharmacyMotion.enter,
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done || active ? PharmacyColors.green : PharmacyColors.bg,
        border: Border.all(
          color: done || active
              ? PharmacyColors.green
              : PharmacyColors.borderStrong,
          width: 2,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: PharmacyColors.green.withValues(alpha: 0.35),
                  blurRadius: 10,
                ),
              ]
            : const [],
      ),
      child: Icon(
        done ? LucideIcons.check : _stages[i].$3,
        size: 13,
        color: done || active ? Colors.white : PharmacyColors.textTertiary,
      ),
    );
  }

  // ──────────────────────────── Sections ───────────────────────────

  /// The figure the pharmacist is actually accountable for, stated once at
  /// the top instead of only appearing at the foot of the bill.
  Widget _totalStrip() {
    final total = _num(_order['totalAmount']);
    final cod = '${_order['paymentMethod']}' == 'cod';
    final paid = '${_order['paymentStatus']}' == 'paid';

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
      decoration: BoxDecoration(
        color: PharmacyColors.greenVeryLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Order value',
                  style: PharmacyType.sans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: PharmacyColors.greenDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _rupees(total),
                  style: PharmacyType.number(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1,
                    color: PharmacyColors.textStrong,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  cod && !paid
                      ? 'Collect on delivery'
                      : paid
                      ? 'Paid online'
                      : 'Payment ${_order['paymentStatus'] ?? 'pending'}',
                  style: PharmacyType.sans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
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
            child: Icon(
              cod ? LucideIcons.banknote : LucideIcons.creditCard,
              size: 20,
              color: PharmacyColors.greenDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _customerGroup() {
    final name = _patient['name']?.toString().trim();
    final display = (name == null || name.isEmpty) ? 'Customer' : name;
    final phone = _patient['phone']?.toString().trim() ?? '';
    final email = _patient['email']?.toString().trim() ?? '';

    return _group([
      Padding(
        padding: const EdgeInsets.fromLTRB(13, 13, 11, 13),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: PharmacyColors.greenLight,
                shape: BoxShape.circle,
              ),
              child: Text(
                display[0].toUpperCase(),
                style: PharmacyType.sans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: PharmacyColors.greenDark,
                ),
              ),
            ),
            const SizedBox(width: 12),
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
                  if (phone.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      phone,
                      style: PharmacyType.number(
                        fontSize: 11.5,
                        color: PharmacyColors.textSecondary,
                      ),
                    ),
                  ],
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PharmacyType.sans(
                        fontSize: 11.5,
                        color: PharmacyColors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (phone.isNotEmpty) ...[
              const SizedBox(width: 8),
              _circleAction(LucideIcons.phone, 'Call', () => _call(phone)),
            ],
          ],
        ),
      ),
    ]);
  }

  /// The address as a block of lines, not a comma-joined run-on. A courier
  /// reads this off the screen; the pincode and the contact number are the
  /// two things they need to find fast, so both get their own line.
  Widget _addressGroup() {
    final label = _address['label']?.toString().trim() ?? '';
    final contact = _address['contactName']?.toString().trim() ?? '';
    final phone = _address['phone']?.toString().trim() ?? '';
    final instructions =
        _order['deliveryInstructions']?.toString().trim() ?? '';

    final lines = [
      _address['line1'],
      _address['line2'],
      _address['landmark'],
    ].map((e) => '${e ?? ''}'.trim()).where((e) => e.isNotEmpty).toList();

    final region = [
      _address['city'],
      _address['state'],
    ].map((e) => '${e ?? ''}'.trim()).where((e) => e.isNotEmpty).join(', ');
    final pincode = '${_address['pincode'] ?? ''}'.trim();

    if (lines.isEmpty && region.isEmpty && pincode.isEmpty) {
      return _group([
        Padding(
          padding: const EdgeInsets.all(13),
          child: Text(
            'No delivery address on this order',
            style: PharmacyType.sans(
              fontSize: 11.5,
              color: PharmacyColors.textTertiary,
            ),
          ),
        ),
      ]);
    }

    return _group([
      Padding(
        padding: const EdgeInsets.fromLTRB(13, 13, 11, 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                LucideIcons.mapPin,
                size: 16,
                color: PharmacyColors.greenDark,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (label.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: PharmacyColors.bgSecondary,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: PharmacyColors.borderStrong),
                      ),
                      child: Text(
                        label.toUpperCase(),
                        style: PharmacyType.sans(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: PharmacyColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  for (final line in lines) ...[
                    Text(
                      line,
                      style: PharmacyType.sans(
                        fontSize: 12.5,
                        height: 1.45,
                        color: PharmacyColors.textPrimary,
                      ),
                    ),
                  ],
                  if (region.isNotEmpty || pincode.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (region.isNotEmpty)
                          Flexible(
                            child: Text(
                              region,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: PharmacyType.sans(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: PharmacyColors.textPrimary,
                              ),
                            ),
                          ),
                        if (pincode.isNotEmpty) ...[
                          const SizedBox(width: 7),
                          Text(
                            pincode,
                            style: PharmacyType.number(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                              color: PharmacyColors.textStrong,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _circleAction(
              LucideIcons.copy,
              'Copy address',
              () => _copy(
                [
                  ...lines,
                  region,
                  pincode,
                ].where((e) => e.isNotEmpty).join('\n'),
                'Address',
              ),
            ),
          ],
        ),
      ),
      if (contact.isNotEmpty || phone.isNotEmpty) ...[
        _hairline,
        _iconRow(
          LucideIcons.user,
          contact.isEmpty ? phone : contact,
          trailing: phone.isEmpty
              ? null
              : _circleAction(LucideIcons.phone, 'Call', () => _call(phone)),
          subtitle: contact.isNotEmpty && phone.isNotEmpty ? phone : null,
        ),
      ],
      if (instructions.isNotEmpty) ...[
        _hairline,
        _iconRow(LucideIcons.messageSquare, instructions, tone: true),
      ],
    ]);
  }

  Widget _paymentGroup() {
    final method = '${_order['paymentMethod'] ?? ''}';
    final status = '${_order['paymentStatus'] ?? 'pending'}';
    final refund = _num(_order['refundAmount']);

    Color statusTone() {
      switch (status) {
        case 'paid':
          return PharmacyColors.greenDark;
        case 'refunded':
        case 'refund_pending':
          return PharmacyColors.info;
        case 'failed':
          return PharmacyColors.error;
        default:
          return PharmacyColors.warning;
      }
    }

    return _group([
      _dataRow(
        'Method',
        method == 'cod' ? 'Cash on delivery' : 'Online payment',
      ),
      _hairline,
      _dataRow('Status', orderStatusLabel(status), valueColor: statusTone()),
      if (refund > 0) ...[
        _hairline,
        _dataRow('Refunded', _rupees(refund), valueColor: PharmacyColors.info),
      ],
    ]);
  }

  /// Who has the parcel. The call button is the whole point: when the
  /// customer rings asking where it is, the store rings the driver.
  Widget _deliveryGroup() {
    final name = '${_delivery['driverName'] ?? ''}';
    final phone = '${_delivery['driverPhone'] ?? ''}';
    final vehicle = '${_delivery['vehicleNumber'] ?? ''}'.trim();
    final at = _date(_delivery['handedOverAt']);
    final attempts = _num(_delivery['attempts']).toInt();
    final failure = '${_delivery['lastFailureReason'] ?? ''}'.trim();

    return _group([
      Padding(
        padding: const EdgeInsets.fromLTRB(13, 11, 8, 11),
        child: Row(
          children: [
            const Icon(
              LucideIcons.bike,
              size: 16,
              color: PharmacyColors.greenDark,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: PharmacyType.sans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: PharmacyColors.textPrimary,
                    ),
                  ),
                  Text(
                    [phone, if (vehicle.isNotEmpty) vehicle].join(' · '),
                    style: PharmacyType.sans(
                      fontSize: 10.5,
                      color: PharmacyColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (phone.isNotEmpty)
              IconButton(
                tooltip: 'Call driver',
                onPressed: () => _call(phone),
                icon: const Icon(
                  LucideIcons.phone,
                  size: 18,
                  color: PharmacyColors.greenDark,
                ),
              ),
          ],
        ),
      ),
      if (at != null) ...[_hairline, _dataRow('Handed over', at)],
      if (attempts > 1) ...[_hairline, _dataRow('Attempt', '$attempts')],
      if (failure.isNotEmpty && _status != 'delivered') ...[
        _hairline,
        _dataRow(
          'Last attempt failed',
          failure,
          valueColor: PharmacyColors.warning,
        ),
      ],
    ]);
  }

  Widget _shipmentGroup() {
    final carrier = '${_tracking['carrier'] ?? ''}'.trim();
    final awb = '${_tracking['trackingNumber'] ?? ''}'.trim();
    final eta = _date(_tracking['estimatedDeliveryAt']);
    final delivered = _date(_tracking['deliveredAt']);

    return _group([
      if (carrier.isNotEmpty) _dataRow('Carrier', carrier),
      if (awb.isNotEmpty) ...[
        if (carrier.isNotEmpty) _hairline,
        _dataRow(
          'Tracking number',
          awb,
          onTap: () => _copy(awb, 'Tracking number'),
          trailingIcon: LucideIcons.copy,
        ),
      ],
      if (delivered != null) ...[
        _hairline,
        _dataRow('Delivered', delivered),
      ] else if (eta != null) ...[
        _hairline,
        _dataRow('Expected by', eta),
      ],
    ]);
  }

  Widget _itemsGroup(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return _group([
        Padding(
          padding: const EdgeInsets.all(13),
          child: Text(
            'No line items on this order',
            style: PharmacyType.sans(
              fontSize: 11.5,
              color: PharmacyColors.textTertiary,
            ),
          ),
        ),
      ]);
    }

    final rows = <Widget>[];
    for (final item in items) {
      if (rows.isNotEmpty) rows.add(_hairline);
      rows.add(_itemRow(item));
    }
    return _group(rows);
  }

  Widget _itemRow(Map<String, dynamic> item) {
    final name = '${item['medicineName'] ?? 'Medicine'}';
    final ordered = _num(item['orderedQuantity']).toInt();
    final generic = '${item['genericName'] ?? ''}'.trim();
    final qty = _num(item['quantity']).toInt();
    final unitPrice = _num(item['unitPrice']);
    final unit = '${item['unit'] ?? ''}'.trim();
    final rxRequired = item['prescriptionRequired'] == true;

    final meta = [
      '$qty × ${_rupees(unitPrice)}',
      if (unit.isNotEmpty) unit,
      if (generic.isNotEmpty) generic,
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: PharmacyColors.greenVeryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              // Category picks the icon; the unit ("strip", "bottle") is not
              // a category and always fell through to the generic pill.
              medicineCategoryIcon(
                '${item['category'] ?? (item['medicineId'] is Map ? item['medicineId']['category'] : '') ?? ''}',
              ),
              size: 16,
              color: PharmacyColors.greenDark,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PharmacyType.sans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: PharmacyColors.textPrimary,
                        ),
                      ),
                    ),
                    if (rxRequired) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: PharmacyColors.warningBg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Rx',
                          style: PharmacyType.sans(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: PharmacyColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PharmacyType.sans(
                    fontSize: 11.5,
                    color: PharmacyColors.textTertiary,
                  ),
                ),
                // Only set when the pharmacy supplied less than was ordered.
                if (ordered > qty) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Short supplied — $qty of $ordered ordered',
                    style: PharmacyType.sans(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: PharmacyColors.warning,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _rupees(_num(item['totalAmount'])),
            style: PharmacyType.number(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: PharmacyColors.textStrong,
            ),
          ),
        ],
      ),
    );
  }

  /// Every line the backend actually stores. The old screen showed only item
  /// total, delivery fee and grand total, so discounts and tax were invisible
  /// and the figures did not add up on screen.
  Widget _billGroup() {
    final subtotal = _num(_order['subtotal']);
    final medDiscount = _num(_order['medicineDiscount']);
    final coupon = _num(_order['couponDiscount']);
    final couponCode = '${_order['couponCode'] ?? ''}'.trim();
    final tax = _num(_order['tax']);
    final delivery = _num(_order['deliveryFee']);
    final total = _num(_order['totalAmount']);

    return _group([
      _dataRow('Subtotal', _rupees(subtotal)),
      if (medDiscount > 0) ...[
        _hairline,
        _dataRow(
          'Medicine discount',
          '−${_rupees(medDiscount)}',
          valueColor: PharmacyColors.greenDark,
        ),
      ],
      if (coupon > 0) ...[
        _hairline,
        _dataRow(
          couponCode.isEmpty ? 'Coupon' : 'Coupon · $couponCode',
          '−${_rupees(coupon)}',
          valueColor: PharmacyColors.greenDark,
        ),
      ],
      if (tax > 0) ...[_hairline, _dataRow('Tax (GST)', _rupees(tax))],
      _hairline,
      _dataRow(
        'Delivery fee',
        delivery > 0 ? _rupees(delivery) : 'Free',
        valueColor: delivery > 0 ? null : PharmacyColors.greenDark,
      ),
      _hairline,
      Container(
        color: PharmacyColors.bgSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Total',
                style: PharmacyType.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: PharmacyColors.textStrong,
                ),
              ),
            ),
            Text(
              _rupees(total),
              style: PharmacyType.number(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: PharmacyColors.textStrong,
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _printGroup() {
    final billReady = _order['fulfillmentSaleId'] != null;
    Widget row(IconData icon, String title, String sub, VoidCallback? onTap) =>
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 12, 11, 12),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: onTap == null
                        ? PharmacyColors.textDisabled
                        : PharmacyColors.greenDark,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: PharmacyType.sans(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: onTap == null
                                ? PharmacyColors.textTertiary
                                : PharmacyColors.textPrimary,
                          ),
                        ),
                        Text(
                          sub,
                          style: PharmacyType.sans(
                            fontSize: 10.5,
                            color: PharmacyColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_printing)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: PharmacyColors.green,
                      ),
                    )
                  else
                    const Icon(
                      LucideIcons.share2,
                      size: 15,
                      color: PharmacyColors.textDisabled,
                    ),
                ],
              ),
            ),
          ),
        );

    return _group([
      row(
        LucideIcons.package,
        'Packing slip',
        'Items with tick boxes, address and amount to collect',
        _printing ? null : () => _sharePdf(packingSlip: true),
      ),
      _hairline,
      row(
        LucideIcons.receiptText,
        'Customer bill',
        billReady
            ? 'GST invoice to put in the bag'
            : 'Available once stock is allocated',
        !billReady || _printing ? null : () => _sharePdf(packingSlip: false),
      ),
    ]);
  }

  /// The platform's cut on this order, and what is left for the pharmacy.
  ///
  /// Shown on every order rather than only delivered ones, so the split is
  /// known *before* accepting rather than discovered after the fact.
  Widget _settlementGroup() {
    final gross = _num(_settlement['commissionableAmount']);
    final rate = _num(_settlement['commissionRate']);
    final fee = _num(_settlement['platformCommission']);
    final earning = _num(_settlement['pharmacyEarning']);
    final excluded = _map(_settlement['excluded']);
    final tax = _num(excluded['tax']);
    final delivery = _num(excluded['deliveryFee']);
    final delivered = _status == 'delivered';

    return _group([
      _dataRow('Medicines (after discounts)', _rupees(gross)),
      _hairline,
      _dataRow(
        'Aadya Plus commission (${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 1)}%)',
        '−${_rupees(fee)}',
        valueColor: PharmacyColors.error,
      ),
      _hairline,
      Container(
        color: PharmacyColors.greenVeryLight,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                delivered ? 'Settled to you' : 'You will receive',
                style: PharmacyType.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: PharmacyColors.textStrong,
                ),
              ),
            ),
            Text(
              _rupees(earning),
              style: PharmacyType.number(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: PharmacyColors.greenDark,
              ),
            ),
          ],
        ),
      ),
      _hairline,
      // Without this the pharmacy would read the order total, read this
      // figure, and reasonably conclude the platform was taking far more.
      _iconRow(
        LucideIcons.circleAlert,
        'Commission is charged on medicines only. '
        '${tax > 0 ? 'GST of ${_rupees(tax)} ' : ''}'
        '${tax > 0 && delivery > 0 ? 'and ' : ''}'
        '${delivery > 0 ? '${tax > 0 ? 'the' : 'The'} ${_rupees(delivery)} delivery fee ' : ''}'
        '${tax > 0 && delivery > 0
            ? 'are excluded from it.'
            : tax > 0 || delivery > 0
            ? 'is excluded from it.'
            : 'Tax and delivery are excluded from it.'}'
        '${delivered ? '' : ' Settled once the order is delivered.'}',
        tone: true,
      ),
    ]);
  }

  Widget _prescriptionGroup() {
    final uploadId = _order['prescriptionUploadId'];
    final notes = '${_order['prescriptionReviewNotes'] ?? ''}'.trim();

    (Color, Color, String) tone() {
      switch (_rx) {
        case 'approved':
          return (
            PharmacyColors.greenDark,
            PharmacyColors.greenVeryLight,
            'Approved',
          );
        case 'rejected':
          return (PharmacyColors.error, PharmacyColors.errorBg, 'Rejected');
        case 'pending_review':
          return (
            PharmacyColors.warning,
            PharmacyColors.warningBg,
            'Awaiting review',
          );
        default:
          return (
            PharmacyColors.textSecondary,
            PharmacyColors.bgSecondary,
            'Not required',
          );
      }
    }

    final (fg, bg, text) = tone();

    return _group([
      Padding(
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
        child: Row(
          children: [
            Icon(LucideIcons.fileText, size: 16, color: fg),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                'Prescription',
                style: PharmacyType.sans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: PharmacyColors.textPrimary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                text,
                style: PharmacyType.sans(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
      if (notes.isNotEmpty) ...[
        _hairline,
        _iconRow(LucideIcons.messageSquare, notes, tone: true),
      ],
      _hairline,
      // Opens the full prescription: patient, prescriber, what was written,
      // and the uploaded scan. Reachable from here as well as from the
      // Prescription Queue, because a pharmacist checking an order should
      // not have to go hunting for the prescription behind it.
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            await Navigator.of(context).push(
              PharmacyPageRoute(
                builder: (_) => PrescriptionDetailsScreen(order: _order),
              ),
            );
            if (mounted) setState(() {});
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 12, 11, 12),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.scanEye,
                  size: 16,
                  color: PharmacyColors.greenDark,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    uploadId == null
                        ? 'View prescription details'
                        : 'View prescription & uploaded scan',
                    style: PharmacyType.sans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: PharmacyColors.textPrimary,
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
      ),
      if (uploadId == null) ...[
        _hairline,
        _iconRow(
          LucideIcons.circleAlert,
          'No scan was uploaded — the customer linked a prescription issued in the app, or none was attached.',
          tone: true,
        ),
      ],
      if (_rx == 'pending_review') ...[
        _hairline,
        Padding(
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
          child: PharmacyTextField(
            label: 'Review note',
            controller: _noteController,
            hint: 'Required when rejecting',
            maxLines: 3,
            dense: true,
            margin: EdgeInsets.zero,
          ),
        ),
      ],
    ]);
  }

  Widget _timelineGroup() {
    final history = _maps(_order['statusHistory']).reversed.toList();
    return _group([
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 13, 13),
        child: Column(
          children: [
            for (var i = 0; i < history.length; i++)
              _timelineRow(
                history[i],
                first: i == 0,
                last: i == history.length - 1,
              ),
          ],
        ),
      ),
    ]);
  }

  Widget _timelineRow(
    Map<String, dynamic> entry, {
    required bool first,
    required bool last,
  }) {
    final status = '${entry['status'] ?? ''}';
    final note = '${entry['note'] ?? ''}'.trim();
    final at = _date(entry['at']);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: first
                      ? PharmacyColors.green
                      : PharmacyColors.borderStrong,
                  shape: BoxShape.circle,
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(width: 1.5, color: PharmacyColors.border),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          orderStatusLabel(status),
                          style: PharmacyType.sans(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: first
                                ? PharmacyColors.textStrong
                                : PharmacyColors.textSecondary,
                          ),
                        ),
                      ),
                      if (at != null)
                        Text(
                          at,
                          style: PharmacyType.sans(
                            fontSize: 10.5,
                            color: PharmacyColors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      note,
                      style: PharmacyType.sans(
                        fontSize: 11.5,
                        height: 1.4,
                        color: PharmacyColors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────── Shared chrome ────────────────────────

  Widget _label(String text) => PharmacySectionTitle(text);

  Widget _group(List<Widget> children) => PharmacyGroup(children: children);

  static Widget get _hairline => const PharmacyHairline();

  Widget _circleAction(IconData icon, String tooltip, VoidCallback onTap) =>
      Tooltip(
        message: tooltip,
        child: Material(
          color: PharmacyColors.bg,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 34,
              height: 34,
              child: Icon(icon, size: 16, color: PharmacyColors.greenDark),
            ),
          ),
        ),
      );

  Widget _iconRow(
    IconData icon,
    String text, {
    String? subtitle,
    Widget? trailing,
    bool tone = false,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(13, 11, 11, 11),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: PharmacyColors.textTertiary),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: PharmacyType.sans(
                  fontSize: tone ? 11.5 : 12.5,
                  height: 1.4,
                  fontWeight: tone ? FontWeight.w400 : FontWeight.w600,
                  color: tone
                      ? PharmacyColors.textSecondary
                      : PharmacyColors.textPrimary,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: PharmacyType.number(
                    fontSize: 11.5,
                    color: PharmacyColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    ),
  );

  Widget _dataRow(
    String label,
    String value, {
    Color? valueColor,
    VoidCallback? onTap,
    IconData? trailingIcon,
  }) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PharmacyType.sans(
                fontSize: 11.5,
                color: PharmacyColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: PharmacyType.number(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: valueColor ?? PharmacyColors.textStrong,
              ),
            ),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: 7),
            Icon(trailingIcon, size: 13, color: PharmacyColors.textTertiary),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: row),
    );
  }

  Widget _bottomBar({required Widget child}) => PharmacyEntrance(
    delay: const Duration(milliseconds: 200),
    offsetY: 40,
    child: _bottomBarBody(child),
  );

  Widget _bottomBarBody(Widget child) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: const BoxDecoration(
      color: PharmacyColors.bg,
      border: Border(top: BorderSide(color: PharmacyColors.borderStrong)),
    ),
    child: SafeArea(top: false, child: child),
  );

  // ───────────────────────────── Helpers ───────────────────────────

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  static double _num(dynamic value) =>
      num.tryParse('${value ?? 0}')?.toDouble() ?? 0;

  static final _inr = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  static String _rupees(double value) => _inr.format(value);

  static String? _date(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    if (d == null) return null;
    return DateFormat('d MMM, h:mm a').format(d.toLocal());
  }

  String _placedAt() {
    final d = DateTime.tryParse('${_order['createdAt'] ?? ''}');
    if (d == null) return '';
    final diff = DateTime.now().difference(d.toLocal());
    if (diff.inMinutes < 60) return 'Placed ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Placed ${diff.inHours}h ago';
    return 'Placed ${DateFormat('d MMM, h:mm a').format(d.toLocal())}';
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
