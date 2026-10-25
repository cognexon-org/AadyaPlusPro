import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../providers/physio_exercise_provider.dart';
import 'exercise_ui.dart';

enum ExerciseSheetAction { edit, archive }

/// Everything about one library exercise. Resolves to what the physio
/// chose to do next (edit or archive), or null when just closed.
Future<ExerciseSheetAction?> showExerciseDetailSheet(
  BuildContext context,
  Map<String, dynamic> exercise,
) => showAppSheet<ExerciseSheetAction>(
  context,
  builder: (_) => ExerciseDetailSheet(exercise: exercise),
);

class ExerciseDetailSheet extends StatelessWidget {
  final Map<String, dynamic> exercise;
  const ExerciseDetailSheet({super.key, required this.exercise});

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    final ex = exercise;
    final description = '${ex['description'] ?? ''}'.trim();
    final steps = exStrings(ex['instructions']);
    final cautions = exStrings(ex['precautions']);
    final equipment = exStrings(ex['equipment']);
    final video = '${ex['videoUrl'] ?? ''}'.trim();
    final image = '${ex['imageUrl'] ?? ''}'.trim();
    final defaults = exDefaultsLine(ex);
    final tags = [
      '${ex['bodyPart'] ?? ''}'.trim(),
      '${ex['category'] ?? ''}'.trim(),
      exDifficultyLabel('${ex['difficulty'] ?? ''}'),
    ].where((e) => e.isNotEmpty).toList();

    Widget heading(String t) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        t,
        style: AppType.sans(
          fontSize: AppType.small,
          fontWeight: FontWeight.w700,
          color: AppColors.textStrong,
        ),
      ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.86,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (exIsWebUrl(image)) ...[
                    ExerciseThumb(
                      exercise: ex,
                      size: double.infinity,
                      height: 170,
                      radius: 14,
                    ),
                    const SizedBox(height: 14),
                  ],
                  Text(
                    exName(ex),
                    style: AppType.sans(
                      fontSize: AppType.heading,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textStrong,
                    ),
                  ),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final t in tags)
                          ExerciseTag(t, background: AppColors.panel),
                        if (exIsWebUrl(video))
                          const ExerciseTag(
                            'Video',
                            icon: LucideIcons.play,
                            accent: true,
                          ),
                      ],
                    ),
                  ],
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      description,
                      style: AppType.sans(
                        fontSize: AppType.body,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                  if (defaults.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.panel,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.repeat,
                            size: 16,
                            color: accent.color,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Default dosing',
                                  style: AppType.sans(
                                    fontSize: AppType.micro,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                                Text(
                                  defaults,
                                  style: AppType.sans(
                                    fontSize: AppType.body,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textStrong,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (steps.isNotEmpty) ...[
                    heading('How to do it'),
                    for (final (i, s) in steps.indexed)
                      _Step(number: i + 1, text: s),
                  ],
                  if (cautions.isNotEmpty) ...[
                    heading('Precautions'),
                    for (final c in cautions) _Caution(text: c),
                  ],
                  if (equipment.isNotEmpty) ...[
                    heading('Equipment'),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final e in equipment)
                          ExerciseTag(e, background: AppColors.panel),
                      ],
                    ),
                  ],
                  if (steps.isEmpty && description.isEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      'No instructions yet. Add steps so patients know how to do it at home.',
                      style: AppType.sans(
                        fontSize: AppType.caption,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
          if (exIsWebUrl(video)) ...[
            AppButton(
              label: 'Watch video',
              icon: LucideIcons.play,
              onPressed: () => openExerciseVideo(context, video),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: AppSecondaryButton(
                  label: 'Archive',
                  icon: LucideIcons.archive,
                  color: AppColors.textSecondary,
                  onPressed: () =>
                      Navigator.of(context).pop(ExerciseSheetAction.archive),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppSecondaryButton(
                  label: 'Edit',
                  icon: LucideIcons.squarePen,
                  onPressed: () =>
                      Navigator.of(context).pop(ExerciseSheetAction.edit),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String text;
  const _Step({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.veryLight,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: AppType.sans(
                fontSize: AppType.micro,
                fontWeight: FontWeight.w700,
                color: accent.color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                text,
                style: AppType.sans(
                  fontSize: AppType.body,
                  color: AppColors.textPrimary,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Caution extends StatelessWidget {
  final String text;
  const _Caution({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(
            LucideIcons.triangleAlert,
            size: 15,
            color: AppColors.warning,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AppType.sans(
              fontSize: AppType.body,
              color: AppColors.textPrimary,
              height: 1.45,
            ),
          ),
        ),
      ],
    ),
  );
}
