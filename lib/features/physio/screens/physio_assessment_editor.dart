import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/network/api_service.dart';
import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/doctor_ui.dart';
import '../providers/physio_care_provider.dart';
import '../widgets/physio_progress_charts.dart';

const _sides = ['left', 'right', 'bilateral', 'na'];
const _results = ['positive', 'negative', 'inconclusive'];

num? _parse(TextEditingController c) => num.tryParse(c.text.trim());

String _numText(dynamic v) {
  final n = v is num ? v : num.tryParse('${v ?? ''}');
  if (n == null) return '';
  return n == n.roundToDouble() ? '${n.round()}' : '$n';
}

final _degFormatter = FilteringTextInputFormatter.allow(
  RegExp(r'^-?\d{0,3}(\.\d?)?'),
);
final _scoreFormatter = FilteringTextInputFormatter.allow(
  RegExp(r'^\d{0,4}(\.\d{0,2})?'),
);

int _seq = 0;

/// One editable row; owns its controllers.
abstract class _Row {
  final int id = ++_seq;
  List<TextEditingController> get controllers;
  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
  }
}

class _RomRow extends _Row {
  final joint = TextEditingController();
  final movement = TextEditingController();
  final active = TextEditingController();
  final passive = TextEditingController();
  String side = 'na';
  _RomRow([Map? m]) {
    if (m == null) return;
    joint.text = '${m['joint'] ?? ''}';
    movement.text = '${m['movement'] ?? ''}';
    active.text = _numText(m['activeDeg']);
    passive.text = _numText(m['passiveDeg']);
    side = _sides.contains(m['side']) ? '${m['side']}' : 'na';
  }
  @override
  List<TextEditingController> get controllers => [
    joint,
    movement,
    active,
    passive,
  ];

  String? degError(TextEditingController c) {
    if (c.text.trim().isEmpty) return null;
    final v = _parse(c);
    if (v == null) return 'Not a number';
    if (v < -90 || v > 360) return '−90 to 360';
    return null;
  }

  String? get jointError => joint.text.trim().isEmpty ? 'Required' : null;
  String? get movementError => movement.text.trim().isEmpty ? 'Required' : null;
  String? get activeError =>
      active.text.trim().isEmpty && passive.text.trim().isEmpty
      ? 'Enter a range'
      : degError(active);
  bool get valid =>
      jointError == null &&
      movementError == null &&
      activeError == null &&
      degError(passive) == null;

  Map<String, dynamic> toJson() => {
    'joint': joint.text.trim(),
    'movement': movement.text.trim(),
    'side': side,
    if (_parse(active) != null) 'activeDeg': _parse(active),
    if (_parse(passive) != null) 'passiveDeg': _parse(passive),
  };
}

class _StrengthRow extends _Row {
  final muscle = TextEditingController();
  String side = 'na';
  int? grade;
  _StrengthRow([Map? m]) {
    if (m == null) return;
    muscle.text = '${m['muscleGroup'] ?? ''}';
    side = _sides.contains(m['side']) ? '${m['side']}' : 'na';
    grade = num.tryParse('${m['grade'] ?? ''}')?.round();
  }
  @override
  List<TextEditingController> get controllers => [muscle];
  String? get muscleError => muscle.text.trim().isEmpty ? 'Required' : null;
  bool get valid => muscleError == null && grade != null;
  Map<String, dynamic> toJson() => {
    'muscleGroup': muscle.text.trim(),
    'side': side,
    'grade': grade,
  };
}

class _OutcomeRow extends _Row {
  final score = TextEditingController();
  final max = TextEditingController();
  String? code;
  _OutcomeRow([Map? m]) {
    if (m == null) return;
    final c = '${m['code'] ?? ''}'.toUpperCase();
    code = kOutcomeMeasures.containsKey(c) ? c : null;
    score.text = _numText(m['score']);
    max.text = _numText(m['maxScore']);
  }
  @override
  List<TextEditingController> get controllers => [score, max];

  String? get scoreError {
    final s = _parse(score);
    if (score.text.trim().isEmpty) return 'Required';
    if (s == null) return 'Not a number';
    final m = _parse(max);
    if (m != null && s > m) return 'Above the maximum';
    return null;
  }

  String? get maxError {
    if (max.text.trim().isEmpty) return null;
    final m = _parse(max);
    if (m == null || m <= 0) return 'Above 0';
    return null;
  }

