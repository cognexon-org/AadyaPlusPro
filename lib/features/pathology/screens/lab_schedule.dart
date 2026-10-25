import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/availability_save_bar.dart';
import '../providers/lab_providers.dart';
import '../widgets/lab_ui.dart';

/// Mon..Sun in the backend's numbering (0 = Sunday).
const _order = [1, 2, 3, 4, 5, 6, 0];
const _names = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

class _Slot {
  int start; // minutes from midnight
  int end;
  int capacity;
  _Slot(this.start, this.end, this.capacity);

  _Slot copy() => _Slot(start, end, capacity);

  static int? _mins(dynamic hhmm) {
    final p = '$hhmm'.split(':');
    if (p.length != 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    return h == null || m == null ? null : h * 60 + m;
  }

  static String hhmm(int mins) =>
      '${(mins ~/ 60).toString().padLeft(2, '0')}:${(mins % 60).toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
    'startTime': hhmm(start),
    'endTime': hhmm(end),
    'maxCapacity': capacity,
  };
}

class _Day {
  bool enabled;
  List<_Slot> slots;
  _Day(this.enabled, this.slots);
  _Day copy() => _Day(enabled, slots.map((s) => s.copy()).toList());
}

String _label(int mins) =>
    DateFormat('h:mm a').format(DateTime(2000, 1, 1, mins ~/ 60, mins % 60));

/// "7–8 am", "11:30 am–12:30 pm" — short enough for a chip.
String _span(int a, int b) {
  String t(int m) {
    final h = (m ~/ 60) % 12 == 0 ? 12 : (m ~/ 60) % 12;
    return m % 60 == 0 ? '$h' : '$h:${(m % 60).toString().padLeft(2, '0')}';
  }

  String ap(int m) => m ~/ 60 < 12 ? 'am' : 'pm';
  return ap(a) == ap(b)
      ? '${t(a)}–${t(b)} ${ap(b)}'
      : '${t(a)} ${ap(a)}–${t(b)} ${ap(b)}';
}

List<_Slot> _range(int from, int to, int step, int cap) => [
  for (var t = from; t + step <= to; t += step) _Slot(t, t + step, cap),
];

/// Collection slots: the lab sets its week once; the server fills in the
/// next weeks from it and keeps rolling forward.
class LabSchedule extends ConsumerStatefulWidget {
  const LabSchedule({super.key});

  @override
  ConsumerState<LabSchedule> createState() => _LabScheduleState();
}

