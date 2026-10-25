import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/doctor_ui.dart';
import '../providers/physio_care_provider.dart';
import '../widgets/physio_progress_charts.dart';
import 'physio_assessment_editor.dart';

String _n(dynamic v) {
  final n = v is num ? v : num.tryParse('${v ?? ''}');
  if (n == null) return '—';
  return n == n.roundToDouble() ? '${n.round()}' : n.toStringAsFixed(1);
}

/// One assessment, read-only and grouped, with Edit.
class PhysioAssessmentDetail extends ConsumerWidget {
  final String assessmentId;
  final String patientId;
  final String patientName;

  /// What the list already had; shown while the fresh copy loads.
  final Map<String, dynamic>? assessment;

  const PhysioAssessmentDetail({
    super.key,
    required this.assessmentId,
    required this.patientId,
    required this.patientName,
    this.assessment,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ModuleAccent.of(context).color;
    final async = ref.watch(physioAssessmentProvider(assessmentId));
    final a = async.valueOrNull ?? assessment;

    Future<void> edit() async {
      if (a == null) return;
      await Navigator.of(context).push<bool>(
        AppPageRoute(
          builder: (_) => PhysioAssessmentEditor(
            patientId: patientId,
            patientName: patientName,
            assessment: a,
          ),
        ),
      );
    }

    final error = async.hasError
        ? doctorError(async.error!, fallback: 'Couldn’t load the assessment.')
        : null;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
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
                  Expanded(
                    child: Text(
                      'Assessment',
                      style: AppType.sans(
                        fontSize: AppType.body,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  if (a != null)
                    TextButton.icon(
                      onPressed: edit,
                      icon: Icon(LucideIcons.pencil, size: 15, color: accent),
                      label: Text(
                        'Edit',
                        style: AppType.sans(
                          fontSize: AppType.body,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: accent,
                onRefresh: () => ref
                    .refresh(physioAssessmentProvider(assessmentId).future)
                    .then<void>((_) {}, onError: (_) {}),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  children: [
                    if (error != null) ...[
                      AppErrorBanner(
                        message: error,
                        onRetry: () => ref.invalidate(
                          physioAssessmentProvider(assessmentId),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (a == null && error == null)
                      const AppDetailSkeleton(rows: 6)
                    else if (a != null)
                      ..._body(context, a),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, Map<String, dynamic> a) {
    final date = parseDate(a['assessedAt'] ?? a['createdAt']);
    List<Map> list(String k) =>
        (a[k] is List ? a[k] as List : const []).whereType<Map>().toList();
    final rom = list('rom');
    final strength = list('strength');
    final outcomes = list('outcomeMeasures');
    final tests = list('specialTests');
    final pain = a['painScore'] is Map ? a['painScore'] as Map : const {};
    final complaint = '${a['chiefComplaint'] ?? ''}'.trim();
    final functional = '${a['functionalNotes'] ?? ''}'.trim();
    final plan = '${a['plan'] ?? ''}'.trim();

    Widget text(String t) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        t,
        style: AppType.sans(
          fontSize: AppType.body,
          color: AppColors.textPrimary,
          height: 1.45,
        ),
      ),
    );

    return [
      Text(
        '${assessmentTypeLabel('${a['type'] ?? ''}')} assessment',
        style: AppType.sans(
          fontSize: AppType.heading,
          fontWeight: FontWeight.w700,
          color: AppColors.textStrong,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        [
          patientName,
          if (date != null) DateFormat('d MMM yyyy, h:mm a').format(date),
        ].join('  ·  '),
        style: AppType.sans(
          fontSize: AppType.small,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 20),
      if (complaint.isNotEmpty) ...[
        const AppSectionTitle('Chief complaint'),
        text(complaint),
        const SizedBox(height: 20),
      ],
      if (pain['rest'] is num || pain['activity'] is num) ...[
        const AppSectionTitle('Pain'),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(14),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                for (final (k, l) in const [
                  ('rest', 'At rest'),
                  ('activity', 'With activity'),
                ]) ...[
                  if (k == 'activity') Container(width: 1, color: AppColors.bg),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          pain[k] is num ? '${(pain[k] as num).round()}' : '—',
                          style: AppType.number(
                            fontSize: AppType.figure,
                            fontWeight: FontWeight.w700,
                            color: painColor(context, pain[k] as num?),
                          ),
                        ),
                        Text(
                          '$l /10',
                          style: AppType.sans(
                            fontSize: AppType.caption,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
      if (rom.isNotEmpty) ...[
        const AppSectionTitle('Range of motion'),
        AppGroup(
          children: [
            for (var i = 0; i < rom.length; i++) ...[
              if (i > 0) const AppHairline(),
              _Line(
                title: [
                  capitalised('${rom[i]['joint'] ?? ''}'.trim()),
                  '${rom[i]['movement'] ?? ''}'.trim().toLowerCase(),
                ].where((s) => s.isNotEmpty).join(' '),
                sub: sideLabel('${rom[i]['side'] ?? ''}'),
                value: [
                  if (rom[i]['activeDeg'] != null)
                    'A ${_n(rom[i]['activeDeg'])}°',
                  if (rom[i]['passiveDeg'] != null)
                    'P ${_n(rom[i]['passiveDeg'])}°',
                ].join('  '),
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
      ],
      if (strength.isNotEmpty) ...[
        const AppSectionTitle('Strength'),
        AppGroup(
          children: [
            for (var i = 0; i < strength.length; i++) ...[
              if (i > 0) const AppHairline(),
              _Line(
                title: '${strength[i]['muscleGroup'] ?? ''}',
                sub: sideLabel('${strength[i]['side'] ?? ''}'),
                value: '${_n(strength[i]['grade'])}/5',
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
      ],
      if (outcomes.isNotEmpty) ...[
        const AppSectionTitle('Outcome measures'),
        AppGroup(
          children: [
            for (var i = 0; i < outcomes.length; i++) ...[
              if (i > 0) const AppHairline(),
              () {
                final code = '${outcomes[i]['code'] ?? ''}';
                final info = kOutcomeMeasures[code];
                return _Line(
                  title: code == 'OTHER' ? 'Other' : code,
                  sub: info == null || info.lowerIsBetter == null
                      ? ''
                      : '${info.label} · ${info.lowerIsBetter! ? 'lower' : 'higher'} is better',
                  value: outcomes[i]['maxScore'] == null
                      ? _n(outcomes[i]['score'])
                      : '${_n(outcomes[i]['score'])} / ${_n(outcomes[i]['maxScore'])}',
                );
              }(),
            ],
          ],
        ),
        const SizedBox(height: 20),
      ],
      if (tests.isNotEmpty) ...[
        const AppSectionTitle('Special tests'),
        AppGroup(
          children: [
            for (var i = 0; i < tests.length; i++) ...[
              if (i > 0) const AppHairline(),
              _Line(
                title: '${tests[i]['name'] ?? ''}',
                sub: '${tests[i]['notes'] ?? ''}'.trim(),
                value: capitalised('${tests[i]['result'] ?? ''}'),
                valueColor: '${tests[i]['result']}' == 'positive'
                    ? AppColors.warning
                    : null,
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
      ],
      if (functional.isNotEmpty) ...[
        const AppSectionTitle('Functional notes'),
        text(functional),
        const SizedBox(height: 20),
      ],
      if (plan.isNotEmpty) ...[const AppSectionTitle('Plan'), text(plan)],
    ];
  }
}

class _Line extends StatelessWidget {
  final String title;
  final String sub;
  final String value;
  final Color? valueColor;
  const _Line({
    required this.title,
    required this.sub,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.isEmpty ? '—' : title,
                style: AppType.sans(
                  fontSize: AppType.body,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              if (sub.isNotEmpty)
                Text(
                  sub,
                  style: AppType.sans(
                    fontSize: AppType.caption,
                    color: AppColors.textTertiary,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          value,
          style: AppType.number(
            fontSize: AppType.body,
            fontWeight: FontWeight.w700,
            color: valueColor ?? AppColors.textStrong,
          ),
        ),
      ],
    ),
  );
}
