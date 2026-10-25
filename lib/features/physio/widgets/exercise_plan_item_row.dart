import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/prescription_ui.dart' show RxQuickChip;
import '../providers/physio_exercise_provider.dart';
import 'exercise_ui.dart';

/// One exercise being prescribed. Owns its controllers; the editor disposes
/// it when the row is removed or the screen closes. [id] is local and
/// stable, so rows keep their values when one above moves or goes.
class ExercisePlanItemDraft {
  static int _next = 0;

  final int id = _next++;
  Map<String, dynamic> exercise;
  final sets = TextEditingController();
  final reps = TextEditingController();
  final hold = TextEditingController();
  final rest = TextEditingController();
  final load = TextEditingController();
  final notes = TextEditingController();
  String side = 'na';
  int timesPerDay = 1;
  int daysPerWeek = 7;

  /// Fields the row doesn't show (durationSec, legacy frequency), kept so
  /// editing a plan doesn't drop them.
  final Map<String, dynamic> extra = {};
  String? doseError;

  ExercisePlanItemDraft._(this.exercise);

  /// A new row for [exercise] with its library defaults.
  factory ExercisePlanItemDraft.fromExercise(Map<String, dynamic> exercise) =>
      ExercisePlanItemDraft._(exercise)..applyDefaults();

  /// A row for a saved plan item; [exercise] is its populated exercise (or
  /// the library copy when the server sent only the id).
  factory ExercisePlanItemDraft.fromItem(
    Map<String, dynamic> item,
    Map<String, dynamic> exercise,
  ) {
    final d = ExercisePlanItemDraft._(exercise);
    String n(dynamic v) => (exInt(v) ?? 0) > 0 ? '${exInt(v)}' : '';
    d.sets.text = n(item['sets']);
    d.reps.text = n(item['reps']);
    d.hold.text = n(item['holdSec']);
    d.rest.text = n(item['restSec']);
    d.load.text = '${item['load'] ?? ''}'.trim();
    d.notes.text = '${item['notes'] ?? ''}'.trim();
    final side = '${item['side'] ?? ''}';
    d.side = const {'left', 'right', 'both'}.contains(side) ? side : 'na';
    d.timesPerDay = (exInt(item['timesPerDay']) ?? 1).clamp(1, 6);
    d.daysPerWeek = (exInt(item['daysPerWeek']) ?? 7).clamp(1, 7);
    if ((exInt(item['durationSec']) ?? 0) > 0) {
      d.extra['durationSec'] = exInt(item['durationSec']);
    }
    final freq = '${item['frequency'] ?? ''}'.trim();
    if (freq.isNotEmpty) d.extra['frequency'] = freq;
    // Sent back on save so the item keeps its id and its progress logs keep
    // counting towards this exercise's adherence.
    final itemId = '${item['_id'] ?? ''}';
    if (itemId.isNotEmpty) d.extra['_id'] = itemId;
    return d;
  }

  String get exerciseId => exId(exercise);

  /// Copies the library's default sets, reps and duration over this row.
  void applyDefaults() {
    final s = exInt(exercise['defaultSets']) ?? 0;
    final r = exInt(exercise['defaultReps']) ?? 0;
    final dur = exInt(exercise['defaultDurationSec']) ?? 0;
    if (s > 0) sets.text = '$s';
    if (r > 0) reps.text = '$r';
    if (dur > 0) {
      extra['durationSec'] = dur;
    }
    doseError = null;
  }

  int _n(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  /// Something to do: sets and reps, a hold, or a timed duration.
  bool get hasDose =>
      (_n(sets) > 0 && _n(reps) > 0) ||
      _n(hold) > 0 ||
      (exInt(extra['durationSec']) ?? 0) > 0;

  Map<String, dynamic> toJson(int index) => {
    ...extra,
    'exerciseId': exerciseId,
    'sets': _n(sets),
    'reps': _n(reps),
    if (_n(hold) > 0) 'holdSec': _n(hold),
    if (_n(rest) > 0) 'restSec': _n(rest),
    'side': side,
    if (load.text.trim().isNotEmpty) 'load': load.text.trim(),
    'timesPerDay': timesPerDay,
    'daysPerWeek': daysPerWeek,
    if (notes.text.trim().isNotEmpty) 'notes': notes.text.trim(),
    'sortOrder': index,
  };

  void dispose() {
    for (final c in [sets, reps, hold, rest, load, notes]) {
      c.dispose();
    }
  }
}

/// The editable card for one [ExercisePlanItemDraft].
class ExercisePlanItemRow extends StatelessWidget {
  final ExercisePlanItemDraft draft;
  final int number;
  final VoidCallback onChanged;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback onRemove;

