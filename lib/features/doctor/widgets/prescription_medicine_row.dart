import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import 'prescription_ui.dart';

/// One medicine being written. Owns its controllers; the editor disposes it
/// when the row is removed or the screen closes. [id] is local and stable,
/// so the row keeps its own values when a row above it is deleted.
class RxMedicineDraft {
  static int _next = 0;

  final int id = _next++;
  final name = TextEditingController();
  final dosage = TextEditingController();
  final frequency = TextEditingController();
  final duration = TextEditingController();
  final instructions = TextEditingController();
  final quantity = TextEditingController();

  /// Fields the editor doesn't show (genericName, unit, notes...), kept so
  /// editing a draft doesn't silently drop them.
  final Map<String, dynamic> extra;
  String? nameError;

  RxMedicineDraft([Map<String, dynamic>? source])
    : extra = Map<String, dynamic>.from(source ?? const {}) {
    final s = source ?? const {};
    name.text = '${s['medicineName'] ?? s['name'] ?? ''}'.trim();
    dosage.text = '${s['dosage'] ?? ''}'.trim();
    frequency.text = '${s['frequency'] ?? ''}'.trim();
    duration.text = '${s['duration'] ?? ''}'.trim();
    instructions.text = '${s['instructions'] ?? ''}'.trim();
    final q = s['quantity'];
    quantity.text = q == null || '$q'.isEmpty ? '' : '$q';
  }

  List<TextEditingController> get _all => [
    name,
    dosage,
    frequency,
    duration,
    instructions,
    quantity,
  ];

  bool get isBlank => _all.every((c) => c.text.trim().isEmpty);

  Map<String, dynamic> toJson() {
    final out = Map<String, dynamic>.from(extra)
      ..remove('name')
      ..remove('quantity');
    String? t(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    out['medicineName'] = name.text.trim();
    for (final e in {
      'dosage': dosage,
      'frequency': frequency,
      'duration': duration,
      'instructions': instructions,
    }.entries) {
      final v = t(e.value);
      if (v == null) {
        out.remove(e.key);
      } else {
        out[e.key] = v;
      }
    }
    final q = num.tryParse(quantity.text.trim());
    if (q != null) out['quantity'] = q;
    return out;
  }

  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
  }
}

/// The editable card for one [RxMedicineDraft].
class RxMedicineRow extends StatelessWidget {
  final RxMedicineDraft draft;
  final int number;
  final VoidCallback? onRemove;

  const RxMedicineRow({
    super.key,
    required this.draft,
    required this.number,
    this.onRemove,
  });

  static const _frequencies = ['1-0-1', '1-0-0', '0-0-1', '1-1-1', 'SOS'];
  static const _durations = ['3 days', '5 days', '7 days', '1 month'];
  static const _food = ['Before food', 'After food', 'With food'];

  void _toggle(TextEditingController c, String v) {
    c.text = c.text.trim() == v ? '' : v;
    c.selection = TextSelection.collapsed(offset: c.text.length);
  }

  Widget _chips(TextEditingController c, List<String> options) =>
      ListenableBuilder(
        listenable: c,
        builder: (_, _) => Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final o in options)
              RxQuickChip(
                label: o,
                selected: c.text.trim() == o,
                onTap: () => _toggle(c, o),
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Medicine $number',
                style: AppType.sans(
                  fontSize: AppType.small,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textStrong,
                ),
              ),
              const Spacer(),
              if (onRemove != null)
                IconButton(
                  tooltip: 'Remove medicine',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    LucideIcons.trash2,
                    size: 17,
                    color: AppColors.textTertiary,
                  ),
                  onPressed: onRemove,
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Field(
                  label: 'Name',
                  controller: draft.name,
                  hint: 'e.g. Paracetamol 650',
                  required: true,
                  errorText: draft.nameError,
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _Field(
                        label: 'Dosage',
                        controller: draft.dosage,
                        hint: '650 mg',
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 92,
                      child: _Field(
                        label: 'Quantity',
                        controller: draft.quantity,
                        hint: '10',
                        number: true,
                      ),
                    ),
                  ],
                ),
                _Field(
                  label: 'Frequency',
                  controller: draft.frequency,
                  hint: 'Morning-noon-night, e.g. 1-0-1',
                  bottom: 8,
                ),
                _chips(draft.frequency, _frequencies),
                const SizedBox(height: 12),
                _Field(
                  label: 'Duration',
                  controller: draft.duration,
                  hint: 'e.g. 5 days',
                  bottom: 8,
                ),
                _chips(draft.duration, _durations),
                const SizedBox(height: 12),
                _Field(
                  label: 'Instructions',
                  controller: draft.instructions,
                  hint: 'e.g. After food',
                  bottom: 8,
                ),
                _chips(draft.instructions, _food),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A text field on the grey medicine card: white fill so it reads as an
/// input against the panel.
class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool required;
  final bool number;
  final String? errorText;
  final double bottom;

  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.required = false,
    this.number = false,
    this.errorText,
    this.bottom = 12,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context).color;
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppColors.radiusInput),
      borderSide: c == Colors.transparent
          ? BorderSide.none
          : BorderSide(color: c, width: w),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            required ? '$label *' : label,
            style: AppType.sans(
              fontSize: AppType.caption,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 5),
          TextField(
            controller: controller,
            keyboardType: number ? TextInputType.number : TextInputType.text,
            inputFormatters: number
                ? [FilteringTextInputFormatter.digitsOnly]
                : null,
            textCapitalization: number
                ? TextCapitalization.none
                : TextCapitalization.sentences,
            cursorColor: accent,
            style: AppType.sans(
              fontSize: AppType.body,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AppColors.bg,
              hintText: hint,
              hintStyle: AppType.sans(
                fontSize: AppType.small,
                color: AppColors.textTertiary,
              ),
              errorText: errorText,
              errorStyle: AppType.sans(fontSize: 11, color: AppColors.error),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
              border: border(Colors.transparent),
              enabledBorder: border(Colors.transparent),
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
