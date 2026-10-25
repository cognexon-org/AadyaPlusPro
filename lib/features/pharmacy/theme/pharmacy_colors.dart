import 'package:flutter/material.dart';

/// Design tokens for the Pharmacy module, taken directly from the Figma
/// source of truth (file `A2Dp16GyQDu98Zgg5Knf0W`) via the Figma MCP server —
/// not hand-picked. The palette is Tailwind slate for neutrals + Tailwind
/// emerald for the brand ramp, on top of a custom `#00A651` brand green.
///
/// Scoped to this module only (not the shared app-wide `AppTheme`), so the
/// pharmacy module stays visually independent of the other role modules.
/// Every pharmacy screen must read colors from here, never from `AppTheme`.
class PharmacyColors {
  PharmacyColors._();

  // Primary — one brand green for the whole app. Fills, icons, text, charts
  // and status all use it; the two tints below are that same green mixed
  // with white, not separate swatches. (The module used to mix in Tailwind's
  // bluer emerald for text and icons, which read as a second green.)
  static const Color green = Color(0xFF00A651);

  /// Same as [green]. Kept as a name so existing call sites need no change.
  static const Color greenDark = green;

  /// [green] at 20% on white — badges, bars' tracks, selected surfaces.
  static const Color greenLight = Color(0xFFCCEDDC);

  /// [green] at 8% on white — tinted panels.
  static const Color greenVeryLight = Color(0xFFEBF8F1);

  // Background — the design puts content on WHITE, with filled surfaces
  // (stat tiles, list rows) in slate-50. Note this is the inverse of the
  // usual "gray page, white card" arrangement.
  static const Color bg = Color(0xFFFFFFFF);
  static const Color bgSecondary = Color(0xFFF8FAFC); // slate-50
  static const Color card = Color(0xFFF8FAFC); // slate-50
  static const Color cardElevated = Color(0xFFFFFFFF);

  /// Minimal style's grouped-panel fill: content sits in soft grey panels on
  /// a white page, with no border and no shadow.
  static const Color panel = Color(0xFFF4F6F8);

  // Hero gradient — the brand green deepening diagonally. The Home hero is
  // the only surface that carries it; it is what gives the screen its single
  // dominant block instead of a page of equal-weight cards.
  static const List<Color> heroGradient = [green, green];

  // Text — Tailwind slate ramp.
  static const Color textStrong = Color(0xFF0F172A); // slate-900, hero figures
  static const Color textPrimary = Color(0xFF1E293B); // slate-800
  static const Color textHeading = Color(
    0xFF334155,
  ); // slate-700, section titles
  static const Color textSecondary = Color(0xFF64748B); // slate-500
  static const Color textTertiary = Color(0xFF94A3B8); // slate-400
  static const Color textDisabled = Color(0xFFCBD5E1); // slate-300

  // Borders
  static const Color border = Color(0xFFF1F5F9); // slate-100
  static const Color borderStrong = Color(0xFFE2E8F0); // slate-200

  // Semantic
  static const Color success = green;
  static const Color warning = Color(0xFFD97706);
  static const Color warningBg = Color(0xFFFEF3C7);
  static const Color error = Color(0xFFDC2626);
  static const Color errorBg = Color(0xFFFEE2E2);
  static const Color info = Color(0xFF2563EB);
  static const Color infoBg = Color(0xFFDBEAFE);

  /// The five-step green ramp the design uses to shade chart bars by
  /// magnitude (lightest = smallest value, brand green = largest).
  static const List<Color> barRamp = [
    Color(0xFFB2E4C9), // brand at 30%
    Color(0xFF80D2A8), // brand at 50%
    Color(0xFF4DC185), // brand at 70%
    Color(0xFF26B36A), // brand at 85%
    green,
  ];

  /// Picks a bar colour from [barRamp] for a value relative to the max.
  static Color barColor(double value, double maxValue) {
    if (maxValue <= 0) return barRamp.first;
    final i = ((value / maxValue) * (barRamp.length - 1)).round();
    return barRamp[i.clamp(0, barRamp.length - 1)];
  }

