import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/doctor_ui.dart' show doctorError;
import '../../doctor/widgets/prescription_ui.dart'
    show rxAppBar, RxBottomBar, RxChipsInput, RxPatientRow, RxQuickChip;
import '../providers/physio_exercise_provider.dart';
import '../widgets/exercise_picker_sheet.dart';
import '../widgets/exercise_plan_item_row.dart';
import '../widgets/exercise_ui.dart';

/// Writes a home exercise programme for a patient, or edits [planId].
///
/// Opened from a session ([appointmentId]) the plan is linked to that
/// visit and titled "Home programme". Pops `true` once saved.
class PhysioExercisePlanEditor extends ConsumerStatefulWidget {
  final String patientId;
  final String patientName;
  final String? appointmentId;

  /// An existing plan to edit.
  final String? planId;

  const PhysioExercisePlanEditor({
    super.key,
    required this.patientId,
    required this.patientName,
    this.appointmentId,
    this.planId,
  });

  @override
  ConsumerState<PhysioExercisePlanEditor> createState() =>
      _PhysioExercisePlanEditorState();
}

class _PhysioExercisePlanEditorState
    extends ConsumerState<PhysioExercisePlanEditor> {
  static const _goalSuggestions = [
    'Reduce pain',
    'Improve range of motion',
    'Build strength',
    'Improve balance',
    'Return to daily activities',
    'Return to sport',
  ];

  final _scroll = ScrollController();
  final _titleKey = GlobalKey();
  final _datesKey = GlobalKey();
  final _exercisesKey = GlobalKey();

  final _title = TextEditingController();
  final _instructions = TextEditingController();
  List<String> _goals = [];
  late DateTime _start;
  DateTime? _end;
  final List<ExercisePlanItemDraft> _items = [];

  ProviderSubscription<AsyncValue<PhysioPlanDetail>>? _planSub;
  bool _loadingPlan = false;
  String? _loadError;
  String _status = 'active';

  bool _tried = false;
  bool _saving = false;
  String? _error;

  String get _appointmentId => (widget.appointmentId ?? '').trim();
  String get _planId => (widget.planId ?? '').trim();
  bool get _editing => _planId.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, now.day);
    if (!_editing && _appointmentId.isNotEmpty) _title.text = 'Home programme';
    _title.addListener(_onTitle);
    if (_editing) {
      _loadingPlan = true;
      _planSub = ref.listenManual<AsyncValue<PhysioPlanDetail>>(
        physioPlanDetailProvider(_planId),
        (_, next) => _onPlan(next),
        fireImmediately: true,
      );
    }
    Future.microtask(() {
      if (mounted) {
        ref.read(physioExerciseCatalogProvider.notifier).ensureLoaded();
      }
    });
  }

  void _onTitle() {
    if (_tried && mounted) setState(() {});
  }

  /// Fills the form once from the saved plan; later refreshes (after this
  /// screen saves) don't overwrite what's typed.
  void _onPlan(AsyncValue<PhysioPlanDetail> next) {
    if (!_loadingPlan || !mounted) return;
    next.when(
      loading: () {},
      error: (e, _) => setState(() => _loadError = '$e'),
      data: (d) => setState(() {
        _fill(d);
        _loadingPlan = false;
        _loadError = null;
      }),
    );
  }

  void _fill(PhysioPlanDetail d) {
    final p = d.plan;
    _status = d.status;
    _title.text = '${p['title'] ?? ''}'.trim();
    _instructions.text = '${p['instructions'] ?? ''}'.trim();
    _goals = exStrings(p['goals']);
    final s = exDate(p['startDate']);
    if (s != null) _start = DateTime(s.year, s.month, s.day);
    final e = exDate(p['endDate']);
    _end = e == null ? null : DateTime(e.year, e.month, e.day);
    final catalog = ref.read(physioExerciseCatalogProvider);
    for (final item in d.items) {
      var ex = planItemExercise(item);
      if (ex.isEmpty) {
        ex =
            catalog.byId(planItemExerciseId(item)) ??
            {'_id': planItemExerciseId(item)};
      }
      _items.add(ExercisePlanItemDraft.fromItem(item, ex));
    }
  }

  @override
  void dispose() {
    _planSub?.close();
    _scroll.dispose();
    _title.dispose();
    _instructions.dispose();
    for (final d in _items) {
      d.dispose();
    }
    super.dispose();
  }

  // ─────────────────────────── Exercises ───────────────────────────

  Future<void> _addExercises() async {
    final picked = await showExercisePickerSheet(
      context,
      exclude: {for (final d in _items) d.exerciseId},
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      for (final ex in picked) {
        if (_items.any((d) => d.exerciseId == exId(ex))) continue;
        _items.add(ExercisePlanItemDraft.fromExercise(ex));
      }
    });
  }

  void _remove(ExercisePlanItemDraft d) {
    setState(() => _items.remove(d));
    WidgetsBinding.instance.addPostFrameCallback((_) => d.dispose());
  }

  void _move(int from, int to) {
    if (to < 0 || to >= _items.length) return;
    setState(() => _items.insert(to, _items.removeAt(from)));
  }

  void _applyDefaults() {
    final catalog = ref.read(physioExerciseCatalogProvider);
    var changed = 0;
    setState(() {
      for (final d in _items) {
        final fresh = catalog.byId(d.exerciseId);
        if (fresh != null) d.exercise = {...d.exercise, ...fresh};
        final before = '${d.sets.text}/${d.reps.text}';
        d.applyDefaults();
        if ('${d.sets.text}/${d.reps.text}' != before) changed++;
      }
    });
    _toast(
      changed == 0
          ? 'Already matching the library defaults.'
          : 'Library defaults applied to $changed exercise${changed == 1 ? '' : 's'}.',
    );
  }

  // ─────────────────────────── Dates ───────────────────────────

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null && mounted) setState(() => _start = picked);
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _end ?? _start.add(const Duration(days: 28)),
      firstDate: _start,
      lastDate: _start.add(const Duration(days: 730)),
    );
    if (picked != null && mounted) setState(() => _end = picked);
  }

  static String _date(DateTime d) => DateFormat('EEE d MMM yyyy').format(d);

  // ─────────────────────────── Save ───────────────────────────

  String? get _titleError =>
      _tried && _title.text.trim().isEmpty ? 'Give the plan a title.' : null;
  String? get _dateError => _tried && _end != null && _end!.isBefore(_start)
      ? 'The end date is before the start date.'
      : null;
  String? get _itemsError => _tried && _items.isEmpty
      ? 'Add at least one exercise from your library.'
      : null;

  bool _validate() {
    _tried = true;
    GlobalKey? first;
    if (_title.text.trim().isEmpty) first = _titleKey;
    if (_end != null && _end!.isBefore(_start)) first ??= _datesKey;
    if (_items.isEmpty) first ??= _exercisesKey;
    for (final d in _items) {
      d.doseError = d.hasDose ? null : 'Add sets and reps, or a hold time.';
      if (d.doseError != null) first ??= _exercisesKey;
    }
    setState(() {});
    final ctx = first?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: AppMotion.medium,
        curve: AppMotion.enter,
        alignment: 0.05,
      );
    }
    return first == null;
  }

  Map<String, dynamic> _payload() => {
    'title': _title.text.trim(),
    'goals': _goals,
    'instructions': _instructions.text.trim(),
    'startDate': _start.toUtc().toIso8601String(),
    'endDate': _end?.toUtc().toIso8601String(),
    'exercises': [for (final (i, d) in _items.indexed) d.toJson(i)],
    if (!_editing && _appointmentId.isNotEmpty) 'appointmentId': _appointmentId,
  };

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    if (!_validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final actions = ref.read(physioExercisePlanActionsProvider);
    try {
      if (_editing) {
        await actions.update(_planId, _payload());
      } else {
        await actions.create(widget.patientId, _payload());
      }
      if (!mounted) return;
      _toast(
        _editing
            ? 'Plan updated. The patient has been notified.'
            : 'Plan assigned. The patient has been notified.',
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = doctorError(e, fallback: 'Couldn’t save the plan.'),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.textStrong,
      content: Text(
        text,
        style: AppType.sans(fontSize: AppType.caption, color: Colors.white),
      ),
    ),
  );

  // ─────────────────────────── Build ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final name = widget.patientName.trim().isEmpty
        ? 'Patient'
        : widget.patientName.trim();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: rxAppBar(
        context,
        title: _editing ? 'Edit exercise plan' : 'New exercise plan',
        subtitle: name,
      ),
      body: Column(
        children: [
          Expanded(
            child: _loadingPlan
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_loadError != null)
                        AppErrorBanner(
                          message: _loadError!,
                          onRetry: () {
                            setState(() => _loadError = null);
                            ref.invalidate(physioPlanDetailProvider(_planId));
                          },
                        )
                      else
                        const AppFormSkeleton(fields: 6),
                    ],
                  )
                : GestureDetector(
                    onTap: () => FocusScope.of(context).unfocus(),
                    behavior: HitTestBehavior.translucent,
                    child: ListView(
                      controller: _scroll,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                      children: _form(name),
                    ),
                  ),
          ),
          RxBottomBar(
            above: _error == null
                ? null
                : AppErrorBanner(message: _error!, onRetry: _save),
            child: AppButton(
              label: _editing ? 'Save plan' : 'Assign plan',
              icon: LucideIcons.check,
              loading: _saving,
              onPressed: _saving || _loadingPlan ? null : _save,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _form(String name) {
    const gap = SizedBox(height: 24);
    final count = _items.length;
    return [
      if (_editing && _status != 'active') ...[
        ExerciseNote(
          icon: LucideIcons.info,
          text:
              'This plan is ${planStatusLabel(_status).toLowerCase()}. Saving changes keeps that status.',
        ),
        const SizedBox(height: 16),
      ],
      AppGroup(
        children: [
          RxPatientRow(
            name: name,
            meta: _appointmentId.isNotEmpty && !_editing
                ? 'Linked to this session'
                : 'Home exercise programme',
          ),
        ],
      ),
      gap,
      KeyedSubtree(
        key: _titleKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSectionTitle('Plan'),
            AppTextField(
              label: 'Title',
              controller: _title,
              hint: 'e.g. Knee rehab, phase 1',
              required: true,
              errorText: _titleError,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
      ),
      RxChipsInput(
        label: 'Add goal',
        hint: 'e.g. Climb stairs without pain',
        values: _goals,
        suggestions: _goalSuggestions,
        icon: LucideIcons.target,
        onChanged: (v) => setState(() => _goals = v),
      ),
      const SizedBox(height: 16),
      KeyedSubtree(
        key: _datesKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: AppPickerField(
                    label: 'Starts',
                    valueText: _date(_start),
                    icon: LucideIcons.calendarDays,
                    onTap: _pickStart,
                    margin: const EdgeInsets.only(bottom: 8),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppPickerField(
                    label: 'Ends',
                    valueText: _end == null ? 'No end date' : _date(_end!),
                    icon: LucideIcons.flag,
                    onTap: _pickEnd,
                    margin: const EdgeInsets.only(bottom: 8),
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final w in const [2, 4, 6, 8])
                  RxQuickChip(
                    label: '$w weeks',
                    selected:
                        _end != null &&
                        DateUtils.isSameDay(
                          _end,
                          _start.add(Duration(days: w * 7)),
                        ),
                    onTap: () => setState(
                      () => _end = _start.add(Duration(days: w * 7)),
                    ),
                  ),
                if (_end != null)
                  RxQuickChip(
                    label: 'No end date',
                    selected: false,
                    onTap: () => setState(() => _end = null),
                  ),
              ],
            ),
            if (_dateError != null) _FieldError(_dateError!),
          ],
        ),
      ),
      const SizedBox(height: 16),
      AppTextField(
        label: 'Instructions for the patient',
        controller: _instructions,
        hint: 'e.g. Warm up for 5 minutes first. Ice for 10 minutes after.',
        maxLines: 3,
        margin: EdgeInsets.zero,
        textCapitalization: TextCapitalization.sentences,
      ),
      gap,
      KeyedSubtree(
        key: _exercisesKey,
        child: AppSectionTitle(
          count == 0 ? 'Exercises' : 'Exercises ($count)',
          action: count == 0 ? null : 'Apply library defaults',
          onAction: _applyDefaults,
        ),
      ),
      if (count == 0)
        _EmptyExercises(onAdd: _addExercises, error: _itemsError)
      else
        for (final (i, d) in _items.indexed)
          Padding(
            key: ValueKey('item-${d.id}'),
            padding: const EdgeInsets.only(bottom: 10),
            child: ExercisePlanItemRow(
              draft: d,
              number: i + 1,
              onChanged: () => setState(() {}),
              onUp: i == 0 ? null : () => _move(i, i - 1),
              onDown: i == count - 1 ? null : () => _move(i, i + 1),
              onRemove: () => _remove(d),
            ),
          ),
      if (count > 0)
        AppSecondaryButton(
          label: 'Add exercises',
          icon: LucideIcons.plus,
          onPressed: _addExercises,
        ),
      if (count > 0) ...[
        const SizedBox(height: 14),
        _WeeklySummary(items: _items),
      ],
    ];
  }
}

