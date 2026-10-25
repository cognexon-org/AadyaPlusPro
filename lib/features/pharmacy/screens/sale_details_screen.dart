import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_service.dart';
import '../theme/pharmacy_colors.dart';
import '../theme/pharmacy_type.dart';
import '../widgets/collect_payment_sheet.dart';
import '../widgets/pharmacy_ui.dart';

/// A single counter sale (POS bill), opened from Home's Recent Bills or from
/// anywhere else a sale row is tapped.
///
/// The list row only carries what the dashboard endpoint returns, so this
/// screen refetches the sale by id: only `GET /sales/:id` populates the line
/// items, their batch allocations, the cashier, and any returns booked
/// against the bill.
class SaleDetailsScreen extends StatefulWidget {
  /// The row as the list already knows it — used to paint the screen
  /// immediately while the full record loads.
  final Map<String, dynamic> sale;

  const SaleDetailsScreen({super.key, required this.sale});

  @override
  State<SaleDetailsScreen> createState() => _SaleDetailsScreenState();
}

class _SaleDetailsScreenState extends State<SaleDetailsScreen> {
  final _api = ApiService();
  late Map<String, dynamic> _sale = widget.sale;
  List<Map<String, dynamic>> _returns = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  String get _id => _sale['_id']?.toString() ?? '';

