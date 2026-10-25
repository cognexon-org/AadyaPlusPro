import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/pharmacy_type.dart';
import '../theme/pharmacy_colors.dart';
import '../providers/pharmacy_profile_provider.dart';
import '../widgets/pharmacy_ui.dart';

class PharmacyCoupons extends ConsumerStatefulWidget {
  const PharmacyCoupons({super.key});
  @override
  ConsumerState<PharmacyCoupons> createState() => _PharmacyCouponsState();
}

class _PharmacyCouponsState extends ConsumerState<PharmacyCoupons> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final cached = ref.read(pharmacyProfileProvider).coupons;
      ref
          .read(pharmacyProfileProvider.notifier)
          .loadCoupons(silent: cached.isNotEmpty);
    });
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
              'New coupon',
              style: PharmacyType.sans(
                fontSize: 15,
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
                      icon: LucideIcons.tag,
                      required: true,
                    ),
                    PharmacyDropdownField<String>(
                      label: 'Discount Type',
                      value: type,
                      icon: LucideIcons.percent,
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
                      icon: LucideIcons.indianRupee,
                      isNum: true,
                      required: true,
                    ),
                    PharmacyTextField(
                      label: 'Minimum Order',
                      controller: minOrder,
                      icon: LucideIcons.shoppingCart,
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
    if (ok != true || !mounted) return;
    final amount = double.tryParse(value.text.trim()) ?? 0;
    final problem = code.text.trim().isEmpty
        ? 'Enter a coupon code.'
        : amount <= 0
        ? 'Enter a discount value above zero.'
        : type == 'percent' && amount > 100
        ? 'A percentage discount cannot be more than 100%.'
        : null;
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(problem),
          backgroundColor: PharmacyColors.warning,
        ),
      );
      return;
    }
    try {
      await ref.read(pharmacyProfileProvider.notifier).createCoupon({
        'code': code.text.trim().toUpperCase(),
        'discountType': type,
        'value': amount,
        'minOrderAmount': double.tryParse(minOrder.text) ?? 0,
        'isActive': true,
        // End of the chosen day — the picker returns midnight, which expired
        // the coupon at the very start of the day the pharmacist picked.
        if (endsAt != null)
          'endsAt': DateTime(
            endsAt!.year,
            endsAt!.month,
            endsAt!.day,
            23,
            59,
            59,
          ).toIso8601String(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Coupon created'),
            backgroundColor: PharmacyColors.success,
          ),
        );
      }
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
      await ref
          .read(pharmacyProfileProvider.notifier)
          .toggleCoupon('${c['_id']}', value);
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
    final profileState = ref.watch(pharmacyProfileProvider);
    final coupons = profileState.coupons;
    final isLoading = profileState.isCouponsLoading && coupons.isEmpty;

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
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: PharmacyColors.textPrimary,
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: _addCoupon,
            icon: const Icon(
              LucideIcons.plus,
              size: 18,
              color: PharmacyColors.green,
            ),
            label: Text(
              'Add',
              style: PharmacyType.sans(
                fontSize: 13,
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
        child: isLoading
            ? ListView(
                padding: const EdgeInsets.all(16),
                children: const [PharmacyListSkeleton(count: 4)],
              )
            : RefreshIndicator(
                color: PharmacyColors.green,
                onRefresh: () => ref
                    .read(pharmacyProfileProvider.notifier)
                    .loadCoupons(force: true),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (coupons.isEmpty)
                      const PharmacyEmptyStateInline(
                        icon: LucideIcons.tag,
                        text: 'No coupons configured.',
                      ),
                    ...coupons.indexed.map((entry) {
                      final (index, c) = entry;
                      final discount = c['discountType'] == 'percent'
                          ? '${c['value']}% off'
                          : '${pharmacyRupees(c['value'])} off';
                      final validTill = c['endsAt'] != null
                          ? DateTime.tryParse('${c['endsAt']}')
                          : null;
                      return PharmacyEntrance(
                        index: index,
                        child: PharmacyCard(
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${c['code'] ?? 'COUPON'}',
                                      style: PharmacyType.sans(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: PharmacyColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$discount · Min ${pharmacyRupees(c['minOrderAmount'])}',
                                      style: PharmacyType.sans(
                                        fontSize: 11.5,
                                        color: PharmacyColors.textSecondary,
                                      ),
                                    ),
                                    if (validTill != null)
                                      Text(
                                        'Valid till ${validTill.day}/${validTill.month}/${validTill.year}',
                                        style: PharmacyType.sans(
                                          fontSize: 11.5,
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
