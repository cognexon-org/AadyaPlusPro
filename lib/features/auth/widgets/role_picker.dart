import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../pharmacy/theme/pharmacy_type.dart';
import '../../pharmacy/widgets/module_accent.dart';
import '../../pharmacy/widgets/pharmacy_motion.dart';
import '../models/user_model.dart';
import '../screens/login_screen.dart' show kProfessionalRoles;
import '../../pharmacy/theme/pharmacy_colors.dart';
import 'onboarding_hero.dart' show kAadyaBlue, stageLight;

ModuleAccent accentForRole(UserRole r) => switch (r) {
  UserRole.doctor => ModuleAccent.doctor,
  UserRole.physiotherapist => ModuleAccent.physio,
  UserRole.pathology => ModuleAccent.pathology,
  UserRole.pharmacy => ModuleAccent.pharmacy,
  UserRole.mr => ModuleAccent.mr,
};

/// The role step: one card per profession on a light Aadya-blue surface,
/// with a soft tint of the module's colour inside one corner. A radio on
/// each; choosing a card colours its border and opens it to show what that
/// role gets. Nothing glows outside the card.
class RolePicker extends StatelessWidget {
  final UserRole? selected;
  final ValueChanged<UserRole> onSelect;
  const RolePicker({super.key, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final roles = kProfessionalRoles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < roles.length; i++)
          PharmacyEntrance(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RoleRow(
                role: roles[i].role,
                title: roles[i].title,
                icon: roles[i].icon,
                selected: selected == roles[i].role,
                onTap: () => onSelect(roles[i].role),
              ),
            ),
          ),
      ],
    );
  }
}

class _RoleRow extends StatelessWidget {
  final UserRole role;
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _RoleRow({
    required this.role,
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  String get _line => switch (role) {
    UserRole.doctor => 'Clinic, video and home consultations',
    UserRole.physiotherapist => 'Sessions, home visits and recovery plans',
    UserRole.pathology => 'Test bookings, sample collection and reports',
    UserRole.pharmacy => 'Online orders, stock and billing',
    UserRole.mr => 'Doctor visits and field work',
  };

  List<String> get _gets => switch (role) {
    UserRole.doctor => const [
      'Take bookings for clinic, video and home visits',
      'Write and send e-prescriptions',
      'Track payments and payouts',
    ],
    UserRole.physiotherapist => const [
      'Run clinic sessions and home visits',
      'Assign home exercise plans',
      'Show recovery with pain and mobility charts',
    ],
    UserRole.pathology => const [
      'Take bookings and send phlebotomists home',
      'Enter results — the report PDF is made for you',
      'Add common tests in one tap',
    ],
    UserRole.pharmacy => const [
      'Online orders that ring until accepted',
      'Stock, batches and expiry dates',
      'Billing and invoices for walk-in customers',
    ],
    UserRole.mr => const <String>[],
  };

  @override
  Widget build(BuildContext context) {
    // Brand blue until chosen; the chosen card takes its module's colour.
    final c = selected ? accentForRole(role).color : kAadyaBlue;
    final light = stageLight(c);
    const radius = 18.0;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title. $_line',
      child: AnimatedContainer(
        duration: PharmacyMotion.medium,
        curve: PharmacyMotion.enter,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: selected ? c : const Color(0xFFD9E4FB),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius - 1),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              splashColor: c.withValues(alpha: 0.12),
              highlightColor: c.withValues(alpha: 0.04),
              child: Ink(
                // The brand blue, lifted almost to white.
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFF7F9FF), Color(0xFFEAF1FE)],
                  ),
                ),
                child: Stack(
                  children: [
                    // The module's light, rising from the top-right corner.
                    Positioned(
                      right: -70,
                      top: -90,
                      child: AnimatedContainer(
                        duration: PharmacyMotion.medium,
                        width: 230,
                        height: 230,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              c.withValues(alpha: selected ? 0.2 : 0.1),
                              c.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // A thin highlight along the top edge, like glass.
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: Container(
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0),
                              Colors.white,
                              Colors.white.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              AnimatedContainer(
                                duration: PharmacyMotion.medium,
                                curve: PharmacyMotion.enter,
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(13),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [light, c],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: c.withValues(alpha: 0.25),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  icon,
                                  size: 21,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: PharmacyType.sans(
                                        fontSize: PharmacyType.title,
                                        fontWeight: FontWeight.w700,
                                        color: PharmacyColors.textStrong,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _line,
                                      style: PharmacyType.sans(
                                        fontSize: PharmacyType.caption,
                                        color: PharmacyColors.textSecondary,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              _Radio(
                                selected: selected,
                                color: c,
                                light: light,
                              ),
                            ],
                          ),
                          // What the role gets, revealed under the chosen card.
                          AnimatedSize(
                            duration: PharmacyMotion.medium,
                            curve: PharmacyMotion.enter,
                            alignment: Alignment.topCenter,
                            child: selected && _gets.isNotEmpty
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 14),
                                    child: Column(
                                      children: [
                                        Container(
                                          height: 1,
                                          color: const Color(0xFFD9E4FB),
                                        ),
                                        const SizedBox(height: 12),
                                        for (final g in _gets)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              left: 60,
                                              bottom: 8,
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  LucideIcons.check,
                                                  size: 15,
                                                  color: c,
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    g,
                                                    style: PharmacyType.sans(
                                                      fontSize:
                                                          PharmacyType.small,
                                                      color: PharmacyColors
                                                          .textPrimary,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  )
                                : const SizedBox(width: double.infinity),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A plain radio: a ring that fills with the role's colour.
class _Radio extends StatelessWidget {
  final bool selected;
  final Color color;
  final Color light;
  const _Radio({
    required this.selected,
    required this.color,
    required this.light,
  });

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: PharmacyMotion.fast,
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: selected ? color : Colors.white,
      border: Border.all(
        color: selected ? color : const Color(0xFFC3D2F2),
        width: 2,
      ),
    ),
    alignment: Alignment.center,
    child: AnimatedScale(
      duration: PharmacyMotion.fast,
      scale: selected ? 1 : 0,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    ),
  );
}