  Future<void> _load() async {
    if (_id.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'This bill has no id, so it cannot be opened.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.getPharmacySaleById(_id);
      final data = response.data;
      if (!mounted) return;
      setState(() {
        if (data is Map && data['sale'] is Map) {
          _sale = Map<String, dynamic>.from(data['sale'] as Map);
        }
        _returns = _maps(data is Map ? data['returns'] : null);
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

  // ───────────────────────────── Build ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    final items = _maps(_sale['items']);
    final status = '${_sale['status'] ?? 'dispensed'}';

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
              _billNumber(),
              style: PharmacyType.sans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: PharmacyColors.textStrong,
              ),
            ),
            Text(
              _soldAt(),
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
            child: Center(child: PharmacyStatusPill.status(status)),
          ),
        ],
      ),
      body: SafeArea(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: PharmacyErrorBanner(message: _error!, onRetry: _load),
              )
            : RefreshIndicator(
                color: PharmacyColors.green,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                  children: [
                    _amountStrip(),
                    const SizedBox(height: 22),
                    _label('CUSTOMER'),
                    _customerGroup(),
                    const SizedBox(height: 22),
                    _label('PAYMENT'),
                    _paymentGroup(),
                    const SizedBox(height: 22),
                    if (_loading && items.isEmpty) ...[
                      const PharmacyListSkeleton(count: 3),
                    ] else ...[
                      _label('ITEMS (${items.length})'),
                      _itemsGroup(items),
                    ],
                    const SizedBox(height: 22),
                    _label('BILL'),
                    _billGroup(),
                    if (_returns.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      _label('RETURNS (${_returns.length})'),
                      _returnsGroup(),
                    ],
                    const SizedBox(height: 22),
                    _label('RECORD'),
                    _recordGroup(),
                    // Walk-in counter collection commented out with the POS
                    // side; the sheet and endpoint remain for order use.
                    // if (_num(_sale['balanceAmount']) > 0) ...[
                    //   const SizedBox(height: 22),
                    //   PharmacyButton(
                    //     label:
                    //         'Collect ${_rupees(_num(_sale['balanceAmount']))} by UPI',
                    //     icon: LucideIcons.qrCode,
                    //     onPressed: _collect,
                    //   ),
                    // ],
                  ],
                ),
              ),
      ),
    );
  }

  // ──────────────────────────── Sections ───────────────────────────

  Widget _amountStrip() {
    final total = _num(_sale['totalAmount']);
    final returned = _num(_sale['returnedAmount']);
    final net = total - returned;
    final balance = _num(_sale['balanceAmount']);
    final profit = _num(_sale['grossProfit']);

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
                      returned > 0 ? 'NET OF RETURNS' : 'BILL TOTAL',
                      style: PharmacyType.sans(
                        fontSize: 10.5,
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
                        _rupees(net),
                        maxLines: 1,
                        style: PharmacyType.number(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                          height: 1,
                          color: PharmacyColors.textStrong,
                        ),
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
                  LucideIcons.receiptText,
                  size: 20,
                  color: PharmacyColors.greenDark,
                ),
              ),
            ],
          ),
          if (balance > 0 || profit != 0 || returned > 0) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: PharmacyColors.greenLight),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                if (returned > 0) _miniStat('Returned', _rupees(returned)),
                if (balance > 0)
                  _miniStat(
                    'Balance due',
                    _rupees(balance),
                    tone: PharmacyColors.warning,
                  ),
                if (profit != 0) _miniStat('Gross profit', _rupees(profit)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, {Color? tone}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        label,
        style: PharmacyType.sans(
          fontSize: 10.5,
          color: PharmacyColors.textSecondary,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: PharmacyType.number(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: tone ?? PharmacyColors.textStrong,
        ),
      ),
    ],
  );

  Widget _customerGroup() {
    final patient = _map(_sale['patientId']);
    final name = [_sale['customerName'], patient['name']]
        .map((e) => '${e ?? ''}'.trim())
        .firstWhere((e) => e.isNotEmpty, orElse: () => '');
    final display = name.isEmpty ? 'Walk-in customer' : name;
    final phone = [_sale['customerPhone'], patient['phone']]
        .map((e) => '${e ?? ''}'.trim())
        .firstWhere((e) => e.isNotEmpty, orElse: () => '');
    final type = '${_sale['customerType'] ?? ''}'.trim();
    final doctor = '${_sale['prescribingDoctor'] ?? ''}'.trim();
    final rxNumber = '${_sale['prescriptionNumber'] ?? ''}'.trim();

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
                  ] else if (type.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      type.replaceAll('_', ' '),
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
      if (doctor.isNotEmpty) ...[_hairline, _dataRow('Prescribed by', doctor)],
      if (rxNumber.isNotEmpty) ...[
        _hairline,
        _dataRow('Prescription no.', rxNumber),
      ],
    ]);
  }

  Widget _paymentGroup() {
    final method = '${_sale['paymentMethod'] ?? ''}'.trim();
    final status = '${_sale['paymentStatus'] ?? 'pending'}';
    final paid = _num(_sale['paidAmount']);
    final balance = _num(_sale['balanceAmount']);
    final reference = '${_sale['paymentReference'] ?? ''}'.trim();

    Color tone() {
      switch (status) {
        case 'paid':
          return PharmacyColors.greenDark;
        case 'refunded':
          return PharmacyColors.info;
        case 'partial':
          return PharmacyColors.warning;
        default:
          return PharmacyColors.warning;
      }
    }

    return _group([
      _dataRow('Method', method.isEmpty ? 'Not recorded' : _titleCase(method)),
      _hairline,
      _dataRow('Status', status.replaceAll('_', ' '), valueColor: tone()),
      _hairline,
      _dataRow('Paid', _rupees(paid)),
      if (balance > 0) ...[
        _hairline,
        _dataRow(
          'Balance due',
          _rupees(balance),
          valueColor: PharmacyColors.warning,
        ),
      ],
      if (reference.isNotEmpty) ...[
        _hairline,
        _dataRow(
          'Reference',
          reference,
          onTap: () => _copy(reference, 'Reference'),
          trailingIcon: LucideIcons.copy,
        ),
      ],
    ]);
  }

  Widget _itemsGroup(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return _group([
        Padding(
          padding: const EdgeInsets.all(13),
          child: Text(
            'No line items recorded on this bill',
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
    final generic = '${item['genericName'] ?? ''}'.trim();
    final unit = '${item['unit'] ?? ''}'.trim();
    final qty = _num(item['quantity']).toInt();
    final price = _num(item['sellingPrice']);
    final returned = _num(item['returnedQuantity']).toInt();
    final batches = _maps(item['batchAllocations']);
    final batchNumbers = batches
        .map((b) => '${_map(b['batchId'])['batchNumber'] ?? ''}'.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final meta = [
      '$qty × ${_rupees(price)}',
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
                // Which batch left the shelf is the part a pharmacist needs
                // when a customer comes back about a strip.
                if (batchNumbers.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      for (final b in batchNumbers)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: PharmacyColors.bgSecondary,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: PharmacyColors.borderStrong,
                            ),
                          ),
                          child: Text(
                            b,
                            style: PharmacyType.number(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: PharmacyColors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                if (returned > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '$returned returned',
                    style: PharmacyType.sans(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: PharmacyColors.error,
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

  Widget _billGroup() {
    final subtotal = _num(_sale['subtotal']);
    final discount = _num(_sale['discount']);
    final tax = _num(_sale['tax']);
    final cgst = _num(_sale['cgst']);
    final sgst = _num(_sale['sgst']);
    final igst = _num(_sale['igst']);
    final roundOff = _num(_sale['roundOff']);
    final total = _num(_sale['totalAmount']);

    return _group([
      _dataRow('Subtotal', _rupees(subtotal)),
      if (discount > 0) ...[
        _hairline,
        _dataRow(
          'Discount',
          '−${_rupees(discount)}',
          valueColor: PharmacyColors.greenDark,
        ),
      ],
      if (cgst > 0 || sgst > 0) ...[
        _hairline,
        _dataRow('CGST', _rupees(cgst)),
        _hairline,
        _dataRow('SGST', _rupees(sgst)),
      ] else if (igst > 0) ...[
        _hairline,
        _dataRow('IGST', _rupees(igst)),
      ] else if (tax > 0) ...[
        _hairline,
        _dataRow('Tax', _rupees(tax)),
      ],
      if (roundOff != 0) ...[
        _hairline,
        _dataRow(
          'Round off',
          '${roundOff > 0 ? '+' : '−'}${_rupees(roundOff.abs())}',
        ),
      ],
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

  Widget _returnsGroup() {
    final rows = <Widget>[];
    for (final r in _returns) {
      if (rows.isNotEmpty) rows.add(_hairline);
      final reason = '${r['reason'] ?? ''}'.trim();
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  LucideIcons.undo2,
                  size: 15,
                  color: PharmacyColors.error,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r['returnNumber'] ?? 'Return'}',
                      style: PharmacyType.sans(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: PharmacyColors.textPrimary,
                      ),
                    ),
                    if (reason.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        reason,
                        style: PharmacyType.sans(
                          fontSize: 11.5,
                          color: PharmacyColors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '−${_rupees(_num(r['refundAmount'] ?? r['totalAmount']))}',
                style: PharmacyType.number(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: PharmacyColors.error,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return _group(rows);
  }

  Widget _recordGroup() {
    final cashier = _map(_sale['createdBy'])['name']?.toString().trim() ?? '';
    final dispenser =
        _map(_sale['dispensedBy'])['name']?.toString().trim() ?? '';
    final invoice = '${_sale['invoiceNumber'] ?? ''}'.trim();
    final notes = '${_sale['notes'] ?? ''}'.trim();
    final dispensedAt = _date(_sale['dispensedAt']);

    return _group([
      _dataRow(
        'Bill number',
        _billNumber(),
        onTap: () => _copy(_billNumber(), 'Bill number'),
        trailingIcon: LucideIcons.copy,
      ),
      if (invoice.isNotEmpty && invoice != _billNumber()) ...[
        _hairline,
        _dataRow('Invoice number', invoice),
      ],
      _hairline,
      _dataRow('Sold on', _date(_sale['saleDate']) ?? _soldAt()),
      if (dispensedAt != null) ...[
        _hairline,
        _dataRow('Dispensed', dispensedAt),
      ],
      if (cashier.isNotEmpty) ...[_hairline, _dataRow('Billed by', cashier)],
      if (dispenser.isNotEmpty && dispenser != cashier) ...[
        _hairline,
        _dataRow('Dispensed by', dispenser),
      ],
      if (notes.isNotEmpty) ...[
        _hairline,
        Padding(
          padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  LucideIcons.messageSquare,
                  size: 15,
                  color: PharmacyColors.textTertiary,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  notes,
                  style: PharmacyType.sans(
                    fontSize: 11.5,
                    height: 1.4,
                    color: PharmacyColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ]);
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

  /// Raises a UPI QR for the balance and reloads the bill once it is paid.
  Future<void> _collect() async {
    final paid = await showCollectPaymentSheet(
      context,
      saleId: _id,
      amount: _num(_sale['balanceAmount']),
      reference: _billNumber(),
    );
    if (paid && mounted) await _load();
  }

  // ──────────────────────────── Actions ────────────────────────────

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

  // ───────────────────────────── Helpers ───────────────────────────

  String _billNumber() =>
      _sale['invoiceNumber']?.toString() ??
      _sale['saleNumber']?.toString() ??
      'Bill';

  String _soldAt() {
    final d = DateTime.tryParse(
      '${_sale['saleDate'] ?? _sale['createdAt'] ?? ''}',
    );
    if (d == null) return '';
    return DateFormat('d MMM yyyy, h:mm a').format(d.toLocal());
  }

  static String _titleCase(String value) =>
      value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

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
