import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import 'doctor_ui.dart';

// ─────────────────────────── Prescription fields ───────────────────────────
//
// One place that knows the Prescription document's shape (models/
// Prescription.js), so screens never guess keys. Medicines use
// `medicineName`; lab tests are `{testName, instructions, fastingRequired}`;
// advice is `{advice, category, priority}` — objects, not strings.

List<Map<String, dynamic>> rxMaps(dynamic value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Map<String, dynamic>>[];

List<String> rxStrings(dynamic value) => value is List
    ? value.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList()
    : (value is String && value.trim().isNotEmpty)
    ? [value.trim()]
    : <String>[];

Map<String, dynamic> rxMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

String rxId(Map<String, dynamic> rx) => '${rx['_id'] ?? ''}';

String rxStatus(Map<String, dynamic> rx) => '${rx['status'] ?? 'draft'}';

Map<String, dynamic> rxPatient(Map<String, dynamic> rx) =>
    rxMap(rx['patientId']);

String rxPatientName(Map<String, dynamic> rx) {
  final n = '${rxPatient(rx)['name'] ?? ''}'.trim();
  return n.isEmpty ? 'Patient' : n;
}

String rxNumber(Map<String, dynamic> rx) {
  final n = '${rx['prescriptionNumber'] ?? ''}'.trim();
  return n.isEmpty ? 'Prescription' : n;
}

DateTime? rxDate(dynamic iso) => DateTime.tryParse('${iso ?? ''}')?.toLocal();

/// The date that matters for a row: when it was issued, else when drafted.
DateTime? rxWhen(Map<String, dynamic> rx) =>
    rxDate(rx['issuedAt']) ?? rxDate(rx['createdAt']);

String rxFullDate(DateTime? d) =>
    d == null ? '—' : DateFormat('d MMM yyyy').format(d);

String rxDateTime(DateTime? d) =>
    d == null ? '—' : DateFormat('d MMM yyyy, h:mm a').format(d);

String rxMedicineName(Map<String, dynamic> m) {
  final n = '${m['medicineName'] ?? m['name'] ?? ''}'.trim();
  return n.isEmpty ? 'Medicine' : n;
}

/// "650 mg · 1-0-1 · 5 days" — whatever parts are filled in.
String rxDosageLine(Map<String, dynamic> m) => [
  m['dosage'],
  m['frequency'],
  m['duration'],
].map((e) => '${e ?? ''}'.trim()).where((e) => e.isNotEmpty).join(' · ');

String rxPatientMeta(Map<String, dynamic> patient) => [
  if (patient['age'] != null && '${patient['age']}'.isNotEmpty)
    '${patient['age']} yrs',
  if ('${patient['gender'] ?? ''}'.trim().isNotEmpty)
    rxCap('${patient['gender']}'.trim()),
  if ('${patient['phone'] ?? ''}'.trim().isNotEmpty)
    '${patient['phone']}'.trim(),
].join(' · ');

String rxCap(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String rxStatusLabel(String s) => switch (s) {
  'draft' => 'Draft',
  'issued' => 'Issued',
  'cancelled' => 'Cancelled',
  'superseded' => 'Superseded',
  _ => rxCap(s),
};

/// Draft amber, issued accent, cancelled red, superseded grey.
Color rxStatusColor(BuildContext context, String s) => switch (s) {
  'draft' => AppColors.warning,
  'issued' => ModuleAccent.of(context).color,
  'cancelled' => AppColors.error,
  _ => AppColors.textTertiary,
};

/// Pulls the prescription out of `{prescription: {...}}` or a bare map.
Map<String, dynamic>? rxFromResponse(dynamic data) {
  if (data is Map) {
    final p = data['prescription'];
    if (p is Map) return Map<String, dynamic>.from(p);
    if (data['_id'] != null) return Map<String, dynamic>.from(data);
  }
  return null;
}

// ─────────────────────────── Widgets ───────────────────────────

/// Status as coloured text with a dot, like [ApptStatusTag].
class RxStatusTag extends StatelessWidget {
  final String status;
  const RxStatusTag(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = rxStatusColor(context, status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          rxStatusLabel(status),
          style: AppType.sans(
            fontSize: AppType.caption,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// White app bar with a Lucide back arrow and an optional subtitle.
PreferredSizeWidget rxAppBar(
  BuildContext context, {
  required String title,
  String? subtitle,
  List<Widget>? actions,
}) {
  final canPop = Navigator.of(context).canPop();
  return AppBar(
    backgroundColor: AppColors.bg,
    elevation: 0,
    scrolledUnderElevation: 0,
    surfaceTintColor: Colors.transparent,
    automaticallyImplyLeading: false,
    titleSpacing: canPop ? 0 : 16,
    leading: canPop
        ? IconButton(
            tooltip: 'Back',
            icon: const Icon(
              LucideIcons.arrowLeft,
              size: 20,
              color: AppColors.textPrimary,
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          )
        : null,
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.sans(
            fontSize: subtitle == null ? AppType.title : AppType.body,
            fontWeight: FontWeight.w700,
            color: AppColors.textStrong,
          ),
        ),
        if (subtitle != null && subtitle.isNotEmpty)
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.sans(
              fontSize: AppType.micro,
              color: AppColors.textTertiary,
            ),
          ),
      ],
    ),
    actions: actions,
  );
}

/// The sticky action strip under a form or detail screen.
class RxBottomBar extends StatelessWidget {
  final Widget child;
  final Widget? above;
  const RxBottomBar({super.key, required this.child, this.above});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: const BoxDecoration(
      color: AppColors.bg,
      border: Border(top: BorderSide(color: AppColors.borderStrong)),
    ),
    child: SafeArea(
      top: false,
      child: Column(mainAxisSize: MainAxisSize.min, children: [?above, child]),
    ),
  );
}

/// A small tappable suggestion, e.g. "1-0-1" or "After food". Lighter than
/// [AppFilterChip] so a row of them under a field doesn't shout.
class RxQuickChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const RxQuickChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    return AppPressable(
      scale: 0.95,
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent.light : AppColors.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? accent.light : AppColors.borderStrong,
          ),
        ),
        child: Text(
          label,
          style: AppType.sans(
            fontSize: AppType.caption,
            fontWeight: FontWeight.w600,
            color: selected ? accent.color : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// A list of short strings (diagnoses, symptoms, tests) typed one at a time
/// and shown as removable chips. Owns its text controller.
class RxChipsInput extends StatefulWidget {
  final String label;
  final String hint;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final List<String> suggestions;
  final bool required;
  final String? errorText;
  final IconData icon;

  const RxChipsInput({
    super.key,
    required this.label,
    required this.hint,
    required this.values,
    required this.onChanged,
    this.suggestions = const [],
    this.required = false,
    this.errorText,
    this.icon = LucideIcons.plus,
  });

  @override
  State<RxChipsInput> createState() => _RxChipsInputState();
}

class _RxChipsInputState extends State<RxChipsInput> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add([String? text]) {
    final parts = (text ?? _controller.text)
        .split(RegExp(r'[,\n]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    final next = [...widget.values];
    for (final p in parts) {
      if (!next.any((v) => v.toLowerCase() == p.toLowerCase())) next.add(p);
    }
    if (text == null) _controller.clear();
    if (next.length != widget.values.length) widget.onChanged(next);
  }

  void _remove(String v) => widget.onChanged([...widget.values]..remove(v));

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    final unused = widget.suggestions
        .where(
          (s) => !widget.values.any((v) => v.toLowerCase() == s.toLowerCase()),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          label: widget.label,
          controller: _controller,
          hint: widget.hint,
          required: widget.required,
          errorText: widget.errorText,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            _add();
            _focus.requestFocus();
          },
          margin: EdgeInsets.zero,
          trailing: IconButton(
            tooltip: 'Add',
            icon: Icon(widget.icon, size: 18, color: accent.color),
            onPressed: _add,
          ),
        ),
        if (widget.values.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final v in widget.values)
                Container(
                  key: ValueKey('chip-$v'),
                  padding: const EdgeInsets.fromLTRB(11, 6, 4, 6),
                  decoration: BoxDecoration(
                    color: accent.veryLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          v,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.sans(
                            fontSize: AppType.small,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textStrong,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      InkResponse(
                        radius: 14,
                        onTap: () => _remove(v),
                        child: const Padding(
                          padding: EdgeInsets.all(3),
                          child: Icon(
                            LucideIcons.x,
                            size: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
        if (unused.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in unused.take(6))
                RxQuickChip(
                  label: '+ $s',
                  selected: false,
                  onTap: () => _add(s),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A label/value row inside an [AppGroup].
class RxInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const RxInfoRow(this.label, this.value, {super.key, this.valueColor});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: AppType.sans(
              fontSize: AppType.small,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: AppType.sans(
              fontSize: AppType.small,
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppColors.textStrong,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The patient line used by the list, editor and details.
class RxPatientRow extends StatelessWidget {
  final String name;
  final String meta;
  final Widget? trailing;
  const RxPatientRow({
    super.key,
    required this.name,
    required this.meta,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
    child: Row(
      children: [
        DoctorAvatar(name: name, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.sans(
                  fontSize: AppType.title,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textStrong,
                ),
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.sans(
                    fontSize: AppType.caption,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    ),
  );
}
