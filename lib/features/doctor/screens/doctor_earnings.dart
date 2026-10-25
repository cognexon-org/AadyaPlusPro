import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../providers/doctor_earnings_provider.dart';
import '../widgets/doctor_ui.dart';
import '../widgets/earnings_widgets.dart';

/// Earnings in the module's minimal style: this month's figure with the
/// last six months under it, four quiet tiles, then every consultation's
/// earning grouped by day.
class DoctorEarnings extends ConsumerStatefulWidget {
  /// What one booking is called — "session" for a physiotherapist.
  final String noun;

  const DoctorEarnings({super.key, this.noun = 'consultation'});

  @override
  ConsumerState<DoctorEarnings> createState() => _DoctorEarningsState();
}

class _DoctorEarningsState extends ConsumerState<DoctorEarnings> {
  static const _recentLimit = 40;

  String get _noun => widget.noun;
  String get _plural => '${widget.noun}s';

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(doctorEarningsProvider.notifier).load();
    });
  }

  Future<void> _refresh() => ref.read(doctorEarningsProvider.notifier).load();

  void _open(DoctorEarningsState s, Map<String, dynamic> row) {
    Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => TransactionDetailsScreen(
          transaction: row,
          commissionRate: s.commissionRate?.toDouble(),
          appointment: s.appointmentOf(row),
          noun: _noun,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(doctorEarningsProvider);
    final accent = ModuleAccent.of(context).color;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: accent,
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              AppScreenHeader(
                title: 'Earnings',
                subtitle: '${capitalised(_plural)} and payouts',
              ),
              const SizedBox(height: 20),
              ..._body(s),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(DoctorEarningsState s) {
    if (!s.hasLoaded) {
      if (s.error != null) {
        return [AppErrorBanner(message: s.error!, onRetry: _refresh)];
      }
      return const [AppDetailSkeleton(rows: 7)];
    }
    final rate = s.commissionRate;
    return [
      if (s.error != null) ...[
        AppErrorBanner(message: s.error!, onRetry: _refresh),
        const SizedBox(height: 12),
      ],
      AppEntrance(child: _hero(s)),
      const SizedBox(height: 12),
      AppEntrance(index: 1, child: _tiles(s)),
      const SizedBox(height: 12),
      Text(
        [
          rate == null
              ? 'Aadya Plus keeps a platform fee on each $_noun; the rest is paid out to you.'
              : 'Aadya Plus keeps ${formatRate(rate)} of each $_noun fee; the rest is paid out to you.',
          if (s.excluded > 0)
            '${s.excluded} cancelled or declined ${s.excluded == 1 ? 'booking is' : 'bookings are'} left out.',
        ].join(' '),
        style: AppType.sans(
          fontSize: AppType.caption,
          color: AppColors.textTertiary,
          height: 1.45,
        ),
      ),
      const SizedBox(height: 26),
      AppEntrance(index: 2, child: _recent(s)),
    ];
  }

  // ─────────────────────────── Hero ───────────────────────────

  Widget _hero(DoctorEarningsState s) {
    final accent = ModuleAccent.of(context).color;
    final months = s.lastSixMonths;
    final now = months.last.earned;
    final prev = months[4].earned;
    final prevName = DateFormat('MMMM').format(months[4].month);
    final String delta;
    IconData? icon;
    var deltaColor = AppColors.textSecondary;
    if (prev <= 0) {
      delta = now > 0 ? 'Nothing in $prevName' : 'No $_plural yet';
    } else {
      final pct = ((now - prev) / prev * 100).round();
      if (pct == 0) {
        delta = 'Same as $prevName';
      } else {
        delta = '${pct.abs()}% ${pct > 0 ? 'more' : 'less'} than $prevName';
        icon = pct > 0 ? LucideIcons.trendingUp : LucideIcons.trendingDown;
        if (pct > 0) deltaColor = accent;
      }
    }
    final maxV = months.fold<num>(0, (a, m) => math.max(a, m.earned));

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This month',
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
            child: AppCountUp(
              value: now,
              format: appRupees,
              style: AppType.number(
                fontSize: AppType.display,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.2,
                height: 1.05,
                color: AppColors.textStrong,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: deltaColor),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  delta,
                  style: AppType.sans(
                    fontSize: AppType.caption,
                    fontWeight: FontWeight.w600,
                    color: deltaColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 128,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < months.length; i++)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          months[i].earned > 0
                              ? compactRupees(months[i].earned)
                              : '',
                          maxLines: 1,
                          style: AppType.sans(
                            fontSize: AppType.micro,
                            fontWeight: i == 5
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: i == 5
                                ? AppColors.textStrong
                                : AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        AppGrowBar(
                          fraction: maxV > 0
                              ? (months[i].earned / maxV).toDouble()
                              : 0,
                          maxHeight: 76,
                          width: 22,
                          index: i,
                          color: i == 5
                              ? accent
                              : accent.withValues(alpha: 0.28),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          DateFormat('MMM').format(months[i].month),
                          style: AppType.sans(
                            fontSize: AppType.caption,
                            fontWeight: i == 5
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: i == 5
                                ? AppColors.textStrong
                                : AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── Tiles ───────────────────────────

  Widget _tiles(DoctorEarningsState s) {
    final rate = s.commissionRate;
    final n = s.consultationsThisMonth;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: EarningsTile(
                label: 'Pending settlement',
                value: appRupees(s.pending),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: EarningsTile(
                label: 'Settled',
                value: appRupees(s.settled),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: EarningsTile(
                label: _noun == 'consultation'
                    ? 'Visits this month'
                    : '${capitalised(_plural)} this month',
                value: '$n',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: EarningsTile(
                label: 'Platform fee rate',
                value: rate == null ? '—' : formatRate(rate),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─────────────────────────── Recent ───────────────────────────

  Widget _recent(DoctorEarningsState s) {
    final rows = s.rows.take(_recentLimit).toList();
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final d = DoctorEarningsState.createdAt(r);
      groups.putIfAbsent(dayLabel(d), () => []).add(r);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionTitle('Recent $_plural'),
        if (rows.isEmpty)
          const AppEmptyState(
            icon: LucideIcons.wallet,
            text: 'Earnings appear here after your first booking.',
          )
        else
          for (final g in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 6, 0, 6),
              child: Text(
                g.key,
                style: AppType.sans(
                  fontSize: AppType.caption,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
            AppGroup(
              children: [
                for (var i = 0; i < g.value.length; i++) ...[
                  if (i > 0) const AppHairline(),
                  EarningsRow(
                    row: g.value[i],
                    appointment: s.appointmentOf(g.value[i]),
                    onTap: () => _open(s, g.value[i]),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

// ─────────────────────────── Details ───────────────────────────

/// One consultation's money: what the patient paid, the platform's fee, what
/// the doctor keeps, and whether it has been paid out.
class TransactionDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> transaction;

  /// Platform fee in percent, when the row doesn't state its own.
  final double? commissionRate;

  /// The full appointment, when known (status, time, patient).
  final Map<String, dynamic>? appointment;

  /// What one booking is called — "session" for a physiotherapist.
  final String noun;

  const TransactionDetailsScreen({
    super.key,
    required this.transaction,
    this.commissionRate,
    this.appointment,
    this.noun = 'consultation',
  });

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final appt = <String, dynamic>{
      if (t['appointmentId'] is Map)
        ...Map<String, dynamic>.from(t['appointmentId'] as Map),
      ...?appointment,
    };
    final earning = DoctorEarningsState.earning(t);
    final fee = DoctorEarningsState.fee(t);
    final cut = DoctorEarningsState.commission(t);
    final rate =
        num.tryParse('${t['commissionRate'] ?? ''}') ??
        (fee > 0 ? cut / fee * 100 : commissionRate);
    final settled = DoctorEarningsState.isSettled(t);
    final payoutDate = DateTime.tryParse('${t['payoutDate'] ?? ''}')?.toLocal();
    final booked = DoctorEarningsState.createdAt(t);
    final start = apptStart(appt);
    final hasTime = '${appt['startTime'] ?? ''}'.isNotEmpty;
    final reference = '${t['transactionId'] ?? t['payoutReference'] ?? ''}'
        .trim();
    final status = '${t['payoutStatus'] ?? 'pending'}';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 20, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(
                      LucideIcons.chevronLeft,
                      size: 22,
                      color: AppColors.textPrimary,
                    ),
                    tooltip: 'Back',
                  ),
                  Text(
                    '${capitalised(noun)} earning',
                    style: AppType.sans(
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  AppEntrance(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your earning',
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
                          child: AppCountUp(
                            value: earning,
                            format: appRupees,
                            style: AppType.number(
                              fontSize: AppType.display,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1.2,
                              color: AppColors.textStrong,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        PayoutStatusText(status: status, date: payoutDate),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  AppEntrance(
                    index: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AppSectionTitle('Breakdown'),
                        AppGroup(
                          children: [
                            EarningsDetailRow(
                              '${capitalised(noun)} fee',
                              appRupees(fee),
                            ),
                            const AppHairline(),
                            EarningsDetailRow(
                              rate == null
                                  ? 'Platform fee'
                                  : 'Platform fee (${formatRate(rate)})',
                              '−${appRupees(cut)}',
                            ),
                            const AppHairline(),
                            EarningsDetailRow(
                              'Your earning',
                              appRupees(earning),
                              strong: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'The platform fee is Aadya Plus’s share of the $noun fee; the rest is paid out to you.',
                          style: AppType.sans(
                            fontSize: AppType.caption,
                            color: AppColors.textTertiary,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  AppEntrance(
                    index: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AppSectionTitle('Appointment'),
                        AppGroup(
                          children: [
                            EarningsDetailRow('Patient', _patient(t, appt)),
                            const AppHairline(),
                            EarningsDetailRow(
                              'Date',
                              start == null
                                  ? '—'
                                  : hasTime
                                  ? '${dayLabel(start)}, ${timeLabel(start)}'
                                  : dayLabel(start),
                            ),
                            if (appt['type'] != null) ...[
                              const AppHairline(),
                              EarningsDetailRow(
                                'Type',
                                apptTypeInfo(apptType(appt)).label,
                              ),
                            ],
                            if (appt['status'] != null) ...[
                              const AppHairline(),
                              EarningsDetailRow(
                                'Status',
                                '',
                                trailing: ApptStatusTag(apptStatus(appt)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  AppEntrance(
                    index: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AppSectionTitle('Payout'),
                        AppGroup(
                          children: [
                            EarningsDetailRow('Status', payoutLabel(status)),
                            if (settled && payoutDate != null) ...[
                              const AppHairline(),
                              EarningsDetailRow(
                                'Paid on',
                                DateFormat('d MMM yyyy').format(payoutDate),
                              ),
                            ],
                            if (reference.isNotEmpty) ...[
                              const AppHairline(),
                              EarningsDetailRow('Reference', reference),
                            ],
                            const AppHairline(),
                            EarningsDetailRow(
                              'Booked on',
                              booked == null
                                  ? '—'
                                  : DateFormat('d MMM yyyy').format(booked),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _patient(Map<String, dynamic> t, Map<String, dynamic> appt) {
    for (final p in [appt['patientId'], t['patientId']]) {
      if (p is Map) {
        final n = '${p['name'] ?? ''}'.trim();
        if (n.isNotEmpty) return n;
      }
    }
    return 'Patient';
  }
}
