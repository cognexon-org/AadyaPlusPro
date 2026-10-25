import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/doctor_ui.dart' show doctorError;
import '../../doctor/widgets/prescription_ui.dart'
    show rxAppBar, RxBottomBar, RxQuickChip, RxChipsInput;
import '../providers/physio_exercise_provider.dart';
import 'exercise_ui.dart';

/// Adds an exercise to the library, or edits [exercise]. Pops the saved
/// exercise.
class ExerciseEditorScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? exercise;
  const ExerciseEditorScreen({super.key, this.exercise});

  @override
  ConsumerState<ExerciseEditorScreen> createState() =>
      _ExerciseEditorScreenState();
}

/// One line of a step list, with a stable id so removing a line above
/// doesn't shift text between fields.
class _Line {
  static int _next = 0;
  final int id = _next++;
  final TextEditingController text;
  _Line([String v = '']) : text = TextEditingController(text: v);
}

class _ExerciseEditorScreenState extends ConsumerState<ExerciseEditorScreen> {
  static const _bodyParts = [
    'Knee',
    'Shoulder',
    'Lower back',
    'Neck',
    'Hip',
    'Ankle',
  ];
  static const _categories = [
    'Strengthening',
    'Stretching',
    'Mobility',
    'Balance',
    'Posture',
  ];
  static const _equipment = [
    'Resistance band',
    'Mat',
    'Dumbbell',
    'Chair',
    'Towel',
    'Foam roller',
  ];

  final _name = TextEditingController();
  final _description = TextEditingController();
  final _bodyPart = TextEditingController();
  final _category = TextEditingController();
  final _sets = TextEditingController();
  final _reps = TextEditingController();
  final _duration = TextEditingController();
  final _frequency = TextEditingController();
  final _image = TextEditingController();
  final _video = TextEditingController();
  final List<_Line> _steps = [];
  final List<_Line> _cautions = [];
  List<String> _equipmentList = [];
  String _difficulty = 'moderate';

  bool _tried = false;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.exercise != null;

  @override
  void initState() {
    super.initState();
    final e = widget.exercise ?? const <String, dynamic>{};
    _name.text = '${e['name'] ?? ''}'.trim();
    _description.text = '${e['description'] ?? ''}'.trim();
    _bodyPart.text = '${e['bodyPart'] ?? ''}'.trim();
    _category.text = '${e['category'] ?? ''}'.trim();
    String n(dynamic v) => (exInt(v) ?? 0) > 0 ? '${exInt(v)}' : '';
    _sets.text = n(e['defaultSets']);
    _reps.text = n(e['defaultReps']);
    _duration.text = n(e['defaultDurationSec']);
    _frequency.text = '${e['defaultFrequency'] ?? ''}'.trim();
    _image.text = '${e['imageUrl'] ?? ''}'.trim();
    _video.text = '${e['videoUrl'] ?? ''}'.trim();
    _difficulty = '${e['difficulty'] ?? 'moderate'}';
    _equipmentList = exStrings(e['equipment']);
    _steps.addAll(exStrings(e['instructions']).map(_Line.new));
    _cautions.addAll(exStrings(e['precautions']).map(_Line.new));
    if (_steps.isEmpty) _steps.add(_Line());
    _name.addListener(_clearNameError);
    _image.addListener(_rebuild);
  }

