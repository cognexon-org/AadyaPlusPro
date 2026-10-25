import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/availability_save_bar.dart';
import '../../pharmacy/widgets/pharmacy_ui.dart'
    show PharmacyUpperCaseFormatter;
import '../providers/lab_providers.dart';
import '../widgets/lab_ui.dart';

const _categories = [
  'Haematology',
  'Diabetes',
  'Heart',
  'Liver',
  'Kidney',
  'Thyroid',
  'Vitamins',
  'Hormones',
  'Infection',
  'Inflammation',
  'Urine',
  'Bone',
  'Allergy',
  'Cancer markers',
];

const _sampleTypes = [
  'Blood (EDTA)',
  'Blood (serum)',
  'Blood (fluoride)',
  'Blood (citrate)',
  'Urine',
  'Stool',
  'Swab',
  'Other',
];

/// One parameter row's fields, kept as controllers while editing.
class _Param {
  final name = TextEditingController();
  final unit = TextEditingController();
  final low = TextEditingController();
  final high = TextEditingController();
  final critLow = TextEditingController();
  final critHigh = TextEditingController();
  final text = TextEditingController();
  bool qualitative = false;
  bool showCritical = false;
  final key = UniqueKey();

  _Param();

  factory _Param.from(Map<String, dynamic> p) {
    String s(dynamic v) => v == null ? '' : '$v';
    final r = _Param()
      ..name.text = s(p['name'])
      ..unit.text = s(p['unit'])
      ..low.text = s(p['low'])
      ..high.text = s(p['high'])
      ..critLow.text = s(p['critLow'])
      ..critHigh.text = s(p['critHigh'])
      ..text.text = s(p['text']);
    r.qualitative =
        p['low'] == null && p['high'] == null && s(p['text']).isNotEmpty;
    r.showCritical = p['critLow'] != null || p['critHigh'] != null;
    return r;
  }

  List<TextEditingController> get all => [
    name,
    unit,
    low,
    high,
    critLow,
    critHigh,
    text,
  ];

  Map<String, dynamic> toJson() {
    num? n(TextEditingController c) => num.tryParse(c.text.trim());
    return {
      'name': name.text.trim(),
      'unit': unit.text.trim(),
      if (!qualitative) ...{
        'low': n(low),
        'high': n(high),
        'critLow': n(critLow),
        'critHigh': n(critHigh),
      },
      if (qualitative) 'text': text.text.trim(),
    };
  }

  void dispose() {
    for (final c in all) {
      c.dispose();
    }
  }
}

/// Add or edit one catalogue test: what it costs, which tube, how long the
/// report takes, and the parameters result entry will ask for.
class LabTestEditor extends ConsumerStatefulWidget {
  final Map<String, dynamic>? test;
  const LabTestEditor({super.key, this.test});

  @override
  ConsumerState<LabTestEditor> createState() => _LabTestEditorState();
}

class _LabTestEditorState extends ConsumerState<LabTestEditor> {
  late final Map<String, dynamic> _t = widget.test ?? const {};
  bool get _editing => widget.test != null && '${_t['_id'] ?? ''}'.isNotEmpty;

  late final _code = TextEditingController(text: '${_t['testCode'] ?? ''}');
  late final _name = TextEditingController(text: '${_t['testName'] ?? ''}');
  late final _price = TextEditingController(text: _s(_t['price']));
  late final _mrp = TextEditingController(text: _s(_t['mrp']));
  late final _tat = TextEditingController(text: _s(_t['reportTime']));
  late final _fastingHours = TextEditingController(
    text: _s(_t['fastingHours']),
  );
  late final _prep = TextEditingController(text: '${_t['preparation'] ?? ''}');
  late String _category = '${_t['category'] ?? ''}';
  late String _sample = '${_t['sampleType'] ?? ''}';
  late bool _fasting = _t['fastingRequired'] == true;
  late bool _home = _t['homeCollectionEligible'] != false;
  late final List<_Param> _params = [
    for (final p in (_t['parameters'] is List ? _t['parameters'] as List : []))
      if (p is Map) _Param.from(Map<String, dynamic>.from(p)),
  ];
  bool _saving = false;
  String? _error;

  static String _s(dynamic v) {
    if (v == null) return '';
    final n = num.tryParse('$v');
    if (n == null) return '$v';
    return n == 0 ? '' : (n == n.roundToDouble() ? '${n.toInt()}' : '$n');
  }

