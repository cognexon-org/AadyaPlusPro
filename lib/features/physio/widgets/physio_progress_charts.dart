import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../providers/physio_care_provider.dart';

/// Pain is a problem signal: 7–10 red, 4–6 amber, 0–3 green (good).
Color painColor(BuildContext context, num? v) {
  if (v == null) return AppColors.textTertiary;
  if (v >= 7) return AppColors.error;
  if (v >= 4) return AppColors.warning;
  return AppColors.success;
}

String _short(DateTime? d) => d == null ? '' : DateFormat('d MMM').format(d);

num? _num(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}');

String _fmt(num? v) {
  if (v == null) return '—';
  return v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
}

/// Change colour: improvement accent, worsening red, flat grey.
// Better is the success green, not the module accent: physio's coral sits
// too close to the red used for "worse".
Color _dirColor(BuildContext context, int dir) => dir > 0
    ? AppColors.success
    : dir < 0
    ? AppColors.error
    : AppColors.textTertiary;

IconData _dirIcon(num change) => change > 0
    ? LucideIcons.trendingUp
    : change < 0
    ? LucideIcons.trendingDown
    : LucideIcons.minus;

/// A small "↘ 2 since 3 Oct" chip. [lowerIsBetter] picks the colour.
class PhysioChangeChip extends StatelessWidget {
  final num change;
  final bool lowerIsBetter;
  final String? suffix;
  final String unit;
  const PhysioChangeChip({
    super.key,
    required this.change,
    required this.lowerIsBetter,
    this.suffix,
    this.unit = '',
  });

