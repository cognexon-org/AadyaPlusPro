import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/network/api_service.dart';
import '../theme/pharmacy_colors.dart';
import '../theme/pharmacy_type.dart';
import 'pharmacy_ui.dart';

/// The delivery half of an order's life, for stores that deliver with their
/// own driver: packed → handed to a driver → delivered, or back to the store
/// after a failed attempt. Shared by the Orders list and the details screen
/// so both ask for exactly the same thing.

/// Extra request body for moving [order] to [target], after asking whatever
/// that step needs. Null means the user backed out.
Future<Map<String, dynamic>?> prepareDeliveryStep(
  BuildContext context,
  Map<String, dynamic> order,
  String target,
) async {
  final from = '${order['orderStatus']}';
  if (target == 'out_for_delivery' && from == 'ready_to_ship') {
    final driver = await showPharmacySheet<Map<String, String>>(
      context,
      builder: (_) => const _HandoverSheet(),
    );
    return driver == null ? null : {'driver': driver};
  }
  if (target == 'delivered') {
    final cod =
        '${order['paymentMethod']}' == 'cod' &&
        '${order['paymentStatus']}' != 'paid';
    final ok = await PharmacyDialog.confirm(
      context,
      title: cod ? 'Cash collected?' : 'Mark as delivered?',
      message: cod
          ? 'Confirm the driver collected ${pharmacyRupees(order['totalAmount'])} '
                'in cash. The order is marked paid and delivered.'
          : 'The customer is told their order has arrived.',
      confirmLabel: cod ? 'Yes, collected' : 'Delivered',
      cancelLabel: 'Back',
      destructive: false,
    );
    return ok ? const {} : null;
  }
  return const {};
}

/// Asks why a delivery failed. Returns the reason, or null if backed out.
Future<String?> askDeliveryFailure(BuildContext context) =>
    showPharmacySheet<String>(
      context,
      builder: (_) => const _DeliveryFailedSheet(),
    );

class _HandoverSheet extends StatefulWidget {
  const _HandoverSheet();

  @override
  State<_HandoverSheet> createState() => _HandoverSheetState();
}

class _HandoverSheetState extends State<_HandoverSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _vehicle = TextEditingController();
  List<Map<String, dynamic>> _recent = const [];

  @override
  void initState() {
    super.initState();
    _name.addListener(_changed);
    _phone.addListener(_changed);
    _loadRecent();
  }

  void _changed() => setState(() {});

  Future<void> _loadRecent() async {
    try {
      final res = await ApiService().getRecentDrivers();
      final list = res.data is Map ? (res.data as Map)['drivers'] : null;
      if (!mounted || list is! List) return;
      setState(
        () => _recent = list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
      );
    } catch (_) {
      // Typing the driver in still works.
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _vehicle.dispose();
    super.dispose();
  }

  String get _digits => _phone.text.replaceAll(RegExp(r'\D'), '');
  bool get _valid =>
      _name.text.trim().isNotEmpty && RegExp(r'^[6-9]\d{9}$').hasMatch(_digits);

  void _pick(Map<String, dynamic> d) {
    _name.text = '${d['name'] ?? ''}';
    _phone.text = '${d['phone'] ?? ''}';
    _vehicle.text = '${d['vehicleNumber'] ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hand over to driver',
            style: PharmacyType.sans(
              fontSize: PharmacyType.title,
              fontWeight: FontWeight.w700,
              color: PharmacyColors.textStrong,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'The customer gets the driver’s name and number, so they know who is coming.',
            style: PharmacyType.sans(
              fontSize: PharmacyType.caption,
              color: PharmacyColors.textTertiary,
            ),
          ),
          if (_recent.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Recent drivers',
              style: PharmacyType.sans(
                fontSize: PharmacyType.caption,
                fontWeight: FontWeight.w600,
                color: PharmacyColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final d in _recent)
                  PharmacyFilterChip(
                    label: '${d['name']}',
                    selected: _digits == '${d['phone']}',
                    onTap: () => _pick(d),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          PharmacyTextField(
            label: 'Driver name',
            controller: _name,
            icon: LucideIcons.user,
            required: true,
            dense: true,
            textCapitalization: TextCapitalization.words,
            margin: const EdgeInsets.only(bottom: 12),
          ),
          PharmacyTextField(
            label: 'Mobile number',
            controller: _phone,
            icon: LucideIcons.phone,
            isNum: true,
            required: true,
            dense: true,
            hint: '10-digit number',
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            margin: const EdgeInsets.only(bottom: 12),
          ),
          PharmacyTextField(
            label: 'Vehicle number',
            controller: _vehicle,
            icon: LucideIcons.bike,
            hint: 'Optional',
            dense: true,
            textCapitalization: TextCapitalization.characters,
            margin: EdgeInsets.zero,
          ),
          const SizedBox(height: 18),
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
                  label: 'Hand over',
                  icon: LucideIcons.bike,
                  onPressed: !_valid
                      ? null
                      : () => Navigator.pop(context, {
                          'name': _name.text.trim(),
                          'phone': _digits,
                          if (_vehicle.text.trim().isNotEmpty)
                            'vehicleNumber': _vehicle.text.trim(),
                        }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeliveryFailedSheet extends StatefulWidget {
  const _DeliveryFailedSheet();

  @override
  State<_DeliveryFailedSheet> createState() => _DeliveryFailedSheetState();
}

class _DeliveryFailedSheetState extends State<_DeliveryFailedSheet> {
  static const _reasons = [
    'Customer not at home',
    'Couldn’t reach the customer',
    'Wrong or incomplete address',
    'Customer refused the order',
  ];
  String? _picked;
  final _other = TextEditingController();

  @override
  void initState() {
    super.initState();
    _other.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  String get _reason =>
      _picked == 'other' ? _other.text.trim() : (_picked ?? '');

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Delivery failed',
            style: PharmacyType.sans(
              fontSize: PharmacyType.title,
              fontWeight: FontWeight.w700,
              color: PharmacyColors.textStrong,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'The order comes back as packed, ready to hand over again. The customer is told why.',
            style: PharmacyType.sans(
              fontSize: PharmacyType.caption,
              color: PharmacyColors.textTertiary,
            ),
          ),
          const SizedBox(height: 14),
          for (final r in [..._reasons, 'other'])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: PharmacyFilterChip(
                block: true,
                label: r == 'other' ? 'Another reason' : r,
                selected: _picked == r,
                onTap: () => setState(() => _picked = r),
              ),
            ),
          if (_picked == 'other') ...[
            const SizedBox(height: 6),
            PharmacyTextField(
              label: 'Reason',
              controller: _other,
              dense: true,
              textCapitalization: TextCapitalization.sentences,
              margin: EdgeInsets.zero,
            ),
          ],
          const SizedBox(height: 16),
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
                flex: 2,
                child: PharmacyButton(
                  label: 'Bring back to store',
                  onPressed: _reason.isEmpty
                      ? null
                      : () => Navigator.pop(context, _reason),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
