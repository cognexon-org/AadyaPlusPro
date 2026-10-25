import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_service.dart';

import '../theme/pharmacy_colors.dart';
import '../theme/pharmacy_type.dart';
import 'pharmacy_ui.dart';

/// The two decisions a pharmacy makes on a new order — how much of it it can
/// supply, and why it is turning it down.
///
/// Shared so the Orders list can act on a card without opening it, and the
/// details screen can offer exactly the same flow. One copy means the two
/// cannot drift.

/// Every reason the backend accepts, in the order a pharmacist is likely to
/// need them. Keys must match `REJECTION_REASONS` in ePharmacy.controller.js.
const kOrderRejectionReasons = <String, String>{
  'out_of_stock': 'Items are out of stock',
  'store_closed': 'Store is closed right now',
  'cannot_fulfil': 'Cannot fulfil this order',
  'prescription_invalid': 'Prescription is not valid',
  'address_not_serviceable': 'Address is not serviceable',
  'other': 'Another reason',
};

/// Pick a reason, optionally add a note.
class OrderRejectReasonSheet extends StatefulWidget {
  final Map<String, String> reasons;
  const OrderRejectReasonSheet({super.key, required this.reasons});

  @override
  State<OrderRejectReasonSheet> createState() => _OrderRejectReasonSheetState();
}

class _OrderRejectReasonSheetState extends State<OrderRejectReasonSheet> {
  String? _selected;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Why are you rejecting?',
          style: PharmacyType.sans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: PharmacyColors.textStrong,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'The customer sees this, so pick the closest match.',
          style: PharmacyType.sans(
            fontSize: 11.5,
            color: PharmacyColors.textTertiary,
          ),
        ),
        const SizedBox(height: 14),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final entry in widget.reasons.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _option(entry.key, entry.value),
                  ),
                if (_selected != null) ...[
                  const SizedBox(height: 6),
                  PharmacyTextField(
                    label: 'Note (optional)',
                    controller: _note,
                    hint: 'Anything the customer should know',
                    maxLines: 2,
                    dense: true,
                    margin: EdgeInsets.zero,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: PharmacySecondaryButton(
                label: 'Back',
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PharmacyButton(
                label: 'Continue',
                onPressed: _selected == null
                    ? null
                    : () => Navigator.pop(context, {
                        'reason': _selected!,
                        'note': _note.text.trim(),
                      }),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _option(String code, String label) {
    final selected = _selected == code;
    // Selected reads as an ink outline and check on the grey panel, not a
    // red fill — the consequence is spelled out in the confirm dialog.
    return PharmacyPressable(
      scale: 0.98,
      onTap: () => setState(() => _selected = code),
      child: AnimatedContainer(
        duration: PharmacyMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: PharmacyColors.panel,
          borderRadius: BorderRadius.circular(PharmacyColors.radiusInput),
          border: Border.all(
            width: 1.5,
            color: selected ? PharmacyColors.textStrong : PharmacyColors.panel,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: PharmacyType.sans(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: PharmacyColors.textPrimary,
                ),
              ),
            ),
            if (selected)
              const Icon(
                LucideIcons.check,
                size: 16,
                color: PharmacyColors.textStrong,
              ),
          ],
        ),
      ),
    );
  }
}

/// Per-line "how many can you actually supply". Starts at the ordered
/// quantity so a full acceptance needs no adjustment at all.
///
/// With [orderId] it also asks the server what is in stock, warns on a line
/// the shelf cannot cover, and lists same-salt alternatives for it.
class OrderAvailabilitySheet extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final String? orderId;

  /// Offered as "Call customer" next to alternatives — a swap needs their OK.
  final String? customerPhone;
  const OrderAvailabilitySheet({
    super.key,
    required this.items,
    this.orderId,
    this.customerPhone,
  });

  @override
  State<OrderAvailabilitySheet> createState() => _OrderAvailabilitySheetState();
}

class _OrderAvailabilitySheetState extends State<OrderAvailabilitySheet> {
  late final Map<String, int> _supplied = {
    for (final item in widget.items)
      '${item['_id'] ?? ''}': (num.tryParse('${item['quantity'] ?? 0}') ?? 0)
          .toInt(),
  };

  int _ordered(Map<String, dynamic> item) =>
      (num.tryParse('${item['quantity'] ?? 0}') ?? 0).toInt();

  bool get _anyShort => widget.items.any(
    (item) => (_supplied['${item['_id'] ?? ''}'] ?? 0) < _ordered(item),
  );

  bool get _allZero => _supplied.values.every((v) => v == 0);