  bool get valid => code != null && scoreError == null && maxError == null;
  Map<String, dynamic> toJson() => {
    'code': code,
    'score': _parse(score),
    if (_parse(max) != null) 'maxScore': _parse(max),
  };
}

class _TestRow extends _Row {
  final name = TextEditingController();
  String? result;
  _TestRow([Map? m]) {
    if (m == null) return;
    name.text = '${m['name'] ?? ''}';
    result = _results.contains(m['result']) ? '${m['result']}' : null;
  }
  @override
  List<TextEditingController> get controllers => [name];
  String? get nameError => name.text.trim().isEmpty ? 'Required' : null;
  bool get valid => nameError == null && result != null;
  Map<String, dynamic> toJson() => {'name': name.text.trim(), 'result': result};
}

/// Records (or edits) a structured assessment: pain, range of motion,
/// strength, outcome scores and special tests. Pops `true` once saved.
class PhysioAssessmentEditor extends ConsumerStatefulWidget {
  final String patientId;
  final String patientName;
  final String? appointmentId;
  final String? courseId;

  /// Editing an existing assessment when set.
  final Map<String, dynamic>? assessment;

  const PhysioAssessmentEditor({
    super.key,
    required this.patientId,
    required this.patientName,
    this.appointmentId,
    this.courseId,
    this.assessment,
  });

  @override
  ConsumerState<PhysioAssessmentEditor> createState() =>
      _PhysioAssessmentEditorState();
}

