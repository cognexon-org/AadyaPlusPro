import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/doctor_ui.dart' show doctorError;
import '../providers/physio_exercise_provider.dart';
import 'exercise_ui.dart';

/// Records an in-clinic session against a plan: which exercises were done,
/// how much, pain before and after. Resolves to the number of exercises
/// logged (null when closed without saving).
Future<int?> showExerciseLogSheet(
  BuildContext context, {
  required String planId,
  required List<Map<String, dynamic>> items,
}) => showAppSheet<int>(
  context,
  builder: (_) => ExerciseLogSheet(planId: planId, items: items),
);

class _Entry {
  final Map<String, dynamic> item;
  final TextEditingController sets;
  final TextEditingController reps;
  bool done = true;
  bool saved = false;

  _Entry(this.item)
    : sets = TextEditingController(text: _n(item['sets'])),
      reps = TextEditingController(text: _n(item['reps']));

  static String _n(dynamic v) => (exInt(v) ?? 0) > 0 ? '${exInt(v)}' : '';

  String get id => '${item['_id'] ?? ''}';

  void dispose() {
    sets.dispose();
    reps.dispose();
  }
}

class ExerciseLogSheet extends ConsumerStatefulWidget {
  final String planId;
  final List<Map<String, dynamic>> items;
  const ExerciseLogSheet({
    super.key,
    required this.planId,
    required this.items,
  });

  @override
  ConsumerState<ExerciseLogSheet> createState() => _ExerciseLogSheetState();
}

class _ExerciseLogSheetState extends ConsumerState<ExerciseLogSheet> {
  late final List<_Entry> _entries = [
    for (final i in widget.items)
      if ('${i['_id'] ?? ''}'.isNotEmpty) _Entry(i),
  ];
  final _notes = TextEditingController();
  int? _painBefore;
  int? _painAfter;
  String? _difficulty;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final e in _entries) {
      e.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  int get _doneCount => _entries.where((e) => e.done).length;

  Future<void> _save() async {
    if (_saving || _doneCount == 0) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    final actions = ref.read(physioExercisePlanActionsProvider);
    final at = DateTime.now().toUtc().toIso8601String();
    var logged = _entries.where((e) => e.saved).length;
    try {
      for (final e in _entries) {
        if (!e.done || e.saved) continue;
        await actions.log(widget.planId, {
          'planItemId': e.id,
          'setsCompleted': int.tryParse(e.sets.text.trim()) ?? 0,
          'repsCompleted': int.tryParse(e.reps.text.trim()) ?? 0,
          'durationSec': exInt(e.item['durationSec']) ?? 0,
          'painBefore': ?_painBefore,
          'painAfter': ?_painAfter,
          'perceivedDifficulty': ?_difficulty,
          'completed': true,
          if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
          'performedAt': at,
        });
        // A retry after a failure skips the ones already saved.
        e.saved = true;
        logged++;
      }
      actions.refreshAfterLogging(widget.planId);
      if (mounted) Navigator.of(context).pop(logged);
    } catch (err) {
      if (logged > 0) actions.refreshAfterLogging(widget.planId);
      if (!mounted) return;
      setState(
        () => _error = doctorError(
          err,
          fallback: logged > 0
              ? 'Saved $logged, but couldn’t save the rest.'
              : 'Couldn’t log the session.',
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Log in-clinic session',
            style: AppType.sans(
              fontSize: AppType.title,
              fontWeight: FontWeight.w700,
              color: AppColors.textStrong,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Counts towards the patient’s adherence. Untick anything not done today.',
            style: AppType.sans(
              fontSize: AppType.caption,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final e in _entries)
                    Padding(
                      key: ValueKey('log-${e.id}'),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _EntryRow(
                        entry: e,
                        onToggle: e.saved
                            ? null
                            : () => setState(() => e.done = !e.done),
                      ),
                    ),
                  const SizedBox(height: 10),
                  _PainPicker(
                    label: 'Pain before',
                    value: _painBefore,
                    onChanged: (v) => setState(() => _painBefore = v),
                  ),
                  const SizedBox(height: 12),
                  _PainPicker(
                    label: 'Pain after',
                    value: _painAfter,
                    onChanged: (v) => setState(() => _painAfter = v),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'How did it feel?',
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (final (i, (v, l)) in const [
                        ('easy', 'Easy'),
                        ('about_right', 'About right'),
                        ('hard', 'Hard'),
                      ].indexed) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: AppFilterChip(
                            block: true,
                            label: l,
                            selected: _difficulty == v,
                            onTap: () => setState(
                              () => _difficulty = _difficulty == v ? null : v,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: 'Notes',
                    controller: _notes,
                    hint: 'e.g. Good control, progress to the blue band',
                    maxLines: 2,
                    margin: EdgeInsets.zero,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
          ),
          if (_error != null) AppErrorBanner(message: _error!, onRetry: _save),
          AppButton(
            label: _doneCount == 0
                ? 'Tick at least one exercise'
                : 'Log $_doneCount exercise${_doneCount == 1 ? '' : 's'}',
            icon: LucideIcons.clipboardCheck,
            loading: _saving,
            onPressed: _doneCount == 0 || _saving ? null : _save,
          ),
          if (_entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'This plan has no exercises to log.',
                textAlign: TextAlign.center,
                style: AppType.sans(
                  fontSize: AppType.caption,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final _Entry entry;
  final VoidCallback? onToggle;
  const _EntryRow({required this.entry, this.onToggle});

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    final ex = planItemExercise(entry.item);
    final done = entry.done;
    return AnimatedContainer(
      duration: AppMotion.fast,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          AppPressable(
            scale: 0.9,
            onTap: onToggle,
            child: AnimatedContainer(
              duration: AppMotion.fast,
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: done ? accent.color : AppColors.bg,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: done ? accent.color : AppColors.borderStrong,
                  width: 1.5,
                ),
              ),
              child: done
                  ? Icon(
                      entry.saved ? LucideIcons.checkCheck : LucideIcons.check,
                      size: 15,
                      color: Colors.white,
                    )
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: onToggle,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exName(ex),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.sans(
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w700,
                      color: done
                          ? AppColors.textStrong
                          : AppColors.textTertiary,
                    ),
                  ),
                  Text(
                    entry.saved
                        ? 'Saved'
                        : planItemDosing(entry.item, schedule: false),
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
          ),
          if (done && !entry.saved) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 56,
              child: ExerciseCardField(
                label: 'Sets',
                controller: entry.sets,
                number: true,
                bottom: 0,
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 56,
              child: ExerciseCardField(
                label: 'Reps',
                controller: entry.reps,
                number: true,
                bottom: 0,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 0–10 pain, tap again to clear. High scores read amber/red.
class _PainPicker extends StatelessWidget {
  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;
  const _PainPicker({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: AppType.sans(
                fontSize: AppType.caption,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            Text(
              value == null ? 'Not recorded' : '$value / 10',
              style: AppType.sans(
                fontSize: AppType.caption,
                fontWeight: FontWeight.w600,
                color: value == null
                    ? AppColors.textTertiary
                    : AppColors.textStrong,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i <= 10; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(
                child: AppPressable(
                  scale: 0.9,
                  onTap: () => onChanged(value == i ? null : i),
                  child: AnimatedContainer(
                    duration: AppMotion.fast,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: value == i
                          ? (i >= 8
                                ? AppColors.error
                                : i >= 6
                                ? AppColors.warning
                                : accent.color)
                          : AppColors.panel,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      '$i',
                      style: AppType.number(
                        fontSize: AppType.caption,
                        fontWeight: FontWeight.w700,
                        color: value == i
                            ? Colors.white
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
