import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';

// ─────────────────────────── Appointment fields ───────────────────────────
//
// One place that knows the appointment's shape, so screens never parse
// dates or guess field names themselves. `appointmentDate` is the day (UTC
// midnight from the server); `startTime`/`endTime` are "HH:mm" local times.

String apptStatus(Map<String, dynamic> a) {
  final s = '${a['status'] ?? 'pending'}';
  return s == 'accepted' ? 'confirmed' : s;
}

String apptType(Map<String, dynamic> a) => '${a['type'] ?? 'clinic'}';

Map<String, dynamic> apptPatient(Map<String, dynamic> a) {
  final p = a['patientId'];
  return p is Map ? Map<String, dynamic>.from(p) : const {};
}

String patientName(Map<String, dynamic> a) {
  final n = '${apptPatient(a)['name'] ?? ''}'.trim();
  return n.isEmpty ? 'Patient' : n;
}

DateTime? _day(Map<String, dynamic> a) {
  final d = DateTime.tryParse('${a['appointmentDate'] ?? ''}');
  if (d == null) return null;
  // The server saves the booked day as *its own* local midnight
  // (`setHours(0,0,0,0)`), i.e. 00:00 UTC on a UTC host but 18:30 UTC the
  // previous day on an IST host. Shifting by 14h before taking the UTC date
  // lands on the intended day for any host zone from UTC to UTC+14, so the
  // app doesn't depend on how the server is configured.
  final u = (d.isUtc ? d : d.toUtc()).add(const Duration(hours: 14));
  return DateTime(u.year, u.month, u.day);
}

DateTime? _at(Map<String, dynamic> a, String key) {
  final day = _day(a);
  if (day == null) return null;
  final parts = '${a[key] ?? ''}'.split(':');
  final h = int.tryParse(parts.isNotEmpty ? parts[0] : '');
  final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
  return h == null ? day : DateTime(day.year, day.month, day.day, h, m);
}

DateTime? apptStart(Map<String, dynamic> a) => _at(a, 'startTime');
DateTime? apptEnd(Map<String, dynamic> a) => _at(a, 'endTime');

num apptFee(Map<String, dynamic> a) =>
    num.tryParse('${a['totalAmount'] ?? a['consultationFee'] ?? 0}') ?? 0;

bool apptPaid(Map<String, dynamic> a) => '${a['paymentStatus']}' == 'paid';

/// "Female" from "female"; empty stays empty.
String capitalised(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String timeLabel(DateTime? d) =>
    d == null ? '—' : DateFormat('h:mm a').format(d);

/// "Today", "Tomorrow", "Mon 3 Nov".
String dayLabel(DateTime? d) {
  if (d == null) return '—';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  return DateFormat(
    day.year == now.year ? 'EEE d MMM' : 'd MMM yy',
  ).format(day);
}

String apptStatusLabel(String s) => switch (s) {
  'pending' => 'Request',
  'confirmed' => 'Confirmed',
  'in_progress' => 'In consultation',
  'completed' => 'Completed',
  'cancelled' => 'Cancelled',
  'rejected' => 'Declined',
  'no_show' => 'No-show',
  'rescheduled' => 'Rescheduled',
  _ => s,
};

({IconData icon, String label}) apptTypeInfo(String type) => switch (type) {
  'video' => (icon: LucideIcons.video, label: 'Video'),
  'home' => (icon: LucideIcons.house, label: 'Home visit'),
  _ => (icon: LucideIcons.building2, label: 'Clinic'),
};

String doctorErrorMessage(DioException e) {
  final d = e.response?.data;
  if (d is Map) {
    final m = d['error'] ?? d['message'];
    if (m != null && '$m'.trim().isNotEmpty) return '$m';
  }
  if (e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout) {
    return 'You’re offline. Check your connection.';
  }
  return 'Something went wrong. Please try again.';
}

String doctorError(Object e, {String fallback = 'Something went wrong.'}) =>
    e is DioException ? doctorErrorMessage(e) : fallback;

// ─────────────────────────── Widgets ───────────────────────────

/// Initials in a tinted circle. Never indexes an empty string.
class DoctorAvatar extends StatelessWidget {
  final String name;
  final double size;
  const DoctorAvatar({super.key, required this.name, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final initials = words.isEmpty
        ? '?'
        : words.take(2).map((w) => w[0].toUpperCase()).join();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: accent.light, shape: BoxShape.circle),
      child: Text(
        initials,
        style: AppType.sans(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
          color: accent.color,
        ),
      ),
    );
  }
}

