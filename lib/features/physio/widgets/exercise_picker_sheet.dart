import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../providers/physio_exercise_provider.dart';
import 'exercise_editor.dart';
import 'exercise_ui.dart';

/// Picks one or more library exercises to add to a plan. Exercises already
/// in the plan ([exclude], by id) are shown as added and can't be picked
/// again (the server rejects duplicates).
Future<List<Map<String, dynamic>>?> showExercisePickerSheet(
  BuildContext context, {
  Set<String> exclude = const {},
}) => showAppSheet<List<Map<String, dynamic>>>(
  context,
  builder: (_) => ExercisePickerSheet(exclude: exclude),
);

class ExercisePickerSheet extends ConsumerStatefulWidget {
  final Set<String> exclude;
  const ExercisePickerSheet({super.key, this.exclude = const {}});

  @override
  ConsumerState<ExercisePickerSheet> createState() =>
      _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends ConsumerState<ExercisePickerSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String? _bodyPart;

  /// Picked ids in the order they were tapped.
  final List<String> _picked = [];

  PhysioExerciseCatalogNotifier get _catalog =>
      ref.read(physioExerciseCatalogProvider.notifier);

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) _catalog.ensureLoaded();
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
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _query = v.trim());
      _catalog.search(v);
    });
  }

  void _toggle(String id) => setState(() {
    if (!_picked.remove(id)) _picked.add(id);
  });

  Future<void> _create() async {
    final saved = await Navigator.of(context).push<Map<String, dynamic>>(
      AppPageRoute(builder: (_) => const ExerciseEditorScreen()),
    );
    if (saved != null && mounted) {
      setState(() {
        _picked.add(exId(saved));
        _query = '';
        _search.clear();
      });
    }
  }

  void _done(PhysioExerciseCatalogState state) {
    Navigator.of(context).pop([for (final id in _picked) ?state.byId(id)]);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(physioExerciseCatalogProvider);
    final accent = ModuleAccent.of(context);
    final list = state.filtered(query: _query, bodyPart: _bodyPart);
    final loading = !state.hasLoaded && state.error == null;
    final bodyParts = state.bodyParts;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Add exercises',
                  style: AppType.sans(
                    fontSize: AppType.title,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textStrong,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _create,
                icon: Icon(LucideIcons.plus, size: 15, color: accent.color),
                label: Text(
                  'New',
                  style: AppType.sans(
                    fontSize: AppType.small,
                    fontWeight: FontWeight.w600,
                    color: accent.color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AppSearchField(
            controller: _search,
            hint: 'Search the library',
            onChanged: _onSearch,
          ),
          if (bodyParts.length > 1) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final b in [null, ...bodyParts])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: AppFilterChip(
                        label: b ?? 'All',
                        selected: _bodyPart == b,
                        onTap: () => setState(() => _bodyPart = b),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: loading
                ? const SingleChildScrollView(child: AppListSkeleton(count: 5))
                : ListView(
                    children: [
                      if (state.error != null)
                        AppErrorBanner(
                          message: state.error!,
                          onRetry: _catalog.load,
                        ),
                      if (list.isEmpty && state.error == null)
                        AppEmptyState(
                          icon: LucideIcons.dumbbell,
                          text: state.items.isEmpty
                              ? 'Your library is empty.\nAdd an exercise to prescribe it.'
                              : 'No exercises match “$_query”.',
                          action: TextButton(
                            onPressed: _create,
                            child: Text(
                              'Add exercise',
                              style: AppType.sans(
                                fontSize: AppType.small,
                                fontWeight: FontWeight.w600,
                                color: accent.color,
                              ),
                            ),
                          ),
                        ),
                      for (final ex in list)
                        Padding(
                          key: ValueKey(exId(ex)),
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _row(ex),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 10),
          AppButton(
            label: _picked.isEmpty
                ? 'Choose exercises'
                : 'Add ${_picked.length} exercise${_picked.length == 1 ? '' : 's'}',
            icon: LucideIcons.check,
            onPressed: _picked.isEmpty ? null : () => _done(state),
          ),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> ex) {
    final accent = ModuleAccent.of(context);
    final id = exId(ex);
    final added = widget.exclude.contains(id);
    final picked = _picked.contains(id);
    return Opacity(
      opacity: added ? 0.55 : 1,
      child: ExerciseCard(
        exercise: ex,
        selected: picked,
        onTap: added ? null : () => _toggle(id),
        trailing: added
            ? Text(
                'Added',
                style: AppType.sans(
                  fontSize: AppType.caption,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textTertiary,
                ),
              )
            : AnimatedContainer(
                duration: AppMotion.fast,
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: picked ? accent.color : AppColors.bg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: picked ? accent.color : AppColors.borderStrong,
                    width: 1.5,
                  ),
                ),
                child: picked
                    ? const Icon(
                        LucideIcons.check,
                        size: 14,
                        color: Colors.white,
                      )
                    : null,
              ),
      ),
    );
  }
}
