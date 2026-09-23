import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/network/api_service.dart';
import '../theme/pharmacy_colors.dart';
import '../theme/pharmacy_type.dart';
import 'pharmacy_ui.dart';

/// Collects a counter payment by showing the customer a Razorpay UPI QR.
///
/// Opened for a counter sale with a balance, or an unpaid online order. Poll
/// rather than push: the server reconciles with Razorpay on every status call,
/// so this settles correctly on installs where the Razorpay webhook is not
/// configured — which is the state of most deployments until the webhook
/// secret is set.
///
/// Returns true if the payment completed while the sheet was open, so the
/// caller can refresh the record it came from.
Future<bool> showCollectPaymentSheet(
  BuildContext context, {
  String? saleId,
  String? orderId,
  required double amount,
  required String reference,
}) async {
  final paid = await showPharmacySheet<bool>(
    context,
    builder: (_) => _CollectPaymentSheet(
      saleId: saleId,
      orderId: orderId,
      amount: amount,
      reference: reference,
    ),
  );
  return paid == true;
}

class _CollectPaymentSheet extends StatefulWidget {
  final String? saleId;
  final String? orderId;
  final double amount;
  final String reference;

  const _CollectPaymentSheet({
    this.saleId,
    this.orderId,
    required this.amount,
    required this.reference,
  });

  @override
  State<_CollectPaymentSheet> createState() => _CollectPaymentSheetState();
}

class _CollectPaymentSheetState extends State<_CollectPaymentSheet> {
  final _api = ApiService();
  Timer? _poll;

  Map<String, dynamic> _payment = const {};
  bool _creating = true;
  bool _closing = false;
  String? _error;

  String get _status => '${_payment['status'] ?? 'created'}';
  String get _id => '${_payment['_id'] ?? ''}';
  bool get _isPaid => _status == 'paid';

