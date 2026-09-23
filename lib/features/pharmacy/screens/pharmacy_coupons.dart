import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/pharmacy_type.dart';
import '../../../core/network/api_service.dart';
import '../theme/pharmacy_colors.dart';
import '../widgets/pharmacy_ui.dart';

class PharmacyCoupons extends ConsumerStatefulWidget {
  const PharmacyCoupons({super.key});
  @override
  ConsumerState<PharmacyCoupons> createState() => _PharmacyCouponsState();
}

class _PharmacyCouponsState extends ConsumerState<PharmacyCoupons> {
  bool _loading = false;
  List<Map<String, dynamic>> _coupons = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await ApiService().getMerchantCoupons();
      final d = Map<String, dynamic>.from(r.data as Map);
      if (!mounted) return;
      setState(() {
        _coupons = (d['coupons'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pharmacyErrorMessage(e, fallback: 'Couldn\'t load coupons.'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: PharmacyColors.error,
          ),
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addCoupon() async {
    final code = TextEditingController(),
        value = TextEditingController(),
        minOrder = TextEditingController();
    String type = 'percent';
    DateTime? endsAt;
    final ok = await showPharmacySheet<bool>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'New Coupon',
              style: PharmacyType.sans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: PharmacyColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PharmacyTextField(
                      label: 'Code',
                      controller: code,
                      icon: CupertinoIcons.tag,
                      required: true,
                    ),
                    PharmacyDropdownField<String>(
                      label: 'Discount Type',
                      value: type,
                      icon: CupertinoIcons.percent,
                      items: const [
                        DropdownMenuItem(
                          value: 'percent',
                          child: Text('Percentage'),
                        ),
                        DropdownMenuItem(value: 'fixed', child: Text('Fixed')),
                      ],
                      onChanged: (v) => setS(() => type = v ?? type),
                    ),
                    PharmacyTextField(
                      label: 'Discount Value',
                      controller: value,
                      icon: CupertinoIcons.money_dollar,
                      isNum: true,
                      required: true,
                    ),
                    PharmacyTextField(
                      label: 'Minimum Order',
                      controller: minOrder,
                      icon: CupertinoIcons.cart,
                      isNum: true,
                    ),
                    PharmacyPickerField(
                      label: 'Expiry Date',
                      valueText: endsAt == null
                          ? 'No expiry (runs indefinitely)'
                          : '${endsAt!.day}/${endsAt!.month}/${endsAt!.year}',
                      margin: EdgeInsets.zero,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: DateTime.now().add(
                            const Duration(days: 30),
                          ),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(
                            const Duration(days: 3650),
                          ),
                        );
                        if (picked != null) setS(() => endsAt = picked);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: PharmacySecondaryButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.pop(ctx, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PharmacyButton(
                    label: 'Create Coupon',
                    onPressed: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true || code.text.trim().isEmpty) return;
    try {
      await ApiService().createMerchantCoupon({
        'code': code.text.trim().toUpperCase(),
        'discountType': type,
        'value': double.tryParse(value.text) ?? 0,
        'minOrderAmount': double.tryParse(minOrder.text) ?? 0,
        'isActive': true,
        if (endsAt != null) 'endsAt': endsAt!.toIso8601String(),
      });
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pharmacyErrorMessage(
                e,
                fallback: 'Something went wrong. Please try again.',
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: PharmacyColors.error,
          ),
        );
    }
  }

  Future<void> _toggleCoupon(Map<String, dynamic> c, bool value) async {
    try {
      await ApiService().updateMerchantCoupon('${c['_id']}', {
        'isActive': value,
      });
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pharmacyErrorMessage(
                e,
                fallback: 'Something went wrong. Please try again.',
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: PharmacyColors.error,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PharmacyColors.bg,
      appBar: AppBar(
        backgroundColor: PharmacyColors.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: PharmacyColors.textPrimary),
        title: Text(
          'Coupons',
          style: PharmacyType.sans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: PharmacyColors.textPrimary,
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: _addCoupon,
            icon: const Icon(
              CupertinoIcons.add,
              size: 18,
              color: PharmacyColors.green,
            ),
            label: Text(
              'Add',
              style: PharmacyType.sans(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: PharmacyColors.green,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        // An AppBar already covers the status bar; this is here for
        // the bottom inset, so content and buttons clear the device
        // gesture bar.
        top: false,
        child: _loading
            ? ListView(
                padding: const EdgeInsets.all(16),
                children: const [PharmacyListSkeleton(count: 4)],
              )
            : RefreshIndicator(
                color: PharmacyColors.green,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_coupons.isEmpty)
                      const PharmacyEmptyStateInline(
                        icon: CupertinoIcons.tag,
                        text: 'No coupons configured.',
                      ),
                    ..._coupons.map((c) {
                      final discount = c['discountType'] == 'percent'
                          ? '${c['value']}% off'
                          : '₹${c['value']} off';
                      final validTill = c['endsAt'] != null
                          ? DateTime.tryParse('${c['endsAt']}')
                          : null;
                      return PharmacyCard(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${c['code'] ?? 'COUPON'}',
                                    style: PharmacyType.sans(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: PharmacyColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$discount · Min ₹${c['minOrderAmount'] ?? 0}',
                                    style: PharmacyType.sans(
                                      fontSize: 12,
                                      color: PharmacyColors.textSecondary,
                                    ),
                                  ),
                                  if (validTill != null)
                                    Text(
                                      'Valid till ${validTill.day}/${validTill.month}/${validTill.year}',
                                      style: PharmacyType.sans(
                                        fontSize: 11,
                                        color: PharmacyColors.textTertiary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            PharmacySwitch(
                              value: c['isActive'] != false,
                              onChanged: (v) => _toggleCoupon(c, v),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
      ),
    );
  }
}
