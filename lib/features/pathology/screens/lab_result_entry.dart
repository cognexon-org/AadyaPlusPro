import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../providers/lab_providers.dart';
import '../widgets/lab_ui.dart';

/// Typing results the way a technician reads an analyser: one row per
/// parameter with its unit and reference range already filled in, and each
/// value flagged High / Low / Critical the moment it's typed. Tests without
/// defined parameters get free rows.
class LabResultEntry extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;

  /// { TESTCODE: { parameters: [...] } } from the order detail response.
  final Map<String, dynamic> catalog;

  const LabResultEntry({super.key, required this.order, required this.catalog});

  @override
  ConsumerState<LabResultEntry> createState() => _LabResultEntryState();
}

/// One editable result line.
class _Line {
  final String testCode;
  final Map<String, dynamic> param; // name, unit, low, high, critLow, critHigh, text
  final bool custom;
  final TextEditingController value;
  final TextEditingController name;
  final TextEditingController unit;
  final TextEditingController range;

  _Line({
    required this.testCode,
    required this.param,
    required String initial,
    this.custom = false,
  }) : value = TextEditingController(text: initial),
       name = TextEditingController(text: '${param['name'] ?? ''}'),
       unit = TextEditingController(text: '${param['unit'] ?? ''}'),
       range = TextEditingController(text: '${param['normalRange'] ?? ''}');

  bool get numeric => param['low'] != null || param['high'] != null;
  String get paramName => custom ? name.text.trim() : '${param['name']}';

  void dispose() {
    value.dispose();
    name.dispose();
    unit.dispose();
    range.dispose();
  }
}

class _LabResultEntryState extends ConsumerState<LabResultEntry> {
  late final List<Map<String, dynamic>> _tests = labTests(widget.order);
  final Map<String, List<_Line>> _lines = {};
  late final _notes = TextEditingController(
    text: '${widget.order['resultNotes'] ?? ''}',
  );
  bool _dirty = false;
  String? _busy;