class _PhysioAssessmentEditorState
    extends ConsumerState<PhysioAssessmentEditor> {
  final _complaint = TextEditingController();
  final _functional = TextEditingController();
  final _plan = TextEditingController();
  String _type = 'progress';
  double? _painRest;
  double? _painActivity;
  final List<_RomRow> _rom = [];
  final List<_StrengthRow> _strength = [];
  final List<_OutcomeRow> _outcomes = [];
  final List<_TestRow> _tests = [];
  bool _tried = false;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.assessment != null;

  @override
  void initState() {
    super.initState();
    final a = widget.assessment;
    if (a != null) {
      _type = '${a['type'] ?? 'progress'}';
      _complaint.text = '${a['chiefComplaint'] ?? ''}';
      _functional.text = '${a['functionalNotes'] ?? ''}';
      _plan.text = '${a['plan'] ?? ''}';
      final pain = a['painScore'];
      if (pain is Map) {
        _painRest = (pain['rest'] as num?)?.toDouble();
        _painActivity = (pain['activity'] as num?)?.toDouble();
      }
      List<Map> list(String k) =>
          (a[k] is List ? a[k] as List : const []).whereType<Map>().toList();
      _rom.addAll(list('rom').map(_RomRow.new));
      _strength.addAll(list('strength').map(_StrengthRow.new));
      _outcomes.addAll(list('outcomeMeasures').map(_OutcomeRow.new));
      _tests.addAll(list('specialTests').map(_TestRow.new));
    } else {
      // The first assessment for a patient is the initial one.
      final known = ref
          .read(physioAssessmentsProvider(widget.patientId))
          .valueOrNull;
      if (known != null && known.isEmpty) _type = 'initial';
    }
    for (final r in [..._rom, ..._strength, ..._outcomes, ..._tests]) {
      _listen(r);
    }
  }

  void _listen(_Row r) {
    for (final c in r.controllers) {
      c.addListener(_onEdit);
    }
  }

  void _onEdit() {
    if (_tried && mounted) setState(() {});
  }

  @override
  void dispose() {
    _complaint.dispose();
    _functional.dispose();
    _plan.dispose();
    for (final r in [..._rom, ..._strength, ..._outcomes, ..._tests]) {
      r.dispose();
    }
    super.dispose();
  }

  void _add<T extends _Row>(List<T> list, T row) {
    _listen(row);
    setState(() => list.add(row));
  }

  void _remove<T extends _Row>(List<T> list, T row) {
    setState(() => list.remove(row));
    // Dispose after the frame that removed its fields.
    WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
  }

  bool get _rowsValid =>
      _rom.every((r) => r.valid) &&
      _strength.every((r) => r.valid) &&
      _outcomes.every((r) => r.valid) &&
      _tests.every((r) => r.valid);

  bool get _hasFinding =>
      _complaint.text.trim().isNotEmpty ||
      _painRest != null ||
      _painActivity != null ||
      _rom.isNotEmpty ||
      _strength.isNotEmpty ||
      _outcomes.isNotEmpty ||
      _tests.isNotEmpty ||
      _functional.text.trim().isNotEmpty ||
      _plan.text.trim().isNotEmpty;

  Map<String, dynamic> _body() {
    final pain = _painRest != null || _painActivity != null;
    return {
      'type': _type,
      if (_editing || _complaint.text.trim().isNotEmpty)
        'chiefComplaint': _complaint.text.trim(),
      if (_editing || pain)
        'painScore': {
          if (_painRest != null) 'rest': _painRest!.round(),
          if (_painActivity != null) 'activity': _painActivity!.round(),
        },
      'rom': [for (final r in _rom) r.toJson()],
      'strength': [for (final r in _strength) r.toJson()],
      'outcomeMeasures': [for (final r in _outcomes) r.toJson()],
      'specialTests': [for (final r in _tests) r.toJson()],
      if (_editing || _functional.text.trim().isNotEmpty)
        'functionalNotes': _functional.text.trim(),
      if (_editing || _plan.text.trim().isNotEmpty) 'plan': _plan.text.trim(),
      if (!_editing && (widget.appointmentId ?? '').isNotEmpty)
        'appointmentId': widget.appointmentId,
      if (!_editing && (widget.courseId ?? '').isNotEmpty)
        'courseId': widget.courseId,
    };
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _tried = true;
      _error = null;
    });
    if (!_hasFinding) {
      setState(() => _error = 'Record at least one finding.');
      return;
    }
    if (!_rowsValid) {
      setState(() => _error = 'Fix the highlighted fields.');
      return;
    }
    setState(() => _saving = true);
    try {
      final api = ApiService();
      final id = '${widget.assessment?['_id'] ?? ''}';
      if (_editing && id.isNotEmpty) {
        await api.updatePhysioAssessment(id, _body());
        ref.invalidate(physioAssessmentProvider(id));
      } else {
        await api.createPhysioAssessment(widget.patientId, _body());
      }
      ref.invalidate(physioAssessmentsProvider(widget.patientId));
      ref.invalidate(physioProgressProvider(widget.patientId));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = doctorError(e, fallback: 'Couldn’t save the assessment.');
      });
    }
  }

  // ─────────────────────────── Build ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  const AppSectionTitle('Type'),
                  Row(
                    children: [
                      for (final t in const [
                        'initial',
                        'progress',
                        'discharge',
                      ]) ...[
                        if (t != 'initial') const SizedBox(width: 8),
                        Expanded(
                          child: AppFilterChip(
                            block: true,
                            label: assessmentTypeLabel(t),
                            selected: _type == t,
                            onTap: () => setState(() => _type = t),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 18),
                  AppTextField(
                    label: 'Chief complaint',
                    controller: _complaint,
                    hint: 'e.g. Right knee pain climbing stairs',
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const AppSectionTitle('Pain'),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                    decoration: BoxDecoration(
                      color: AppColors.panel,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        _PainSlider(
                          label: 'At rest',
                          value: _painRest,
                          onChanged: (v) => setState(() => _painRest = v),
                        ),
                        const SizedBox(height: 4),
                        _PainSlider(
                          label: 'With activity',
                          value: _painActivity,
                          onChanged: (v) => setState(() => _painActivity = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  _section(
                    'Range of motion',
                    'Add movement',
                    () => _add(_rom, _RomRow()),
                    _rom.isEmpty
                        ? null
                        : [
                            for (final r in _rom)
                              _RowCard(
                                key: ValueKey(r.id),
                                onRemove: () => _remove(_rom, r),
                                children: _romFields(r),
                              ),
                          ],
                  ),
                  _section(
                    'Strength',
                    'Add muscle',
                    () => _add(_strength, _StrengthRow()),
                    _strength.isEmpty
                        ? null
                        : [
                            for (final r in _strength)
                              _RowCard(
                                key: ValueKey(r.id),
                                onRemove: () => _remove(_strength, r),
                                children: _strengthFields(r),
                              ),
                          ],
                  ),
                  _section(
                    'Outcome measures',
                    'Add score',
                    () => _add(_outcomes, _OutcomeRow()),
                    _outcomes.isEmpty
                        ? null
                        : [
                            for (final r in _outcomes)
                              _RowCard(
                                key: ValueKey(r.id),
                                onRemove: () => _remove(_outcomes, r),
                                children: _outcomeFields(r),
                              ),
                          ],
                  ),
                  _section(
                    'Special tests',
                    'Add test',
                    () => _add(_tests, _TestRow()),
                    _tests.isEmpty
                        ? null
                        : [
                            for (final r in _tests)
                              _RowCard(
                                key: ValueKey(r.id),
                                onRemove: () => _remove(_tests, r),
                                children: _testFields(r),
                              ),
                          ],
                  ),
                  AppTextField(
                    label: 'Functional notes',
                    controller: _functional,
                    hint: 'Gait, transfers, daily activities',
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  AppTextField(
                    label: 'Plan',
                    controller: _plan,
                    hint: 'Treatment plan and goals until the next review',
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ],
              ),
            ),
            _saveBar(),
          ],
        ),
      ),
    );
  }

  Widget _topBar() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 4, 20, 4),
    child: Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(
            LucideIcons.x,
            size: 22,
            color: AppColors.textPrimary,
          ),
          tooltip: 'Close',
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _editing ? 'Edit assessment' : 'New assessment',
                style: AppType.sans(
                  fontSize: AppType.title,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textStrong,
                ),
              ),
              Text(
                widget.patientName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.sans(
                  fontSize: AppType.caption,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _saveBar() => Container(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
    decoration: const BoxDecoration(
      color: AppColors.bg,
      border: Border(top: BorderSide(color: AppColors.border)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null) ...[
          AppErrorBanner(message: _error!),
          const SizedBox(height: 10),
        ],
        AppButton(
          label: _editing ? 'Save changes' : 'Save assessment',
          loading: _saving,
          onPressed: _save,
        ),
      ],
    ),
  );

  Widget _section(
    String title,
    String action,
    VoidCallback onAdd,
    List<Widget>? rows,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionTitle(title, action: action, onAction: onAdd),
        if (rows == null)
          AppPressable(
            scale: 0.985,
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    LucideIcons.plus,
                    size: 15,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'None recorded',
                    style: AppType.sans(
                      fontSize: AppType.small,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...rows,
      ],
    ),
  );

  Widget _sideChips(String value, ValueChanged<String> onChanged) =>
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final s in _sides) ...[
              AppFilterChip(
                label: s == 'na' ? 'N/A' : sideLabel(s),
                selected: value == s,
                onTap: () => onChanged(s),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      );

  static const _fieldGap = EdgeInsets.only(bottom: 10);

  List<Widget> _romFields(_RomRow r) => [
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AppTextField(
            label: 'Joint',
            controller: r.joint,
            hint: 'Knee',
            dense: true,
            textCapitalization: TextCapitalization.words,
            errorText: _tried ? r.jointError : null,
            margin: _fieldGap,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AppTextField(
            label: 'Movement',
            controller: r.movement,
            hint: 'Flexion',
            dense: true,
            textCapitalization: TextCapitalization.words,
            errorText: _tried ? r.movementError : null,
            margin: _fieldGap,
          ),
        ),
      ],
    ),
    _sideChips(r.side, (s) => setState(() => r.side = s)),
    const SizedBox(height: 10),
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AppTextField(
            label: 'Active (°)',
            controller: r.active,
            hint: '0',
            dense: true,
            keyboardType: const TextInputType.numberWithOptions(
              signed: true,
              decimal: true,
            ),
            inputFormatters: [_degFormatter],
            errorText: _tried ? r.activeError : null,
            margin: EdgeInsets.zero,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AppTextField(
            label: 'Passive (°)',
            controller: r.passive,
            hint: '0',
            dense: true,
            keyboardType: const TextInputType.numberWithOptions(
              signed: true,
              decimal: true,
            ),
            inputFormatters: [_degFormatter],
            errorText: _tried ? r.degError(r.passive) : null,
            margin: EdgeInsets.zero,
          ),
        ),
      ],
    ),
  ];

  List<Widget> _strengthFields(_StrengthRow r) => [
    AppTextField(
      label: 'Muscle group',
      controller: r.muscle,
      hint: 'Quadriceps',
      dense: true,
      textCapitalization: TextCapitalization.words,
      errorText: _tried ? r.muscleError : null,
      margin: _fieldGap,
    ),
    _sideChips(r.side, (s) => setState(() => r.side = s)),
    const SizedBox(height: 10),
    _label('Grade (0–5)', error: _tried && r.grade == null),
    Row(
      children: [
        for (var g = 0; g <= 5; g++) ...[
          if (g > 0) const SizedBox(width: 6),
          Expanded(
            child: AppFilterChip(
              block: true,
              label: '$g',
              selected: r.grade == g,
              onTap: () => setState(() => r.grade = g),
            ),
          ),
        ],
      ],
    ),
  ];

  List<Widget> _outcomeFields(_OutcomeRow r) {
    final info = kOutcomeMeasures[r.code];
    return [
      _label('Measure', error: _tried && r.code == null),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final m in kOutcomeMeasures.values)
            AppFilterChip(
              label: m.code == 'OTHER' ? 'Other' : m.code,
              selected: r.code == m.code,
              onTap: () => setState(() {
                final prev = kOutcomeMeasures[r.code]?.maxScore;
                r.code = m.code;
                // Fill the maximum for known scales, unless it was edited.
                final auto =
                    r.max.text.trim().isEmpty ||
                    (prev != null && _parse(r.max) == prev);
                if (auto) r.max.text = _numText(m.maxScore);
              }),
            ),
        ],
      ),
      if (info != null) ...[
        const SizedBox(height: 6),
        Text(
          [
            info.label,
            if (info.lowerIsBetter != null)
              info.lowerIsBetter! ? 'lower is better' : 'higher is better',
          ].join(' · '),
          style: AppType.sans(
            fontSize: AppType.caption,
            color: AppColors.textTertiary,
          ),
        ),
      ],
      const SizedBox(height: 10),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AppTextField(
              label: 'Score',
              controller: r.score,
              dense: true,
              isDecimal: true,
              inputFormatters: [_scoreFormatter],
              errorText: _tried ? r.scoreError : null,
              margin: EdgeInsets.zero,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AppTextField(
              label: 'Out of',
              controller: r.max,
              dense: true,
              isDecimal: true,
              inputFormatters: [_scoreFormatter],
              errorText: _tried ? r.maxError : null,
              margin: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _testFields(_TestRow r) => [
    AppTextField(
      label: 'Test',
      controller: r.name,
      hint: 'Lachman',
      dense: true,
      textCapitalization: TextCapitalization.words,
      errorText: _tried ? r.nameError : null,
      margin: _fieldGap,
    ),
    _label('Result', error: _tried && r.result == null),
    Row(
      children: [
        for (final res in _results) ...[
          if (res != _results.first) const SizedBox(width: 6),
          Expanded(
            child: AppFilterChip(
              block: true,
              label: capitalised(res),
              selected: r.result == res,
              onTap: () => setState(() => r.result = res),
            ),
          ),
        ],
      ],
    ),
  ];

  Widget _label(String text, {bool error = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      error ? '$text — pick one' : text,
      style: AppType.sans(
        fontSize: AppType.caption,
        fontWeight: FontWeight.w500,
        color: error ? AppColors.error : AppColors.textSecondary,
      ),
    ),
  );
}

/// A bordered card for one repeating row, with a remove button.
class _RowCard extends StatelessWidget {
  final List<Widget> children;
  final VoidCallback onRemove;
  const _RowCard({super.key, required this.children, required this.onRemove});

  @override
  Widget build(BuildContext context) => AppEntrance(
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 12),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
          IconButton(
            onPressed: onRemove,
            tooltip: 'Remove',
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              LucideIcons.trash2,
              size: 16,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    ),
  );
}