class _LabScheduleState extends ConsumerState<LabSchedule> {
  Map<int, _Day>? _week;
  String _saved = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(labScheduleProvider.notifier).ensureLoaded();
      if (mounted) _adopt();
    });
  }

  void _adopt() {
    final days = ref.read(labScheduleProvider.notifier).days;
    final week = <int, _Day>{for (final w in _order) w: _Day(false, [])};
    for (final d in days) {
      final w = int.tryParse('${d['weekday']}');
      if (w == null || w < 0 || w > 6) continue;
      final slots = <_Slot>[];
      for (final s in (d['slots'] is List ? d['slots'] as List : const [])) {
        if (s is! Map) continue;
        final a = _Slot._mins(s['startTime']);
        final b = _Slot._mins(s['endTime']);
        if (a == null || b == null) continue;
        slots.add(_Slot(a, b, int.tryParse('${s['maxCapacity']}') ?? 10));
      }
      week[w] = _Day(d['enabled'] != false && slots.isNotEmpty, slots);
    }
    setState(() {
      _week = week;
      _saved = _sig(week);
    });
  }

  String _sig(Map<int, _Day> w) => _order
      .map(
        (d) =>
            '${w[d]!.enabled}:${w[d]!.slots.map((s) => '${s.start}-${s.end}-${s.capacity}').join(',')}',
      )
      .join('|');

  bool get _dirty => _week != null && _sig(_week!) != _saved;

  Future<void> _refresh() async {
    await ref.read(labScheduleProvider.notifier).load(silent: true);
    if (mounted && !_dirty) _adopt();
  }

  Future<void> _save() async {
    final week = _week!;
    for (final w in _order) {
      final d = week[w]!;
      final s = [...d.slots]..sort((a, b) => a.start.compareTo(b.start));
      for (var i = 0; i < s.length; i++) {
        if (s[i].end <= s[i].start) {
          doctorToast(
            context,
            '${_names[w]}: a slot ends before it starts.',
            error: true,
          );
          return;
        }
        if (i > 0 && s[i].start < s[i - 1].end) {
          doctorToast(context, '${_names[w]}: slots overlap.', error: true);
          return;
        }
      }
      d.slots = s;
    }
    setState(() => _saving = true);
    try {
      await ref.read(labScheduleProvider.notifier).saveWeek([
        for (final w in _order)
          {
            'weekday': w,
            'enabled': week[w]!.enabled && week[w]!.slots.isNotEmpty,
            'slots': week[w]!.slots.map((s) => s.toJson()).toList(),
          },
      ]);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = _sig(week);
      });
      doctorToast(context, 'Slots saved — patients can book them now');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        doctorToast(
          context,
          labError(e, fallback: 'Couldn’t save the slots.'),
          error: true,
        );
      }
    }
  }

  Future<void> _presets() async {
    final pick = await showAppSheet<int>(
      context,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Quick setup',
            style: AppType.sans(
              fontSize: AppType.title,
              fontWeight: FontWeight.w700,
              color: AppColors.textStrong,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Applies to Monday to Saturday. Sunday stays as it is.',
            style: AppType.sans(
              fontSize: AppType.caption,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          _PresetRow(
            title: 'Morning',
            subtitle: '7 – 11 am, hourly, 10 per slot',
            onTap: () => Navigator.pop(ctx, 0),
          ),
          _PresetRow(
            title: 'Full day',
            subtitle: '7 am – 7 pm, hourly, 10 per slot',
            onTap: () => Navigator.pop(ctx, 1),
          ),
          _PresetRow(
            title: 'Every 30 minutes',
            subtitle: '7 – 11 am, 5 per slot',
            onTap: () => Navigator.pop(ctx, 2),
          ),
        ],
      ),
    );
    if (pick == null || !mounted) return;
    final slots = switch (pick) {
      0 => _range(7 * 60, 11 * 60, 60, 10),
      1 => _range(7 * 60, 19 * 60, 60, 10),
      _ => _range(7 * 60, 11 * 60, 30, 5),
    };
    setState(() {
      for (final w in [1, 2, 3, 4, 5, 6]) {
        _week![w] = _Day(true, slots.map((s) => s.copy()).toList());
      }
    });
  }

  void _copyMonday() {
    final mon = _week![1]!;
    setState(() {
      for (final w in [2, 3, 4, 5, 6]) {
        _week![w] = mon.copy();
      }
    });
    doctorToast(context, 'Monday copied to Tuesday – Saturday');
  }

  Future<int?> _time(int initial) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  Future<void> _editSlot(int weekday, int? index) async {
    final day = _week![weekday]!;
    final existing = index == null ? null : day.slots[index];
    final last = day.slots.isEmpty ? null : day.slots.last;
    var start = existing?.start ?? (last?.end ?? 7 * 60);
    var end = existing?.end ?? (start + 60);
    final cap = TextEditingController(
      text: '${existing?.capacity ?? last?.capacity ?? 10}',
    );
    final result = await showAppSheet<String>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_names[weekday]} · ${index == null ? 'new slot' : 'edit slot'}',
              style: AppType.sans(
                fontSize: AppType.title,
                fontWeight: FontWeight.w700,
                color: AppColors.textStrong,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: AppPickerField(
                    label: 'From',
                    valueText: _label(start),
                    icon: LucideIcons.clock,
                    onTap: () async {
                      final v = await _time(start);
                      if (v != null) {
                        setS(() {
                          start = v;
                          if (end <= start) end = start + 60;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppPickerField(
                    label: 'To',
                    valueText: _label(end),
                    icon: LucideIcons.clock,
                    onTap: () async {
                      final v = await _time(end);
                      if (v != null) setS(() => end = v);
                    },
                  ),
                ),
              ],
            ),
            AppTextField(
              label: 'Patients per slot',
              controller: cap,
              isNum: true,
              icon: LucideIcons.users,
            ),
            Row(
              children: [
                if (index != null) ...[
                  Expanded(
                    child: AppSecondaryButton(
                      label: 'Remove',
                      color: AppColors.error,
                      onPressed: () => Navigator.pop(ctx, 'remove'),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: AppButton(
                    label: index == null ? 'Add slot' : 'Done',
                    onPressed: end > start
                        ? () => Navigator.pop(ctx, 'save')
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final capacity = int.tryParse(cap.text.trim());
    cap.dispose();
    if (!mounted || result == null) return;
    setState(() {
      if (result == 'remove' && index != null) {
        day.slots.removeAt(index);
        if (day.slots.isEmpty) day.enabled = false;
        return;
      }
      final c = capacity == null || capacity < 1 ? 10 : capacity;
      if (index == null) {
        day.slots.add(_Slot(start, end, c));
        day.enabled = true;
      } else {
        day.slots[index] = _Slot(start, end, c);
      }
      day.slots.sort((a, b) => a.start.compareTo(b.start));
    });
  }

  Future<void> _dayTapped(Map<String, dynamic> d) async {
    final date = '${d['date']}';
    final holiday = d['holiday'] == true;
    final booked = int.tryParse('${d['booked']}') ?? 0;
    final day = DateTime.tryParse(date);
    final ok = await AppModal.confirm(
      context,
      title: holiday
          ? 'Open on ${day == null ? date : DateFormat('EEE d MMM').format(day)}?'
          : 'Close on ${day == null ? date : DateFormat('EEE d MMM').format(day)}?',
      message: holiday
          ? 'Slots come back from your weekly timetable.'
          : booked > 0
          ? '$booked booking${booked == 1 ? ' is' : 's are'} on this day. Reschedule them first.'
          : 'Patients won’t be able to book this day — for a holiday or a day off.',
      icon: holiday ? LucideIcons.calendarCheck : LucideIcons.calendarX,
      confirmLabel: holiday ? 'Open' : 'Close day',
      destructive: !holiday,
    );
    if (!ok || !mounted) return;
    try {
      await ref
          .read(labScheduleProvider.notifier)
          .setHoliday(date, closed: !holiday);
      if (mounted) doctorToast(context, holiday ? 'Day opened' : 'Day closed');
    } catch (e) {
      if (mounted) doctorToast(context, labError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(labScheduleProvider);
    final upcoming = ref.read(labScheduleProvider.notifier).upcoming;
    final accent = ModuleAccent.of(context).color;
    final week = _week;

    return DoctorDiscardGuard(
      dirty: _dirty,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: doctorSettingsAppBar('Collection slots'),
        bottomNavigationBar: doctorSaveBar(
          dirty: _dirty,
          saving: _saving,
          onSave: _save,
          label: 'Save slots',
        ),
        body: RefreshIndicator(
          color: accent,
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              if (!st.hasLoaded || week == null)
                st.error != null
                    ? AppErrorBanner(
                        message: st.error!,
                        onRetry: () async {
                          await ref.read(labScheduleProvider.notifier).load();
                          if (mounted) _adopt();
                        },
                      )
                    : const AppListSkeleton(count: 5)
              else ...[
                if (st.error != null) ...[
                  AppErrorBanner(message: st.error!, onRetry: _refresh),
                  const SizedBox(height: 12),
                ],
                Text(
                  'Set your week once. Slots for the coming weeks are created '
                  'from it automatically and keep rolling forward.',
                  style: AppType.sans(
                    fontSize: AppType.small,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: AppSecondaryButton(
                        label: 'Quick setup',
                        icon: LucideIcons.wandSparkles,
                        onPressed: _presets,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppSecondaryButton(
                        label: 'Copy Monday',
                        icon: LucideIcons.copy,
                        onPressed: week[1]!.slots.isEmpty ? null : _copyMonday,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                for (final w in _order) ...[
                  _dayCard(w, week[w]!),
                  const SizedBox(height: 10),
                ],
                if (upcoming.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const AppSectionTitle('Next 14 days'),
                  Text(
                    'Tap a day to close it for a holiday, or open it again.',
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  AppGroup(
                    children: [
                      for (var i = 0; i < upcoming.length; i++) ...[
                        if (i > 0) const AppHairline(),
                        _UpcomingRow(
                          day: upcoming[i],
                          onTap: () => _dayTapped(upcoming[i]),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayCard(int w, _Day d) {
    final accent = ModuleAccent.of(context);
    final capacity = d.slots.fold<int>(0, (n, s) => n + s.capacity);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _names[w],
                      style: AppType.sans(
                        fontSize: AppType.body,
                        fontWeight: FontWeight.w700,
                        color: d.enabled
                            ? AppColors.textStrong
                            : AppColors.textTertiary,
                      ),
                    ),
                    Text(
                      d.enabled && d.slots.isNotEmpty
                          ? '${d.slots.length} slot${d.slots.length == 1 ? '' : 's'} · up to $capacity patients'
                          : 'Closed',
                      style: AppType.sans(
                        fontSize: AppType.caption,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AppSwitch(
                value: d.enabled,
                onChanged: (v) => setState(() {
                  d.enabled = v;
                  if (v && d.slots.isEmpty) {
                    d.slots = _range(7 * 60, 11 * 60, 60, 10);
                  }
                }),
              ),
            ],
          ),
          if (d.enabled) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < d.slots.length; i++)
                  AppPressable(
                    onTap: () => _editSlot(w, i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.borderStrong),
                      ),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: _span(d.slots[i].start, d.slots[i].end),
                              style: AppType.sans(
                                fontSize: AppType.caption,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            TextSpan(
                              text: '  ·  ${d.slots[i].capacity}',
                              style: AppType.sans(
                                fontSize: AppType.caption,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                AppPressable(
                  onTap: () => _editSlot(w, null),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: accent.veryLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.plus, size: 13, color: accent.color),
                        const SizedBox(width: 4),
                        Text(
                          'Slot',
                          style: AppType.sans(
                            fontSize: AppType.caption,
                            fontWeight: FontWeight.w700,
                            color: accent.color,
                          ),
                        ),
                      ],
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
}

class _PresetRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _PresetRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: AppPressable(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppType.sans(
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textStrong,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: AppColors.textDisabled,
            ),
          ],
        ),
      ),
    ),
  );
}

class _UpcomingRow extends StatelessWidget {
  final Map<String, dynamic> day;
  final VoidCallback onTap;
  const _UpcomingRow({required this.day, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context).color;
    final date = DateTime.tryParse('${day['date']}');
    final holiday = day['holiday'] == true;
    final slots = int.tryParse('${day['slots']}') ?? 0;
    final cap = int.tryParse('${day['capacity']}') ?? 0;
    final booked = int.tryParse('${day['booked']}') ?? 0;
    final fill = cap == 0 ? 0.0 : (booked / cap).clamp(0.0, 1.0);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            SizedBox(
              width: 86,
              child: Text(
                date == null ? '${day['date']}' : dayLabel(date),
                style: AppType.sans(
                  fontSize: AppType.small,
                  fontWeight: FontWeight.w600,
                  color: holiday
                      ? AppColors.textTertiary
                      : AppColors.textPrimary,
                ),
              ),
            ),
            Expanded(
              child: holiday
                  ? Text(
                      'Closed',
                      style: AppType.sans(
                        fontSize: AppType.caption,
                        fontWeight: FontWeight.w600,
                        color: AppColors.error,
                      ),
                    )
                  : slots == 0
                  ? Text(
                      'No slots',
                      style: AppType.sans(
                        fontSize: AppType.caption,
                        color: AppColors.textTertiary,
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: fill,
                        minHeight: 6,
                        backgroundColor: AppColors.borderStrong,
                        color: fill >= 1 ? AppColors.warning : accent,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 58,
              child: Text(
                holiday || slots == 0 ? '' : '$booked / $cap',
                textAlign: TextAlign.right,
                style: AppType.sans(
                  fontSize: AppType.caption,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