  const ExercisePlanItemRow({
    super.key,
    required this.draft,
    required this.number,
    required this.onChanged,
    required this.onRemove,
    this.onUp,
    this.onDown,
  });

  static const _doses = [(2, 10), (3, 10), (3, 12), (3, 15)];
  static const _sides = [
    ('na', 'N/A'),
    ('left', 'Left'),
    ('right', 'Right'),
    ('both', 'Both'),
  ];

  Widget _icon(IconData icon, String tip, VoidCallback? onTap) => IconButton(
    tooltip: tip,
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
    padding: EdgeInsets.zero,
    icon: Icon(
      icon,
      size: 17,
      color: onTap == null ? AppColors.textDisabled : AppColors.textTertiary,
    ),
    onPressed: onTap,
  );

  @override
  Widget build(BuildContext context) {
    final ex = draft.exercise;
    final meta = [
      '${ex['bodyPart'] ?? ''}'.trim(),
      '${ex['category'] ?? ''}'.trim(),
    ].where((e) => e.isNotEmpty).join(' · ');
    final dur = exInt(draft.extra['durationSec']) ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExerciseThumb(exercise: ex, size: 40, radius: 10),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$number. ${exName(ex)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.sans(
                        fontSize: AppType.body,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textStrong,
                      ),
                    ),
                    if (meta.isNotEmpty || dur > 0)
                      Text(
                        [
                          meta,
                          if (dur > 0) exSeconds(dur),
                        ].where((e) => e.isNotEmpty).join(' · '),
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
              _icon(LucideIcons.arrowUp, 'Move up', onUp),
              _icon(LucideIcons.arrowDown, 'Move down', onDown),
              _icon(LucideIcons.trash2, 'Remove exercise', onRemove),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, (label, c, hint)) in [
                      ('Sets', draft.sets, '3'),
                      ('Reps', draft.reps, '10'),
                      ('Hold', draft.hold, '0'),
                      ('Rest', draft.rest, '30'),
                    ].indexed) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: ExerciseCardField(
                          label: label,
                          controller: c,
                          hint: hint,
                          number: true,
                          suffix: i >= 2 ? 's' : null,
                          bottom: 8,
                        ),
                      ),
                    ],
                  ],
                ),
                if (draft.doseError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 2),
                    child: Text(
                      draft.doseError!,
                      style: AppType.sans(fontSize: 11, color: AppColors.error),
                    ),
                  ),
                ListenableBuilder(
                  listenable: Listenable.merge([draft.sets, draft.reps]),
                  builder: (_, _) => Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (s, r) in _doses)
                        RxQuickChip(
                          label: '$s × $r',
                          selected:
                              draft.sets.text.trim() == '$s' &&
                              draft.reps.text.trim() == '$r',
                          onTap: () {
                            draft.sets.text = '$s';
                            draft.reps.text = '$r';
                            draft.doseError = null;
                            onChanged();
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _Label('Side'),
                Row(
                  children: [
                    for (final (i, (value, label)) in _sides.indexed) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(
                        child: _Segment(
                          label: label,
                          selected: draft.side == value,
                          onTap: () {
                            draft.side = value;
                            onChanged();
                          },
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ExerciseStepper(
                        label: 'Times a day',
                        value: draft.timesPerDay,
                        min: 1,
                        max: 6,
                        format: (v) => '$v×',
                        onChanged: (v) {
                          draft.timesPerDay = v;
                          onChanged();
                        },
                      ),
                    ),
                    Expanded(
                      child: ExerciseStepper(
                        label: 'Days a week',
                        value: draft.daysPerWeek,
                        min: 1,
                        max: 7,
                        format: (v) => v == 7 ? 'Daily' : '$v',
                        onChanged: (v) {
                          draft.daysPerWeek = v;
                          onChanged();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ExerciseCardField(
                  label: 'Load',
                  controller: draft.load,
                  hint: 'e.g. Red band, 2 kg ankle weight',
                ),
                ExerciseCardField(
                  label: 'Notes for the patient',
                  controller: draft.notes,
                  hint: 'e.g. Keep the knee straight, slow on the way down',
                  maxLines: 2,
                  bottom: 0,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Text(
      text,
      style: AppType.sans(
        fontSize: AppType.caption,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
    ),
  );
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: AppPressable(
        scale: 0.96,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? accent.light : AppColors.bg,
            borderRadius: BorderRadius.circular(8),
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
      ),
    );
  }
}
