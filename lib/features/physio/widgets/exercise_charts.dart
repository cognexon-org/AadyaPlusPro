import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/ui/app_ui.dart';
import '../providers/physio_exercise_provider.dart';

/// Adherence as a ring with the percentage in the middle. Amber under 50%.
class ExerciseAdherenceRing extends StatelessWidget {
  final int percent;
  final double size;
  const ExerciseAdherenceRing({
    super.key,
    required this.percent,
    this.size = 92,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    final low = percent < 50;
    final color = low ? AppColors.warning : accent.color;
    final reduced = AppMotion.reduced(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: percent.clamp(0, 100) / 100),
      duration: reduced ? Duration.zero : AppMotion.slow,
      curve: AppMotion.enter,
      builder: (_, t, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(fraction: t, color: color, track: AppColors.bg),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(t * 100).round()}%',
                  style: AppType.number(
                    fontSize: AppType.figure,
                    fontWeight: FontWeight.w800,
                    color: low ? AppColors.warning : AppColors.textStrong,
                  ),
                ),
                Text(
                  'adherence',
                  style: AppType.sans(
                    fontSize: AppType.micro,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  final Color color;
  final Color track;
  _RingPainter({
    required this.fraction,
    required this.color,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 9.0;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    if (fraction <= 0) return;
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * fraction, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color;
}

/// Exercises logged on each of the last seven days, against the plan's
/// daily target (dashed line).
class ExerciseWeekBars extends StatelessWidget {
  final List<int> days; // oldest → today, length 7
  final double dailyTarget;
  const ExerciseWeekBars({
    super.key,
    required this.days,
    required this.dailyTarget,
  });

  /// Completed logs per day for the last 7 days, oldest first.
  static List<int> fromLogs(List<Map<String, dynamic>> logs) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = List<int>.filled(7, 0);
    for (final l in logs) {
      if (l['completed'] == false) continue;
      final d = exDate(l['performedAt']);
      if (d == null) continue;
      final diff = today.difference(DateTime(d.year, d.month, d.day)).inDays;
      if (diff >= 0 && diff < 7) out[6 - diff]++;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    final now = DateTime.now();
    final peak = days.fold<int>(0, (m, v) => v > m ? v : m).toDouble();
    final maxY = math.max(math.max(peak, dailyTarget), 3.0) + 1;
    return SizedBox(
      height: 96,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(enabled: false),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              if (dailyTarget > 0)
                HorizontalLine(
                  y: dailyTarget,
                  color: AppColors.textTertiary,
                  strokeWidth: 1,
                  dashArray: [4, 4],
                ),
            ],
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 18,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  final d = now.subtract(Duration(days: 6 - i));
                  return Text(
                    i == 6 ? 'Today' : DateFormat('E').format(d)[0],
                    style: AppType.sans(
                      fontSize: AppType.micro,
                      fontWeight: i == 6 ? FontWeight.w700 : FontWeight.w500,
                      color: i == 6 ? accent.color : AppColors.textTertiary,
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var x = 0; x < 7; x++)
              BarChartGroupData(
                x: x,
                barRods: [
                  BarChartRodData(
                    toY: days[x].toDouble(),
                    width: 16,
                    color: x == 6 ? accent.color : accent.light,
                    borderRadius: BorderRadius.circular(5),
                    backDrawRodData: BackgroundBarChartRodData(
                      show: true,
                      toY: maxY,
                      color: AppColors.bg,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// One day's average pain.
typedef PainPoint = ({DateTime day, double? before, double? after});

/// Pain before and after, averaged per day, oldest first (last 21 days
/// that have any pain score).
List<PainPoint> painTrend(List<Map<String, dynamic>> logs) {
  final byDay = <DateTime, (List<num>, List<num>)>{};
  for (final l in logs) {
    final d = exDate(l['performedAt']);
    if (d == null) continue;
    final b = l['painBefore'];
    final a = l['painAfter'];
    if (b is! num && a is! num) continue;
    final day = DateTime(d.year, d.month, d.day);
    final bucket = byDay.putIfAbsent(day, () => (<num>[], <num>[]));
    if (b is num) bucket.$1.add(b);
    if (a is num) bucket.$2.add(a);
  }
  double? avg(List<num> v) =>
      v.isEmpty ? null : v.fold<num>(0, (s, x) => s + x) / v.length;
  final days = byDay.keys.toList()..sort();
  final recent = days.length > 21 ? days.sublist(days.length - 21) : days;
  return [
    for (final d in recent)
      (day: d, before: avg(byDay[d]!.$1), after: avg(byDay[d]!.$2)),
  ];
}

/// Pain before (grey, dashed) and after (accent) over time, 0–10.
class ExercisePainChart extends StatelessWidget {
  final List<PainPoint> points;
  const ExercisePainChart({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    LineChartBarData line(
      double? Function(PainPoint p) pick,
      Color color, {
      bool dashed = false,
    }) => LineChartBarData(
      spots: [
        for (final (i, p) in points.indexed)
          if (pick(p) != null) FlSpot(i.toDouble(), pick(p)!),
      ],
      isCurved: true,
      preventCurveOverShooting: true,
      curveSmoothness: 0.25,
      color: color,
      barWidth: dashed ? 1.5 : 2.5,
      dashArray: dashed ? [4, 4] : null,
      dotData: FlDotData(
        show: true,
        getDotPainter: (_, _, _, _) => FlDotCirclePainter(
          radius: dashed ? 2 : 3,
          color: dashed ? AppColors.bg : color,
          strokeWidth: dashed ? 1.5 : 0,
          strokeColor: color,
        ),
      ),
    );
    final last = points.length - 1;
    return Container(
      height: 150,
      padding: const EdgeInsets.only(right: 14),
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 10,
          minX: 0,
          maxX: math.max(1, last).toDouble(),
          lineTouchData: const LineTouchData(enabled: false),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 5,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: AppColors.borderStrong, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: 5,
                getTitlesWidget: (v, _) => Text(
                  v.toInt().toString(),
                  style: AppType.sans(
                    fontSize: AppType.micro,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                interval: 1,
                getTitlesWidget: (v, meta) {
                  final i = v.round();
                  if (v != i.toDouble() || i < 0 || i > last) {
                    return const SizedBox.shrink();
                  }
                  final show =
                      i == 0 || i == last || (last > 4 && i == last ~/ 2);
                  if (!show) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      DateFormat('d MMM').format(points[i].day),
                      style: AppType.sans(
                        fontSize: AppType.micro,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            line((p) => p.before, AppColors.textTertiary, dashed: true),
            line((p) => p.after, accent.color),
          ],
        ),
      ),
    );
  }
}

/// A thin horizontal progress bar.
class ExerciseProgressBar extends StatelessWidget {
  final double fraction;
  final Color color;
  const ExerciseProgressBar({
    super.key,
    required this.fraction,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(3),
    child: SizedBox(
      height: 5,
      child: Stack(
        children: [
          Container(color: AppColors.borderStrong),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction.clamp(0, 1)),
            duration: AppMotion.reduced(context)
                ? Duration.zero
                : AppMotion.slow,
            curve: AppMotion.enter,
            builder: (_, t, _) => FractionallySizedBox(
              widthFactor: t,
              child: Container(color: color),
            ),
          ),
        ],
      ),
    ),
  );
}
