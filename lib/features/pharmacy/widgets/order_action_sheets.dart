import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
            fontSize: 16,
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
    return Material(
      color: selected ? PharmacyColors.errorBg : PharmacyColors.bg,
      borderRadius: BorderRadius.circular(PharmacyColors.radiusInput),
      child: InkWell(
        borderRadius: BorderRadius.circular(PharmacyColors.radiusInput),
        onTap: () => setState(() => _selected = code),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PharmacyColors.radiusInput),
            border: Border.all(
              color: selected
                  ? PharmacyColors.error
                  : PharmacyColors.borderStrong,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: PharmacyType.sans(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? PharmacyColors.error
                        : PharmacyColors.textPrimary,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  LucideIcons.check,
                  size: 16,
                  color: PharmacyColors.error,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Per-line "how many can you actually supply". Starts at the ordered
/// quantity so a full acceptance needs no adjustment at all.
class OrderAvailabilitySheet extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  const OrderAvailabilitySheet({super.key, required this.items});

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

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What can you supply?',
          style: PharmacyType.sans(
            fontSize: 16,
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: short ? PharmacyTileStyle.amber.surface : PharmacyColors.bg,
          borderRadius: BorderRadius.circular(PharmacyColors.radiusInput),
          border: Border.all(
            color: short
                ? PharmacyTileStyle.amber.border
                : PharmacyColors.borderStrong,
          ),
        ),
        child: Row(
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
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: PharmacyColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    short ? 'Ordered $ordered' : '$ordered ordered',
                    style: PharmacyType.sans(
                      fontSize: 10.5,
                      color: short
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
            fontSize: 14,
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
    color: onTap == null
        ? PharmacyColors.bgSecondary
        : PharmacyColors.greenVeryLight,
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
              : PharmacyColors.greenDark,
        ),
      ),
    ),
  );
}