class _EmptyExercises extends StatelessWidget {
  final VoidCallback onAdd;
  final String? error;
  const _EmptyExercises({required this.onAdd, this.error});

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    return AppPressable(
      scale: 0.985,
      onTap: onAdd,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        decoration: BoxDecoration(
          color: error != null ? AppColors.errorBg : AppColors.panel,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(LucideIcons.dumbbell, size: 22, color: accent.color),
            const SizedBox(height: 8),
            Text(
              'Add exercises from your library',
              style: AppType.sans(
                fontSize: AppType.body,
                fontWeight: FontWeight.w700,
                color: AppColors.textStrong,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              error ?? 'Sets, reps, hold and how often are set per exercise.',
              textAlign: TextAlign.center,
              style: AppType.sans(
                fontSize: AppType.caption,
                color: error != null ? AppColors.error : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "About 34 sessions a week" — what the plan asks of the patient.
class _WeeklySummary extends StatelessWidget {
  final List<ExercisePlanItemDraft> items;
  const _WeeklySummary({required this.items});

  @override
  Widget build(BuildContext context) {
    final perWeek = items.fold<int>(
      0,
      (s, d) => s + d.timesPerDay * d.daysPerWeek,
    );
    final perDay = items.fold<double>(
      0,
      (s, d) => s + d.timesPerDay * d.daysPerWeek / 7,
    );
    return ExerciseNote(
      icon: LucideIcons.repeat,
      text:
          '${items.length} exercise${items.length == 1 ? '' : 's'} · $perWeek sessions a week (about ${perDay.toStringAsFixed(perDay % 1 == 0 ? 0 : 1)} a day). Adherence is measured against this.',
    );
  }
}

class _FieldError extends StatelessWidget {
  final String text;
  const _FieldError(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, left: 2),
    child: Text(
      text,
      style: AppType.sans(fontSize: 11, color: AppColors.error),
    ),
  );
}