  void _clearNameError() {
    if (_tried && _name.text.trim().isNotEmpty && mounted) setState(() {});
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _description,
      _bodyPart,
      _category,
      _sets,
      _reps,
      _duration,
      _frequency,
      _image,
      _video,
    ]) {
      c.dispose();
    }
    for (final l in [..._steps, ..._cautions]) {
      l.text.dispose();
    }
    super.dispose();
  }

  String? get _nameError =>
      _tried && _name.text.trim().isEmpty ? 'Enter the exercise name.' : null;
  String? get _imageError =>
      _tried && _image.text.trim().isNotEmpty && !exIsWebUrl(_image.text)
      ? 'Use a full link starting with https://'
      : null;
  String? get _videoError =>
      _tried && _video.text.trim().isNotEmpty && !exIsWebUrl(_video.text)
      ? 'Use a full link starting with https://'
      : null;

  Map<String, dynamic> _payload() {
    List<String> lines(List<_Line> l) => [
      for (final x in l)
        if (x.text.text.trim().isNotEmpty) x.text.text.trim(),
    ];
    int n(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;
    return {
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'bodyPart': _bodyPart.text.trim(),
      'category': _category.text.trim(),
      'difficulty': _difficulty,
      'equipment': _equipmentList,
      'instructions': lines(_steps),
      'precautions': lines(_cautions),
      'defaultSets': n(_sets),
      'defaultReps': n(_reps),
      'defaultDurationSec': n(_duration),
      'defaultFrequency': _frequency.text.trim(),
      'imageUrl': _image.text.trim(),
      'videoUrl': _video.text.trim(),
    };
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    setState(() => _tried = true);
    if (_nameError != null || _imageError != null || _videoError != null) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final catalog = ref.read(physioExerciseCatalogProvider.notifier);
    try {
      final saved = _editing
          ? await catalog.update(exId(widget.exercise!), _payload())
          : await catalog.create(_payload());
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = doctorError(e, fallback: 'Couldn’t save the exercise.'),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<String> _merge(List<String> fromData, List<String> defaults) {
    final seen = <String>{};
    return [
      for (final v in [...fromData, ...defaults])
        if (seen.add(v.toLowerCase())) v,
    ].take(8).toList();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(physioExerciseCatalogProvider);
    final gap = const SizedBox(height: 24);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: rxAppBar(
        context,
        title: _editing ? 'Edit exercise' : 'Add exercise',
        subtitle: _editing ? exName(widget.exercise!) : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.translucent,
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                children: [
                  const AppSectionTitle('Exercise'),
                  AppTextField(
                    label: 'Name',
                    controller: _name,
                    hint: 'e.g. Straight leg raise',
                    required: true,
                    errorText: _nameError,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  AppTextField(
                    label: 'Description',
                    controller: _description,
                    hint: 'What it works and why',
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  AppTextField(
                    label: 'Body part',
                    controller: _bodyPart,
                    hint: 'e.g. Knee',
                    margin: const EdgeInsets.only(bottom: 8),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  _Quick(
                    controller: _bodyPart,
                    options: _merge(catalog.bodyParts, _bodyParts),
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: 'Category',
                    controller: _category,
                    hint: 'e.g. Strengthening',
                    margin: const EdgeInsets.only(bottom: 8),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  _Quick(
                    controller: _category,
                    options: _merge(catalog.categories, _categories),
                  ),
                  const SizedBox(height: 14),
                  _Label('Difficulty'),
                  Row(
                    children: [
                      for (final (i, d) in const [
                        'easy',
                        'moderate',
                        'hard',
                      ].indexed) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: AppFilterChip(
                            block: true,
                            label: exDifficultyLabel(d),
                            selected: _difficulty == d,
                            onTap: () => setState(() => _difficulty = d),
                          ),
                        ),
                      ],
                    ],
                  ),
                  gap,
                  const AppSectionTitle('Default dosing'),
                  Text(
                    'Filled in when you add this exercise to a plan.',
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AppTextField(
                          label: 'Sets',
                          controller: _sets,
                          hint: '3',
                          isNum: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppTextField(
                          label: 'Reps',
                          controller: _reps,
                          hint: '10',
                          isNum: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppTextField(
                          label: 'Duration (s)',
                          controller: _duration,
                          hint: '30',
                          isNum: true,
                        ),
                      ),
                    ],
                  ),
                  AppTextField(
                    label: 'Frequency',
                    controller: _frequency,
                    hint: 'e.g. Twice a day',
                    margin: const EdgeInsets.only(bottom: 8),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  _Quick(
                    controller: _frequency,
                    options: const ['Daily', 'Twice a day', '3 times a week'],
                  ),
                  gap,
                  AppSectionTitle(
                    'Instructions',
                    action: 'Add step',
                    onAction: () => setState(() => _steps.add(_Line())),
                  ),
                  _Lines(
                    lines: _steps,
                    numbered: true,
                    hint: 'e.g. Lie on your back, one knee bent',
                    addLabel: 'Add step',
                    onAdd: () => setState(() => _steps.add(_Line())),
                    onRemove: (l) => _remove(_steps, l),
                  ),
                  gap,
                  AppSectionTitle(
                    'Precautions',
                    action: 'Add',
                    onAction: () => setState(() => _cautions.add(_Line())),
                  ),
                  _Lines(
                    lines: _cautions,
                    numbered: false,
                    hint: 'e.g. Stop if pain goes above 5/10',
                    addLabel: 'Add precaution',
                    onAdd: () => setState(() => _cautions.add(_Line())),
                    onRemove: (l) => _remove(_cautions, l),
                  ),
                  gap,
                  const AppSectionTitle('Equipment'),
                  RxChipsInput(
                    label: 'Add equipment',
                    hint: 'e.g. Resistance band',
                    values: _equipmentList,
                    suggestions: _equipment,
                    onChanged: (v) => setState(() => _equipmentList = v),
                  ),
                  gap,
                  const AppSectionTitle('Picture and video'),
                  if (exIsWebUrl(_image.text)) ...[
                    ExerciseThumb(
                      exercise: {'imageUrl': _image.text.trim()},
                      size: double.infinity,
                      height: 150,
                    ),
                    const SizedBox(height: 12),
                  ],
                  AppTextField(
                    label: 'Image link',
                    controller: _image,
                    icon: LucideIcons.image,
                    hint: 'https://…',
                    errorText: _imageError,
                    keyboardType: TextInputType.url,
                  ),
                  AppTextField(
                    label: 'Video link',
                    controller: _video,
                    icon: LucideIcons.video,
                    hint: 'YouTube or any https:// link',
                    errorText: _videoError,
                    keyboardType: TextInputType.url,
                    margin: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          RxBottomBar(
            above: _error == null
                ? null
                : AppErrorBanner(message: _error!, onRetry: _save),
            child: AppButton(
              label: _editing ? 'Save changes' : 'Add to library',
              icon: LucideIcons.check,
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ),
        ],
      ),
    );
  }

  void _remove(List<_Line> list, _Line l) {
    setState(() => list.remove(l));
    WidgetsBinding.instance.addPostFrameCallback((_) => l.text.dispose());
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: AppType.sans(
        fontSize: AppType.small,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
    ),
  );
}

/// Tappable suggestions that fill (or clear) [controller].
class _Quick extends StatelessWidget {
  final TextEditingController controller;
  final List<String> options;
  const _Quick({required this.controller, required this.options});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (_, _) => Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final o in options)
          RxQuickChip(
            label: o,
            selected: controller.text.trim().toLowerCase() == o.toLowerCase(),
            onTap: () {
              controller.text =
                  controller.text.trim().toLowerCase() == o.toLowerCase()
                  ? ''
                  : o;
              controller.selection = TextSelection.collapsed(
                offset: controller.text.length,
              );
            },
          ),
      ],
    ),
  );
}

/// An add/remove list of one-line entries (steps, precautions).
class _Lines extends StatelessWidget {
  final List<_Line> lines;
  final bool numbered;
  final String hint;
  final String addLabel;
  final VoidCallback onAdd;
  final ValueChanged<_Line> onRemove;

  const _Lines({
    required this.lines,
    required this.numbered,
    required this.hint,
    required this.addLabel,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    if (lines.isEmpty) {
      return AppSecondaryButton(
        label: addLabel,
        icon: LucideIcons.plus,
        onPressed: onAdd,
      );
    }
    return Column(
      children: [
        for (final (i, l) in lines.indexed)
          Padding(
            key: ValueKey('line-${l.id}'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(top: 9, right: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: numbered ? accent.veryLight : AppColors.warningBg,
                    shape: BoxShape.circle,
                  ),
                  child: numbered
                      ? Text(
                          '${i + 1}',
                          style: AppType.sans(
                            fontSize: AppType.micro,
                            fontWeight: FontWeight.w700,
                            color: accent.color,
                          ),
                        )
                      : const Icon(
                          LucideIcons.triangleAlert,
                          size: 12,
                          color: AppColors.warning,
                        ),
                ),
                Expanded(
                  child: AppTextField(
                    label: '',
                    controller: l.text,
                    hint: hint,
                    maxLines: 2,
                    margin: EdgeInsets.zero,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    LucideIcons.x,
                    size: 17,
                    color: AppColors.textTertiary,
                  ),
                  onPressed: () => onRemove(l),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