  /// medicineId -> {available, alternatives[]} from /substitutes.
  Map<String, Map<String, dynamic>> _stock = const {};
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _loadStock();
  }

  Future<void> _loadStock() async {
    final id = widget.orderId;
    if (id == null || id.isEmpty) return;
    try {
      final res = await ApiService().getOrderSubstitutes(id);
      final list = res.data is Map ? (res.data as Map)['items'] : null;
      if (list is! List || !mounted) return;
      final stock = <String, Map<String, dynamic>>{
        for (final e in list.whereType<Map>())
          '${e['medicineId']}': Map<String, dynamic>.from(e),
      };
      setState(() {
        _stock = stock;
        // Start each line at what the shelf can actually cover, so the
        // pharmacist confirms the shortfall rather than discovering it as
        // a stock error after tapping Accept.
        for (final item in widget.items) {
          final s = stock['${item['medicineId']}'];
          final available = (num.tryParse('${s?['available']}') ?? -1).toInt();
          final key = '${item['_id'] ?? ''}';
          if (available >= 0 && available < (_supplied[key] ?? 0)) {
            _supplied[key] = available;
          }
        }
      });
    } catch (_) {
      // Stock hints are a convenience; the sheet works without them.
    }
  }

  Future<void> _callCustomer() async {
    final phone = (widget.customerPhone ?? '').replaceAll(RegExp(r'\s'), '');
    if (phone.isEmpty) return;
    await launchUrl(Uri(scheme: 'tel', path: phone));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What can you supply?',
          style: PharmacyType.sans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: PharmacyColors.textStrong,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Leave as-is to accept the order in full.',
          style: PharmacyType.sans(
            fontSize: 11.5,
            color: PharmacyColors.textTertiary,
          ),
        ),
        const SizedBox(height: 14),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              children: [for (final item in widget.items) _line(item)],
            ),
          ),
        ),
        if (_allZero) ...[
          const SizedBox(height: 10),
          Text(
            'Nothing left to supply — reject the order instead.',
            style: PharmacyType.sans(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: PharmacyColors.error,
            ),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: PharmacySecondaryButton(
                label: 'Cancel',
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: PharmacyButton(
                label: _anyShort ? 'Accept with changes' : 'Accept in full',
                onPressed: _allZero
                    ? null
                    : () => Navigator.pop(context, _supplied),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _line(Map<String, dynamic> item) {
    final id = '${item['_id'] ?? ''}';
    final ordered = _ordered(item);
    final supplied = _supplied[id] ?? ordered;
    final short = supplied < ordered;
    final stock = _stock['${item['medicineId']}'];
    final available = num.tryParse('${stock?['available']}')?.toInt();
    final alternatives = ((stock?['alternatives'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final lowStock = available != null && available < ordered;
    final open = _expanded.contains(id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: PharmacyColors.panel,
          borderRadius: BorderRadius.circular(PharmacyColors.radiusInput),
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
                        '${item['medicineName'] ?? 'Medicine'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PharmacyType.sans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: PharmacyColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        [
                          short ? 'Ordered $ordered' : '$ordered ordered',
                          if (available != null)
                            available == 0
                                ? 'none in stock'
                                : '$available in stock',
                        ].join(' · '),
                        style: PharmacyType.sans(
                          fontSize: 10.5,
                          color: short || lowStock
                              ? PharmacyColors.warning
                              : PharmacyColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                _stepper(id, supplied, ordered),
              ],
            ),
            if ((short || lowStock) && alternatives.isNotEmpty) ...[
              const SizedBox(height: 6),
              InkWell(
                onTap: () => setState(
                  () => open ? _expanded.remove(id) : _expanded.add(id),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.arrowLeftRight,
                        size: 13,
                        color: PharmacyColors.greenDark,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${alternatives.length} same-salt alternative${alternatives.length == 1 ? '' : 's'} in stock',
                        style: PharmacyType.sans(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: PharmacyColors.greenDark,
                        ),
                      ),
                      Icon(
                        open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                        size: 14,
                        color: PharmacyColors.greenDark,
                      ),
                    ],
                  ),
                ),
              ),
              if (open) ...[
                for (final alt in alternatives) _alternative(alt),
                const SizedBox(height: 4),
                Text(
                  'A swap needs the customer\'s OK and isn\'t added to this order. '
                  'Agree it on a call; accept what you can supply here.',
                  style: PharmacyType.sans(
                    fontSize: 10.5,
                    height: 1.4,
                    color: PharmacyColors.textTertiary,
                  ),
                ),
                if ((widget.customerPhone ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _callCustomer,
                      style: TextButton.styleFrom(
                        foregroundColor: PharmacyColors.greenDark,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(LucideIcons.phone, size: 14),
                      label: Text(
                        'Call customer',
                        style: PharmacyType.sans(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _alternative(Map<String, dynamic> alt) {
    final notes = [
      if ('${alt['strength'] ?? ''}'.isNotEmpty) '${alt['strength']}',
      '${alt['available']} in stock',
      pharmacyRupees(alt['sellingPrice']),
    ].join(' · ');
    final differs = alt['sameStrength'] == false
        ? 'Different strength'
        : alt['sameForm'] == false
        ? 'Different form'
        : null;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: PharmacyColors.bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${alt['medicineName'] ?? 'Medicine'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PharmacyType.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: PharmacyColors.textPrimary,
                  ),
                ),
                Text(
                  notes,
                  style: PharmacyType.sans(
                    fontSize: 10.5,
                    color: PharmacyColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          if (differs != null)
            Text(
              differs,
              style: PharmacyType.sans(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: PharmacyColors.warning,
              ),
            ),
        ],
      ),
    );
  }

  Widget _stepper(String id, int supplied, int ordered) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _stepButton(
        LucideIcons.minus,
        supplied <= 0
            ? null
            : () => setState(() => _supplied[id] = supplied - 1),
      ),
      SizedBox(
        width: 34,
        child: Text(
          '$supplied',
          textAlign: TextAlign.center,
          style: PharmacyType.number(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: PharmacyColors.textStrong,
          ),
        ),
      ),
      _stepButton(
        LucideIcons.plus,
        supplied >= ordered
            ? null
            : () => setState(() => _supplied[id] = supplied + 1),
      ),
    ],
  );

  Widget _stepButton(IconData icon, VoidCallback? onTap) => Material(
    color: PharmacyColors.bg,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox(
        width: 30,
        height: 30,
        child: Icon(
          icon,
          size: 15,
          color: onTap == null
              ? PharmacyColors.textDisabled
              : PharmacyColors.textStrong,
        ),
      ),
    ),
  );
}
