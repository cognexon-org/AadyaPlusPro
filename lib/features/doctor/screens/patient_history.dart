import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/ui/app_ui.dart';
import '../providers/doctor_patients_provider.dart';
import '../widgets/doctor_ui.dart';
import '../widgets/patient_summary.dart';
import 'doctor_appointments.dart';
import 'prescription_details.dart';

/// One patient's history with this doctor: their visits and the
/// prescriptions written for them. Both endpoints are scoped to the signed-in
/// doctor by the server.
class PatientHistoryScreen extends ConsumerStatefulWidget {
  final String patientId;
  final String patientName;

  /// The patient as the list knew them (name, phone, age, gender); filled in
  /// from the prescriptions when missing.
  final Map<String, dynamic>? patient;

  const PatientHistoryScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    this.patient,
  });

  @override
  ConsumerState<PatientHistoryScreen> createState() =>
      _PatientHistoryScreenState();
}

class _PatientHistoryScreenState extends ConsumerState<PatientHistoryScreen> {
  /// What the list knew about the patient; wins over the prescriptions'.
  late final Map<String, dynamic> _seed = {
    '_id': widget.patientId,
    'name': widget.patientName,
    ...?widget.patient,
  };

  // Set in build from the provider's data.
  late Map<String, dynamic> _patient = _seed;
  PatientHistory? _source;
  PatientHistory _history = const PatientHistory();

  AutoDisposeFutureProvider<PatientHistory> get _provider =>
      patientHistoryProvider(widget.patientId);

  /// Errors are shown from the provider's error state, not rethrown.
  Future<void> _load() =>
      ref.refresh(_provider.future).then<void>((_) {}, onError: (_) {});

  /// The provider's history with the seed patient merged in (memoised).
  void _resolve(PatientHistory? h) {
    if (h == null || identical(h, _source)) return;
    _source = h;
    _patient = h.mergedPatient(_seed);
    _history = h.withPatient(_patient);
  }

  String get _name {
    final n = '${_patient['name'] ?? ''}'.trim();
    return n.isEmpty ? 'Patient' : n;
  }

  String get _phone => '${_patient['phone'] ?? ''}'.trim();

  Future<void> _call() async {
    if (_phone.isEmpty) return;
    final ok = await launchUrl(Uri(scheme: 'tel', path: _phone));
    if (!ok && mounted) {
      showAppError(context, null, fallback: 'Couldn’t start a call.');
    }
  }

  Future<void> _openAppointment(Map<String, dynamic> a) async {
    await Navigator.of(context).push(
      AppPageRoute(builder: (_) => AppointmentDetailsScreen(appointment: a)),
    );
    if (mounted) _load();
  }

