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
import 'pharmacy_online_settings.dart';
import 'pharmacy_procurement.dart';
import '../providers/pharmacy_profile_provider.dart';
import 'prescription_queue.dart';
import 'schedule_register_screen.dart';

class PharmacyProfile extends ConsumerWidget {
  const PharmacyProfile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final storeState = ref.watch(pharmacyStoreProvider);
    final profileState = ref.watch(pharmacyProfileProvider);
    final store = storeState.selectedStore ?? const <String, dynamic>{};
    final profile = profileState.profile;

    if (profileState.loadedStoreId == null && !profileState.isProfileLoading) {
      Future.microtask(
        () => ref.read(pharmacyProfileProvider.notifier).initialize(),
      );
    }

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
            PharmacyEntrance(
              child: _identityCard(context, store, profile, storeState, user),
            ),
            const SizedBox(height: 22),
            _label('MANAGEMENT'),
            PharmacyEntrance(
              index: 2,
              child: _group([
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
                  'Prescription queue',
                  'Review prescription-required online orders',
                  const PrescriptionQueue(),
                ),
                _hairline,
                _tile(
                  context,
                  LucideIcons.bookLock,
                  'Schedule H register',
                  'Scheduled drugs dispensed, for inspection',
                  const ScheduleRegisterScreen(),
                ),
                _hairline,
                _tile(
                  context,
                  LucideIcons.globe,
                  'Online store',
                  'Serviceability, delivery settings and coupons',
                  const PharmacyOnlineSettings(),
                ),
              ]),
            ),
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
            PharmacyEntrance(
              index: 4,
              child: PharmacySecondaryButton(
                label: 'Logout',
                icon: LucideIcons.logOut,
                color: PharmacyColors.error,
                onPressed: () async {
                  final ok = await PharmacyDialog.confirm(
                    context,
                    title: 'Log out?',
                    message:
                        'You will stop receiving new-order alerts on this phone until you log in again.',
                    icon: LucideIcons.logOut,
                    confirmLabel: 'Log out',
                  );
                  if (ok) ref.read(authProvider.notifier).logout();
                },
              ),
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
    Map<String, dynamic> profile,
    PharmacyStoreState storeState,
    UserModel? user,
  ) {
    final address = Map<String, dynamic>.from(
      (profile['address'] as Map?) ?? (store['address'] as Map?) ?? const {},
    );
    final addressText = [
      address['street'],
      address['city'],
      address['state'],
      address['pincode'],
    ].where((v) => v != null && '$v'.trim().isNotEmpty).join(', ');

    final name =
        '${profile['pharmacyName'] ?? store['name'] ?? user?.name ?? 'Pharmacy'}';
    final code = '${store['code'] ?? ''}'.trim();
    final licence =
        '${profile['licenseNumber'] ?? store['drugLicenseNumber'] ?? store['licenseNumber'] ?? ''}'
            .trim();
    final gstin = '${profile['gstin'] ?? store['gstin'] ?? ''}'.trim();
    final phone = '${profile['phone'] ?? store['phone'] ?? user?.phone ?? ''}'
        .trim();
    final email = '${profile['email'] ?? store['email'] ?? user?.email ?? ''}'
        .trim();
    final rawStatus = profile['verificationStatus']?.toString().toLowerCase();
    final verificationStatus = rawStatus == 'approved'
        ? VerificationStatus.approved
        : rawStatus == 'rejected'
        ? VerificationStatus.rejected
        : rawStatus == 'suspended'
        ? VerificationStatus.suspended
        : user?.verificationStatus;

    final (statusText, statusTone, statusIcon) = switch (verificationStatus) {
      VerificationStatus.approved => (
        'Verified pharmacy',
        PharmacyColors.greenDark,
        LucideIcons.badgeCheck,
      ),
      VerificationStatus.rejected => (
        'Verification rejected',
        PharmacyColors.error,
        LucideIcons.circleAlert,
      ),
      VerificationStatus.suspended => (
        'Suspended',
        PharmacyColors.error,
        LucideIcons.circleAlert,
      ),
      VerificationStatus.pending => (
        'Verification pending',
        PharmacyColors.warning,
        LucideIcons.hourglass,
      ),
      null => ('', PharmacyColors.textSecondary, LucideIcons.circle),
    };

    // Minimal: a plain header — no green slab — then the reference numbers
    // as a grouped list a pharmacist can read off and type elsewhere.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: PharmacyColors.panel,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.store,
                size: 24,
                color: PharmacyColors.textHeading,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: PharmacyType.sans(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: PharmacyColors.textStrong,
                    ),
                  ),
                  if (addressText.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      addressText,
                      style: PharmacyType.sans(
                        fontSize: 11.5,
                        height: 1.4,
                        color: PharmacyColors.textSecondary,
                      ),
                    ),
                  ],
                  if (statusText.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(statusIcon, size: 14, color: statusTone),
                        const SizedBox(width: 5),
                        Text(
                          statusText,
                          style: PharmacyType.sans(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: statusTone,
                          ),
                        ),
                        if (storeState.stores.length > 1 && code.isNotEmpty)
                          Text(
                            '  ·  $code',
                            style: PharmacyType.sans(
                              fontSize: 11.5,
                              color: PharmacyColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            _editButton(context),
          ],
        ),
        const SizedBox(height: 20),
        PharmacyGroup(
          children: [
            _dataRow(LucideIcons.fileText, 'Drug licence', licence),
            const PharmacyHairline(),
            _dataRow(LucideIcons.receipt, 'GSTIN', gstin),
            if (phone.isNotEmpty) ...[
              const PharmacyHairline(),
              _dataRow(LucideIcons.phone, 'Phone', phone),
            ],
            if (email.isNotEmpty) ...[
              const PharmacyHairline(),
              _dataRow(LucideIcons.mail, 'Email', email),
            ],
          ],
        ),
      ],
    );
  }

  Widget _editButton(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => Navigator.of(
      context,
    ).push(PharmacyPageRoute(builder: (_) => const PharmacyEditProfile())),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
      child: Text(
        'Edit',
        style: PharmacyType.sans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: PharmacyColors.greenDark,
        ),
      ),
    ),
  );

  /// A missing licence or GSTIN says "Not set" in amber rather than hiding
  /// the row — a pharmacy without a drug licence on file is a thing to fix.
  Widget _dataRow(IconData icon, String label, String value) {
    final missing = value.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 18, color: PharmacyColors.textHeading),
          const SizedBox(width: 12),
          Text(
            label,
            style: PharmacyType.sans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: PharmacyColors.textPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              missing ? 'Not set' : value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: PharmacyType.number(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: missing
                    ? PharmacyColors.warning
                    : PharmacyColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────── Section chrome ───────────────────────

  Widget _label(String text) => PharmacySectionTitle(text);

  Widget _group(List<Widget> children) => PharmacyGroup(children: children);

  static Widget get _hairline => const PharmacyHairline();

  Widget _tile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    Widget page,
  ) => PharmacyPressable(
    scale: 0.985,
    onTap: () =>
        Navigator.of(context).push(PharmacyPageRoute(builder: (_) => page)),
    child: Container(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 11, 12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: PharmacyColors.bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 17, color: PharmacyColors.textHeading),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: PharmacyType.sans(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                      color: PharmacyColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: PharmacyType.sans(
                      fontSize: 11.5,
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
