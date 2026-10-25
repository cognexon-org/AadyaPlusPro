import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/ui/app_ui.dart';
import '../providers/physio_exercise_provider.dart';

/// The exercise's picture, or a quiet dumbbell when it has none or the
/// image fails to load.
class ExerciseThumb extends StatelessWidget {
  final Map<String, dynamic> exercise;
  final double size;
  final double? height;
  final double radius;

  const ExerciseThumb({
    super.key,
    required this.exercise,
    this.size = 56,
    this.height,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    final url = '${exercise['imageUrl'] ?? ''}'.trim();
    final h = height ?? size;
    final fallback = Container(
      width: size,
      height: h,
      color: accent.veryLight,
      alignment: Alignment.center,
      child: Icon(
        LucideIcons.dumbbell,
        size: (h < size ? h : size) * 0.4,
        color: accent.color,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url.startsWith('http')
          ? Image.network(
              url,
              width: size,
              height: h,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : fallback,
            )
          : fallback,
    );
  }
}

/// A small grey tag: "Knee", "Strengthening".
class ExerciseTag extends StatelessWidget {
  final String text;
  final IconData? icon;
  final bool accent;
  final Color? background;
  const ExerciseTag(
    this.text, {
    super.key,
    this.icon,
    this.accent = false,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final a = ModuleAccent.of(context);
    final fg = accent ? a.color : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? (accent ? a.veryLight : AppColors.bg),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: AppType.sans(
              fontSize: AppType.micro,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Active / Completed / Cancelled.
class PlanStatusTag extends StatelessWidget {
  final String status;
  const PlanStatusTag(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    final (fg, bg) = switch (status) {
      'active' => (accent.color, accent.veryLight),
      'cancelled' => (AppColors.textTertiary, AppColors.panel),
      _ => (AppColors.textSecondary, AppColors.panel),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        planStatusLabel(status),
        style: AppType.sans(
          fontSize: AppType.micro,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

/// − value + for a small whole number (times a day, days a week).
class ExerciseStepper extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final String Function(int v)? format;
  final ValueChanged<int> onChanged;

  const ExerciseStepper({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.format,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    Widget btn(IconData icon, bool enabled, VoidCallback onTap, String tip) =>
        Semantics(
          button: true,
          label: tip,
          child: AppPressable(
            scale: 0.9,
            onTap: enabled ? onTap : null,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 15,
                color: enabled ? accent.color : AppColors.textDisabled,
              ),
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppType.sans(
            fontSize: AppType.caption,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            btn(
              LucideIcons.minus,
              value > min,
              () => onChanged(value - 1),
              'Fewer',
            ),
            SizedBox(
              width: 52,
              child: Text(
                format?.call(value) ?? '$value',
                textAlign: TextAlign.center,
                style: AppType.number(
                  fontSize: AppType.body,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textStrong,
                ),
              ),
            ),
            btn(
              LucideIcons.plus,
              value < max,
              () => onChanged(value + 1),
              'More',
            ),
          ],
        ),
      ],
    );
  }
}

/// Opens an exercise video in the browser / YouTube app.
Future<void> openExerciseVideo(BuildContext context, String url) async {
  final uri = Uri.tryParse(url.trim());
  var ok = false;
  if (uri != null && uri.hasScheme) {
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
  }
  if (!ok && context.mounted) {
    showAppError(context, null, fallback: 'Couldn’t open the video link.');
  }
}

/// True for an http(s) link with a host.
bool exIsWebUrl(String v) {
  final uri = Uri.tryParse(v.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

/// The white-on-grey text field used inside grey cards (plan rows, log
/// sheet), matching the doctor's prescription rows.
class ExerciseCardField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool number;
  final String? errorText;
  final double bottom;
  final String? suffix;
  final int maxLines;

  const ExerciseCardField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.number = false,
    this.errorText,
    this.bottom = 12,
    this.suffix,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context).color;
    OutlineInputBorder border(Color? c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppColors.radiusInput),
      borderSide: c == null ? BorderSide.none : BorderSide(color: c, width: w),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.sans(
              fontSize: AppType.caption,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 5),
          TextField(
            controller: controller,
            maxLines: maxLines,
            minLines: 1,
            keyboardType: number ? TextInputType.number : TextInputType.text,
            inputFormatters: number
                ? [FilteringTextInputFormatter.digitsOnly]
                : null,
            textCapitalization: number
                ? TextCapitalization.none
                : TextCapitalization.sentences,
            cursorColor: accent,
            style: AppType.number(
              fontSize: AppType.body,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AppColors.bg,
              hintText: hint,
              suffixText: suffix,
              suffixStyle: AppType.sans(
                fontSize: AppType.caption,
                color: AppColors.textTertiary,
              ),
              hintStyle: AppType.sans(
                fontSize: AppType.small,
                color: AppColors.textTertiary,
              ),
              errorText: errorText,
              errorMaxLines: 2,
              errorStyle: AppType.sans(fontSize: 11, color: AppColors.error),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 11,
              ),
              border: border(null),
              enabledBorder: border(null),
              focusedBorder: border(accent, 1.5),
              errorBorder: border(AppColors.error),
              focusedErrorBorder: border(AppColors.error, 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tinted note: what a section is for, or a gentle heads-up.
class ExerciseNote extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool warn;
  const ExerciseNote({
    super.key,
    required this.icon,
    required this.text,
    this.warn = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warn ? AppColors.warningBg : accent.veryLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: warn ? AppColors.warning : accent.color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppType.sans(
                fontSize: AppType.caption,
                color: AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One library exercise as a grey row: picture, name, body part and
/// category, default dosing and a video badge.
class ExerciseCard extends StatelessWidget {
  final Map<String, dynamic> exercise;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool selected;

  const ExerciseCard({
    super.key,
    required this.exercise,
    this.onTap,
    this.trailing,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    final ex = exercise;
    final meta = [
      '${ex['bodyPart'] ?? ''}'.trim(),
      '${ex['category'] ?? ''}'.trim(),
    ].where((e) => e.isNotEmpty).join(' · ');
    final defaults = exDefaultsLine(ex);
    final difficulty = '${ex['difficulty'] ?? ''}';
    final video = exIsWebUrl('${ex['videoUrl'] ?? ''}');
    return AppPressable(
      scale: 0.985,
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? accent.veryLight : AppColors.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent.light : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            ExerciseThumb(exercise: ex, size: 60),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exName(ex),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.sans(
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textStrong,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.sans(
                        fontSize: AppType.caption,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (difficulty.isNotEmpty)
                        ExerciseTag(exDifficultyLabel(difficulty)),
                      if (video)
                        const ExerciseTag(
                          'Video',
                          icon: LucideIcons.play,
                          accent: true,
                        ),
                      if (defaults.isNotEmpty)
                        Text(
                          defaults,
                          style: AppType.sans(
                            fontSize: AppType.micro,
                            color: AppColors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}
