import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/doctor_ui.dart';
import '../providers/physio_care_provider.dart';
import 'physio_course_sheet.dart';

String _date(DateTime d) => DateFormat(
  d.year == DateTime.now().year ? 'd MMM' : 'd MMM yyyy',
).format(d);

/// Asks for the method, then marks [course] paid. Errors show as a toast.
Future<void> markCoursePaid(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> course,
) async {
  final method = await showPaymentMethodSheet(context);
  if (method == null || !context.mounted) return;
  try {
    await ref.read(physioCoursesProvider.notifier).update('${course['_id']}', {
      'paymentStatus': 'paid',
      'paymentMethod': method,
    });
  } catch (e) {
    if (context.mounted) {
      showAppError(
        context,
        null,
        fallback: doctorError(e, fallback: 'Couldn’t update the payment.'),
      );
    }
  }
}

/// Completes or cancels [course] after a confirmation.
Future<void> setCourseStatus(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> course,
  String status,
) async {
  final cancel = status == 'cancelled';
  final left = courseLeft(course);
  final ok = await AppModal.confirm(
    context,
    title: cancel ? 'Cancel this course?' : 'Complete this course?',
    message: cancel
        ? 'A cancelled course can’t be reopened. Sessions already counted stay on record.'
        : left > 0
        ? '$left ${left == 1 ? 'session is' : 'sessions are'} still unused. '
              'Completing closes the course for new sessions.'
        : 'Closes the course for new sessions.',
    icon: cancel ? LucideIcons.circleX : LucideIcons.circleCheck,
    confirmLabel: cancel ? 'Cancel course' : 'Complete',
    cancelLabel: 'Back',
    destructive: cancel,
  );
  if (!ok || !context.mounted) return;
  try {
    await ref.read(physioCoursesProvider.notifier).update('${course['_id']}', {
      'status': status,
    });
  } catch (e) {
    if (context.mounted) {
      showAppError(
        context,
        null,
        fallback: doctorError(e, fallback: 'Couldn’t update the course.'),
      );
    }
  }
}

/// Sessions used of total, as a thin animated bar.
class PhysioCourseBar extends StatelessWidget {
  final int used;
  final int total;
  final double height;
  const PhysioCourseBar({
    super.key,
    required this.used,
    required this.total,
    this.height = 6,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context).color;
    final f = total <= 0 ? 0.0 : (used / total).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Container(
        height: height,
        color: AppColors.bg,
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: f),
          duration: AppMotion.slow,
          curve: AppMotion.enter,
          builder: (_, v, _) => FractionallySizedBox(
            widthFactor: v,
            heightFactor: 1,
            child: Container(color: accent),
          ),
        ),
      ),
    );
  }
}

/// The patient's treatment course: progress, expiry, payment and actions.
class PhysioCourseCard extends ConsumerWidget {
  final Map<String, dynamic> course;
  const PhysioCourseCard({super.key, required this.course});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ModuleAccent.of(context).color;
    final c = course;
    final used = courseUsed(c);
    final total = courseTotal(c);
    final status = courseStatus(c);
    final active = status == 'active';
    final paid = coursePayment(c) == 'paid';
    final refunded = coursePayment(c) == 'refunded';
    final expires = courseExpires(c);
    final daysLeft = expires == null
        ? null
        : DateTime(
            expires.year,
            expires.month,
            expires.day,
          ).difference(DateUtils.dateOnly(DateTime.now())).inDays;
    final expiringSoon = active && daysLeft != null && daysLeft <= 7;
    final method = '${c['paymentMethod'] ?? ''}';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  courseTitle(c),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.sans(
                    fontSize: AppType.title,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textStrong,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                courseStatusLabel(status),
                style: AppType.sans(
                  fontSize: AppType.caption,
                  fontWeight: FontWeight.w600,
                  color: active
                      ? accent
                      : status == 'expired'
                      ? AppColors.warning
                      : AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$used',
                style: AppType.number(
                  fontSize: AppType.display,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textStrong,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 4),
                child: Text(
                  'of $total sessions',
                  style: AppType.sans(
                    fontSize: AppType.small,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${courseLeft(c)} left',
                  style: AppType.sans(
                    fontSize: AppType.small,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          PhysioCourseBar(used: used, total: total),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _Meta(
                icon: LucideIcons.wallet,
                text: refunded
                    ? '${appRupees(c['price'] ?? 0)} · Refunded'
                    : paid
                    ? '${appRupees(c['price'] ?? 0)} · Paid${method.isEmpty ? '' : ' (${paymentMethodLabel(method)})'}'
                    : '${appRupees(c['price'] ?? 0)} · Payment pending',
                color: paid || refunded ? null : AppColors.warning,
              ),
              if (expires != null)
                _Meta(
                  icon: LucideIcons.calendarClock,
                  text: !active
                      ? 'Valid till ${_date(expires)}'
                      : daysLeft! < 0
                      ? 'Expired ${_date(expires)}'
                      : daysLeft == 0
                      ? 'Expires today'
                      : 'Expires ${_date(expires)}',
                  color: expiringSoon ? AppColors.warning : null,
                ),
            ],
          ),
          if (active) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (!paid && !refunded) ...[
                  Expanded(
                    child: AppButton(
                      label: 'Mark paid',
                      compact: true,
                      onPressed: () => markCoursePaid(context, ref, c),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: _SmallButton(
                    label: 'Complete',
                    onTap: () => setCourseStatus(context, ref, c, 'completed'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SmallButton(
                    label: 'Cancel',
                    color: AppColors.error,
                    onTap: () => setCourseStatus(context, ref, c, 'cancelled'),
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
      const SizedBox(width: 5),
      Text(
        text,
        style: AppType.sans(
          fontSize: AppType.caption,
          fontWeight: color == null ? FontWeight.w500 : FontWeight.w600,
          color: color ?? AppColors.textSecondary,
        ),
      ),
    ],
  );
}

/// A white pill button for the grey card (the kit's secondary button is
/// grey, which would vanish on a panel).
class _SmallButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _SmallButton({required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) => AppPressable(
    scale: 0.96,
    onTap: onTap,
    child: Container(
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: AppType.sans(
          fontSize: AppType.body,
          fontWeight: FontWeight.w600,
          color: color ?? AppColors.textPrimary,
        ),
      ),
    ),
  );
}

/// A past (closed) course as a one-line row.
class PhysioPastCourseRow extends StatelessWidget {
  final Map<String, dynamic> course;
  const PhysioPastCourseRow({super.key, required this.course});

  @override
  Widget build(BuildContext context) {
    final c = course;
    final created = parseDate(c['startDate'] ?? c['createdAt']);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  courseTitle(c),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.sans(
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  [
                    '${courseUsed(c)} of ${courseTotal(c)} sessions',
                    if (created != null) 'started ${_date(created)}',
                  ].join(' · '),
                  style: AppType.sans(
                    fontSize: AppType.caption,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            courseStatusLabel(courseStatus(c)),
            style: AppType.sans(
              fontSize: AppType.caption,
              fontWeight: FontWeight.w600,
              color: courseStatus(c) == 'expired'
                  ? AppColors.warning
                  : AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
