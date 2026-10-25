import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import 'availability_model.dart';

/// Opens the editor for one day. Resolves to the edited blocks, or null if
/// the sheet was dismissed.
Future<List<AvailabilityBlock>?> showAvailabilityDaySheet(
  BuildContext context, {
  required String day,
  required List<AvailabilityBlock> blocks,
}) => showAppSheet<List<AvailabilityBlock>>(
  context,
  builder: (_) => AvailabilityDaySheet(day: day, initial: blocks),
);

/// Add, change and remove one day's time blocks. Owns its working copy, so
/// nothing reaches the screen until Done.
class AvailabilityDaySheet extends StatefulWidget {
  final String day;
  final List<AvailabilityBlock> initial;

  const AvailabilityDaySheet({
    super.key,
    required this.day,
    required this.initial,
  });

  @override
  State<AvailabilityDaySheet> createState() => _AvailabilityDaySheetState();
}

class _AvailabilityDaySheetState extends State<AvailabilityDaySheet> {
  late List<AvailabilityBlock> _blocks = widget.initial.isEmpty
      ? [const AvailabilityBlock(start: 9 * 60, end: 13 * 60)]
      : [...widget.initial];

  List<String?> get _problems => blockProblems(_blocks);
  bool get _valid => _problems.every((p) => p == null);

  static const _lastMinute = 24 * 60 - 1;

  bool get _canAdd {
    final lastEnd = _blocks.isEmpty
        ? 0
        : _blocks.map((b) => b.end).reduce((a, b) => a > b ? a : b);
    return lastEnd < _lastMinute - 15;
  }

  void _add() {
    final lastEnd = _blocks.isEmpty
        ? 9 * 60 - 60
        : _blocks.map((b) => b.end).reduce((a, b) => a > b ? a : b);
    // Leave an hour's gap after the last block, like a lunch break.
    final start = (lastEnd + 60).clamp(0, _lastMinute - 15);
    final end = (start + 4 * 60).clamp(start + 15, _lastMinute);
    setState(() {
      _blocks = [
        ..._blocks,
        AvailabilityBlock(start: start, end: end, type: _lastType),
      ];
    });
  }

  String get _lastType => _blocks.isEmpty ? 'clinic' : _blocks.last.type;

  void _remove(int i) => setState(() => _blocks = [..._blocks]..removeAt(i));

  void _update(int i, AvailabilityBlock b) =>
      setState(() => _blocks = [..._blocks]..[i] = b);

  Future<void> _pick(int i, {required bool start}) async {
    final b = _blocks[i];
    final current = start ? b.start : b.end;
    final accent = ModuleAccent.of(context).color;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60 % 24, minute: current % 60),
      helpText: start ? 'Starts at' : 'Ends at',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(
            ctx,
          ).colorScheme.copyWith(primary: accent, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted || i >= _blocks.length) return;
    final minutes = picked.hour * 60 + picked.minute;
    _update(i, start ? b.copyWith(start: minutes) : b.copyWith(end: minutes));
  }

  void _done() {
    if (!_valid) return;
    final sorted = [..._blocks]..sort((a, b) => a.start.compareTo(b.start));
    Navigator.of(context).pop(sorted);
  }

  @override
  Widget build(BuildContext context) {
    final problems = _problems;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          weekDayLabel(widget.day),
          style: AppType.sans(
            fontSize: AppType.heading,
            fontWeight: FontWeight.w700,
            color: AppColors.textStrong,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Patients can book within these times.',
          style: AppType.sans(
            fontSize: AppType.caption,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              if (_blocks.isEmpty)
                const AppEmptyState(
                  icon: LucideIcons.calendarOff,
                  text: 'No hours on this day. Add a time block to open it.',
                ),
              for (var i = 0; i < _blocks.length; i++) ...[
                if (i > 0) Container(height: 1, color: AppColors.borderStrong),
                _blockCard(i, problems[i]),
              ],
            ],
          ),
        ),
        AppPressable(
          scale: 0.97,
          onTap: _canAdd ? _add : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  LucideIcons.plus,
                  size: 16,
                  color: _canAdd
                      ? ModuleAccent.of(context).color
                      : AppColors.textDisabled,
                ),
                const SizedBox(width: 6),
                Text(
                  'Add time block',
                  style: AppType.sans(
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w600,
                    color: _canAdd
                        ? ModuleAccent.of(context).color
                        : AppColors.textDisabled,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        AppButton(label: 'Done', onPressed: _valid ? _done : null),
      ],
    );
  }

  /// Laid straight on the white sheet — grey fields and chips, a hairline
  /// between blocks — rather than in a grey card, where the unselected chips
  /// (also grey) would disappear.
  Widget _blockCard(int i, String? problem) {
    final b = _blocks[i];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _timeButton(
                  'From',
                  b.start,
                  () => _pick(i, start: true),
                  problem != null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '–',
                  style: AppType.sans(
                    fontSize: AppType.body,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
              Expanded(
                child: _timeButton(
                  'To',
                  b.end,
                  () => _pick(i, start: false),
                  problem != null,
                ),
              ),
              IconButton(
                tooltip: 'Remove',
                onPressed: () => _remove(i),
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  LucideIcons.trash2,
                  size: 17,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(right: 40),
            child: Row(
              children: [
                for (final t in kSlotTypes) ...[
                  if (t != kSlotTypes.first) const SizedBox(width: 6),
                  Expanded(
                    child: AppFilterChip(
                      label: t == 'all' ? 'All' : slotTypeLabel(t),
                      selected: b.type == t,
                      block: true,
                      onTap: () => _update(i, b.copyWith(type: t)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (problem != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  LucideIcons.circleAlert,
                  size: 13,
                  color: AppColors.error,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    problem,
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Grey like every other field, so the two times read as tappable values.
  Widget _timeButton(
    String label,
    int minutes,
    VoidCallback onTap,
    bool error,
  ) => AppPressable(
    scale: 0.97,
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(AppColors.radiusInput),
        border: error ? Border.all(color: AppColors.error) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppType.sans(
              fontSize: AppType.micro,
              color: AppColors.textTertiary,
            ),
          ),
          Text(
            formatClock(minutes),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.sans(
              fontSize: AppType.body,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    ),
  );
}
