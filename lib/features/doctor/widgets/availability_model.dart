import 'package:intl/intl.dart';

/// The doctor's weekly hours as the app edits them.
///
/// The server stores `availability: [{day, slots: [{startTime 'HH:mm',
/// endTime, type, maxPatients}]}]` and has no "day off" flag — a day is off
/// when it has no slots. Here a day keeps its blocks while switched off, so
/// toggling a day off and on again does not lose what was typed; only days
/// that are on are sent back.

const kWeekDays = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

const kSlotTypes = ['clinic', 'video', 'home', 'all'];

String weekDayLabel(String day) => day.isEmpty
    ? day
    : '${day[0].toUpperCase()}${day.substring(1).toLowerCase()}';

String slotTypeLabel(String type) => switch (type) {
  'video' => 'Video',
  'home' => 'Home',
  'all' => 'All types',
  _ => 'Clinic',
};

/// One continuous stretch of a day, in minutes from midnight.
class AvailabilityBlock {
  final int start;
  final int end;
  final String type;
  final int maxPatients;

  const AvailabilityBlock({
    required this.start,
    required this.end,
    this.type = 'clinic',
    this.maxPatients = 1,
  });

  int get minutes => end > start ? end - start : 0;

  AvailabilityBlock copyWith({int? start, int? end, String? type}) =>
      AvailabilityBlock(
        start: start ?? this.start,
        end: end ?? this.end,
        type: type ?? this.type,
        maxPatients: maxPatients,
      );

  /// Null when the slot cannot be read — a bad record is dropped rather than
  /// crashing the screen.
  static AvailabilityBlock? fromJson(dynamic json) {
    if (json is! Map) return null;
    final start = parseHhMm(json['startTime']);
    final end = parseHhMm(json['endTime']);
    if (start == null || end == null) return null;
    final type = '${json['type'] ?? 'clinic'}';
    return AvailabilityBlock(
      start: start,
      end: end,
      type: kSlotTypes.contains(type) ? type : 'clinic',
      maxPatients: int.tryParse('${json['maxPatients'] ?? 1}') ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
    'startTime': formatHhMm(start),
    'endTime': formatHhMm(end),
    'type': type,
    'maxPatients': maxPatients < 1 ? 1 : maxPatients,
  };

  @override
  bool operator ==(Object other) =>
      other is AvailabilityBlock &&
      other.start == start &&
      other.end == end &&
      other.type == type &&
      other.maxPatients == maxPatients;

  @override
  int get hashCode => Object.hash(start, end, type, maxPatients);
}

class AvailabilityDay {
  final bool enabled;
  final List<AvailabilityBlock> blocks;
  const AvailabilityDay({this.enabled = false, this.blocks = const []});

  bool get isOpen => enabled && blocks.isNotEmpty;

  AvailabilityDay copyWith({bool? enabled, List<AvailabilityBlock>? blocks}) =>
      AvailabilityDay(
        enabled: enabled ?? this.enabled,
        blocks: blocks ?? this.blocks,
      );

  @override
  bool operator ==(Object other) =>
      other is AvailabilityDay &&
      other.enabled == enabled &&
      _sameBlocks(other.blocks, blocks);

  @override
  int get hashCode => Object.hash(enabled, Object.hashAll(blocks));
}

bool _sameBlocks(List<AvailabilityBlock> a, List<AvailabilityBlock> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Monday to Sunday, always all seven keys.
Map<String, AvailabilityDay> parseWeek(dynamic raw) {
  final week = {for (final d in kWeekDays) d: const AvailabilityDay()};
  if (raw is! List) return week;
  for (final entry in raw) {
    if (entry is! Map) continue;
    final day = '${entry['day'] ?? ''}'.toLowerCase();
    if (!week.containsKey(day)) continue;
    final slots = entry['slots'];
    final blocks = <AvailabilityBlock>[
      ...week[day]!.blocks,
      if (slots is List)
        for (final s in slots) ?AvailabilityBlock.fromJson(s),
    ]..sort((a, b) => a.start.compareTo(b.start));
    week[day] = AvailabilityDay(enabled: blocks.isNotEmpty, blocks: blocks);
  }
  return week;
}

List<Map<String, dynamic>> weekToJson(Map<String, AvailabilityDay> week) => [
  for (final d in kWeekDays)
    if (week[d]?.isOpen ?? false)
      {
        'day': d,
        'slots': [for (final b in week[d]!.blocks) b.toJson()],
      },
];

bool sameWeek(Map<String, AvailabilityDay> a, Map<String, AvailabilityDay> b) =>
    kWeekDays.every((d) => a[d] == b[d]);

int? parseHhMm(dynamic value) {
  final parts = '${value ?? ''}'.trim().split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null || h < 0 || h > 24 || m < 0 || m > 59) {
    return null;
  }
  return (h * 60 + m).clamp(0, 24 * 60);
}

String formatHhMm(int minutes) {
  final m = minutes.clamp(0, 24 * 60 - 1);
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// "9:00 AM".
String formatClock(int minutes) {
  final m = minutes.clamp(0, 24 * 60 - 1);
  return DateFormat('h:mm a').format(DateTime(2000, 1, 1, m ~/ 60, m % 60));
}

/// "9:00 AM – 1:00 PM · Clinic".
String blockLabel(AvailabilityBlock b) =>
    '${formatClock(b.start)} – ${formatClock(b.end)} · ${slotTypeLabel(b.type)}';

/// One message per block, or null when the block is fine. Overlap is
/// checked against every other block regardless of type: one doctor cannot
/// be in the clinic and on a video call at the same time.
List<String?> blockProblems(List<AvailabilityBlock> blocks) {
  return [
    for (var i = 0; i < blocks.length; i++)
      if (blocks[i].end <= blocks[i].start)
        'End time must be after the start time.'
      else if ([
        for (var j = 0; j < blocks.length; j++)
          if (j != i &&
              blocks[j].end > blocks[j].start &&
              blocks[i].start < blocks[j].end &&
              blocks[j].start < blocks[i].end)
            j,
      ].isNotEmpty)
        'Overlaps another time block.'
      else
        null,
  ];
}

/// Total open minutes in the week, across enabled days.
int weeklyMinutes(Map<String, AvailabilityDay> week) => week.values
    .where((d) => d.isOpen)
    .expand((d) => d.blocks)
    .fold(0, (sum, b) => sum + b.minutes);

/// The consultation types the week offers; 'all' counts as every type.
Set<String> weeklyTypes(Map<String, AvailabilityDay> week) {
  final types = <String>{};
  for (final b in week.values.where((d) => d.isOpen).expand((d) => d.blocks)) {
    if (b.type == 'all') {
      types.addAll(const ['clinic', 'video', 'home']);
    } else {
      types.add(b.type);
    }
  }
  return types;
}

/// "34 hours", "7.5 hours", "1 hour", "45 min".
String hoursLabel(int minutes) {
  if (minutes <= 0) return '0 hours';
  if (minutes < 60) return '$minutes min';
  final h = minutes / 60;
  final text = h == h.roundToDouble()
      ? h.toStringAsFixed(0)
      : h.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
  return '$text ${h == 1 ? 'hour' : 'hours'}';
}
