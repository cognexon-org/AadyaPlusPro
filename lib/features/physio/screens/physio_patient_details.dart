import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/doctor_ui.dart';
import '../../doctor/widgets/patient_summary.dart';
import '../providers/physio_care_provider.dart';
import '../widgets/physio_course_card.dart';
import '../widgets/physio_course_sheet.dart';
import '../widgets/physio_progress_charts.dart';
import 'physio_appointment_details.dart';
import 'physio_assessment_detail.dart';
import 'physio_assessment_editor.dart';
import 'physio_exercise_plan_detail.dart';
import 'physio_exercise_plan_editor.dart';

enum _Tab { overview, sessions, exercises, progress }

String _date(DateTime? d) => d == null
    ? '—'
    : DateFormat(
        d.year == DateTime.now().year ? 'd MMM' : 'd MMM yyyy',
      ).format(d);

/// One patient's record with the signed-in physio: treatment course, next
/// session and latest pain (Overview), their sessions, exercise plans with
/// adherence, and measured progress from assessments.
class PhysioPatientDetails extends ConsumerStatefulWidget {
  /// The patient as the caller knew them (at least `_id`; name, phone, age,
  /// gender when known).
  final Map<String, dynamic> patient;

  /// 0 Overview, 1 Sessions, 2 Exercises, 3 Progress.
  final int initialTab;

  const PhysioPatientDetails({
    super.key,
    required this.patient,
    this.initialTab = 0,
  });

  @override
  ConsumerState<PhysioPatientDetails> createState() =>
      _PhysioPatientDetailsState();
}

class _PhysioPatientDetailsState extends ConsumerState<PhysioPatientDetails> {
  late _Tab _tab =
      _Tab.values[widget.initialTab.clamp(0, _Tab.values.length - 1)];