  void _openPrescription(Map<String, dynamic> rx) {
    Navigator.of(context).push(
      AppPageRoute(builder: (_) => PrescriptionDetailsScreen(prescription: rx)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context).color;
    final async = ref.watch(_provider);
    _resolve(async.valueOrNull);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: RefreshIndicator(
                color: accent,
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  children: [
                    AppEntrance(child: _profile()),
                    const SizedBox(height: 18),
                    ..._body(async),
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
          'Patient history',
          style: AppType.sans(
            fontSize: AppType.body,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    ),
  );

  Widget _profile() {
    final accent = ModuleAccent.of(context);
    final meta = patientMeta(_patient);
    return Row(
      children: [
        DoctorAvatar(name: _name, size: 56),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _name,
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
                  _phone.isNotEmpty ? _phone : 'No phone on file',
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
        if (_phone.isNotEmpty) ...[
          const SizedBox(width: 10),
          AppPressable(
            onTap: _call,
            semanticLabel: 'Call $_name',
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

  List<Widget> _body(AsyncValue<PatientHistory> async) {
    final loaded = async.hasValue;
    final error = async.hasError
        ? doctorError(async.error!, fallback: 'Couldn’t load this patient.')
        : null;
    if (error != null && !loaded) {
      return [AppErrorBanner(message: error, onRetry: _load)];
    }
    if (!loaded) return const [AppDetailSkeleton(rows: 6)];

    final appointments = _history.appointments;
    final prescriptions = _history.prescriptions;
    final stats = visitStats(appointments);
    final liveRx = prescriptions
        .where((r) => '${r['status']}' != 'cancelled')
        .length;
    return [
      if (error != null) ...[
        AppErrorBanner(message: error, onRetry: _load),
        const SizedBox(height: 12),
      ],
      AppEntrance(
        index: 1,
        child: _stats([
          ('${stats.visits}', stats.visits == 1 ? 'Visit' : 'Visits'),
          (shortDate(stats.last), 'Last visit'),
          ('$liveRx', liveRx == 1 ? 'Prescription' : 'Prescriptions'),
        ]),
      ),
      if (stats.next != null) ...[
        const SizedBox(height: 10),
        _nextLine(stats.next!),
      ],
      const SizedBox(height: 24),
      AppEntrance(
        index: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSectionTitle('Visits'),
            if (appointments.isEmpty)
              const AppEmptyState(
                icon: LucideIcons.calendarX,
                text: 'No visits with you yet.',
              )
            else
              for (final a in appointments) ...[
                DoctorAppointmentCard(
                  appointment: a,
                  showDay: true,
                  onTap: () => _openAppointment(a),
                ),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
      const SizedBox(height: 20),
      AppEntrance(
        index: 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSectionTitle('Prescriptions'),
            if (prescriptions.isEmpty)
              const AppEmptyState(
                icon: LucideIcons.fileText,
                text: 'No prescriptions written yet.',
              )
            else
              AppGroup(
                children: [
                  for (var i = 0; i < prescriptions.length; i++) ...[
                    if (i > 0) const AppHairline(),
                    _PrescriptionRow(
                      rx: prescriptions[i],
                      onTap: () => _openPrescription(prescriptions[i]),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    ];
  }

  Widget _stats(List<(String, String)> items) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: BoxDecoration(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(14),
    ),
    child: IntrinsicHeight(
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Container(width: 1, color: AppColors.bg),
            Expanded(
              child: Column(
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      items[i].$1,
                      style: AppType.number(
                        fontSize: AppType.title,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textStrong,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    items[i].$2,
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
  );

  Widget _nextLine(DateTime next) {
    final accent = ModuleAccent.of(context).color;
    return Row(
      children: [
        Icon(LucideIcons.calendarClock, size: 14, color: accent),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Next visit ${dayLabel(next)} at ${timeLabel(next)}',
            style: AppType.sans(
              fontSize: AppType.small,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
        ),
      ],
    );
  }
}

class _PrescriptionRow extends StatelessWidget {
  final Map<String, dynamic> rx;
  final VoidCallback onTap;
  const _PrescriptionRow({required this.rx, required this.onTap});

  static String _join(dynamic list, {String? key}) {
    if (list is! List) return list is String ? list.trim() : '';
    return list
        .map((e) => (e is Map ? '${e[key] ?? e['name'] ?? ''}' : '$e').trim())
        .where((e) => e.isNotEmpty && e != 'null')
        .join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final number = '${rx['prescriptionNumber'] ?? ''}'.trim();
    final date = DateTime.tryParse(
      '${rx['issuedAt'] ?? rx['createdAt'] ?? ''}',
    )?.toLocal();
    final diagnosis = _join(rx['diagnosis']);
    final meds = _join(rx['medicines'], key: 'medicineName');
    final status = '${rx['status'] ?? ''}';
    final statusText = switch (status) {
      'draft' => 'Draft',
      'cancelled' => 'Cancelled',
      'superseded' => 'Replaced',
      _ => '',
    };
    final statusColor = switch (status) {
      'draft' => AppColors.warning,
      'cancelled' => AppColors.error,
      _ => AppColors.textTertiary,
    };

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
                          number.isEmpty ? 'Prescription' : number,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.sans(
                            fontSize: AppType.body,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textStrong,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        date == null
                            ? ''
                            : DateFormat(
                                date.year == DateTime.now().year
                                    ? 'd MMM'
                                    : 'd MMM yyyy',
                              ).format(date),
                        style: AppType.sans(
                          fontSize: AppType.caption,
                          color: AppColors.textTertiary,
                        ),
                      ),
                      if (statusText.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          statusText,
                          style: AppType.sans(
                            fontSize: AppType.caption,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    diagnosis.isEmpty ? 'No diagnosis noted' : diagnosis,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.sans(
                      fontSize: AppType.small,
                      fontWeight: FontWeight.w500,
                      color: diagnosis.isEmpty
                          ? AppColors.textTertiary
                          : AppColors.textPrimary,
                    ),
                  ),
                  if (meds.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(
                            LucideIcons.pill,
                            size: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            meds,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.sans(
                              fontSize: AppType.caption,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
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
