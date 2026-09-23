import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';

/// App-wide modal shell — the single source of truth for every dialog in
/// this app (edit forms, add-record forms, confirmations, destructive
/// prompts). Replaces bare `AlertDialog` so every module (doctor / physio /
/// pathology / pharmacy / mr / auth) gets the same premium, consistent look:
/// an icon badge + title/subtitle header, a scrollable content area with
/// generous spacing, and a properly weighted action row — instead of the
/// default Material dialog's cramped title/content/actions stack.
class AppDialog {
  AppDialog._();

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    String? subtitle,
    IconData? icon,
    Color accentColor = AppTheme.primary,
    required Widget content,
    List<Widget> actions = const [],
    bool scrollable = true,
    double maxWidth = 440,
  }) {
    return showDialog<T>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 32,
                  offset: const Offset(0, 14),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (icon != null) ...[
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.10),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: accentColor, size: 21),
                        ),
                        const SizedBox(width: 14),
                      ],
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(top: icon != null ? 3 : 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: GoogleFonts.manrope(
                                  fontSize: 17.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textPrimary,
                                  height: 1.2,
                                ),
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  style: GoogleFonts.manrope(
                                    fontSize: 12.5,
                                    color: AppTheme.textSecondary,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => Navigator.of(ctx).pop(),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            CupertinoIcons.xmark,
                            size: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: scrollable
                        ? SingleChildScrollView(child: content)
                        : content,
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Row(children: _spaced(actions)),
                  ),
                ] else
                  const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static List<Widget> _spaced(List<Widget> actions) {
    if (actions.length == 1) return [Expanded(child: actions.first)];
    final out = <Widget>[];
    for (var i = 0; i < actions.length; i++) {
      out.add(Expanded(child: actions[i]));
      if (i != actions.length - 1) out.add(const SizedBox(width: 10));
    }
    return out;
  }

  /// Muted, low-emphasis dismiss/cancel action.
  static Widget cancelButton(
    BuildContext context, {
    String label = 'Cancel',
    VoidCallback? onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed ?? () => Navigator.of(context).pop(),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.textSecondary,
        side: const BorderSide(color: AppTheme.border),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      child: Text(label),
    );
  }

  /// High-emphasis primary/confirm action, tinted with the module's accent.
  static Widget primaryButton(
    String label,
    VoidCallback? onPressed, {
    Color color = AppTheme.primary,
    bool loading = false,
  }) {
    return FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.manrope(
          fontSize: 14,
          fontWeight: FontWeight.w700,
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
          : Text(label),
    );
  }

  /// A short, plain-language confirmation prompt (replaces the classic
  /// "Are you sure?" AlertDialog). Pass [destructive] to tint it red for
  /// deactivate/delete/reject-style actions.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    IconData icon = CupertinoIcons.question_circle,
    Color accentColor = AppTheme.primary,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = false,
  }) async {
    final color = destructive ? AppTheme.error : accentColor;
    final result = await show<bool>(
      context,
      title: title,
      icon: icon,
      accentColor: color,
      content: Text(
        message,
        style: GoogleFonts.manrope(
          fontSize: 13.5,
          color: AppTheme.textSecondary,
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
