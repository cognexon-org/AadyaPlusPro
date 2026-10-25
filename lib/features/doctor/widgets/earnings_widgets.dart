import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/ui/app_ui.dart';
import '../providers/doctor_earnings_provider.dart';
import 'doctor_ui.dart';

/// "20%" or "17.5%".
String formatRate(num rate) =>
    '${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 1)}%';

/// "₹850", "₹4.2k", "₹1.3L" — for chart labels.
String compactRupees(num v) {
  if (v >= 100000) return '₹${_trim(v / 100000)}L';
  if (v >= 1000) return '₹${_trim(v / 1000)}k';
  return '₹${v.round()}';
}

String _trim(num v) => v >= 10 ? '${v.round()}' : v.toStringAsFixed(1);

String payoutLabel(String status) => switch (status) {
  'paid' => 'Paid out',
  'processing' => 'Payout in progress',
  'failed' => 'Payout failed',
  'cancelled' => 'Cancelled',
  _ => 'Awaiting payout',
};

/// Payout state as one coloured line; amber while waiting, red on failure.
class PayoutStatusText extends StatelessWidget {
  final String status;
  final DateTime? date;
  const PayoutStatusText({super.key, required this.status, this.date});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'paid' => AppColors.textSecondary,
      'failed' || 'cancelled' => AppColors.error,
      _ => AppColors.warning,
    };
    final text = status == 'paid' && date != null
        ? 'Paid out ${DateFormat('d MMM').format(date!)}'
        : payoutLabel(status);
    return Text(
      text,
      style: AppType.sans(
        fontSize: AppType.caption,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
  }
}

/// A small grey tile: label over a figure.
class EarningsTile extends StatelessWidget {
  final String label;
  final String value;
  const EarningsTile({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.sans(
            fontSize: AppType.caption,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: AppType.number(
              fontSize: AppType.heading,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: AppColors.textStrong,
            ),
          ),
        ),
      ],
    ),
  );
}

/// One consultation's earning in the recent list.
class EarningsRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final Map<String, dynamic> appointment;
  final VoidCallback? onTap;
  const EarningsRow({
    super.key,
    required this.row,
    required this.appointment,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    var name = '';
    for (final p in [appointment['patientId'], row['patientId']]) {
      if (p is Map && '${p['name'] ?? ''}'.trim().isNotEmpty) {
        name = '${p['name']}'.trim();
        break;
      }
    }
    if (name.isEmpty) name = 'Patient';
    final start = apptStart(appointment);
    final hasTime = '${appointment['startTime'] ?? ''}'.isNotEmpty;
    final sub = [
      if (appointment['type'] != null)
        apptTypeInfo(apptType(appointment)).label,
      if (start != null)
        hasTime ? '${dayLabel(start)}, ${timeLabel(start)}' : dayLabel(start),
    ].join(' · ');
    final status = '${row['payoutStatus'] ?? 'pending'}';

    return AppPressable(
      scale: 0.985,
      onTap: onTap,
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.sans(
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
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
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  appRupees(DoctorEarningsState.earning(row)),
                  style: AppType.number(
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textStrong,
                  ),
                ),
                const SizedBox(height: 2),
                PayoutStatusText(status: status),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Label on the left, value on the right, inside an [AppGroup].
class EarningsDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;
  final Widget? trailing;
  const EarningsDetailRow(
    this.label,
    this.value, {
    super.key,
    this.strong = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    child: Row(
      children: [
        Text(
          label,
          style: AppType.sans(
            fontSize: AppType.body,
            fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child:
                trailing ??
                Text(
                  value,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.number(
                    fontSize: AppType.body,
                    fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
                    color: strong
                        ? AppColors.textStrong
                        : AppColors.textSecondary,
                  ),
                ),
          ),
        ),
      ],
    ),
  );
}