  late final String _id = () {
    final p = widget.patient;
    final id = refId(p['_id']);
    return id.isNotEmpty ? id : refId(p['patientId']);
  }();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      final st = ref.read(physioCoursesProvider);
      ref.read(physioCoursesProvider.notifier).load(silent: st.hasLoaded);
    });
  }

  /// What the caller knew, with gaps filled from a course's populated patient.
  Map<String, dynamic> _patient(PhysioCoursesState courses) {
    final out = {...widget.patient, '_id': _id};
    for (final c in courses.forPatient(_id)) {
      final p = c['patientId'];
      if (p is! Map) continue;
      for (final e in p.entries) {
        final v = e.value;
        if (v != null && '$v'.isNotEmpty && out['${e.key}'] == null) {
          out['${e.key}'] = v;
        }
      }
    }
    return out;
  }

  String _nameOf(Map<String, dynamic> p) {
    final n = '${p['name'] ?? ''}'.trim();
    return n.isEmpty ? 'Patient' : n;
  }

  Future<void> _refresh() async {
    final courses = ref.read(physioCoursesProvider.notifier).load(silent: true);
    final Future<Object?> tab = switch (_tab) {
      _Tab.overview => Future.wait([
        ref.refresh(physioPatientSessionsProvider(_id).future),
        ref.refresh(physioProgressProvider(_id).future),
      ]),
      _Tab.sessions => ref.refresh(physioPatientSessionsProvider(_id).future),
      _Tab.exercises => ref.refresh(physioCarePlansProvider(_id).future),
      _Tab.progress => Future.wait([
        ref.refresh(physioProgressProvider(_id).future),
        ref.refresh(physioAssessmentsProvider(_id).future),
      ]),
    };
    // Errors are shown from the providers' error states.
    await Future.wait<Object?>([
      courses,
      tab,
    ]).then<void>((_) {}, onError: (_) {});
  }

  // ─────────────────────────── Navigation ───────────────────────────

  Future<void> _call(String phone) async {
    final ok = await launchUrl(Uri(scheme: 'tel', path: phone));
    if (!ok && mounted) {
      showAppError(context, null, fallback: 'Couldn’t start a call.');
    }
  }

  Future<void> _startCourse(Map<String, dynamic> patient) =>
      showStartCourseSheet(
        context,
        patientId: _id,
        patientName: _nameOf(patient),
        patient: patient,
      );

  Future<void> _newAssessment(String name) async {
    final active = ref.read(physioCoursesProvider).activeFor(_id);
    await Navigator.of(context).push<bool>(
      AppPageRoute(
        builder: (_) => PhysioAssessmentEditor(
          patientId: _id,
          patientName: name,
          courseId: active == null ? null : '${active['_id']}',
        ),
      ),
    );
  }

  Future<void> _assignExercises(String name) async {
    await Navigator.of(context).push(
      AppPageRoute(
        builder: (_) =>
            PhysioExercisePlanEditor(patientId: _id, patientName: name),
      ),
    );
    if (mounted) ref.invalidate(physioCarePlansProvider(_id));
  }

  Future<void> _openPlan(String planId) async {
    if (planId.isEmpty) return;
    await Navigator.of(context).push(
      AppPageRoute(builder: (_) => PhysioExercisePlanDetail(planId: planId)),
    );
    if (mounted) ref.invalidate(physioCarePlansProvider(_id));
  }

  Future<void> _openSession(Map<String, dynamic> a) async {
    await Navigator.of(context).push(
      AppPageRoute(builder: (_) => PhysioAppointmentDetails(appointment: a)),
    );
    if (!mounted) return;
    ref.invalidate(physioPatientSessionsProvider(_id));
    ref.read(physioCoursesProvider.notifier).load(silent: true);
  }

  void _openAssessment(Map<String, dynamic> a, String name) {
    final id = '${a['_id'] ?? ''}';
    if (id.isEmpty) return;
    Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => PhysioAssessmentDetail(
          assessmentId: id,
          patientId: _id,
          patientName: name,
          assessment: a,
        ),
      ),
    );
  }

  // ─────────────────────────── Build ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context).color;
    final courses = ref.watch(physioCoursesProvider);
    final patient = _patient(courses);
    final name = _nameOf(patient);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: RefreshIndicator(
                color: accent,
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  children: [
                    AppEntrance(child: _profile(patient, name)),
                    const SizedBox(height: 18),
                    _Segmented(
                      value: _tab,
                      onChanged: (t) => setState(() => _tab = t),
                    ),
                    const SizedBox(height: 18),
                    if (_id.isEmpty)
                      const AppErrorBanner(
                        message: 'This patient record is missing its id.',
                      )
                    else
                      AnimatedSwitcher(
                        duration: AppMotion.fast,
                        child: KeyedSubtree(
                          key: ValueKey(_tab),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: switch (_tab) {
                              _Tab.overview => _overview(
                                courses,
                                patient,
                                name,
                              ),
                              _Tab.sessions => _sessions(patient),
                              _Tab.exercises => _exercises(name),
                              _Tab.progress => _progress(name),
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() => Padding(
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
          'Patient',
          style: AppType.sans(
            fontSize: AppType.body,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    ),
  );

  Widget _profile(Map<String, dynamic> p, String name) {
    final accent = ModuleAccent.of(context);
    final meta = patientMeta(p);
    final phone = '${p['phone'] ?? ''}'.trim();
    return Row(
      children: [
        DoctorAvatar(name: name, size: 56),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.sans(
                  fontSize: AppType.heading,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: AppColors.textStrong,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  if (meta.isNotEmpty) meta,
                  phone.isNotEmpty ? phone : 'No phone on file',
                ].join('  ·  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.sans(
                  fontSize: AppType.small,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (phone.isNotEmpty) ...[
          const SizedBox(width: 10),
          AppPressable(
            onTap: () => _call(phone),
            semanticLabel: 'Call $name',
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accent.light,
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.phone, size: 18, color: accent.color),
            ),
          ),
        ],
      ],
    );
  }

  /// Skeleton / error banner / content for one async section.
  List<Widget> _async<T>(
    AsyncValue<T> async,
    List<Widget> Function(T data) data, {
    required String error,
    required VoidCallback retry,
    int skeleton = 3,
  }) {
    if (async.hasValue) {
      return [
        if (async.hasError) ...[
          AppErrorBanner(
            message: doctorError(async.error!, fallback: error),
            onRetry: retry,
          ),
          const SizedBox(height: 10),
        ],
        ...data(async.requireValue),
      ];
    }
    if (async.hasError) {
      return [
        AppErrorBanner(
          message: doctorError(async.error!, fallback: error),
          onRetry: retry,
        ),
      ];
    }
    return [AppListSkeleton(count: skeleton)];
  }

  // ─────────────────────────── Overview ───────────────────────────

  List<Widget> _overview(
    PhysioCoursesState courses,
    Map<String, dynamic> patient,
    String name,
  ) {
    final active = courses.activeFor(_id);
    final past = courses
        .forPatient(_id)
        .where((c) => courseStatus(c) != 'active')
        .toList();
    final sessions = ref.watch(physioPatientSessionsProvider(_id));
    final progress = ref.watch(physioProgressProvider(_id));
    final next = sessions.valueOrNull == null
        ? null
        : _nextSession(sessions.requireValue);

    return [
      AppSectionTitle(
        'Treatment course',
        action: active == null && courses.hasLoaded ? 'Start a course' : null,
        onAction: () => _startCourse(patient),
      ),
      if (!courses.hasLoaded && courses.error != null)
        AppErrorBanner(
          message: courses.error!,
          onRetry: () => ref.read(physioCoursesProvider.notifier).load(),
        )
      else if (!courses.hasLoaded)
        const AppListSkeleton(count: 1)
      else if (active != null)
        AppEntrance(index: 1, child: PhysioCourseCard(course: active))
      else
        AppEmptyState(
          icon: LucideIcons.layers,
          text: 'No active course. Sell a package or set sessions and price.',
          action: AppButton(
            label: 'Start a course',
            icon: LucideIcons.plus,
            fullWidth: false,
            compact: true,
            onPressed: () => _startCourse(patient),
          ),
        ),
      if (next != null) ...[
        const SizedBox(height: 10),
        _NextSessionRow(
          appointment: next,
          onTap: () => _openSession({...next, 'patientId': patient}),
        ),
      ],
      const SizedBox(height: 22),
      const AppSectionTitle('Pain'),
      ..._async(
        progress,
        (p) => [_painSummary(p, name)],
        error: 'Couldn’t load progress.',
        retry: () => ref.invalidate(physioProgressProvider(_id)),
        skeleton: 1,
      ),
      const SizedBox(height: 22),
      const AppSectionTitle('Quick actions'),
      AppGroup(
        children: [
          _ActionRow(
            icon: LucideIcons.clipboardPlus,
            title: 'New assessment',
            subtitle: 'Pain, range of motion, strength, outcome scores',
            onTap: () => _newAssessment(name),
          ),
          const AppHairline(),
          _ActionRow(
            icon: LucideIcons.dumbbell,
            title: 'Assign exercises',
            subtitle: 'Home programme with sets, reps and hold',
            onTap: () => _assignExercises(name),
          ),
        ],
      ),
      if (past.isNotEmpty) ...[
        const SizedBox(height: 22),
        const AppSectionTitle('Past courses'),
        AppGroup(
          children: [
            for (var i = 0; i < past.length; i++) ...[
              if (i > 0) const AppHairline(),
              PhysioPastCourseRow(course: past[i]),
            ],
          ],
        ),
      ],
    ];
  }

  Map<String, dynamic>? _nextSession(List<Map<String, dynamic>> list) {
    final now = DateTime.now();
    Map<String, dynamic>? best;
    DateTime? bestAt;
    for (final a in list) {
      final s = apptStart(a);
      if (s == null || s.isBefore(now)) continue;
      if (!const {
        'pending',
        'confirmed',
        'rescheduled',
      }.contains(apptStatus(a))) {
        continue;
      }
      if (bestAt == null || s.isBefore(bestAt)) {
        best = a;
        bestAt = s;
      }
    }
    return best;
  }

  Widget _painSummary(Map<String, dynamic> progress, String name) {
    final pain = (progress['pain'] is List ? progress['pain'] as List : [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (pain.isEmpty) {
      return AppEmptyState(
        icon: LucideIcons.activity,
        text: 'No pain score yet. Record an assessment to start tracking.',
        action: AppSecondaryButton(
          label: 'Record assessment',
          icon: LucideIcons.clipboardPlus,
          fullWidth: false,
          onPressed: () => _newAssessment(name),
        ),
      );
    }
    final lastDate = parseDate(pain.last['date']);
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
            children: [
              Expanded(child: _painFigure(pain, 'activity', 'With activity')),
              Container(width: 1, height: 44, color: AppColors.bg),
              const SizedBox(width: 16),
              Expanded(child: _painFigure(pain, 'rest', 'At rest')),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Latest ${_date(lastDate)} · ${pain.length} '
            '${pain.length == 1 ? 'assessment' : 'assessments'}',
            style: AppType.sans(
              fontSize: AppType.caption,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _painFigure(List<Map<String, dynamic>> pain, String key, String l) {
    final values = [
      for (final p in pain)
        if (p[key] is num) p[key] as num,
    ];
    final latest = values.isEmpty ? null : values.last;
    final prev = values.length > 1 ? values[values.length - 2] : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l,
          style: AppType.sans(
            fontSize: AppType.caption,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              latest == null ? '—' : '${latest.round()}',
              style: AppType.number(
                fontSize: AppType.display,
                fontWeight: FontWeight.w700,
                color: latest == null
                    ? AppColors.textTertiary
                    : painColor(context, latest),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 3),
              child: Text(
                '/10',
                style: AppType.sans(
                  fontSize: AppType.small,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (latest != null && prev != null)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: PhysioChangeChip(
                    change: latest - prev,
                    lowerIsBetter: true,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ─────────────────────────── Sessions ───────────────────────────

  List<Widget> _sessions(Map<String, dynamic> patient) {
    final async = ref.watch(physioPatientSessionsProvider(_id));
    return _async(
      async,
      (list) => [
        AppSectionTitle(
          list.isEmpty
              ? 'Sessions'
              : '${list.length} ${list.length == 1 ? 'session' : 'sessions'}',
        ),
        if (list.isEmpty)
          const AppEmptyState(
            icon: LucideIcons.calendarX,
            text: 'No sessions with you yet.',
          )
        else
          for (var i = 0; i < list.length; i++)
            AppEntrance(
              index: i,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DoctorAppointmentCard(
                  appointment: {...list[i], 'patientId': patient},
                  showDay: true,
                  onTap: () => _openSession({...list[i], 'patientId': patient}),
                ),
              ),
            ),
      ],
      error: 'Couldn’t load sessions.',
      retry: () => ref.invalidate(physioPatientSessionsProvider(_id)),
      skeleton: 4,
    );
  }

  // ─────────────────────────── Exercises ───────────────────────────

  List<Widget> _exercises(String name) {
    final async = ref.watch(physioCarePlansProvider(_id));
    return [
      AppSectionTitle(
        'Exercise plans',
        action: 'New plan',
        onAction: () => _assignExercises(name),
      ),
      ..._async(
        async,
        (plans) => [
          if (plans.isEmpty)
            AppEmptyState(
              icon: LucideIcons.dumbbell,
              text:
                  'No exercise plan yet. Give a home programme to follow '
                  'between sessions.',
              action: AppButton(
                label: 'New plan',
                icon: LucideIcons.plus,
                fullWidth: false,
                compact: true,
                onPressed: () => _assignExercises(name),
              ),
            )
          else
            AppEntrance(
              child: AppGroup(
                children: [
                  for (var i = 0; i < plans.length; i++) ...[
                    if (i > 0) const AppHairline(),
                    _PlanRow(
                      plan: plans[i],
                      onTap: () => _openPlan(plans[i].id),
                    ),
                  ],
                ],
              ),
            ),
        ],
        error: 'Couldn’t load exercise plans.',
        retry: () => ref.invalidate(physioCarePlansProvider(_id)),
      ),
    ];
  }

  // ─────────────────────────── Progress ───────────────────────────

  List<Widget> _progress(String name) {
    final progress = ref.watch(physioProgressProvider(_id));
    final assessments = ref.watch(physioAssessmentsProvider(_id));
    return [
      ..._async(
        progress,
        (p) => _progressBody(p, name),
        error: 'Couldn’t load progress.',
        retry: () => ref.invalidate(physioProgressProvider(_id)),
      ),
      const SizedBox(height: 22),
      AppSectionTitle(
        'Assessments',
        action: 'New',
        onAction: () => _newAssessment(name),
      ),
      ..._async(
        assessments,
        (list) => [
          if (list.isEmpty)
            AppEmptyState(
              icon: LucideIcons.clipboardList,
              text:
                  'No assessments yet. An initial assessment sets the '
                  'baseline for progress.',
              action: AppButton(
                label: 'New assessment',
                icon: LucideIcons.plus,
                fullWidth: false,
                compact: true,
                onPressed: () => _newAssessment(name),
              ),
            )
          else
            AppGroup(
              children: [
                for (var i = 0; i < list.length; i++) ...[
                  if (i > 0) const AppHairline(),
                  _AssessmentRow(
                    assessment: list[i],
                    onTap: () => _openAssessment(list[i], name),
                  ),
                ],
              ],
            ),
        ],
        error: 'Couldn’t load assessments.',
        retry: () => ref.invalidate(physioAssessmentsProvider(_id)),
      ),
    ];
  }

  List<Widget> _progressBody(Map<String, dynamic> p, String name) {
    final pain = (p['pain'] is List ? p['pain'] as List : const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final om = p['outcomeMeasures'] is Map
        ? Map<String, dynamic>.from(p['outcomeMeasures'])
        : <String, dynamic>{};
    final rom = p['rom'] is Map
        ? Map<String, dynamic>.from(p['rom'])
        : <String, dynamic>{};
    final count = num.tryParse('${p['assessmentCount'] ?? ''}')?.round() ?? 0;
    if (count == 0) return const [];
    return [
      if (pain.isNotEmpty) ...[
        const AppSectionTitle('Pain over time'),
        AppEntrance(child: PhysioPainChart(points: pain)),
        const SizedBox(height: 22),
      ],
      if (om.isNotEmpty) ...[
        const AppSectionTitle('Outcome measures'),
        for (final e in om.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: PhysioOutcomeCard(
              code: e.key,
              series: (e.value is List ? e.value as List : const [])
                  .whereType<Map>()
                  .map((m) => Map<String, dynamic>.from(m))
                  .toList(),
            ),
          ),
        const SizedBox(height: 14),
      ],
      if (rom.isNotEmpty) ...[
        const AppSectionTitle('Range of motion'),
        PhysioRomTable(rom: rom),
      ],
    ];
  }
}

// ─────────────────────────── Pieces ───────────────────────────

class _Segmented extends StatelessWidget {
  final _Tab value;
  final ValueChanged<_Tab> onChanged;
  const _Segmented({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const tabs = _Tab.values;
    final i = tabs.indexOf(value);
    return Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: AppMotion.medium,
            curve: AppMotion.enter,
            alignment: Alignment(-1 + i * 2 / (tabs.length - 1), 0),
            child: FractionallySizedBox(
              widthFactor: 1 / tabs.length,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: const [
                    BoxShadow(color: Color(0x14000000), blurRadius: 4),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final t in tabs)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: t == value,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(t),
                      child: Center(
                        child: Text(
                          switch (t) {
                            _Tab.overview => 'Overview',
                            _Tab.sessions => 'Sessions',
                            _Tab.exercises => 'Exercises',
                            _Tab.progress => 'Progress',
                          },
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.sans(
                            fontSize: AppType.small,
                            fontWeight: t == value
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: t == value
                                ? AppColors.textStrong
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context).color;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppType.sans(
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: AppColors.textDisabled,
            ),
          ],
        ),
      ),
    );
  }
}

class _NextSessionRow extends StatelessWidget {
  final Map<String, dynamic> appointment;
  final VoidCallback onTap;
  const _NextSessionRow({required this.appointment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    final start = apptStart(appointment);
    final pending = apptStatus(appointment) == 'pending';
    return AppPressable(
      scale: 0.985,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
        decoration: BoxDecoration(
          color: accent.veryLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.calendarClock, size: 16, color: accent.color),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: 'Next session  ',
                  style: AppType.sans(
                    fontSize: AppType.small,
                    color: AppColors.textSecondary,
                  ),
                  children: [
                    TextSpan(
                      text: '${dayLabel(start)}, ${timeLabel(start)}',
                      style: AppType.sans(
                        fontSize: AppType.small,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textStrong,
                      ),
                    ),
                    if (pending)
                      TextSpan(
                        text: '  · request',
                        style: AppType.sans(
                          fontSize: AppType.small,
                          fontWeight: FontWeight.w600,
                          color: AppColors.warning,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 16, color: accent.color),
          ],
        ),
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  final PhysioPlanSummary plan;
  final VoidCallback onTap;
  const _PlanRow({required this.plan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context).color;
    final p = plan;
    final compliance = p.compliance;
    final active = p.status == 'active';
    final low = active && compliance != null && compliance < 50;
    final created = parseDate(p.plan['startDate'] ?? p.plan['createdAt']);
    return AppPressable(
      scale: 0.985,
      onTap: onTap,
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          p.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.sans(
                            fontSize: AppType.body,
                            fontWeight: FontWeight.w700,
                            color: active
                                ? AppColors.textStrong
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        capitalised(p.status),
                        style: AppType.sans(
                          fontSize: AppType.caption,
                          fontWeight: FontWeight.w600,
                          color: active ? accent : AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      '${p.exerciseCount} ${p.exerciseCount == 1 ? 'exercise' : 'exercises'}',
                      if (created != null && p.lastLogged == null)
                        'from ${_date(created)}',
                      p.lastLogged != null
                          ? 'last done ${_date(p.lastLogged)}'
                          : (active ? 'not logged yet' : null),
                    ].whereType<String>().join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (compliance != null) ...[
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$compliance%',
                    style: AppType.number(
                      fontSize: AppType.title,
                      fontWeight: FontWeight.w700,
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
            ],
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

class _AssessmentRow extends StatelessWidget {
  final Map<String, dynamic> assessment;
  final VoidCallback onTap;
  const _AssessmentRow({required this.assessment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = assessment;
    final date = parseDate(a['assessedAt'] ?? a['createdAt']);
    final complaint = '${a['chiefComplaint'] ?? ''}'.trim();
    final pain = a['painScore'] is Map ? a['painScore'] as Map : const {};
    final rest = pain['rest'];
    final activity = pain['activity'];
    final painText = [
      if (activity is num) 'activity ${activity.round()}',
      if (rest is num) 'rest ${rest.round()}',
    ].join(', ');
    int len(String k) => a[k] is List ? (a[k] as List).length : 0;
    final counts = [
      if (len('rom') > 0) '${len('rom')} ROM',
      if (len('outcomeMeasures') > 0)
        '${len('outcomeMeasures')} ${len('outcomeMeasures') == 1 ? 'score' : 'scores'}',
      if (len('specialTests') > 0)
        '${len('specialTests')} ${len('specialTests') == 1 ? 'test' : 'tests'}',
    ].join(' · ');

    return AppPressable(
      scale: 0.985,
      onTap: onTap,
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        assessmentTypeLabel('${a['type'] ?? ''}'),
                        style: AppType.sans(
                          fontSize: AppType.body,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textStrong,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _date(date),
                        style: AppType.sans(
                          fontSize: AppType.caption,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  if (complaint.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      complaint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.sans(
                        fontSize: AppType.small,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                  if (painText.isNotEmpty || counts.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (painText.isNotEmpty) 'Pain $painText',
                        if (counts.isNotEmpty) counts,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.sans(
                        fontSize: AppType.caption,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
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
