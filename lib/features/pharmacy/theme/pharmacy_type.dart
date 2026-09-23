import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography for the Pharmacy module.
///
/// Every pharmacy screen calls [PharmacyType.sans] instead of GoogleFonts
/// directly, so the module's typeface is a one-line change in [_face] rather
/// than a find-and-replace across ~175 call sites.
///
/// The face is Plus Jakarta Sans: it holds up at both ends of this design —
/// 9.5pt tracked small caps for section labels, and the 38pt display figure
/// in the hero — where Inter went flat and characterless at display size.
/// Alternatives that fit the same brief, if you want to try another:
/// `GoogleFonts.manrope` (what the rest of the app already uses, so the whole
/// product would share one face), `GoogleFonts.figtree`, `GoogleFonts.dmSans`,
/// `GoogleFonts.sora`.
class PharmacyType {
  PharmacyType._();

  static const _face = GoogleFonts.plusJakartaSans;

  static TextStyle sans({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? wordSpacing,
    double? height,
    FontStyle? fontStyle,
    Color? backgroundColor,
    TextDecoration? decoration,
    Color? decorationColor,
    List<Shadow>? shadows,
    List<FontFeature>? fontFeatures,
    TextStyle? textStyle,
  }) => _face(
    textStyle: textStyle,
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    letterSpacing: letterSpacing,
    wordSpacing: wordSpacing,
    height: height,
    fontStyle: fontStyle,
    backgroundColor: backgroundColor,
    decoration: decoration,
    decorationColor: decorationColor,
    shadows: shadows,
    fontFeatures: fontFeatures,
  );

  /// Same face with tabular (fixed-width) figures. Use it wherever numbers
  /// stack in a column — the bill amounts, the inventory table — so the digits
  /// line up vertically instead of ragging.
  static TextStyle number({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) => _face(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}