/// 0–10 pain with a colour that warns as it rises; empty until touched.
class _PainSlider extends StatelessWidget {
  final String label;
  final double? value;
  final ValueChanged<double?> onChanged;
  const _PainSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final color = value == null
        ? AppColors.textDisabled
        : painColor(context, value);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppType.sans(
                  fontSize: AppType.body,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (value != null) ...[
              GestureDetector(
                onTap: () => onChanged(null),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Clear',
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ),
              Text(
                '${value!.round()}',
                style: AppType.number(
                  fontSize: AppType.heading,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Text(
                '/10',
                style: AppType.sans(
                  fontSize: AppType.caption,
                  color: AppColors.textTertiary,
                ),
              ),
            ] else
              Text(
                'Not recorded',
                style: AppType.sans(
                  fontSize: AppType.caption,
                  color: AppColors.textTertiary,
                ),
              ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: color,
            inactiveTrackColor: AppColors.bg,
            thumbColor: value == null ? AppColors.textTertiary : color,
            overlayColor: color.withValues(alpha: 0.12),
            activeTickMarkColor: Colors.transparent,
            inactiveTickMarkColor: Colors.transparent,
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: Slider(
            value: value ?? 0,
            min: 0,
            max: 10,
            divisions: 10,
            semanticFormatterCallback: (v) => '$label pain ${v.round()} of 10',
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
