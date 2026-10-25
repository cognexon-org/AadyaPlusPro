import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';

// Small pieces shared by the physio Profile tab and its settings screens.

/// Non-empty trimmed strings from a list (or a lone string) field.
List<String> physioStrings(dynamic v) => v is List
    ? v.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList()
    : (v is String && v.trim().isNotEmpty ? [v.trim()] : <String>[]);

/// "600" from 600.0, "" for a missing or non-positive amount.
String physioAmountText(dynamic v) {
  final n = num.tryParse('${v ?? ''}');
  if (n == null || n <= 0) return '';
  return n == n.roundToDouble() ? n.toInt().toString() : '$n';
}

/// A settings tile: icon chip, title, one-line subtitle, chevron.
class PhysioProfileTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const PhysioProfileTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => AppPressable(
    scale: 0.985,
    onTap: onTap,
    child: Container(
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(14, 12, 11, 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: AppColors.textHeading),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppType.sans(
                    fontWeight: FontWeight.w600,
                    fontSize: AppType.small,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.sans(
                    fontSize: AppType.caption,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            LucideIcons.chevronRight,
            size: 15,
            color: AppColors.textDisabled,
          ),
        ],
      ),
    ),
  );
}

/// A removable chip on the accent's very light tint.
class PhysioRemovableChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onRemove;

  const PhysioRemovableChip({
    super.key,
    required this.label,
    required this.onRemove,
    this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(11, 6, 6, 6),
    decoration: BoxDecoration(
      color: ModuleAccent.of(context).veryLight,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.sans(
              fontSize: AppType.caption,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 4),
        AppPressable(
          semanticLabel: 'Remove $label',
          onTap: onRemove,
          child: const Padding(
            padding: EdgeInsets.all(2),
            child: Icon(
              LucideIcons.x,
              size: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

/// A list of short values — specialisations, degrees, languages — typed one
/// at a time and shown as removable chips. Owns its own text controller.
class PhysioChipsInput extends StatefulWidget {
  final String label;
  final String hint;
  final IconData icon;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final bool required;
  final String? errorText;

  const PhysioChipsInput({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    required this.values,
    required this.onChanged,
    this.required = false,
    this.errorText,
  });

  @override
  State<PhysioChipsInput> createState() => _PhysioChipsInputState();
}

class _PhysioChipsInputState extends State<PhysioChipsInput> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _add() {
    final values = _controller.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    final next = [...widget.values];
    for (final v in values) {
      if (!next.any((e) => e.toLowerCase() == v.toLowerCase())) next.add(v);
    }
    _controller.clear();
    if (next.length != widget.values.length) widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context).color;
    final canAdd = _controller.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            label: widget.label,
            controller: _controller,
            icon: widget.icon,
            hint: widget.hint,
            required: widget.required,
            errorText: widget.errorText,
            dense: true,
            margin: EdgeInsets.zero,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _add(),
            trailing: TextButton(
              onPressed: canAdd ? _add : null,
              child: Text(
                'Add',
                style: AppType.sans(
                  fontSize: AppType.small,
                  fontWeight: FontWeight.w600,
                  color: canAdd ? accent : AppColors.textDisabled,
                ),
              ),
            ),
          ),
          if (widget.values.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final v in widget.values)
                  PhysioRemovableChip(
                    label: v,
                    onRemove: () =>
                        widget.onChanged([...widget.values]..remove(v)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────── Services ───────────────────────────

/// One treatment the physio offers, as listed on their public profile.
class PhysioService {
  final String name;
  final String description;
  final int? duration;
  final num? price;

  const PhysioService({
    required this.name,
    this.description = '',
    this.duration,
    this.price,
  });

  static PhysioService? fromJson(dynamic json) {
    if (json is! Map) return null;
    final name = '${json['name'] ?? ''}'.trim();
    if (name.isEmpty) return null;
    return PhysioService(
      name: name,
      description: '${json['description'] ?? ''}'.trim(),
      duration: int.tryParse('${json['duration'] ?? ''}'),
      price: num.tryParse('${json['price'] ?? ''}'),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (description.isNotEmpty) 'description': description,
    'duration': ?duration,
    'price': ?price,
  };

  String get summary => [
    if (duration != null && duration! > 0) '$duration min',
    if (price != null && price! > 0) appRupees(price),
  ].join(' · ');

  String get key => '$name|$description|$duration|$price';
}

/// Add or change one service. Owns its controllers; resolves to the edited
/// service, or null when dismissed.
Future<PhysioService?> showPhysioServiceSheet(
  BuildContext context, {
  PhysioService? initial,
}) => showAppSheet<PhysioService>(
  context,
  builder: (_) => _PhysioServiceSheet(initial: initial),
);

class _PhysioServiceSheet extends StatefulWidget {
  final PhysioService? initial;
  const _PhysioServiceSheet({this.initial});

  @override
  State<_PhysioServiceSheet> createState() => _PhysioServiceSheetState();
}

class _PhysioServiceSheetState extends State<_PhysioServiceSheet> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _description = TextEditingController(
    text: widget.initial?.description ?? '',
  );
  late final _duration = TextEditingController(
    text: widget.initial?.duration?.toString() ?? '',
  );
  late final _price = TextEditingController(
    text: physioAmountText(widget.initial?.price),
  );
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _duration, _price]) {
      c.addListener(_changed);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _duration, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (mounted && _submitted) setState(() {});
  }

  String? get _nameError =>
      _submitted && _name.text.trim().length < 2 ? 'Name the treatment.' : null;

  String? get _durationError {
    if (!_submitted || _duration.text.trim().isEmpty) return null;
    final n = int.tryParse(_duration.text.trim());
    return n == null || n < 5 || n > 480 ? 'Between 5 and 480 minutes.' : null;
  }

  String? get _priceError {
    if (!_submitted || _price.text.trim().isEmpty) return null;
    final n = num.tryParse(_price.text.trim());
    return n == null || n < 0 || n > 100000 ? 'Enter a valid price.' : null;
  }

  void _done() {
    setState(() => _submitted = true);
    if (_nameError != null || _durationError != null || _priceError != null) {
      return;
    }
    Navigator.of(context).pop(
      PhysioService(
        name: _name.text.trim(),
        description: _description.text.trim(),
        duration: int.tryParse(_duration.text.trim()),
        price: num.tryParse(_price.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.initial == null ? 'Add a service' : 'Edit service',
            style: AppType.sans(
              fontSize: AppType.title,
              fontWeight: FontWeight.w700,
              color: AppColors.textStrong,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Treatments patients see on your profile.',
            style: AppType.sans(
              fontSize: AppType.caption,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Name',
            controller: _name,
            hint: 'e.g. Knee rehabilitation',
            required: true,
            dense: true,
            errorText: _nameError,
            textCapitalization: TextCapitalization.sentences,
            margin: const EdgeInsets.only(bottom: 12),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Duration (min)',
                  controller: _duration,
                  icon: LucideIcons.clock,
                  isNum: true,
                  dense: true,
                  errorText: _durationError,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  margin: const EdgeInsets.only(bottom: 12),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(
                  label: 'Price',
                  controller: _price,
                  icon: LucideIcons.indianRupee,
                  isNum: true,
                  dense: true,
                  errorText: _priceError,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  margin: const EdgeInsets.only(bottom: 12),
                ),
              ),
            ],
          ),
          AppTextField(
            label: 'Description',
            controller: _description,
            hint: 'What the session involves (optional)',
            maxLines: 3,
            dense: true,
            textCapitalization: TextCapitalization.sentences,
            margin: const EdgeInsets.only(bottom: 18),
          ),
          AppButton(
            label: widget.initial == null ? 'Add service' : 'Done',
            onPressed: _done,
          ),
        ],
      ),
    );
  }
}
