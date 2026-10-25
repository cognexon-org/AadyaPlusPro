import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import 'doctor_ui.dart';

/// Statuses that count as a visit (booked or seen). Requests, cancellations,
/// declines and no-shows don't, and are never a "last" or "next" visit.
const _visitStatuses = {'confirmed', 'in_progress', 'completed', 'rescheduled'};

/// One patient as the doctor knows them, built from their appointments —
/// the server has no "my patients" endpoint.
class PatientSummary {
  final String id;
  final Map<String, dynamic> patient;
  final int visits;
  final DateTime? lastVisit;
  final DateTime? nextVisit;

  /// Most recent appointment date of any status, for "Recent" sorting.
  final DateTime? lastSeen;

  const PatientSummary({
    required this.id,
    required this.patient,
    required this.visits,
    this.lastVisit,
    this.nextVisit,
    this.lastSeen,
  });

  String get name {
    final n = '${patient['name'] ?? ''}'.trim();
    return n.isEmpty ? 'Patient' : n;
  }

  String get phone => '${patient['phone'] ?? ''}'.trim();

  /// "34 yrs · Male", or empty.
  String get meta => patientMeta(patient);
}

String patientMeta(Map<String, dynamic> p) {
  final age = '${p['age'] ?? ''}'.trim();
  final gender = '${p['gender'] ?? ''}'.trim();
  return [
    if (age.isNotEmpty && age != 'null') '$age yrs',
    if (gender.isNotEmpty && gender != 'null')
      '${gender[0].toUpperCase()}${gender.substring(1)}',
  ].join(' · ');
}

/// Visit stats for one patient's appointments.
({int visits, DateTime? last, DateTime? next, DateTime? seen}) visitStats(
  Iterable<Map<String, dynamic>> appointments,
) {
  final now = DateTime.now();
  var visits = 0;
  DateTime? last, next, seen;
  for (final a in appointments) {
    final start = apptStart(a);
    final status = apptStatus(a);
    if (start != null && (seen == null || start.isAfter(seen))) seen = start;
    if (!_visitStatuses.contains(status) || start == null) continue;
    visits++;
    if (start.isAfter(now) && status != 'completed') {
      if (next == null || start.isBefore(next)) next = start;
    } else if (!start.isAfter(now)) {
      if (last == null || start.isAfter(last)) last = start;
    }
  }
  return (visits: visits, last: last, next: next, seen: seen);
}

/// Groups appointments (with `patientId` populated) by patient.
List<PatientSummary> groupPatients(List<Map<String, dynamic>> appointments) {
  final byId = <String, List<Map<String, dynamic>>>{};
  final info = <String, Map<String, dynamic>>{};
  for (final a in appointments) {
    final p = apptPatient(a);
    final id = '${p['_id'] ?? ''}';
    if (id.isEmpty) continue;
    byId.putIfAbsent(id, () => []).add(a);
    // Keep the copy with the most fields filled in.
    final known = info[id];
    if (known == null || p.length > known.length) info[id] = p;
  }
  return [
    for (final e in byId.entries)
      () {
        final s = visitStats(e.value);
        return PatientSummary(
          id: e.key,
          patient: info[e.key] ?? const {},
          visits: s.visits,
          lastVisit: s.last,
          nextVisit: s.next,
          lastSeen: s.seen,
        );
      }(),
  ];
}

/// "12 Oct", or "12 Oct 2025" outside this year.
String shortDate(DateTime? d) {
  if (d == null) return '—';
  return DateFormat(
    d.year == DateTime.now().year ? 'd MMM' : 'd MMM yyyy',
  ).format(d);
}

/// One row of the patients list.
class PatientRow extends StatelessWidget {
  final PatientSummary summary;
  final VoidCallback? onTap;
  const PatientRow({super.key, required this.summary, this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context).color;
    final s = summary;
    final sub = [
      if (s.meta.isNotEmpty) s.meta else if (s.phone.isNotEmpty) s.phone,
      s.lastVisit != null
          ? 'Last visit ${shortDate(s.lastVisit)}'
          : (s.nextVisit != null ? 'First visit soon' : 'No visits yet'),
    ].join('  ·  ');
    return AppPressable(
      scale: 0.985,
      onTap: onTap,
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            DoctorAvatar(name: s.name, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.sans(
                      fontSize: AppType.title,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textStrong,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (s.nextVisit != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          LucideIcons.calendarClock,
                          size: 12,
                          color: accent,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Next: ${dayLabel(s.nextVisit)} ${DateFormat('HH:mm').format(s.nextVisit!)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.sans(
                              fontSize: AppType.caption,
                              fontWeight: FontWeight.w600,
                              color: accent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${s.visits}',
                  style: AppType.number(
                    fontSize: AppType.title,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textStrong,
                  ),
                ),
                Text(
                  s.visits == 1 ? 'visit' : 'visits',
                  style: AppType.sans(
                    fontSize: AppType.micro,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 6),
            const Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
