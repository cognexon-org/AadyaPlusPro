import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/doctor_ui.dart';
import '../../doctor/widgets/patient_summary.dart';
import '../providers/physio_care_provider.dart';
import '../providers/physio_providers.dart';
import 'physio_patient_details.dart';

enum _Sort { recent, name, sessions }

/// Everyone the physio has seen or will see, grouped from their sessions
/// (server-scoped by role), with their active treatment course at a glance.
class PhysioPatients extends ConsumerStatefulWidget {
  const PhysioPatients({super.key});

  @override
  ConsumerState<PhysioPatients> createState() => _PhysioPatientsState();
}

class _PhysioPatientsState extends ConsumerState<PhysioPatients> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  _Sort _sort = _Sort.recent;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      final hasLoaded = ref.read(physioPatientsProvider).hasLoaded;
      ref.read(physioPatientsProvider.notifier).load(silent: hasLoaded);
      ref
          .read(physioCoursesProvider.notifier)
          .load(silent: ref.read(physioCoursesProvider).hasLoaded);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() => Future.wait([
    ref.read(physioPatientsProvider.notifier).load(),
    ref.read(physioCoursesProvider.notifier).load(silent: true),
  ]);

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value.trim().toLowerCase());
    });
  }

  List<PatientSummary> _visible(List<PatientSummary> patients) {
    final q = _query;
    final digits = q.replaceAll(RegExp(r'\D'), '');
    final list = patients.where((p) {
      if (q.isEmpty) return true;
      if (p.name.toLowerCase().contains(q)) return true;
      return digits.isNotEmpty &&
          p.phone.replaceAll(RegExp(r'\D'), '').contains(digits);
    }).toList();
    final epoch = DateTime(1970);
    switch (_sort) {
      case _Sort.recent:
        list.sort(
          (a, b) => (b.lastSeen ?? epoch).compareTo(a.lastSeen ?? epoch),
        );
      case _Sort.name:
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case _Sort.sessions:
        list.sort((a, b) {
          final c = b.visits.compareTo(a.visits);
          return c != 0
              ? c
              : (b.lastSeen ?? epoch).compareTo(a.lastSeen ?? epoch);
        });
    }
    return list;
  }

  void _open(PatientSummary p) {
    Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => PhysioPatientDetails(
          patient: {...p.patient, '_id': p.id, 'name': p.name},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context).color;
    final st = ref.watch(physioPatientsProvider);
    final courses = ref.watch(physioCoursesProvider);
    final visible = _visible(st.patients);
    final count = st.patients.length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: accent,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              AppScreenHeader(
                title: 'Patients',
                subtitle: !st.hasLoaded
                    ? 'Everyone you’ve treated'
                    : count == 1
                    ? '1 patient'
                    : '$count patients',
              ),
              const SizedBox(height: 16),
              AppSearchField(
                controller: _search,
                hint: 'Search by name or phone',
                onChanged: _onSearch,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final s in _Sort.values) ...[
                    AppFilterChip(
                      label: switch (s) {
                        _Sort.recent => 'Recent',
                        _Sort.name => 'A–Z',
                        _Sort.sessions => 'Most sessions',
                      },
                      selected: _sort == s,
                      onTap: () => setState(() => _sort = s),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              ..._body(st, visible, courses),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(
    DoctorPatientsState st,
    List<PatientSummary> visible,
    PhysioCoursesState courses,
  ) {
    final error = st.error;
    if (error != null && !st.hasLoaded) {
      return [AppErrorBanner(message: error, onRetry: _load)];
    }
    if (!st.hasLoaded) return const [AppListSkeleton(count: 6)];
    return [
      if (error != null) ...[
        AppErrorBanner(message: error, onRetry: _load),
        const SizedBox(height: 12),
      ],
      if (visible.isEmpty)
        AppEmptyState(
          icon: _query.isEmpty ? LucideIcons.users : LucideIcons.searchX,
          text: _query.isEmpty
              ? 'Patients appear here after their first booking.'
              : 'No patient matches “${_search.text.trim()}”.',
        )
      else
        AppEntrance(
          child: AppGroup(
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                if (i > 0) const AppHairline(),
                _PatientRow(
                  summary: visible[i],
                  course: courses.activeFor(visible[i].id),
                  onTap: () => _open(visible[i]),
                ),
              ],
            ],
          ),
        ),
    ];
  }
}

class _PatientRow extends StatelessWidget {
  final PatientSummary summary;
  final Map<String, dynamic>? course;
  final VoidCallback onTap;
  const _PatientRow({
    required this.summary,
    required this.course,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    final s = summary;
    final c = course;
    final sub = [
      if (s.meta.isNotEmpty) s.meta else if (s.phone.isNotEmpty) s.phone,
      s.lastVisit != null
          ? 'Last ${shortDate(s.lastVisit)}'
          : (s.nextVisit != null ? 'First session soon' : 'No sessions yet'),
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
                  if (c != null || s.nextVisit != null) ...[
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (c != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: accent.light,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Active course ${courseUsed(c)}/${courseTotal(c)}',
                              style: AppType.sans(
                                fontSize: AppType.micro,
                                fontWeight: FontWeight.w700,
                                color: accent.color,
                              ),
                            ),
                          ),
                        if (s.nextVisit != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.calendarClock,
                                size: 12,
                                color: accent.color,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Next ${dayLabel(s.nextVisit)} ${timeLabel(s.nextVisit)}',
                                style: AppType.sans(
                                  fontSize: AppType.caption,
                                  fontWeight: FontWeight.w600,
                                  color: accent.color,
                                ),
                              ),
                            ],
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
                  s.visits == 1 ? 'session' : 'sessions',
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