  @override
  void initState() {
    super.initState();
    for (final t in _tests) {
      final code = '${t['testCode']}'.toUpperCase();
      final params = ((widget.catalog[code] as Map?)?['parameters'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final existing = {
        for (final r in (t['results'] as List? ?? const []).whereType<Map>())
          '${r['parameter']}'.toLowerCase(): Map<String, dynamic>.from(r),
      };
      final lines = <_Line>[
        for (final p in params)
          _Line(
            testCode: code,
            param: p,
            initial: '${existing['${p['name']}'.toLowerCase()]?['value'] ?? ''}',
          ),
      ];
      // Results entered for parameters the catalogue doesn't list (or a
      // test with no parameters at all) stay editable as free rows.
      final known = params.map((p) => '${p['name']}'.toLowerCase()).toSet();
      for (final r in existing.values) {
        if (known.contains('${r['parameter']}'.toLowerCase())) continue;
        lines.add(
          _Line(
            testCode: code,
            param: {
              'name': r['parameter'],
              'unit': r['unit'],
              'normalRange': r['normalRange'],
            },
            initial: '${r['value'] ?? ''}',
            custom: true,
          ),
        );
      }
      if (lines.isEmpty) {
        lines.add(_Line(testCode: code, param: const {}, initial: '', custom: true));
      }
      _lines[code] = lines;
    }
    for (final l in _all) {
      l.value.addListener(_changed);
      l.name.addListener(_changed);
    }
    _notes.addListener(_changed);
  }

  Iterable<_Line> get _all => _lines.values.expand((l) => l);

  void _changed() => setState(() => _dirty = true);

  @override
  void dispose() {
    for (final l in _all) {
      l.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  int get _filled =>
      _all.where((l) => l.value.text.trim().isNotEmpty && l.paramName.isNotEmpty).length;

  bool get _everyTestHasAValue => _lines.values.every(
    (lines) => lines.any((l) => l.value.text.trim().isNotEmpty && l.paramName.isNotEmpty),
  );

  String? _flagOf(_Line l) => l.custom
      ? null
      : labFlagFor(l.param, l.value.text);

  void _addRow(String code) {
    final line = _Line(testCode: code, param: const {}, initial: '', custom: true);
    line.value.addListener(_changed);
    line.name.addListener(_changed);
    setState(() {
      _lines[code]!.add(line);
      _dirty = true;
    });
  }

  void _removeRow(String code, _Line line) {
    setState(() {
      _lines[code]!.remove(line);
      _dirty = true;
    });
    line.dispose();
  }

  List<Map<String, dynamic>> _payload() => [
    for (final e in _lines.entries)
      {
        'testCode': e.key,
        'values': [
          for (final l in e.value)
            if (l.paramName.isNotEmpty)
              {
                'parameter': l.paramName,
                'value': l.value.text.trim(),
                if (l.custom) 'unit': l.unit.text.trim(),
                if (l.custom && l.range.text.trim().isNotEmpty)
                  'normalRange': l.range.text.trim(),
              },
        ],
      },
  ];

  Future<void> _save({required bool finalise}) async {
    if (_busy != null) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = finalise ? 'final' : 'draft');
    try {
      await ref.read(labOrdersProvider.notifier).saveResults(
        '${widget.order['_id']}',
        results: _payload(),
        notes: _notes.text.trim(),
        finalise: finalise,
      );
      if (!mounted) return;
      _dirty = false;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showAppError(
        context,
        null,
        fallback: labError(e, fallback: 'Couldn’t save the results.'),
      );
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final leave = await AppModal.show<bool>(
      context,
      title: 'Discard results?',
      subtitle: 'Values typed since the last save will be lost.',
      icon: LucideIcons.triangleAlert,
      accentColor: AppColors.warning,
      content: const SizedBox.shrink(),
      actions: [
        AppSecondaryButton(
          label: 'Keep editing',
          fullWidth: false,
          onPressed: () => Navigator.pop(context, false),
        ),
        AppButton(
          label: 'Discard',
          fullWidth: false,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    return leave == true;
  }

  @override
  Widget build(BuildContext context) {
    final total = _all.length;
    final abnormal = _all.where((l) {
      final f = _flagOf(l);
      return f != null && f != 'normal';
    }).length;
    final critical = _all.where((l) => _flagOf(l) == 'critical').length;
    final accent = ModuleAccent.of(context).color;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          _dirty = false;
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter results',
                style: AppType.sans(
                  fontSize: AppType.title,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '${labPatientName(widget.order)} · ${labNumber(widget.order)}',
                style: AppType.sans(
                  fontSize: AppType.caption,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Progress + what's out of range so far.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '$_filled of $total entered',
                          style: AppType.sans(
                            fontSize: AppType.small,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const Spacer(),
                        if (critical > 0)
                          _Pill('$critical critical', AppColors.error)
                        else if (abnormal > 0)
                          _Pill('$abnormal out of range', const Color(0xFFC2410C)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: total == 0 ? 0 : _filled / total,
                        minHeight: 5,
                        color: accent,
                        backgroundColor: AppColors.border,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    for (final t in _tests) ...[
                      _testHeader(t),
                      AppGroup(
                        children: [
                          for (var i = 0;
                              i < _lines['${t['testCode']}'.toUpperCase()]!.length;
                              i++) ...[
                            if (i > 0) const AppHairline(),
                            _lineRow(
                              '${t['testCode']}'.toUpperCase(),
                              _lines['${t['testCode']}'.toUpperCase()]![i],
                            ),
                          ],
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              _addRow('${t['testCode']}'.toUpperCase()),
                          icon: Icon(LucideIcons.plus, size: 15, color: accent),
                          label: Text(
                            'Add parameter',
                            style: AppType.sans(
                              fontSize: AppType.caption,
                              fontWeight: FontWeight.w700,
                              color: accent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const AppSectionTitle('Remarks'),
                    AppTextField(
                      label: '',
                      hint: 'Interpretation or comments printed on the report',
                      controller: _notes,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      margin: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: const BoxDecoration(
                  color: AppColors.bg,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: AppSecondaryButton(
                        label: _busy == 'draft' ? 'Saving…' : 'Save draft',
                        onPressed: _busy != null || _filled == 0
                            ? null
                            : () => _save(finalise: false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: AppButton(
                        label: 'Ready to release',
                        icon: LucideIcons.check,
                        loading: _busy == 'final',
                        onPressed: _busy != null || !_everyTestHasAValue
                            ? null
                            : () => _save(finalise: true),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _testHeader(Map<String, dynamic> t) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '${t['testName'] ?? t['testCode']}',
            style: AppType.sans(
              fontSize: AppType.title,
              fontWeight: FontWeight.w700,
              color: AppColors.textStrong,
            ),
          ),
        ),
        if ('${t['sampleType'] ?? ''}'.isNotEmpty) TubeChip('${t['sampleType']}'),
      ],
    ),
  );

  Widget _lineRow(String code, _Line l) {
    if (l.custom) return _customRow(code, l);
    final flag = _flagOf(l);
    final color = labFlagColor(flag);
    final range = labRangeText(l.param);
    final unit = '${l.param['unit'] ?? ''}';
    final expected = '${l.param['text'] ?? ''}'.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.paramName,
                      style: AppType.sans(
                        fontSize: AppType.body,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      [
                        if (range.isNotEmpty) range,
                        if (unit.isNotEmpty && l.numeric) unit,
                      ].join(' '),
                      style: AppType.sans(
                        fontSize: AppType.caption,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 118,
                child: TextField(
                  controller: l.value,
                  textAlign: TextAlign.right,
                  textInputAction: TextInputAction.next,
                  keyboardType: l.numeric
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.text,
                  inputFormatters: l.numeric
                      ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,<>]'))]
                      : null,
                  style: AppType.sans(
                    fontSize: AppType.title,
                    fontWeight: flag != null && flag != 'normal'
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: color,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: l.numeric ? '—' : (expected.isEmpty ? 'Result' : expected),
                    hintStyle: AppType.sans(
                      fontSize: AppType.body,
                      color: AppColors.textDisabled,
                    ),
                    suffixText: l.numeric && unit.isNotEmpty ? ' $unit' : null,
                    suffixStyle: AppType.sans(
                      fontSize: AppType.micro,
                      color: AppColors.textTertiary,
                    ),
                    filled: true,
                    fillColor: flag == 'critical'
                        ? AppColors.error.withValues(alpha: 0.07)
                        : flag != null && flag != 'normal'
                        ? color.withValues(alpha: 0.06)
                        : AppColors.bg,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    // Empty fields need an edge, or they vanish into the row.
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: flag == null || flag == 'normal'
                            ? AppColors.border
                            : Colors.transparent,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: ModuleAccent.of(context).color,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 54,
                child: Text(
                  labFlagLabel(flag),
                  textAlign: TextAlign.right,
                  style: AppType.sans(
                    fontSize: AppType.micro,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          // Qualitative tests: one tap for the usual answers.
          if (!l.numeric) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.end,
                children: [
                  for (final q in _quickAnswers(expected))
                    AppFilterChip(
                      label: q,
                      selected: l.value.text.trim().toLowerCase() == q.toLowerCase(),
                      onTap: () => l.value.text = q,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<String> _quickAnswers(String expected) {
    final e = expected.toLowerCase();
    if (e == 'negative' || e == 'positive') return const ['Negative', 'Positive'];
    if (e.contains('reactive')) return const ['Non-reactive', 'Reactive'];
    if (e == 'clear') return const ['Clear', 'Slightly turbid', 'Turbid'];
    if (e == 'pale yellow') return const ['Pale yellow', 'Yellow', 'Dark yellow'];
    if (expected.isEmpty) return const [];
    return [expected];
  }

  Widget _customRow(String code, _Line l) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 10, 4, 6),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _MiniField(controller: l.name, hint: 'Parameter'),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _MiniField(controller: l.value, hint: 'Result', bold: true),
            ),
            IconButton(
              tooltip: 'Remove',
              onPressed: () => _removeRow(code, l),
              icon: const Icon(
                LucideIcons.x,
                size: 16,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: _MiniField(controller: l.unit, hint: 'Unit')),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _MiniField(controller: l.range, hint: 'Reference range'),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ],
    ),
  );
}

class _MiniField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool bold;
  const _MiniField({
    required this.controller,
    required this.hint,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    textCapitalization: TextCapitalization.sentences,
    style: AppType.sans(
      fontSize: AppType.body,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      color: AppColors.textPrimary,
    ),
    decoration: InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: AppType.sans(
        fontSize: AppType.small,
        color: AppColors.textDisabled,
      ),
      filled: true,
      fillColor: AppColors.bg,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: AppType.sans(
        fontSize: AppType.micro,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );
}
