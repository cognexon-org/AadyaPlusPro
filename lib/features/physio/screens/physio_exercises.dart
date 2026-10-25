import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/doctor_ui.dart' show doctorError;
import '../../doctor/widgets/prescription_ui.dart' show rxAppBar, RxQuickChip;
import '../providers/physio_exercise_provider.dart';
import '../widgets/exercise_detail_sheet.dart';
import '../widgets/exercise_editor.dart';
import '../widgets/exercise_ui.dart';

/// The physio's exercise library: the exercises plans are built from, with
/// pictures, videos, instructions and default dosing.
class PhysioExercises extends ConsumerStatefulWidget {
  const PhysioExercises({super.key});

  @override
  ConsumerState<PhysioExercises> createState() => _PhysioExercisesState();
}

class _PhysioExercisesState extends ConsumerState<PhysioExercises> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String? _bodyPart;
  String? _category;
  String? _difficulty;

  PhysioExerciseCatalogNotifier get _catalog =>
      ref.read(physioExerciseCatalogProvider.notifier);

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      _catalog.load(silent: ref.read(physioExerciseCatalogProvider).hasLoaded);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _query = v.trim());
      _catalog.search(v);
    });
  }

  void _clearFilters() => setState(() {
    _bodyPart = null;
    _category = null;
    _difficulty = null;
  });

  Future<void> _add() async {
    final saved = await Navigator.of(context).push<Map<String, dynamic>>(
      AppPageRoute(builder: (_) => const ExerciseEditorScreen()),
    );
    if (saved != null && mounted) _toast('${exName(saved)} added.');
  }

  Future<void> _edit(Map<String, dynamic> ex) async {
    final saved = await Navigator.of(context).push<Map<String, dynamic>>(
      AppPageRoute(builder: (_) => ExerciseEditorScreen(exercise: ex)),
    );
    if (saved != null && mounted) _toast('Changes saved.');
  }

  Future<void> _open(Map<String, dynamic> ex) async {
    final action = await showExerciseDetailSheet(context, ex);
    if (!mounted || action == null) return;
    switch (action) {
      case ExerciseSheetAction.edit:
        await _edit(ex);
      case ExerciseSheetAction.archive:
        await _archive(ex);
    }
  }

  Future<void> _archive(Map<String, dynamic> ex) async {
    final ok = await AppModal.confirm(
      context,
      title: 'Archive ${exName(ex)}?',
      message:
          'It leaves the library and can’t be added to new plans. Plans that already use it keep it.',
      icon: LucideIcons.archive,
      confirmLabel: 'Archive',
    );
    if (!ok || !mounted) return;
    try {
      await _catalog.archive(exId(ex));
      if (mounted) _toast('${exName(ex)} archived.');
    } catch (e) {
      if (!mounted) return;
      showAppError(
        context,
        null,
        fallback: doctorError(e, fallback: 'Couldn’t archive the exercise.'),
      );
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(physioExerciseCatalogProvider);
    final accent = ModuleAccent.of(context);
    final all = state.items;
    final loading = !state.hasLoaded && state.error == null;
    final visible = state.filtered(
      query: _query,
      bodyPart: _bodyPart,
      category: _category,
      difficulty: _difficulty,
    );
    final filtering =
        _bodyPart != null || _category != null || _difficulty != null;
    final bodyParts = state.bodyParts;
    final secondary = [
      for (final c in state.categories) ('category', c, c),
      for (final d in state.difficulties)
        ('difficulty', d, exDifficultyLabel(d)),
    ];

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: rxAppBar(
        context,
        title: 'Exercise library',
        subtitle: state.hasLoaded && all.isNotEmpty
            ? '${all.length} exercise${all.length == 1 ? '' : 's'}'
            : null,
      ),
      floatingActionButton: AppFab(
        label: 'Add exercise',
        icon: LucideIcons.plus,
        onPressed: _add,
      ),
      body: RefreshIndicator(
        color: accent.color,
        onRefresh: () => _catalog.load(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
          children: [
            AppSearchField(
              controller: _search,
              hint: 'Search exercises, body parts, equipment',
              onChanged: _onSearch,
            ),
            if (bodyParts.isNotEmpty) ...[
              const SizedBox(height: 12),
              _ChipRow(
                children: [
                  AppFilterChip(
                    label: 'All',
                    selected: _bodyPart == null,
                    onTap: () => setState(() => _bodyPart = null),
                  ),
                  for (final b in bodyParts)
                    AppFilterChip(
                      label: b,
                      selected: _bodyPart == b,
                      onTap: () =>
                          setState(() => _bodyPart = _bodyPart == b ? null : b),
                    ),
                ],
              ),
            ],
            if (secondary.length > 1) ...[
              const SizedBox(height: 8),
              _ChipRow(
                children: [
                  for (final (kind, value, label) in secondary)
                    RxQuickChip(
                      label: label,
                      selected: kind == 'category'
                          ? _category == value
                          : _difficulty == value,
                      onTap: () => setState(() {
                        if (kind == 'category') {
                          _category = _category == value ? null : value;
                        } else {
                          _difficulty = _difficulty == value ? null : value;
                        }
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            if (state.error != null)
              AppErrorBanner(message: state.error!, onRetry: _catalog.load),
            if (loading)
              const AppListSkeleton(count: 6)
            else if (visible.isEmpty && state.error == null)
              AppEmptyState(
                icon: LucideIcons.dumbbell,
                text: all.isEmpty
                    ? 'Your library is empty.\nAdd the exercises you prescribe most, with steps, a picture or video and default sets and reps.'
                    : _query.isNotEmpty
                    ? 'No exercises match “$_query”.'
                    : 'No exercises match these filters.',
                action: all.isNotEmpty && filtering
                    ? TextButton(
                        onPressed: _clearFilters,
                        child: Text(
                          'Clear filters',
                          style: AppType.sans(
                            fontSize: AppType.small,
                            fontWeight: FontWeight.w600,
                            color: accent.color,
                          ),
                        ),
                      )
                    : null,
              )
            else ...[
              if (filtering || _query.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    '${visible.length} of ${all.length}',
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              for (final (i, ex) in visible.indexed)
                Padding(
                  key: ValueKey(exId(ex)),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppEntrance(
                    index: i,
                    child: ExerciseCard(
                      exercise: ex,
                      onTap: () => _open(ex),
                      trailing: const Icon(
                        LucideIcons.chevronRight,
                        size: 16,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  final List<Widget> children;
  const _ChipRow({required this.children});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 34,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemBuilder: (_, i) => Center(child: children[i]),
    ),
  );
}