/// Status as coloured text with a dot — the minimal style keeps fills for
/// actions. Problems are red/amber; everything else is ink or accent.
class ApptStatusTag extends StatelessWidget {
  final String status;
  const ApptStatusTag(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context).color;
    final color = switch (status) {
      'pending' => AppColors.warning,
      'in_progress' => accent,
      'confirmed' => accent,
      'cancelled' || 'rejected' || 'no_show' => AppColors.error,
      _ => AppColors.textTertiary,
    };
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
          apptStatusLabel(status),
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

/// Clinic / Video / Home visit, as a small icon + label.
class ApptTypeTag extends StatelessWidget {
  final String type;
  const ApptTypeTag(this.type, {super.key});

  @override
  Widget build(BuildContext context) {
    final info = apptTypeInfo(type);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(info.icon, size: 13, color: AppColors.textTertiary),
        const SizedBox(width: 4),
        Text(
          info.label,
          style: AppType.sans(
            fontSize: AppType.caption,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// The appointment row used across Today, Appointments, Patients history and
/// the calendar. Time on the left like a diary, patient and details in the
/// middle, optional actions underneath.
class DoctorAppointmentCard extends StatelessWidget {
  final Map<String, dynamic> appointment;
  final VoidCallback? onTap;

  /// Show the day above the time (lists that span days).
  final bool showDay;

  /// Buttons under the card, e.g. Decline / Accept.
  final Widget? actions;

  const DoctorAppointmentCard({
    super.key,
    required this.appointment,
    this.onTap,
    this.showDay = false,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final start = apptStart(a);
    final status = apptStatus(a);
    final patient = apptPatient(a);
    final meta = [
      if (patient['age'] != null) '${patient['age']} yrs',
      if ('${patient['gender'] ?? ''}'.isNotEmpty) _cap('${patient['gender']}'),
    ].join(' · ');
    final symptoms = (a['symptoms'] is List)
        ? (a['symptoms'] as List)
              .map((e) => '$e')
              .where((e) => e.isNotEmpty)
              .join(', ')
        : '';
    final muted = const {'cancelled', 'rejected', 'no_show'}.contains(status);

    return AppPressable(
      scale: 0.985,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 62,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showDay)
                        Text(
                          dayLabel(start),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.sans(
                            fontSize: AppType.micro,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      Text(
                        timeLabel(start),
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
                              patientName(a),
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
                          ApptStatusTag(status),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 10,
                        runSpacing: 2,
                        children: [
                          ApptTypeTag(apptType(a)),
                          if (meta.isNotEmpty)
                            Text(
                              meta,
                              style: AppType.sans(
                                fontSize: AppType.caption,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          Text(
                            '${appRupees(apptFee(a))} · ${apptPaid(a) ? 'Paid' : 'Unpaid'}',
                            style: AppType.sans(
                              fontSize: AppType.caption,
                              color: apptPaid(a)
                                  ? AppColors.textTertiary
                                  : AppColors.warning,
                            ),
                          ),
                        ],
                      ),
                      if (symptoms.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          symptoms,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.sans(
                            fontSize: AppType.small,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (actions != null) ...[const SizedBox(height: 12), actions!],
          ],
        ),
      ),
    );
  }

  static String _cap(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}