  @override
  void dispose() {
    for (final c in [_code, _name, _price, _mrp, _tat, _fastingHours, _prep]) {
      c.dispose();
    }
    for (final p in _params) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _pickCategory() async {
    final custom = TextEditingController();
    final picked = await showAppSheet<String>(
      context,
      builder: (ctx) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetTitle('Category'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _categories)
                  AppFilterChip(
                    label: c,
                    selected: c == _category,
                    onTap: () => Navigator.pop(ctx, c),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Or type your own',
              controller: custom,
              textCapitalization: TextCapitalization.words,
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            AppButton(
              label: 'Use this',
              onPressed: () => Navigator.pop(ctx, custom.text.trim()),
            ),
          ],
        ),
      ),
    );
    custom.dispose();
    if (picked != null && picked.isNotEmpty && mounted) {
      setState(() => _category = picked);
    }
  }

  Future<void> _pickSample() async {
    final picked = await showAppSheet<String>(
      context,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _sheetTitle('Sample type'),
          for (final s in _sampleTypes)
            InkWell(
              onTap: () => Navigator.pop(ctx, s),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 11,
                  horizontal: 4,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: tubeFor(s).color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        s,
                        style: AppType.sans(
                          fontSize: AppType.body,
                          fontWeight: s == _sample
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (s == _sample)
                      Icon(
                        LucideIcons.check,
                        size: 16,
                        color: ModuleAccent.of(context).color,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (picked != null && mounted) setState(() => _sample = picked);
  }

  Widget _sheetTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      t,
      style: AppType.sans(
        fontSize: AppType.title,
        fontWeight: FontWeight.w700,
        color: AppColors.textStrong,
      ),
    ),
  );

  Future<void> _save() async {
    final code = _code.text.trim().toUpperCase();
    final name = _name.text.trim();
    final price = num.tryParse(_price.text.trim());
    if (code.isEmpty || name.isEmpty || price == null || price < 0) {
      setState(() => _error = 'Code, name and a valid price are needed.');
      return;
    }
    final bad = _params.where(
      (p) =>
          p.name.text.trim().isEmpty &&
          p.all.any((c) => c.text.trim().isNotEmpty),
    );
    if (bad.isNotEmpty) {
      setState(() => _error = 'Every parameter needs a name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final data = {
      'testCode': code,
      'testName': name,
      'category': _category,
      'sampleType': _sample,
      'price': price,
      'mrp': num.tryParse(_mrp.text.trim()) ?? price,
      'reportTime': num.tryParse(_tat.text.trim()) ?? 0,
      'fastingRequired': _fasting,
      'fastingHours': _fasting
          ? (num.tryParse(_fastingHours.text.trim()) ?? 8)
          : 0,
      'homeCollectionEligible': _home,
      'preparation': _prep.text.trim(),
      'parameters': [
        for (final p in _params)
          if (p.name.text.trim().isNotEmpty) p.toJson(),
      ],
    };
    try {
      await ref
          .read(labCatalogProvider.notifier)
          .saveTest(data, id: _editing ? '${_t['_id']}' : null);
      if (!mounted) return;
      doctorToast(context, _editing ? 'Test updated' : 'Test added');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = labError(e, fallback: 'Couldn’t save the test.');
        });
      }
    }
  }

  Future<void> _toggleActive() async {
    final active = _t['isActive'] != false;
    if (active) {
      final ok = await AppModal.confirm(
        context,
        title: 'Stop offering this test?',
        message:
            'Patients won’t be able to book it. Orders already booked are '
            'not affected, and you can restore it any time.',
        icon: LucideIcons.archive,
        confirmLabel: 'Deactivate',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(labCatalogProvider.notifier)
          .setTestActive('${_t['_id']}', !active);
      if (!mounted) return;
      doctorToast(context, active ? 'Test deactivated' : 'Test restored');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        doctorToast(context, labError(e), error: true);
      }
    }
  }

  void _addParam() => setState(() => _params.add(_Param()));

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: doctorSettingsAppBar(_editing ? 'Edit test' : 'New test'),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(
          color: AppColors.bg,
          border: Border(top: BorderSide(color: AppColors.borderStrong)),
        ),
        child: SafeArea(
          top: false,
          child: AppButton(
            label: _editing ? 'Save changes' : 'Add test',
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          if (_error != null) ...[
            AppErrorBanner(message: _error!),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: AppTextField(
                  label: 'Code',
                  controller: _code,
                  readOnly: _editing,
                  required: true,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9_-]')),
                    PharmacyUpperCaseFormatter(),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppTextField(
                  label: 'Test name',
                  controller: _name,
                  required: true,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
            ],
          ),
          AppPickerField(
            label: 'Category',
            valueText: _category.isEmpty ? 'Choose' : _category,
            icon: LucideIcons.tag,
            onTap: _pickCategory,
          ),
          AppPickerField(
            label: 'Sample type',
            valueText: _sample.isEmpty ? 'Choose' : _sample,
            icon: LucideIcons.testTube,
            onTap: _pickSample,
          ),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Price (₹)',
                  controller: _price,
                  isDecimal: true,
                  required: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppTextField(
                  label: 'MRP (₹)',
                  controller: _mrp,
                  isDecimal: true,
                  hint: 'Same as price',
                ),
              ),
            ],
          ),
          AppTextField(
            label: 'Report ready in (hours)',
            controller: _tat,
            isNum: true,
            hint: 'e.g. 12',
            icon: LucideIcons.clock,
          ),
          AppSwitchRow(
            label: 'Fasting required',
            subtitle: 'Shown to the patient when they book',
            value: _fasting,
            onChanged: (v) => setState(() => _fasting = v),
          ),
          if (_fasting)
            AppTextField(
              label: 'Fasting hours',
              controller: _fastingHours,
              isNum: true,
              hint: '8',
            ),
          AppSwitchRow(
            label: 'Home collection',
            subtitle: 'Can be collected at the patient’s home',
            value: _home,
            onChanged: (v) => setState(() => _home = v),
          ),
          const SizedBox(height: 8),
          AppTextField(
            label: 'Preparation notes',
            controller: _prep,
            maxLines: 3,
            hint: 'e.g. Avoid alcohol 24 hours before',
          ),
          const SizedBox(height: 6),
          AppSectionTitle(
            _params.isEmpty ? 'Parameters' : 'Parameters · ${_params.length}',
            action: 'Add',
            onAction: _addParam,
          ),
          Text(
            'What result entry asks for. Ranges drive the H / L / critical '
            'flags on the report.',
            style: AppType.sans(
              fontSize: AppType.caption,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 10),
          if (_params.isEmpty)
            AppPressable(
              onTap: _addParam,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: accent.veryLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.plus, size: 18, color: accent.color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Add the first parameter, e.g. Haemoglobin',
                        style: AppType.sans(
                          fontSize: AppType.small,
                          fontWeight: FontWeight.w600,
                          color: accent.color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: (from, to) => setState(() {
                _params.insert(to, _params.removeAt(from));
              }),
              children: [
                for (var i = 0; i < _params.length; i++)
                  _ParamCard(
                    key: _params[i].key,
                    index: i,
                    param: _params[i],
                    onChanged: () => setState(() {}),
                    onRemove: () => setState(() {
                      _params.removeAt(i).dispose();
                    }),
                  ),
              ],
            ),
          if (_editing) ...[
            const SizedBox(height: 20),
            AppSecondaryButton(
              label: _t['isActive'] == false
                  ? 'Restore this test'
                  : 'Stop offering this test',
              icon: _t['isActive'] == false
                  ? LucideIcons.rotateCcw
                  : LucideIcons.archive,
              color: _t['isActive'] == false ? null : AppColors.error,
              onPressed: _saving ? null : _toggleActive,
            ),
          ],
        ],
      ),
    );
  }
}

