import 'package:flutter/widgets.dart';

import '../theme/pharmacy_colors.dart';

/// Each module of the app has one accent colour; everything else (white
/// page, grey panels, slate text, red/amber for problems) is shared. The
/// kit's buttons, fields, chips, switches and nav bar read the accent from
/// the nearest [ModuleTheme], so a module sets it once at its root.
///
/// Hues sit far apart on the wheel so no two modules look alike, and none is
/// red or amber — those stay reserved for errors and warnings.
@immutable
class ModuleAccent {
  /// Buttons, focus rings, icons, selected states.
  final Color color;

  /// [color] at ~20% on white — selected surfaces, badges, tracks.
  final Color light;

  /// [color] at ~8% on white — tinted panels.
  final Color veryLight;

  const ModuleAccent({
    required this.color,
    required this.light,
    required this.veryLight,
  });

  ModuleAccent.from(this.color)
    : light = Color.alphaBlend(
        color.withValues(alpha: 0.2),
        const Color(0xFFFFFFFF),
      ),
      veryLight = Color.alphaBlend(
        color.withValues(alpha: 0.08),
        const Color(0xFFFFFFFF),
      );

  /// Sign in, sign up, OTP, splash — Aadya blue, from the logo.
  static final onboarding = ModuleAccent.from(const Color(0xFF1F5EDC));

  /// Pharmacy — the logo's green.
  static const pharmacy = ModuleAccent(
    color: PharmacyColors.green,
    light: PharmacyColors.greenLight,
    veryLight: PharmacyColors.greenVeryLight,
  );

  /// Doctor — clinical teal.
  static final doctor = ModuleAccent.from(const Color(0xFF0E8A8A));

  /// Physiotherapist — energetic coral.
  static final physio = ModuleAccent.from(const Color(0xFFE8572A));

  /// Pathology lab — plum.
  static final pathology = ModuleAccent.from(const Color(0xFF9B2FAE));

  /// Medical representative — indigo.
  static final mr = ModuleAccent.from(const Color(0xFF4F46E5));

  /// The nearest module's accent; pharmacy green when none is set, so
  /// existing pharmacy screens are unchanged.
  static ModuleAccent of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ModuleTheme>()?.accent ??
      pharmacy;
}

/// Sets the accent for everything below it.
class ModuleTheme extends InheritedWidget {
  final ModuleAccent accent;
  const ModuleTheme({super.key, required this.accent, required super.child});

  @override
  bool updateShouldNotify(ModuleTheme old) => old.accent != accent;
}
