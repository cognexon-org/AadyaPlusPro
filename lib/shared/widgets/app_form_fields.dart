import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';

/// Generic labeled text field for dialogs/forms outside the pharmacy module
/// (doctor, physio, pathology, mr, auth). Mirrors the pharmacy module's
/// `PharmacyTextField` so every dialog in the app shares one visual language:
/// label above the field, optional leading icon, dense comfortable padding.
class AppTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData? icon;
  final bool isNum;
  final bool isDecimal;
  final int maxLines;
  final String? hint;
  final bool required;
  final bool obscureText;
  final EdgeInsetsGeometry margin;

  const AppTextField({
    super.key,
    required this.label,
    required this.controller,
    this.icon,
    this.isNum = false,
    this.isDecimal = false,
    this.maxLines = 1,
    this.hint,
    this.required = false,
    this.obscureText = false,
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
            required ? '$label *' : label,
            style: GoogleFonts.manrope(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            maxLines: obscureText ? 1 : maxLines,
            obscureText: obscureText,
            keyboardType: isDecimal
                ? const TextInputType.numberWithOptions(decimal: true)
                : isNum
                ? TextInputType.number
                : TextInputType.text,
            style: GoogleFonts.manrope(fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
              prefixIcon: icon == null
                  ? null
                  : Icon(icon, size: 18, color: AppTheme.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Generic labeled dropdown matching [AppTextField]'s look.
class AppDropdownField<T> extends StatelessWidget {
  final String label;
  final T? value;
  final IconData? icon;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final EdgeInsetsGeometry margin;

  const AppDropdownField({
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
            label,
            style: GoogleFonts.manrope(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<T>(
            initialValue: value,
            items: items,
            onChanged: onChanged,
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: AppTheme.textPrimary,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
              prefixIcon: icon == null
                  ? null
                  : Icon(icon, size: 18, color: AppTheme.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Generic full-row tappable switch for dialogs/forms outside pharmacy.
class AppSwitchRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final IconData? icon;
  final Color accentColor;
  final bool value;
  final ValueChanged<bool> onChanged;
  final EdgeInsetsGeometry margin;

  const AppSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.accentColor = AppTheme.primary,
    this.margin = const EdgeInsets.only(bottom: 10),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                if (icon != null) ...[
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 15, color: accentColor),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.manrope(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: GoogleFonts.manrope(
                            fontSize: 11.5,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Switch(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: accentColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A tappable field-styled row used to launch a date/time picker inside a
/// dialog, matching [AppTextField]'s label/field visual rhythm instead of a
/// bare `ListTile`.
class AppPickerField extends StatelessWidget {
  final String label;
  final String valueText;
  final IconData icon;
  final VoidCallback onTap;
  final bool required;
  final EdgeInsetsGeometry margin;

  const AppPickerField({
    super.key,
    required this.label,
    required this.valueText,
    required this.onTap,
    this.icon = Icons.calendar_today_outlined,
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
            required ? '$label *' : label,
            style: GoogleFonts.manrope(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: AppTheme.textTertiary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        valueText,
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          color: AppTheme.textPrimary,
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
