import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_service.dart';
import '../theme/pharmacy_colors.dart';
import '../theme/pharmacy_type.dart';
import '../widgets/pharmacy_ui.dart';
import 'pharmacy_orders.dart' show orderStatusLabel;
import '../widgets/collect_payment_sheet.dart';
import '../widgets/order_action_sheets.dart';
import 'prescription_details_screen.dart';

/// Full order-detail screen, reached by tapping a row in the Orders list.
///
/// Laid out as labelled hairline groups, the same idiom as Home and the
/// settings screens, so a pharmacist reads it the way they read the rest of
/// the module: a section label, then rows.
class OrderDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> order;
  const OrderDetailsScreen({super.key, required this.order});

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  final _api = ApiService();
  final _noteController = TextEditingController();
  late Map<String, dynamic> _order = widget.order;

  /// What this order is worth to the pharmacy after the platform's cut.
  /// Returned alongside the order by GET /merchant/orders/:id.
  Map<String, dynamic> _settlement = const {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
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
      });
    } on DioException {
      // Keep the summary row rather than replacing the screen with an error:
      // everything the list gave us is still valid and still actionable.
    }
  }

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
      'ready_to_ship': 'shipped',
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
    await _run(
      () => _api.reviewMerchantPrescription(
        _id,
        approved: approved,
        reason: note,
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
      builder: (_) => OrderAvailabilitySheet(items: items),
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

  Future<void> _advance(String status) async => _run(
    () => _api.updateMerchantOrderStatus(_id, status),
    'Order moved to ${orderStatusLabel(status)}',
  );

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
      _toast(success, PharmacyColors.success);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(_message(e), PharmacyColors.error);
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
      }
    } on DioException {
      // The payment landed; a failed refresh is cosmetic.
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
          style: PharmacyType.sans(fontSize: 12.5, color: Colors.white),
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
                fontSize: 15,
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
            child: Center(child: PharmacyStatusPill.status(_status)),
          ),
        ],
      ),
      body: SafeArea(
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
                  children: [
                    _totalStrip(),
                    const SizedBox(height: 22),
                    _label('CUSTOMER'),
                    _customerGroup(),
                    const SizedBox(height: 22),
                    _label('DELIVERY ADDRESS'),
                    _addressGroup(),
                    const SizedBox(height: 22),
                    _label('PAYMENT'),
                    _paymentGroup(),
                    if ('${_order['paymentStatus']}' != 'paid' &&
                        !['cancelled', 'returned'].contains(_status)) ...[
                      const SizedBox(height: 10),
                      PharmacyButton(
                        label:
                            'Collect ${_rupees(_num(_order['totalAmount']))} by UPI',
                        icon: LucideIcons.qrCode,
                        onPressed: _collect,
                      ),
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
                    if (_settlement.isNotEmpty) ...[
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
                  ],
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
            else if (next != null)
              _bottomBar(
                child: PharmacyButton(
                  label: 'Move to ${orderStatusLabel(next)}',
                  icon: LucideIcons.arrowRight,
                  loading: _busy,
                  onPressed: _busy ? null : () => _advance(next),
                ),
              ),
          ],
        ),
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
        border: Border.all(color: PharmacyColors.greenLight),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ORDER VALUE',
                  style: PharmacyType.sans(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    color: PharmacyColors.greenDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _rupees(total),
                  style: PharmacyType.number(
                    fontSize: 26,
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
                  fontSize: 16,
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
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: PharmacyColors.textStrong,
                    ),
                  ),
                  if (phone.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      phone,
                      style: PharmacyType.number(
                        fontSize: 12.5,
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
              fontSize: 12.5,
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
                          fontSize: 9,
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
                        fontSize: 13,
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
                                fontSize: 13,
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
                              fontSize: 13,
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
      _dataRow('Status', status.replaceAll('_', ' '), valueColor: statusTone()),
      if (refund > 0) ...[
        _hairline,
        _dataRow('Refunded', _rupees(refund), valueColor: PharmacyColors.info),
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
              fontSize: 12.5,
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
              medicineCategoryIcon(unit.isEmpty ? null : unit),
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
                          fontSize: 13,
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
                            fontSize: 9,
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
                    fontSize: 11,
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
              fontSize: 13,
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
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: PharmacyColors.textStrong,
                ),
              ),
            ),
            Text(
              _rupees(total),
              style: PharmacyType.number(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: PharmacyColors.textStrong,
              ),
            ),
          ],
        ),
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
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: PharmacyColors.textStrong,
                ),
              ),
            ),
            Text(
              _rupees(earning),
              style: PharmacyType.number(
                fontSize: 16,
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
        '${delivery > 0 ? 'the ${_rupees(delivery)} delivery fee ' : ''}'
        '${tax > 0 || delivery > 0 ? 'are excluded from it.' : 'Tax and delivery are excluded from it.'}'
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
                  fontSize: 13,
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
        color: PharmacyColors.bg,
        child: InkWell(
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
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
                      fontSize: 13,
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
                            fontSize: 12.5,
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

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 0, 2, 9),
    child: Text(
      text,
      style: PharmacyType.sans(
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
        color: PharmacyColors.textTertiary,
      ),
    ),
  );

  Widget _group(List<Widget> children) => Container(
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

  Widget _circleAction(IconData icon, String tooltip, VoidCallback onTap) =>
      Tooltip(
        message: tooltip,
        child: Material(
          color: PharmacyColors.greenVeryLight,
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
                fontSize: 12.5,
                color: PharmacyColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: PharmacyType.number(
                fontSize: 12.5,
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
    if (onTap == null) return Container(color: PharmacyColors.bg, child: row);
    return Material(
      color: PharmacyColors.bg,
      child: InkWell(onTap: onTap, child: row),
    );
  }

  Widget _bottomBar({required Widget child}) => Container(
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