  // Status pills (order lifecycle)
  static const Color statusPrescriptionReviewBg = Color(0xFFFFF5E6);
  static const Color statusPrescriptionReviewFg = Color(0xFFB86600);
  static const Color statusPlacedBg = Color(0xFFEEF4FF);
  static const Color statusPlacedFg = Color(0xFF3978D8);
  static const Color statusConfirmedBg = greenVeryLight;
  static const Color statusConfirmedFg = green;
  static const Color statusPackingBg = Color(0xFFF2F3F5);
  static const Color statusPackingFg = Color(0xFF59625D);
  static const Color statusReadyToShipBg = Color(0xFFEEF4FF);
  static const Color statusReadyToShipFg = Color(0xFF3978D8);
  static const Color statusShippedBg = Color(0xFFF1EEFF);
  static const Color statusShippedFg = Color(0xFF6651B8);
  static const Color statusOutForDeliveryBg = Color(0xFFFFF5E6);
  static const Color statusOutForDeliveryFg = Color(0xFFB86600);
  static const Color statusDeliveredBg = greenVeryLight;
  static const Color statusDeliveredFg = green;
  static const Color statusCancelledBg = Color(0xFFFFF0F0);
  static const Color statusCancelledFg = Color(0xFFC23B3B);

  /// Maps an order status key (backend enum, e.g. 'prescription_review',
  /// 'ready_to_ship') to its (background, foreground) pill colors.
  static (Color bg, Color fg) statusColors(String status) {
    switch (status) {
      case 'prescription_review':
        return (statusPrescriptionReviewBg, statusPrescriptionReviewFg);
      case 'placed':
        return (statusPlacedBg, statusPlacedFg);
      case 'confirmed':
        return (statusConfirmedBg, statusConfirmedFg);
      case 'packing':
        return (statusPackingBg, statusPackingFg);
      case 'ready_to_ship':
        return (statusReadyToShipBg, statusReadyToShipFg);
      case 'shipped':
        return (statusShippedBg, statusShippedFg);
      case 'out_for_delivery':
        return (statusOutForDeliveryBg, statusOutForDeliveryFg);
      case 'delivered':
        return (statusDeliveredBg, statusDeliveredFg);
      case 'cancelled':
        return (statusCancelledBg, statusCancelledFg);
      default:
        return (statusPackingBg, statusPackingFg);
    }
  }

  // Shadows — the design carries surfaces on borders, not elevation: no
  // card in the Figma file has a drop shadow. Only floating chrome (FABs,
  // sheets, modals) lifts off the page.
  static List<BoxShadow> get shadowDefault => const [];

  static List<BoxShadow> get shadowElevated => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.07),
      blurRadius: 14,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get shadowModal => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.12),
      blurRadius: 30,
      offset: const Offset(0, 10),
    ),
  ];

  // Corner radii
  static const double radiusSmall = 8;
  static const double radiusInput = 10;
  static const double radiusCard = 14;
  static const double radiusCardLarge = 16;
  static const double radiusSheet = 22;
  static const double radiusButton = 10;
}

/// One quick-action tile's colour set, exactly as the Figma design defines
/// it: a very light tinted surface, a slightly stronger border, a pastel
/// icon disc, and a saturated glyph colour that reads on the disc.
class PharmacyTileStyle {
  final Color surface;
  final Color border;
  final Color disc;
  final Color icon;

  const PharmacyTileStyle({
    required this.surface,
    required this.border,
    required this.disc,
    required this.icon,
  });

  static const emerald = PharmacyTileStyle(
    surface: PharmacyColors.greenVeryLight,
    border: PharmacyColors.greenLight,
    disc: PharmacyColors.greenLight,
    icon: PharmacyColors.green,
  );
  static const amber = PharmacyTileStyle(
    surface: Color(0xFFFFFBEB),
    border: Color(0xFFFEF3C7),
    disc: Color(0xFFFEF3C7),
    icon: Color(0xFFD97706),
  );
  static const blue = PharmacyTileStyle(
    surface: Color(0xFFEFF6FF),
    border: Color(0xFFDBEAFE),
    disc: Color(0xFFDBEAFE),
    icon: Color(0xFF2563EB),
  );
  static const sky = PharmacyTileStyle(
    surface: Color(0xFFF0F9FF),
    border: Color(0xFFE0F2FE),
    disc: Color(0xFFE0F2FE),
    icon: Color(0xFF0284C7),
  );
  static const purple = PharmacyTileStyle(
    surface: Color(0xFFFAF5FF),
    border: Color(0xFFF3E8FF),
    disc: Color(0xFFF3E8FF),
    icon: Color(0xFF9333EA),
  );
  static const rose = PharmacyTileStyle(
    surface: Color(0xFFFFF1F2),
    border: Color(0xFFFFE4E6),
    disc: Color(0xFFFFE4E6),
    icon: Color(0xFFE11D48),
  );
  static const teal = PharmacyTileStyle(
    surface: Color(0xFFF0FDFA),
    border: Color(0xFFCCFBF1),
    disc: Color(0xFFCCFBF1),
    icon: Color(0xFF0D9488),
  );
}
