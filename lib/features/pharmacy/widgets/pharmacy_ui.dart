import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme/pharmacy_type.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/pharmacy_colors.dart';
import 'module_accent.dart';
import 'pharmacy_motion.dart';

export 'module_accent.dart';
export 'pharmacy_motion.dart';

/// Shared visual language for every pharmacy screen, built to the Pharmacy
/// Module Master UI Design System: iOS-native, restrained, information-dense.
/// One header style, one card style, one stat tile, one status pill, one
/// loading/empty state — so screens stop each reinventing their own
/// container/border/shadow combo. Every color/radius/spacing value here
/// comes from [PharmacyColors] — never from the app-wide `AppTheme`.

/// The backend's Medicine.category enum, in one place — screens must use
/// this exact set of keys (a free-text field here would let a pharmacist
/// type a value Mongoose then rejects, since the enum is case-sensitive and
/// closed).
const kMedicineCategories = <String, String>{
  'tablet': 'Tablet',
  'capsule': 'Capsule',
  'syrup': 'Syrup',
  'injection': 'Injection',
  'cream': 'Cream',
  'ointment': 'Ointment',
  'drops': 'Drops',
  'inhaler': 'Inhaler',
  'other': 'Other',
};

const kMedicineCategoryIcons = <String, IconData>{
  'tablet': LucideIcons.pill,
  'capsule': LucideIcons.pillBottle,
  'syrup': LucideIcons.droplets,
  'injection': LucideIcons.syringe,
  'cream': LucideIcons.sparkle,
  'ointment': LucideIcons.flaskConical,
  'drops': LucideIcons.droplet,
  'inhaler': LucideIcons.sprayCan,
  'other': LucideIcons.circleHelp,
};

IconData medicineCategoryIcon(String? category) {
  return kMedicineCategoryIcons[category?.toLowerCase()] ?? LucideIcons.pill;
}

/// "Selling Price (₹)" → "Selling price (₹)". Field labels are sentence
/// case in the minimal style; words in capitals (GSTIN, UPI, MRP) are kept.
String pharmacyFieldLabel(String label) {
  final words = label.split(' ');
  return [
    for (var i = 0; i < words.length; i++)
      i == 0 || words[i].length < 2 || words[i] == words[i].toUpperCase()
          ? words[i]
          : '${words[i][0].toLowerCase()}${words[i].substring(1)}',
  ].join(' ');
}

TextStyle _inter({
  required double size,
  FontWeight weight = FontWeight.w400,
  Color color = PharmacyColors.textPrimary,
  double? letterSpacing,
  double? height,
}) {
  return PharmacyType.sans(
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
  );
}

class PharmacyScreenHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const PharmacyScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: _inter(
                  size: 17,
                  weight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: PharmacyColors.textStrong,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: _inter(
                    size: 11.5,
                    weight: FontWeight.w500,
                    color: PharmacyColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          // The notification bell now floats over Home only, so a trailing
          // action can sit at the edge on every screen that uses this header.
          trailing!,
        ],
      ],
    );
  }
}

/// The standard content card: white surface, 14px radius, thin neutral
/// border, one extremely subtle shadow. No gradients, no heavy elevation.
class PharmacyCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? borderColor;
  final VoidCallback? onTap;

  const PharmacyCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: PharmacyColors.panel,
        borderRadius: BorderRadius.circular(PharmacyColors.radiusCard),
        // A border only when a caller asks for one (e.g. a warning card).
        border: borderColor == null ? null : Border.all(color: borderColor!),
      ),
      child: child,
    );
    return Padding(
      padding: margin,
      child: onTap == null
          ? card
          : PharmacyPressable(scale: 0.985, onTap: onTap, child: card),
    );
  }
}

/// A small outline icon on a plain, single-tone rounded-square — used
/// sparingly (headers, hero cards, empty states), never as decoration on
/// every list row. Flat, one colour, no gradient, no border.
class PharmacyIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;
  final bool circle;

  const PharmacyIconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 36,
    this.iconSize = 18,
    this.circle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle
            ? null
            : BorderRadius.circular(PharmacyColors.radiusSmall),
      ),
      child: Icon(icon, size: iconSize, color: color),
    );
  }
}