  @override
  void initState() {
    super.initState();
    Future.microtask(_create);
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final res = await _api.createCounterPaymentQr(
        saleId: widget.saleId,
        orderId: widget.orderId,
      );
      final data = res.data;
      if (!mounted) return;
      setState(() {
        _payment = data is Map && data['counterPayment'] is Map
            ? Map<String, dynamic>.from(data['counterPayment'] as Map)
            : const {};
        _creating = false;
      });
      if (_isPaid) return;
      _startPolling();
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = _message(e);
      });
    }
  }

  /// Three seconds is a compromise: fast enough that the customer is not left
  /// holding a phone wondering, slow enough that a till left open on this
  /// sheet is not hammering the server.
  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_id.isEmpty || !mounted) return;
    try {
      final res = await _api.getCounterPayment(_id);
      final data = res.data;
      if (!mounted) return;
      final next = data is Map && data['counterPayment'] is Map
          ? Map<String, dynamic>.from(data['counterPayment'] as Map)
          : const <String, dynamic>{};
      if (next.isEmpty) return;
      setState(() => _payment = next);
      if (_status != 'created') _poll?.cancel();
    } on DioException {
      // A dropped poll is not worth surfacing — the next tick retries.
    }
  }

  Future<void> _cancel() async {
    if (_id.isEmpty) {
      if (mounted) Navigator.pop(context, false);
      return;
    }
    setState(() => _closing = true);
    try {
      await _api.closeCounterPayment(_id);
    } on DioException {
      // Closing is best-effort; the QR expires on its own regardless.
    }
    _poll?.cancel();
    if (mounted) Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isPaid ? 'Payment received' : 'Collect payment',
                    style: PharmacyType.sans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: PharmacyColors.textStrong,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.reference,
                    style: PharmacyType.sans(
                      fontSize: 11.5,
                      color: PharmacyColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              _rupees(widget.amount),
              style: PharmacyType.number(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: PharmacyColors.textStrong,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_error != null)
          PharmacyErrorBanner(message: _error!, onRetry: _create)
        else if (_creating)
          _placeholder(
            const PharmacyShimmer(
              child: PharmacySkeletonBlock(height: 200, radius: 14),
            ),
          )
        else if (_isPaid)
          _paidPanel()
        else
          _qrPanel(),
        const SizedBox(height: 16),
        if (_isPaid)
          PharmacyButton(
            label: 'Done',
            icon: LucideIcons.circleCheckBig,
            onPressed: () => Navigator.pop(context, true),
          )
        else
          Row(
            children: [
              Expanded(
                child: PharmacySecondaryButton(
                  label: _closing ? 'Cancelling…' : 'Cancel',
                  onPressed: _closing ? null : _cancel,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PharmacySecondaryButton(
                  label: 'Check now',
                  icon: LucideIcons.refreshCw,
                  onPressed: _creating || _id.isEmpty ? null : _refresh,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _placeholder(Widget child) =>
      SizedBox(height: 200, width: double.infinity, child: child);

  Widget _qrPanel() {
    final image = '${_payment['qrImageUrl'] ?? ''}';
    final expired = _status == 'expired' || _status == 'closed';

    if (expired) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: PharmacyTileStyle.amber.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: PharmacyTileStyle.amber.border),
        ),
        child: Column(
          children: [
            const Icon(
              LucideIcons.clock,
              size: 24,
              color: PharmacyColors.warning,
            ),
            const SizedBox(height: 10),
            Text(
              _status == 'closed'
                  ? 'This QR was cancelled.'
                  : 'This QR expired before it was paid.',
              textAlign: TextAlign.center,
              style: PharmacyType.sans(
                fontSize: 12.5,
                color: PharmacyColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            PharmacySecondaryButton(
              label: 'Raise a new QR',
              onPressed: _create,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: PharmacyColors.borderStrong),
          ),
          child: Column(
            children: [
              if (image.isEmpty)
                _placeholder(const Center(child: Text('QR image unavailable')))
              else
                // Razorpay serves the QR image on a public URL, so no auth
                // header is needed here.
                Image.network(
                  image,
                  height: 210,
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : const SizedBox(
                          height: 210,
                          child: Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: PharmacyColors.green,
                            ),
                          ),
                        ),
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: 210,
                    child: Center(child: Text('Could not load the QR image')),
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                'Ask the customer to scan with any UPI app',
                style: PharmacyType.sans(
                  fontSize: 11.5,
                  color: PharmacyColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                color: PharmacyColors.green,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'Waiting for payment…',
                style: PharmacyType.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: PharmacyColors.textSecondary,
                ),
              ),
            ),
            if (_expiryLabel() != null)
              Text(
                _expiryLabel()!,
                style: PharmacyType.sans(
                  fontSize: 11,
                  color: PharmacyColors.textTertiary,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _paidPanel() {
    final paise = num.tryParse('${_payment['amountPaidPaise'] ?? 0}') ?? 0;
    final vpa = '${_payment['payerVpa'] ?? ''}'.trim();
    final ref = '${_payment['razorpayPaymentId'] ?? ''}'.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: PharmacyColors.greenVeryLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PharmacyColors.greenLight),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: PharmacyColors.greenLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              LucideIcons.circleCheckBig,
              size: 26,
              color: PharmacyColors.greenDark,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${_rupees(paise / 100)} received',
            style: PharmacyType.number(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: PharmacyColors.textStrong,
            ),
          ),
          if (vpa.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'from $vpa',
              style: PharmacyType.sans(
                fontSize: 12,
                color: PharmacyColors.textSecondary,
              ),
            ),
          ],
          if (ref.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              ref,
              style: PharmacyType.number(
                fontSize: 10.5,
                color: PharmacyColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? _expiryLabel() {
    final closeBy = DateTime.tryParse('${_payment['closeBy'] ?? ''}');
    if (closeBy == null) return null;
    final left = closeBy.difference(DateTime.now());
    if (left.isNegative) return 'expired';
    return 'valid ${left.inMinutes + 1} min';
  }

  static final _inr = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  static String _rupees(num value) => _inr.format(value);

  static String _message(DioException e) {
    final d = e.response?.data;
    if (d is Map) {
      return d['message']?.toString() ??
          d['error']?.toString() ??
          'Could not start the payment';
    }
    return e.message ?? 'Could not start the payment';
  }
}
