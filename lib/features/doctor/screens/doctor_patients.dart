import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../providers/doctor_patients_provider.dart';
import '../widgets/patient_summary.dart';
import 'patient_history.dart';

enum _Sort { recent, name, visits }

/// Everyone the doctor has seen or will see, built from their appointments
/// (the server has no "my patients" endpoint). Loads the full history — not
/// the dashboard's ±60-day window — so older patients appear too.
class DoctorPatients extends ConsumerStatefulWidget {
  const DoctorPatients({super.key});

  @override
  ConsumerState<DoctorPatients> createState() => _DoctorPatientsState();
}

class _DoctorPatientsState extends ConsumerState<DoctorPatients> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  _Sort _sort = _Sort.recent;

  @override
  void initState() {
    super.initState();
    // Reload on every visit, as before; silently once a list is on screen.
    Future.microtask(() {
      if (!mounted) return;
      final hasLoaded = ref.read(doctorPatientsProvider).hasLoaded;
      ref.read(doctorPatientsProvider.notifier).load(silent: hasLoaded);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() => ref.read(doctorPatientsProvider.notifier).load();

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
      case _Sort.visits:
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
        builder: (_) => PatientHistoryScreen(
          patientId: p.id,
          patientName: p.name,
          patient: p.patient,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context).color;
    final st = ref.watch(doctorPatientsProvider);
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
                    ? 'Everyone you’ve seen'
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
                        _Sort.visits => 'Most visits',
                      },
                      selected: _sort == s,
                      onTap: () => setState(() => _sort = s),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              ..._body(st, visible),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(DoctorPatientsState st, List<PatientSummary> visible) {
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
                PatientRow(summary: visible[i], onTap: () => _open(visible[i])),
              ],
            ],
          ),
        ),
    ];
  }
}