/// Compact labeled metric box used in the Home 2x2 KPI grid and similar
/// summary rows. Carries an optional trend delta (e.g. "+12%").
class PharmacyMetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color color;
  final String? trend;
  final bool trendUp;

  /// Smaller value type, for a tile carrying a currency figure rather than a
  /// count. `₹12,68,500` at 22pt does not fit half a phone width.
  final bool compact;

  const PharmacyMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.color = PharmacyColors.green,
    this.trend,
    this.trendUp = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PharmacyColors.panel,
        borderRadius: BorderRadius.circular(PharmacyColors.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _inter(
                    size: 11.5,
                    weight: FontWeight.w500,
                    color: PharmacyColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                // FittedBox rather than ellipsis: a truncated amount ("₹12,68…")
                // is worse than a smaller one, because it reads as a different
                // number.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: _inter(
                      size: compact ? 15 : 17,
                      weight: FontWeight.w700,
                      color: PharmacyColors.textStrong,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
              ),
              if (trend != null) ...[
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        trendUp ? LucideIcons.arrowUp : LucideIcons.arrowDown,
                        size: 11,
                        color: trendUp
                            ? PharmacyColors.success
                            : PharmacyColors.error,
                      ),
                      Text(
                        trend!,
                        style: _inter(
                          size: 10.5,
                          weight: FontWeight.w600,
                          color: trendUp
                              ? PharmacyColors.success
                              : PharmacyColors.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The module's single selectable chip — the All / Low Stock row on Medicines,
/// the All / Placed / Packing row on Orders, the payment-method selector on
/// New Sale. Every one of those was its own near-identical copy; they are all
/// this now, so the selected state cannot drift between screens again.
///
/// Selected reads as an ink-dark chip with white text — a selected filter is
/// a state, not an action, so it doesn't take the module accent.
class PharmacyFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Full-width, squarer variant for a row of equal-width options (the
  /// payment-method selector) rather than a scrolling pill row.
  final bool block;

  const PharmacyFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.block = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(
      block ? PharmacyColors.radiusInput : 20,
    );
    // Colour, border and shadow all cross-fade, so moving the selection
    // reads as one chip handing over to the next rather than two snapping.
    return PharmacyPressable(
      scale: 0.95,
      onTap: onTap,
      child: AnimatedContainer(
        duration: PharmacyMotion.medium,
        curve: PharmacyMotion.enter,
        padding: block
            ? const EdgeInsets.symmetric(vertical: 10)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        alignment: block ? Alignment.center : null,
        decoration: BoxDecoration(
          // Minimal style: a selected filter is a state, not an action, so it
          // is ink-dark rather than brand green; unselected is the grey panel.
          color: selected ? PharmacyColors.textStrong : PharmacyColors.panel,
          borderRadius: radius,
        ),
        child: AnimatedDefaultTextStyle(
          duration: PharmacyMotion.medium,
          style: PharmacyType.sans(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : PharmacyColors.textSecondary,
          ),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

/// Compact tinted status pill matching the design system's exact status
/// color table (order lifecycle, PO/transfer/return states, etc.).
class PharmacyStatusPill extends StatelessWidget {
  final String text;
  final Color color;
  final Color? background;
  final IconData? icon;

  const PharmacyStatusPill({
    super.key,
    required this.text,
    required this.color,
    this.background,
    this.icon,
  });

  /// Builds a pill directly from a backend order-status key using the
  /// design system's exact per-status color table.
  factory PharmacyStatusPill.status(String status, {String? label, Key? key}) {
    final (bg, fg) = PharmacyColors.statusColors(status);
    return PharmacyStatusPill(
      key: key,
      text: label ?? status.replaceAll('_', ' '),
      color: fg,
      background: bg,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: _inter(size: 11.5, weight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

/// A single skeleton block — a muted rounded rectangle used to compose
/// skeleton-loading layouts that approximate the real content shape.
/// Turns any thrown object into something worth showing a pharmacist.
///
/// A raw `'$e'` is the wrong thing to put on screen twice over: a Dio error
/// stringifies to a wall of request/response detail — which is what once
/// filled the whole screen with a Java stack trace — and a genuine server
/// message like "Batch number is required" is far more useful than either.
///
/// So: prefer what the server said, fall back to a plain sentence, and never
/// surface the exception itself.
String pharmacyErrorMessage(Object? error, {required String fallback}) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map) {
      final message = (data['message'] ?? data['error'])?.toString().trim();
      if (message != null && message.isNotEmpty) return message;
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'The server took too long to respond. Check your connection and try again.';
      case DioExceptionType.connectionError:
        return "Can't reach the server. Check your connection and try again.";
      default:
        break;
    }
  }
  return fallback;
}

final _pharmacyInr = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);
final _pharmacyInrPaise = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 2,
);

/// A money figure in Indian grouping (₹12,68,500). Paise are shown only when
/// there are some — a ₹12.50 strip price must not round to ₹13, but a ₹450
/// order total should not read ₹450.00. For screens that printed raw values
/// like `₹${item['sellingPrice']}`, which gave ₹1268500 or ₹12.5.
String pharmacyRupees(dynamic value) {
  final n = num.tryParse('${value ?? ''}') ?? 0;
  return n == n.roundToDouble()
      ? _pharmacyInr.format(n)
      : _pharmacyInrPaise.format(n);
}

/// The module's error toast. Capped at three lines so a long server message
/// cannot take over the screen.
void showPharmacyError(
  BuildContext context,
  Object? error, {
  required String fallback,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        pharmacyErrorMessage(error, fallback: fallback),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: _inter(size: 11.5, color: Colors.white),
      ),
      backgroundColor: PharmacyColors.error,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Wraps a tree of [PharmacySkeletonBlock]s in one looping shimmer sweep.
///
/// The sweep is applied to the *group*, not to each block: a highlight that
/// restarts inside every individual bar reads as noise, while one pass
/// travelling across the whole placeholder reads as loading. So skeleton
/// blocks stay inert and this supplies the motion.
class PharmacyShimmer extends StatelessWidget {
  final Widget child;

  /// Lets a caller mount the same tree without motion — for a screenshot, or
  /// when the platform reports that animations should be reduced.
  final bool enabled;

  const PharmacyShimmer({super.key, required this.child, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    if (!enabled || MediaQuery.disableAnimationsOf(context)) return child;
    return child
        .animate(onPlay: (controller) => controller.repeat())
        .shimmer(
          duration: 1150.ms,
          // A beat between passes; a shimmer with no gap looks frantic.
          delay: 350.ms,
          color: Colors.white,
          angle: 0.35,
        );
  }
}

class PharmacySkeletonBlock extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const PharmacySkeletonBlock({
    super.key,
    this.width = double.infinity,
    this.height = 14,
    this.radius = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: PharmacyColors.borderStrong,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Skeleton loading state for a list screen — a handful of card-shaped
/// placeholders instead of a full-screen spinner, so the layout doesn't
/// jump once real content arrives.
class PharmacyListSkeleton extends StatelessWidget {
  final int count;

  const PharmacyListSkeleton({super.key, this.count = 5});

  /// One placeholder card: 16px padding top and bottom around a 40px block,
  /// plus the card's 12px bottom margin.
  static const _cardExtent = 84.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Inside a bounded box — an Expanded, a sized sheet tab — asking for
        // more cards than fit overflows the Column. Draw only what the space
        // allows; a placeholder has no obligation to show a particular number
        // of rows.
        final fits = constraints.maxHeight.isFinite
            ? (constraints.maxHeight / _cardExtent).floor().clamp(1, count)
            : count;
        return _build(fits);
      },
    );
  }

  Widget _build(int count) {
    return PharmacyShimmer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          count,
          (i) => PharmacyCard(
            child: Row(
              children: [
                const PharmacySkeletonBlock(
                  width: 40,
                  height: 40,
                  radius: PharmacyColors.radiusSmall,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      PharmacySkeletonBlock(width: 140, height: 13),
                      SizedBox(height: 8),
                      PharmacySkeletonBlock(width: 90, height: 11),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder shaped like a form: a short label bar over a full-width field
/// box, repeated. Used by the edit-profile and settings screens, where a list
/// skeleton would promise rows that never arrive.
class PharmacyFormSkeleton extends StatelessWidget {
  final int fields;

  const PharmacyFormSkeleton({super.key, this.fields = 5});

  @override
  Widget build(BuildContext context) {
    return PharmacyShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < fields; i++) ...[
            const PharmacySkeletonBlock(width: 96, height: 11),
            const SizedBox(height: 7),
            const PharmacySkeletonBlock(
              height: 44,
              radius: PharmacyColors.radiusInput,
            ),
            SizedBox(height: i == fields - 1 ? 0 : 16),
          ],
        ],
      ),
    );
  }
}

/// Placeholder shaped like a detail page: a header tile with a title and
/// subtitle, a band of stat boxes, then a run of label/value rows.
class PharmacyDetailSkeleton extends StatelessWidget {
  final int rows;

  const PharmacyDetailSkeleton({super.key, this.rows = 6});

  @override
  Widget build(BuildContext context) {
    return PharmacyShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PharmacySkeletonBlock(width: 52, height: 52, radius: 14),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    PharmacySkeletonBlock(width: 170, height: 16),
                    SizedBox(height: 9),
                    PharmacySkeletonBlock(width: 110, height: 12),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: const [
              Expanded(child: PharmacySkeletonBlock(height: 62, radius: 14)),
              SizedBox(width: 12),
              Expanded(child: PharmacySkeletonBlock(height: 62, radius: 14)),
              SizedBox(width: 12),
              Expanded(child: PharmacySkeletonBlock(height: 62, radius: 14)),
            ],
          ),
          const SizedBox(height: 24),
          for (var i = 0; i < rows; i++) ...[
            Row(
              children: [
                PharmacySkeletonBlock(
                  width: 84 + (i.isEven ? 26 : 0),
                  height: 12,
                ),
                const Spacer(),
                PharmacySkeletonBlock(
                  width: 60 + (i.isOdd ? 22 : 0),
                  height: 12,
                ),
              ],
            ),
            SizedBox(height: i == rows - 1 ? 0 : 20),
          ],
        ],
      ),
    );
  }
}

/// Consistent branded loading state for a section too small for a skeleton
/// list (a tab, a modal, an inline refresh).
class PharmacyLoading extends StatelessWidget {
  const PharmacyLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: ModuleAccent.of(context).color,
        ),
      ),
    );
  }
}

/// Consistent inline error banner — never surfaces raw API errors.
class PharmacyErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const PharmacyErrorBanner({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PharmacyColors.panel,
        borderRadius: BorderRadius.circular(PharmacyColors.radiusCard),
      ),
      child: Row(
        children: [
          const Icon(
            LucideIcons.circleAlert,
            size: 18,
            color: PharmacyColors.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: _inter(size: 11.5, color: PharmacyColors.error),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text(
                'Retry',
                style: _inter(
                  size: 11.5,
                  weight: FontWeight.w600,
                  color: PharmacyColors.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact empty-state row for embedding inside a ListView — a small
/// outline icon, a short headline, no decorative illustration.
class PharmacyEmptyStateInline extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const PharmacyEmptyStateInline({
    super.key,
    required this.icon,
    required this.text,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: PharmacyColors.panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PharmacyFloat(
            child: Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: PharmacyColors.bg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 24, color: PharmacyColors.textSecondary),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            text,
            style: _inter(
              size: 12.5,
              color: PharmacyColors.textSecondary,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// A labeled text field for forms — label above, 10px radius, 46-50px
/// height, green focus border. What every form in the pharmacy module uses
/// instead of a bare `TextField`.
class PharmacyTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData? icon;
  final bool isNum;
  final bool isDecimal;
  final int maxLines;
  final String? hint;
  final bool required;
  final EdgeInsetsGeometry margin;

  /// Tighter type and padding, for a form long enough that the default
  /// 48px-tall field turns the screen into a scroll marathon.
  final bool dense;

  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;

  /// A widget at the field's right edge — e.g. a scan button.
  final Widget? trailing;

  final bool obscureText;
  final bool readOnly;

  /// Overrides the keyboard chosen from [isNum]/[isDecimal] (email, phone).
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;

  /// Shown under the field in red, and outlines it — for a value the user
  /// has to fix before going on.
  final String? errorText;

  const PharmacyTextField({
    super.key,
    required this.label,
    required this.controller,
    this.icon,
    this.isNum = false,
    this.isDecimal = false,
    this.maxLines = 1,
    this.hint,
    this.required = false,
    this.margin = const EdgeInsets.only(bottom: 16),
    this.dense = false,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.trailing,
    this.obscureText = false,
    this.readOnly = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.autofillHints,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty)
            Text(
              required
                  ? '${pharmacyFieldLabel(label)} *'
                  : pharmacyFieldLabel(label),
              style: _inter(
                size: dense ? 11.5 : 11.5,
                weight: FontWeight.w500,
                color: PharmacyColors.textSecondary,
              ),
            ),
          if (label.isNotEmpty) SizedBox(height: dense ? 5 : 6),
          TextField(
            controller: controller,
            maxLines: obscureText ? 1 : maxLines,
            obscureText: obscureText,
            readOnly: readOnly,
            textInputAction: textInputAction,
            onSubmitted: onSubmitted,
            autofillHints: autofillHints,
            inputFormatters: inputFormatters,
            textCapitalization: textCapitalization,
            keyboardType:
                keyboardType ??
                (isDecimal
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : isNum
                    ? TextInputType.number
                    : TextInputType.text),
            style: _inter(
              size: 13,
              color: readOnly
                  ? PharmacyColors.textSecondary
                  : PharmacyColors.textPrimary,
            ),
            cursorColor: ModuleAccent.of(context).color,
            decoration: InputDecoration(
              hintText: hint,
              errorText: errorText,
              errorMaxLines: 2,
              errorStyle: _inter(size: 11, color: PharmacyColors.error),
              hintStyle: _inter(
                size: dense ? 12.5 : 12.5,
                color: PharmacyColors.textTertiary,
              ),
              isDense: true,
              filled: true,
              fillColor: PharmacyColors.panel,
              suffixIcon: trailing,
              contentPadding: EdgeInsets.symmetric(
                horizontal: dense ? 12 : 14,
                vertical: maxLines > 1 ? (dense ? 10 : 12) : (dense ? 10 : 12),
              ),
              prefixIconConstraints: dense
                  ? const BoxConstraints(minWidth: 38, minHeight: 0)
                  : null,
              prefixIcon: icon == null
                  ? null
                  : Icon(
                      icon,
                      size: dense ? 16 : 18,
                      color: PharmacyColors.textTertiary,
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(PharmacyColors.radiusInput),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(PharmacyColors.radiusInput),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(PharmacyColors.radiusInput),
                borderSide: BorderSide(
                  color: ModuleAccent.of(context).color,
                  width: 1.5,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(PharmacyColors.radiusInput),
                borderSide: const BorderSide(color: PharmacyColors.error),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(PharmacyColors.radiusInput),
                borderSide: const BorderSide(
                  color: PharmacyColors.error,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A labeled dropdown matching [PharmacyTextField]'s look.
class PharmacyDropdownField<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final IconData? icon;
  final EdgeInsetsGeometry margin;

  const PharmacyDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.icon,
    this.margin = const EdgeInsets.only(bottom: 16),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pharmacyFieldLabel(label),
            style: _inter(
              size: 11.5,
              weight: FontWeight.w500,
              color: PharmacyColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<T>(
            initialValue: value,
            // Fills the field so a long item ellipsises instead of
            // overflowing a half-width field.
            isExpanded: true,
            items: items,
            onChanged: onChanged,
            style: _inter(size: 13, color: PharmacyColors.textPrimary),
            icon: const Icon(
              LucideIcons.chevronDown,
              size: 16,
              color: PharmacyColors.textTertiary,
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: PharmacyColors.panel,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              prefixIcon: icon == null
                  ? null
                  : Icon(icon, size: 18, color: PharmacyColors.textTertiary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(PharmacyColors.radiusInput),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(PharmacyColors.radiusInput),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(PharmacyColors.radiusInput),
                borderSide: BorderSide(
                  color: ModuleAccent.of(context).color,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tappable switch row — replaces bare Material `SwitchListTile`.
/// The module's switch, sized down from Material's default.
///
/// A stock [Switch] is ~59x48 including its 48dp tap target, which next to
/// 13.5pt row text reads as the heaviest thing on the screen. Two changes
/// shrink it: `shrinkWrap` drops the enforced 48dp box, and the scale takes
/// the control itself down. The tap target is not a concern here because the
/// whole row is the target — [PharmacySwitchRow] wraps it in an InkWell, and
/// the coupon list row does the same.
class PharmacySwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const PharmacySwitch({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.78,
      child: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: Colors.white,
        activeTrackColor: ModuleAccent.of(context).color,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: PharmacyColors.borderStrong,
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class PharmacySwitchRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  final EdgeInsetsGeometry margin;

  /// When false the row dims and stops responding — for a setting that only
  /// applies while some parent setting is on. It stays visible rather than
  /// disappearing, so the list does not reflow as you toggle the parent.
  final bool enabled;

  const PharmacySwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.margin = const EdgeInsets.only(bottom: 4),
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(PharmacyColors.radiusSmall),
        child: InkWell(
          borderRadius: BorderRadius.circular(PharmacyColors.radiusSmall),
          onTap: enabled ? () => onChanged(!value) : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: PharmacyColors.textSecondary),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pharmacyFieldLabel(label),
                          style: _inter(
                            size: 13,
                            weight: FontWeight.w500,
                            color: PharmacyColors.textPrimary,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: _inter(
                              size: 11.5,
                              color: PharmacyColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  PharmacySwitch(
                    value: value,
                    onChanged: enabled ? onChanged : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A search field styled to match the rest of the pharmacy module.
/// A tappable field-styled row that launches a date/time picker, matching
/// [PharmacyTextField]'s label/field rhythm instead of a bare `ListTile`.
class PharmacyPickerField extends StatelessWidget {
  final String label;
  final String valueText;
  final IconData icon;
  final VoidCallback onTap;
  final bool required;
  final EdgeInsetsGeometry margin;

  const PharmacyPickerField({
    super.key,
    required this.label,
    required this.valueText,
    required this.onTap,
    this.icon = LucideIcons.calendar,
    this.required = false,
    this.margin = const EdgeInsets.only(bottom: 16),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            required
                ? '${pharmacyFieldLabel(label)} *'
                : pharmacyFieldLabel(label),
            style: _inter(
              size: 11.5,
              weight: FontWeight.w500,
              color: PharmacyColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(PharmacyColors.radiusInput),
              onTap: onTap,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: PharmacyColors.panel,
                  borderRadius: BorderRadius.circular(
                    PharmacyColors.radiusInput,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: PharmacyColors.textTertiary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        valueText,
                        style: _inter(
                          size: 13,
                          color: PharmacyColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PharmacySearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final VoidCallback? onSubmitted;
  final VoidCallback? onRefresh;
  final ValueChanged<String>? onChanged;

  /// Shows a barcode button inside the field when set.
  final VoidCallback? onScan;

  const PharmacySearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.onSubmitted,
    this.onRefresh,
    this.onChanged,
    this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => onSubmitted?.call(),
      onChanged: onChanged,
      style: _inter(size: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: _inter(size: 12.5, color: PharmacyColors.textTertiary),
        filled: true,
        fillColor: PharmacyColors.panel,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 13),
        prefixIcon: const Icon(
          LucideIcons.search,
          size: 18,
          color: PharmacyColors.textTertiary,
        ),
        suffixIcon: onScan != null
            ? IconButton(
                tooltip: 'Scan barcode',
                icon: Icon(
                  LucideIcons.scanBarcode,
                  size: 20,
                  color: ModuleAccent.of(context).color,
                ),
                onPressed: onScan,
              )
            : onRefresh == null
            ? null
            : IconButton(
                icon: const Icon(
                  LucideIcons.refreshCw,
                  size: 18,
                  color: PharmacyColors.textSecondary,
                ),
                onPressed: onRefresh,
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PharmacyColors.radiusInput),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PharmacyColors.radiusInput),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PharmacyColors.radiusInput),
          borderSide: BorderSide(
            color: ModuleAccent.of(context).color,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}

/// Primary green filled button — 10px radius, 48px height, no gradient.
class PharmacyButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool fullWidth;

  /// 40px instead of 46px — for a button inside a card or list row, where a
  /// full-height button outweighs the content around it.
  final bool compact;

  const PharmacyButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.loading = false,
    this.fullWidth = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: ModuleAccent.of(context).color,
        disabledBackgroundColor: ModuleAccent.of(
          context,
        ).color.withValues(alpha: 0.4),
        foregroundColor: Colors.white,
        minimumSize: Size(0, compact ? 40 : 46),
        padding: compact ? const EdgeInsets.symmetric(horizontal: 16) : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PharmacyColors.radiusButton),
        ),
      ),
      child: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          // The label is Flexible and ellipsises: this button is dropped into
          // fixed-width slots (the save bars use a 140px box), and an
          // unconstrained Row there overflows rather than shrinking.
          : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: _inter(
                      size: 13,
                      weight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
    );
    return fullWidth ? SizedBox(width: double.infinity, child: child) : child;
  }
}

/// Secondary outlined button — white surface, green text/border.
class PharmacySecondaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool fullWidth;
  final Color? color;

  const PharmacySecondaryButton({
    super.key,
    required this.label,
    this.icon,
    required this.onPressed,
    this.fullWidth = true,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    // No colour given: the icon takes the module accent, the label stays ink.
    final color = this.color ?? ModuleAccent.of(context).color;
    final child = OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        backgroundColor: PharmacyColors.panel,
        side: BorderSide.none,
        minimumSize: const Size(0, 46),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PharmacyColors.radiusButton),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _inter(
                size: 13,
                weight: FontWeight.w600,
                color: this.color == null ? PharmacyColors.textPrimary : color,
              ),
            ),
          ),
        ],
      ),
    );
    return fullWidth ? SizedBox(width: double.infinity, child: child) : child;
  }
}

/// Consistent floating action button — solid green fill, plain neutral
/// shadow, no gradient.
class PharmacyFab extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const PharmacyFab({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return PharmacyPressable(
      scale: 0.94,
      onTap: onPressed,
      semanticLabel: label,
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: PharmacyColors.shadowElevated,
      ),
      child: Material(
        color: ModuleAccent.of(context).color,
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: _inter(
                    size: 13,
                    weight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps a builder's content with a rounded top sheet + drag handle, so every
/// showModalBottomSheet in the pharmacy module looks the same (used for
/// filters, branch selection, payment method, medicine selection, etc. per
/// the design system — bottom sheets are the default modal, not centered
/// dialogs).
Future<T?> showPharmacySheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool scrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: scrollControlled,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: const BoxDecoration(
        color: PharmacyColors.bg,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(PharmacyColors.radiusSheet),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          // The keyboard's height is added to the bottom padding, so a sheet
          // containing text fields lifts above it instead of being covered by
          // it. `isScrollControlled` alone only allows the sheet to grow — it
          // does nothing about the inset.
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            20 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: PharmacyColors.borderStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Flexible(child: builder(ctx)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Pharmacy-flavoured modal dialog shell — used only where a destructive
/// confirmation genuinely calls for a centered dialog rather than a bottom
/// sheet. Icon badge + title/subtitle header, scrollable content, weighted
/// action row.
class PharmacyDialog {
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    String? subtitle,
    IconData icon = LucideIcons.squarePen,
    Color? accentColor,
    required Widget content,
    required List<Widget> actions,
  }) {
    return showDialog<T>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            decoration: BoxDecoration(
              color: PharmacyColors.bg,
              borderRadius: BorderRadius.circular(
                PharmacyColors.radiusCardLarge,
              ),
              boxShadow: PharmacyColors.shadowModal,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        icon,
                        color: accentColor ?? ModuleAccent.of(ctx).color,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: _inter(
                                size: 15,
                                weight: FontWeight.w600,
                                color: PharmacyColors.textPrimary,
                              ),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                subtitle,
                                style: _inter(
                                  size: 11.5,
                                  color: PharmacyColors.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SingleChildScrollView(child: content),
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i != 0) const SizedBox(width: 10),
                        Expanded(child: actions[i]),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget cancelButton(
    BuildContext context, {
    String label = 'Cancel',
    VoidCallback? onPressed,
  }) {
    return PharmacySecondaryButton(
      label: label,
      onPressed: onPressed ?? () => Navigator.of(context).pop(),
    );
  }

  static Widget primaryButton(
    String label,
    VoidCallback? onPressed, {
    Color? color,
  }) {
    return Builder(
      builder: (context) => FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color ?? ModuleAccent.of(context).color,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PharmacyColors.radiusButton),
          ),
        ),
        child: Text(
          label,
          style: _inter(size: 13, weight: FontWeight.w600, color: Colors.white),
        ),
      ),
    );
  }

  /// The one case the design system allows a centered dialog for:
  /// destructive confirmations (deactivate, delete, discard). Every other
  /// modal in the module should use [showPharmacySheet] instead.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    IconData icon = LucideIcons.triangleAlert,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = true,
  }) async {
    final color = destructive
        ? PharmacyColors.error
        : ModuleAccent.of(context).color;
    final result = await show<bool>(
      context,
      title: title,
      icon: icon,
      accentColor: color,
      content: Text(
        message,
        style: _inter(
          size: 13,
          color: PharmacyColors.textSecondary,
          height: 1.5,
        ),
      ),
      actions: [
        cancelButton(
          context,
          label: cancelLabel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        primaryButton(
          confirmLabel,
          () => Navigator.of(context).pop(true),
          color: color,
        ),
      ],
    );
    return result == true;
  }
}

/// Forces typed text to uppercase as it is entered — for GSTINs, drug licence
/// numbers and other codes the server stores in capitals.
class PharmacyUpperCaseFormatter extends TextInputFormatter {
  const PharmacyUpperCaseFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}

// ═══════════════════════ Minimal section primitives ═══════════════════════

/// "DELIVERY ADDRESS" → "Delivery address". Screens still pass the old
/// upper-case labels; the minimal style sets section titles in sentence case.
String pharmacySentenceCase(String text) {
  final t = text.trim();
  if (t.isEmpty) return t;
  if (t != t.toUpperCase()) return t;
  final lower = t.toLowerCase();
  return '${lower[0].toUpperCase()}${lower.substring(1)}'
      .replaceAll('gstin', 'GSTIN')
      .replaceAll('upi', 'UPI')
      .replaceAll(' rx', ' Rx');
}

/// A section heading above a [PharmacyGroup]: 15pt bold ink, optional green
/// text action on the right.
class PharmacySectionTitle extends StatelessWidget {
  final String text;
  final String? action;
  final VoidCallback? onAction;

  const PharmacySectionTitle(
    this.text, {
    super.key,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Padding(
    // Flush left, so titles line up with form-field labels below them.
    padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            pharmacySentenceCase(text),
            style: _inter(
              size: 13,
              weight: FontWeight.w700,
              color: PharmacyColors.textStrong,
            ),
          ),
        ),
        if (action != null)
          GestureDetector(
            onTap: onAction,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                action!,
                style: _inter(
                  size: 11.5,
                  weight: FontWeight.w600,
                  color: ModuleAccent.of(context).color,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// The minimal style's grouped panel: grey fill, 14px corners, no border or
/// shadow. Pass rows and hairlines as children.
class PharmacyGroup extends StatelessWidget {
  final List<Widget> children;
  const PharmacyGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: PharmacyColors.panel,
      borderRadius: BorderRadius.circular(14),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );
}

/// Divider between rows inside a [PharmacyGroup] — white on the grey panel,
/// inset from the left like an iOS grouped list.
class PharmacyHairline extends StatelessWidget {
  const PharmacyHairline({super.key});

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: const EdgeInsets.only(left: 16),
    color: PharmacyColors.bg,
  );
}

/// "You're offline" strip, shown above the pharmacy nav bar while the server
/// cannot be reached. The screens keep showing what they last loaded; the
/// orders check retries every 20 seconds and clears this on its own.
class PharmacyOfflineBanner extends StatelessWidget {
  final VoidCallback onRetry;
  const PharmacyOfflineBanner({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: PharmacyColors.textStrong,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          const Icon(LucideIcons.wifiOff, size: 16, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "You're offline · showing the last loaded data",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _inter(
                size: 12.5,
                weight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              'Retry',
              style: _inter(
                size: 12.5,
                weight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