class _ParamCard extends StatelessWidget {
  final int index;
  final _Param param;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  const _ParamCard({
    super.key,
    required this.index,
    required this.param,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context).color;
    final p = param;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 4),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.only(top: 30, right: 6),
                    child: Icon(
                      LucideIcons.gripVertical,
                      size: 16,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: AppTextField(
                    label: 'Parameter',
                    controller: p.name,
                    dense: true,
                    margin: const EdgeInsets.only(bottom: 8),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: AppTextField(
                    label: 'Unit',
                    controller: p.unit,
                    dense: true,
                    margin: const EdgeInsets.only(bottom: 8),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  padding: const EdgeInsets.only(top: 22),
                  onPressed: onRemove,
                  icon: const Icon(
                    LucideIcons.x,
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 22, right: 6),
              child: Column(
                children: [
                  if (!p.qualitative)
                    Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            label: 'Low',
                            controller: p.low,
                            isDecimal: true,
                            dense: true,
                            margin: const EdgeInsets.only(bottom: 8),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AppTextField(
                            label: 'High',
                            controller: p.high,
                            isDecimal: true,
                            dense: true,
                            margin: const EdgeInsets.only(bottom: 8),
                          ),
                        ),
                      ],
                    )
                  else
                    AppTextField(
                      label: 'Expected result',
                      controller: p.text,
                      hint: 'e.g. Negative',
                      dense: true,
                      margin: const EdgeInsets.only(bottom: 8),
                    ),
                  if (!p.qualitative && p.showCritical)
                    Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            label: 'Critical below',
                            controller: p.critLow,
                            isDecimal: true,
                            dense: true,
                            margin: const EdgeInsets.only(bottom: 8),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AppTextField(
                            label: 'Critical above',
                            controller: p.critHigh,
                            isDecimal: true,
                            dense: true,
                            margin: const EdgeInsets.only(bottom: 8),
                          ),
                        ),
                      ],
                    ),
                  Row(
                    children: [
                      _Toggle(
                        label: 'Qualitative',
                        on: p.qualitative,
                        onTap: () {
                          p.qualitative = !p.qualitative;
                          onChanged();
                        },
                      ),
                      if (!p.qualitative) ...[
                        const SizedBox(width: 14),
                        _Toggle(
                          label: 'Critical limits',
                          on: p.showCritical,
                          onTap: () {
                            p.showCritical = !p.showCritical;
                            onChanged();
                          },
                        ),
                      ],
                      const Spacer(),
                      Text(
                        labRangeText(p.toJson()),
                        style: AppType.sans(
                          fontSize: AppType.caption,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _Toggle({required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context).color;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              on ? LucideIcons.squareCheck : LucideIcons.square,
              size: 15,
              color: on ? accent : AppColors.textTertiary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppType.sans(
                fontSize: AppType.caption,
                fontWeight: FontWeight.w600,
                color: on ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
