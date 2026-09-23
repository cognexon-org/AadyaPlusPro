import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../auth/models/user_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/pharmacy_store_provider.dart';
import '../theme/pharmacy_colors.dart';
import '../theme/pharmacy_type.dart';
import '../widgets/pharmacy_ui.dart';
import 'pharmacy_edit_profile.dart';
import 'pharmacy_inventory_ops.dart';
import 'pharmacy_online_settings.dart';
import 'pharmacy_procurement.dart';
import 'prescription_queue.dart';

class PharmacyProfile extends ConsumerWidget {
  const PharmacyProfile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final storeState = ref.watch(pharmacyStoreProvider);
    final store = storeState.selectedStore ?? const <String, dynamic>{};

    return Scaffold(
      backgroundColor: PharmacyColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            const PharmacyScreenHeader(
              title: 'Profile',
              subtitle: 'Branch profile & management tools',
            ),
            const SizedBox(height: 18),
            _identityCard(context, store, storeState, user),
            const SizedBox(height: 22),
            _label('MANAGEMENT'),
            _group([
              _tile(
                context,
                LucideIcons.truck,
                'Procurement & GRN',
                'Suppliers, purchase orders and receiving',
                const PharmacyProcurement(),
              ),
              _hairline,
              // Inter-store transfers only mean something to a pharmacy
              // running more than one branch, and every account on the
              // platform is currently single-branch. Screen kept, tile off.
              // _tile(
              //   context,
              //   LucideIcons.repeat2,
              //   'Transfers & Returns',
              //   'Inter-store transfers and sales returns',
              //   const PharmacyInventoryOps(),
              // ),
              // _hairline,
              _tile(
                context,
                LucideIcons.fileStack,
                'Prescription Queue',
                'Review prescription-required online orders',
                const PrescriptionQueue(),
              ),
              _hairline,
              _tile(
                context,
                LucideIcons.globe,
                'Online Store',
                'Serviceability, delivery settings and coupons',
                const PharmacyOnlineSettings(),
              ),
            ]),
            if (storeState.stores.length > 1) ...[
              const SizedBox(height: 22),
              _label('BRANCH'),
              _group([
                Padding(
                  padding: const EdgeInsets.all(13),
                  child: const PharmacyStoreSelector(),
                ),
              ]),
            ],
            const SizedBox(height: 26),
            PharmacySecondaryButton(
              label: 'Logout',
              icon: LucideIcons.logOut,
              color: PharmacyColors.error,
              onPressed: () => ref.read(authProvider.notifier).logout(),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────── Identity card ──────────────────────────

  /// The branch's own record: who this store is, and the numbers a regulator
  /// or a supplier would ask for.
  ///
  /// The licence, GSTIN and phone are a hairline-ruled label/value table
  /// rather than sentences with a leading icon. These are reference numbers —
  /// they get read off the screen and typed into something else, so they need
  /// a fixed place on the row, not a position that shifts with the length of
  /// the label beside them. A missing one says "Not set" in amber instead of
  /// hiding the row, because a pharmacy without a drug licence on file is a
  /// thing to fix, not a thing to leave blank.
  Widget _identityCard(
    BuildContext context,
    Map<String, dynamic> store,
    PharmacyStoreState storeState,
    UserModel? user,
  ) {
    final address = Map<String, dynamic>.from(
      (store['address'] as Map?) ?? const {},
    );
    final addressText = [
      address['street'],
      address['city'],
      address['state'],
      address['pincode'],
    ].where((v) => v != null && '$v'.trim().isNotEmpty).join(', ');

    final code = '${store['code'] ?? ''}'.trim();
    final licence =
        '${store['drugLicenseNumber'] ?? store['licenseNumber'] ?? ''}'.trim();
    final gstin = '${store['gstin'] ?? ''}'.trim();
    final phone = '${store['phone'] ?? user?.phone ?? ''}'.trim();
    final email = '${store['email'] ?? user?.email ?? ''}'.trim();

    // Not `_group`: that idiom is a white panel with slate hairlines, and this
    // card is the brand-green one. It keeps the same radius and row rhythm so
    // it still reads as part of the same set.
    return Container(
      decoration: BoxDecoration(
        color: PharmacyColors.green,
        borderRadius: BorderRadius.circular(13),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.32),
                          ),
                        ),
                        child: const Icon(
                          LucideIcons.store,
                          size: 21,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${store['name'] ?? user?.name ?? 'Pharmacy'}',
                              style: PharmacyType.sans(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                                color: Colors.white,
                              ),
                            ),
                            if (addressText.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2),
                                    child: Icon(
                                      LucideIcons.mapPin,
                                      size: 12,
                                      color: Color(0xCCFFFFFF),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      addressText,
                                      style: PharmacyType.sans(
                                        fontSize: 12,
                                        height: 1.4,
                                        color: Colors.white.withValues(
                                          alpha: 0.85,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      _editButton(context),
                    ],
                  ),
                  const SizedBox(height: 11),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _verificationPill(user?.verificationStatus),
                      // The branch code ("MAIN") only tells branches apart, so it
                      // is clutter until there is more than one.
                      if (storeState.stores.length > 1 && code.isNotEmpty)
                        _pill(
                          code,
                          Colors.white,
                          Colors.white.withValues(alpha: 0.18),
                          Colors.white.withValues(alpha: 0.3),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            _onGreenHairline,
            _dataRow(LucideIcons.fileText, 'Drug licence', licence),
            _onGreenHairline,
            _dataRow(LucideIcons.receipt, 'GSTIN', gstin),
            if (phone.isNotEmpty) ...[
              _onGreenHairline,
              _dataRow(LucideIcons.phone, 'Phone', phone),
            ],
            if (email.isNotEmpty) ...[
              _onGreenHairline,
              _dataRow(LucideIcons.building2, 'Email', email),
            ],
          ],
        ),
      ),
    );
  }

  /// Divider for the green card — a white wash, since a slate hairline
  /// disappears against the fill.
  static Widget get _onGreenHairline =>
      Container(height: 1, color: Colors.white.withValues(alpha: 0.16));

  Widget _editButton(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: 0.18),
    borderRadius: BorderRadius.circular(9),
    child: InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const PharmacyEditProfile())),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.pencil, size: 12, color: Colors.white),
            const SizedBox(width: 5),
            Text(
              'Edit',
              style: PharmacyType.sans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _verificationPill(VerificationStatus? status) {
    switch (status) {
      case VerificationStatus.approved:
        return _pill(
          'Verified',
          PharmacyColors.greenDark,
          Colors.white,
          Colors.white,
          icon: LucideIcons.badgeCheck,
        );
      case VerificationStatus.rejected:
        return _pill(
          'Verification rejected',
          PharmacyColors.error,
          PharmacyColors.errorBg,
          PharmacyColors.errorBg,
          icon: LucideIcons.circleAlert,
        );
      case VerificationStatus.suspended:
        return _pill(
          'Suspended',
          PharmacyColors.error,
          PharmacyColors.errorBg,
          PharmacyColors.errorBg,
          icon: LucideIcons.circleAlert,
        );
      case VerificationStatus.pending:
        return _pill(
          'Verification pending',
          PharmacyColors.warning,
          PharmacyColors.warningBg,
          PharmacyColors.warningBg,
          icon: LucideIcons.hourglass,
        );
      case null:
        // Status not loaded yet — better to show nothing than to assert a
        // state we have not actually read.
        return const SizedBox.shrink();
    }
  }

  Widget _pill(
    String text,
    Color fg,
    Color bg,
    Color border, {
    IconData? icon,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 5),
        ],
        Text(
          text,
          style: PharmacyType.sans(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: fg,
          ),
        ),
      ],
    ),
  );

  Widget _dataRow(IconData icon, String label, String value) {
    final missing = value.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.7)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: PharmacyType.sans(
                fontSize: 12.5,
                color: Colors.white.withValues(alpha: 0.78),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              missing ? 'Not set' : value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: PharmacyType.number(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                // Amber-200, not the slate-page amber: the darker one is
                // invisible against the green fill.
                color: missing ? const Color(0xFFFDE68A) : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────── Section chrome ───────────────────────

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

  Widget _tile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    Widget page,
  ) => Material(
    color: PharmacyColors.bg,
    child: InkWell(
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 11, 12),
        child: Row(
          children: [
            Icon(icon, size: 17, color: PharmacyColors.greenDark),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: PharmacyType.sans(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: PharmacyColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: PharmacyType.sans(
                      fontSize: 11,
                      color: PharmacyColors.textTertiary,
                    ),
                  ),
                ],
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
  );
}