  @override
  Widget build(BuildContext context) {
    final dir = change == 0 ? 0 : ((change < 0) == lowerIsBetter ? 1 : -1);
    final color = _dirColor(context, dir);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_dirIcon(change), size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          [
            change == 0
                ? 'No change'
                : '${change > 0 ? '+' : '−'}${_fmt(change.abs())}$unit',
            if (suffix != null) suffix,
          ].join(' '),
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

/// Rest and activity pain (0–10) over the assessments, oldest → newest.
class PhysioPainChart extends StatelessWidget {
  /// `[{date, rest, activity}]`, chronological.
  final List<Map<String, dynamic>> points;
  const PhysioPainChart({super.key, required this.points});

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context).color;
    final n = points.length;
    final dates = [for (final p in points) parseDate(p['date'])];
    final step = math.max(1, (n / 5).ceil());

    List<FlSpot> spots(String key) => [
      for (var i = 0; i < n; i++)
        _num(points[i][key]) == null
            ? FlSpot.nullSpot
            : FlSpot(i.toDouble(), _num(points[i][key])!.toDouble()),
    ];

    LineChartBarData line(String key, Color color, {bool dashed = false}) =>
        LineChartBarData(
          spots: spots(key),
          color: color,
          barWidth: 2,
          isCurved: false,
          dashArray: dashed ? [5, 4] : null,
          dotData: FlDotData(
            show: true,
            getDotPainter: (_, _, _, _) => FlDotCirclePainter(
              radius: 4,
              color: color,
              strokeWidth: 2,
              strokeColor: AppColors.panel,
            ),
          ),
        );

    Widget legend(Color c, String label, {bool dashed = false}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14,
          height: 2,
          child: dashed
              ? Row(
                  children: [
                    Container(width: 5, height: 2, color: c),
                    const SizedBox(width: 4),
                    Container(width: 5, height: 2, color: c),
                  ],
                )
              : ColoredBox(color: c),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppType.sans(
            fontSize: AppType.caption,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              legend(accent, 'With activity'),
              const SizedBox(width: 16),
              legend(AppColors.textSecondary, 'At rest', dashed: true),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 10,
                minX: -0.4,
                maxX: math.max(0, n - 1) + 0.4,
                clipData: const FlClipData.none(),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 5,
                  getDrawingHorizontalLine: (_) =>
                      const FlLine(color: AppColors.bg, strokeWidth: 1.5),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.textStrong,
                    getTooltipItems: (items) => [
                      for (final s in items)
                        LineTooltipItem(
                          '${s.barIndex == 0 ? 'Activity' : 'Rest'} ${_fmt(s.y)}',
                          AppType.sans(
                            fontSize: AppType.caption,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                    ],
                  ),
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
                        '${v.round()}',
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
                        if (v != i || i < 0 || i >= n) {
                          return const SizedBox.shrink();
                        }
                        if (i != n - 1 && i % step != 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _short(dates[i]),
                            style: AppType.sans(
                              fontSize: AppType.micro,
                              fontWeight: i == n - 1
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: i == n - 1
                                  ? AppColors.textPrimary
                                  : AppColors.textTertiary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  line('activity', accent),
                  line('rest', AppColors.textSecondary, dashed: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One outcome measure: latest score, first → latest, improvement.
class PhysioOutcomeCard extends StatelessWidget {
  final String code;

  /// `[{date, score, maxScore, percent}]`, chronological.
  final List<Map<String, dynamic>> series;
  const PhysioOutcomeCard({
    super.key,
    required this.code,
    required this.series,
  });

  @override
  Widget build(BuildContext context) {
    final info = kOutcomeMeasures[code];
    final first = series.isEmpty ? null : series.first;
    final last = series.isEmpty ? null : series.last;
    final f = _num(first?['score']);
    final l = _num(last?['score']);
    final max = _num(last?['maxScore']) ?? info?.maxScore;
    final dir = outcomeDirection(code, f, l);
    final change = (f != null && l != null) ? l - f : null;
    final better = info?.lowerIsBetter == null
        ? null
        : info!.lowerIsBetter!
        ? 'Lower is better'
        : 'Higher is better';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                  code == 'OTHER' ? 'Other' : code,
                  style: AppType.sans(
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textStrong,
                  ),
                ),
                Text(
                  [?info?.label, ?better].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.sans(
                    fontSize: AppType.caption,
                    color: AppColors.textTertiary,
                  ),
                ),
                if (series.length > 1) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        '${_fmt(f)} → ${_fmt(l)}',
                        style: AppType.number(
                          fontSize: AppType.small,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (change != null)
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                dir > 0
                                    ? LucideIcons.circleCheck
                                    : dir < 0
                                    ? LucideIcons.circleAlert
                                    : _dirIcon(change),
                                size: 13,
                                color: _dirColor(context, dir),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  dir > 0
                                      ? 'Improved ${_fmt(change.abs())}'
                                      : dir < 0
                                      ? 'Worse by ${_fmt(change.abs())}'
                                      : change == 0
                                      ? 'No change'
                                      : '${change > 0 ? '+' : '−'}${_fmt(change.abs())}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppType.sans(
                                    fontSize: AppType.caption,
                                    fontWeight: FontWeight.w600,
                                    color: _dirColor(context, dir),
                                  ),
                                ),
                              ),
                            ],
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
                _fmt(l),
                style: AppType.number(
                  fontSize: AppType.figure,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textStrong,
                ),
              ),
              Text(
                max == null
                    ? _short(parseDate(last?['date']))
                    : 'of ${_fmt(max)}',
                style: AppType.sans(
                  fontSize: AppType.micro,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Range of motion, first → latest active degrees per joint movement.
class PhysioRomTable extends StatelessWidget {
  /// `{"joint|movement|side": [{date, activeDeg}]}`.
  final Map<String, dynamic> rom;
  const PhysioRomTable({super.key, required this.rom});

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String, num?, num?, int)>[];
    for (final e in rom.entries) {
      final parts = e.key.split('|');
      final joint = parts.isNotEmpty ? parts[0] : '';
      final movement = parts.length > 1 ? parts[1] : '';
      final side = parts.length > 2 ? sideLabel(parts[2]) : '';
      final series = (e.value is List ? e.value as List : const [])
          .whereType<Map>()
          .toList();
      if (series.isEmpty) continue;
      rows.add((
        [
          _cap(joint),
          movement.toLowerCase(),
        ].where((s) => s.isNotEmpty).join(' '),
        side,
        _num(series.first['activeDeg']),
        _num(series.last['activeDeg']),
        series.length,
      ));
    }
    rows.sort((a, b) => a.$1.compareTo(b.$1));

    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Row(
              children: [
                Expanded(child: _head('Movement')),
                SizedBox(width: 60, child: _head('First', end: true)),
                SizedBox(width: 60, child: _head('Latest', end: true)),
                SizedBox(width: 56, child: _head('Change', end: true)),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++) ...[
            const AppHairline(),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: rows[i].$1,
                        children: [
                          if (rows[i].$2.isNotEmpty)
                            TextSpan(
                              text: '  ${rows[i].$2}',
                              style: AppType.sans(
                                fontSize: AppType.caption,
                                color: AppColors.textTertiary,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.sans(
                        fontSize: AppType.small,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text(
                      rows[i].$5 > 1 ? '${_fmt(rows[i].$3)}°' : '—',
                      textAlign: TextAlign.end,
                      style: AppType.number(
                        fontSize: AppType.small,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text(
                      '${_fmt(rows[i].$4)}°',
                      textAlign: TextAlign.end,
                      style: AppType.number(
                        fontSize: AppType.small,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textStrong,
                      ),
                    ),
                  ),
                  SizedBox(width: 56, child: _change(context, rows[i])),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// More range is better.
  Widget _change(BuildContext context, (String, String, num?, num?, int) r) {
    if (r.$5 < 2 || r.$3 == null || r.$4 == null) {
      return const SizedBox.shrink();
    }
    final c = r.$4! - r.$3!;
    final color = _dirColor(context, c.sign.toInt());
    return Text(
      c == 0 ? '0°' : '${c > 0 ? '+' : '−'}${_fmt(c.abs())}°',
      textAlign: TextAlign.end,
      style: AppType.number(
        fontSize: AppType.small,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    );
  }

  static String _cap(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  Widget _head(String t, {bool end = false}) => Text(
    t,
    textAlign: end ? TextAlign.end : TextAlign.start,
    style: AppType.sans(
      fontSize: AppType.micro,
      fontWeight: FontWeight.w600,
      color: AppColors.textTertiary,
    ),
  );
}
