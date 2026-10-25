import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/doctor_ui.dart';

export '../../doctor/widgets/doctor_ui.dart'
    show capitalised, dayLabel, timeLabel, doctorError;

// ─────────────────────────── Order fields ───────────────────────────
//
// One place that knows a lab order's (LabTest) shape. `scheduledDate` is the
// day at the server's local midnight, `startTime` "HH:mm".

Map<String, dynamic> labPatient(Map<String, dynamic> o) {
  final p = o['patientId'];
  return p is Map ? Map<String, dynamic>.from(p) : const {};
}

String labPatientName(Map<String, dynamic> o) {
  final n = '${labPatient(o)['name'] ?? ''}'.trim();
  return n.isEmpty ? 'Patient' : n;
}

String labNumber(Map<String, dynamic> o) => '${o['labTestNumber'] ?? ''}';

String labStatus(Map<String, dynamic> o) => '${o['status'] ?? 'requested'}';

bool labIsHome(Map<String, dynamic> o) => o['type'] == 'home_collection';

String labCollection(Map<String, dynamic> o) =>
    '${o['collectionStatus'] ?? (labIsHome(o) ? 'unassigned' : 'not_required')}';

/// Tests on the order that weren't cancelled.
List<Map<String, dynamic>> labTests(Map<String, dynamic> o) =>
    (o['tests'] is List ? o['tests'] as List : const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((t) => t['status'] != 'cancelled')
        .toList();

/// "CBC, Lipid profile +2".
String labTestSummary(Map<String, dynamic> o, {int show = 2}) {
  final names = labTests(o)
      .map((t) => '${t['testName'] ?? t['testCode'] ?? ''}'.trim())
      .where((n) => n.isNotEmpty)
      .toList();
  if (names.isEmpty) return 'Lab tests';
  if (names.length <= show) return names.join(', ');
  return '${names.take(show).join(', ')} +${names.length - show}';
}

Map<String, dynamic> labPhlebotomist(Map<String, dynamic> o) {
  final p = o['assignedPhlebotomistId'];
  return p is Map ? Map<String, dynamic>.from(p) : const {};
}

DateTime? _serverDay(dynamic raw) {
  final d = DateTime.tryParse('${raw ?? ''}');
  if (d == null) return null;
  // Same trick as the appointments: the server's local midnight, read
  // correctly whatever zone the server runs in.
  final u = (d.isUtc ? d : d.toUtc()).add(const Duration(hours: 14));
  return DateTime(u.year, u.month, u.day);
}

/// The collection slot as a local date-time.
DateTime? labSlot(Map<String, dynamic> o) {
  final day = _serverDay(o['scheduledDate']);
  if (day == null) return null;
  final parts = '${o['startTime'] ?? o['scheduledTime'] ?? ''}'.split(':');
  final h = int.tryParse(parts.isNotEmpty ? parts[0] : '');
  final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
  return h == null ? day : DateTime(day.year, day.month, day.day, h, m);
}

DateTime? labTime(Map<String, dynamic> o, String key) {
  final d = DateTime.tryParse('${o[key] ?? ''}');
  return d?.toLocal();
}

num labTotal(Map<String, dynamic> o) =>
    num.tryParse('${o['totalAmount'] ?? 0}') ?? 0;

bool labPaid(Map<String, dynamic> o) => o['paymentStatus'] == 'paid';

bool labOverdue(Map<String, dynamic> o) => o['overdue'] == true;

/// { entered, abnormal, critical, testsWithResults, tests } from the server.
Map<String, int> labResultSummary(Map<String, dynamic> o) {
  final s = o['resultSummary'];
  int read(String k) => s is Map ? int.tryParse('${s[k] ?? 0}') ?? 0 : 0;
  return {
    for (final k in [
      'entered',
      'abnormal',
      'critical',
      'testsWithResults',
      'tests',
    ])
      k: read(k),
  };
}

bool labHasReport(Map<String, dynamic> o) =>
    o['reportFile'] is Map && (o['reportFile'] as Map)['uploadedAt'] != null;

// ─────────────────────────── Stages ───────────────────────────
//
// The lab's working view of an order, coarser than its status.

enum LabStage { collect, processing, reports, completed, cancelled }

LabStage labStage(Map<String, dynamic> o) => switch (labStatus(o)) {
  'requested' || 'scheduled' => LabStage.collect,
  'sample_collected' || 'processing' => LabStage.processing,
  'ready_for_review' => LabStage.reports,
  'completed' => LabStage.completed,
  _ => LabStage.cancelled,
};

String labStageLabel(LabStage s) => switch (s) {
  LabStage.collect => 'To collect',
  LabStage.processing => 'In process',
  LabStage.reports => 'Ready to release',
  LabStage.completed => 'Completed',
  LabStage.cancelled => 'Cancelled',
};

String labStatusLabel(String s) => switch (s) {
  'requested' || 'scheduled' => 'Booked',
  'sample_collected' => 'Sample collected',
  'processing' => 'Processing',
  'ready_for_review' => 'Ready to release',
  'completed' => 'Report released',
  'cancelled' => 'Cancelled',
  _ => capitalised(s.replaceAll('_', ' ')),
};

String labCollectionLabel(String s) => switch (s) {
  'unassigned' => 'Not assigned',
  'assigned' => 'Assigned',
  'en_route' => 'On the way',
  'arrived' => 'Arrived',
  'collected' => 'Collected',
  'delivered_to_lab' => 'At the lab',
  'failed' => 'Collection failed',
  _ => '',
};

// ─────────────────────────── Samples & flags ───────────────────────────

/// Vacutainer cap colour for a sample type, so the phlebotomist picks the
/// right tube at a glance (EDTA lavender, serum gold, fluoride grey…).
({Color color, String label}) tubeFor(String? sampleType) {
  final s = (sampleType ?? '').toLowerCase();
  if (s.contains('edta')) {
    return (color: const Color(0xFF8B5CF6), label: 'EDTA');
  }
  if (s.contains('fluoride')) {
    return (color: const Color(0xFF94A3B8), label: 'Fluoride');
  }
  if (s.contains('citrate')) {
    return (color: const Color(0xFF38BDF8), label: 'Citrate');
  }
  if (s.contains('heparin')) {
    return (color: const Color(0xFF22C55E), label: 'Heparin');
  }
  if (s.contains('urine')) {
    return (color: const Color(0xFFEAB308), label: 'Urine');
  }
  if (s.contains('stool')) {
    return (color: const Color(0xFF92400E), label: 'Stool');
  }
  if (s.contains('swab')) {
    return (color: const Color(0xFFF97316), label: 'Swab');
  }
  if (s.contains('serum') || s.contains('blood')) {
    return (color: const Color(0xFFF59E0B), label: 'Serum');
  }
  return (color: AppColors.textTertiary, label: sampleType ?? 'Sample');
}

Color labFlagColor(String? flag) => switch (flag) {
  'critical' => AppColors.error,
  'high' => const Color(0xFFC2410C),
  'low' => const Color(0xFF1D4ED8),
  _ => AppColors.textStrong,
};

String labFlagLabel(String? flag) => switch (flag) {
  'critical' => 'Critical',
  'high' => 'High',
  'low' => 'Low',
  _ => '',
};

/// Flag for a typed value against a catalogue parameter — mirrors the
/// server (services/labResults.service.js) so the screen can colour values
/// while they're being typed.
String? labFlagFor(Map<String, dynamic> param, String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  num? n(dynamic v) =>
      v == null ? null : num.tryParse('$v'.replaceAll(',', ''));
  final v = n(value);
  final low = n(param['low']);
  final high = n(param['high']);
  if (v != null && (low != null || high != null)) {
    final cl = n(param['critLow']);
    final ch = n(param['critHigh']);
    if ((cl != null && v <= cl) || (ch != null && v >= ch)) return 'critical';
    if (low != null && v < low) return 'low';
    if (high != null && v > high) return 'high';
    return 'normal';
  }
  final expected = '${param['text'] ?? ''}'.trim().toLowerCase();
  if (expected.isEmpty) return 'normal';
  return value.toLowerCase() == expected ? 'normal' : 'high';
}

/// "12 – 16 g/dL", "Up to 200", or the expected text.
String labRangeText(Map<String, dynamic> param) {
  num? n(dynamic v) => v == null ? null : num.tryParse('$v');
  String f(num x) => x == x.roundToDouble() ? '${x.toInt()}' : '$x';
  final low = n(param['low']);
  final high = n(param['high']);
  if (low != null && high != null) {
    return low == 0 ? 'Up to ${f(high)}' : '${f(low)} – ${f(high)}';
  }
  if (low != null) return 'Above ${f(low)}';
  if (high != null) return 'Up to ${f(high)}';
  return '${param['text'] ?? ''}';
}

String labError(Object e, {String fallback = 'Something went wrong.'}) =>
    doctorError(e, fallback: fallback);

// ─────────────────────────── Widgets ───────────────────────────

/// A small tube-cap dot with its label.
class TubeChip extends StatelessWidget {
  final String? sampleType;
  const TubeChip(this.sampleType, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = tubeFor(sampleType);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: t.color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          t.label,
          style: AppType.sans(
            fontSize: AppType.caption,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Dot + label for the order's stage, coloured by urgency.
class LabStageTag extends StatelessWidget {
  final Map<String, dynamic> order;
  const LabStageTag(this.order, {super.key});

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context).color;
    final stage = labStage(order);
    final overdue = labOverdue(order);
    final color = overdue
        ? AppColors.error
        : switch (stage) {
            LabStage.collect => AppColors.warning,
            LabStage.processing => accent,
            LabStage.reports => AppColors.success,
            LabStage.completed => AppColors.textTertiary,
            LabStage.cancelled => AppColors.error,
          };
    final label = overdue ? 'Overdue' : labStatusLabel(labStatus(order));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: AppType.sans(
            fontSize: AppType.caption,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// The order row used on Today and Orders: slot time on the left like a
/// diary, patient and tests in the middle, what's next underneath.
class LabOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback? onTap;
  final bool showDay;
  final Widget? actions;

  const LabOrderCard({
    super.key,
    required this.order,
    this.onTap,
    this.showDay = false,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final o = order;
    final slot = labSlot(o);
    final stage = labStage(o);
    final muted = stage == LabStage.cancelled || stage == LabStage.completed;
    final home = labIsHome(o);
    final patient = labPatient(o);
    final collector = '${labPhlebotomist(o)['name'] ?? ''}';
    final summary = labResultSummary(o);
    final tests = labTests(o);
    final sampleTypes = {
      for (final t in tests)
        if ('${t['sampleType'] ?? ''}'.isNotEmpty)
          tubeFor('${t['sampleType']}').label,
    };
    final meta = [
      if (patient['age'] != null) '${patient['age']} yrs',
      if ('${patient['gender'] ?? ''}'.isNotEmpty)
        capitalised('${patient['gender']}'),
    ].join(' · ');

    return AppPressable(
      scale: 0.985,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(14),
          border: labOverdue(o)
              ? Border.all(color: AppColors.error.withValues(alpha: 0.35))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 68,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showDay)
                        Text(
                          dayLabel(slot),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.sans(
                            fontSize: AppType.micro,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      Text(
                        timeLabel(slot),
                        style: AppType.sans(
                          fontSize: AppType.body,
                          fontWeight: FontWeight.w700,
                          color: muted
                              ? AppColors.textTertiary
                              : AppColors.textStrong,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 38,
                  margin: const EdgeInsets.only(right: 12),
                  color: AppColors.borderStrong,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              labPatientName(o),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.sans(
                                fontSize: AppType.title,
                                fontWeight: FontWeight.w700,
                                color: muted
                                    ? AppColors.textSecondary
                                    : AppColors.textStrong,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          LabStageTag(o),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        labTestSummary(o),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.sans(
                          fontSize: AppType.small,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 10,
                        runSpacing: 3,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _Meta(
                            icon: home
                                ? LucideIcons.house
                                : LucideIcons.building2,
                            text: home
                                ? (stage == LabStage.collect
                                      ? (collector.isEmpty
                                            ? 'Home · not assigned'
                                            : 'Home · $collector')
                                      : 'Home collection')
                                : 'Lab visit',
                            color:
                                home &&
                                    stage == LabStage.collect &&
                                    collector.isEmpty
                                ? AppColors.warning
                                : null,
                          ),
                          for (final s in sampleTypes.take(2)) TubeChip(s),
                          if (meta.isNotEmpty)
                            Text(
                              meta,
                              style: AppType.sans(
                                fontSize: AppType.caption,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          if (summary['critical']! > 0)
                            _Meta(
                              icon: LucideIcons.triangleAlert,
                              text: '${summary['critical']} critical',
                              color: AppColors.error,
                            )
                          else if (summary['abnormal']! > 0 &&
                              stage != LabStage.completed)
                            _Meta(
                              icon: LucideIcons.activity,
                              text: '${summary['abnormal']} abnormal',
                              color: const Color(0xFFC2410C),
                            ),
                          if (!labPaid(o) && stage != LabStage.cancelled)
                            _Meta(
                              icon: LucideIcons.wallet,
                              text: '${appRupees(labTotal(o))} due',
                              color: AppColors.warning,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (actions != null) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 81),
                child: actions!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const _Meta({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: color ?? AppColors.textTertiary),
      const SizedBox(width: 4),
      Text(
        text,
        style: AppType.sans(
          fontSize: AppType.caption,
          fontWeight: color == null ? FontWeight.w400 : FontWeight.w600,
          color: color ?? AppColors.textSecondary,
        ),
      ),
    ],
  );
}
