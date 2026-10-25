import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/screens/app_chat_screen.dart';
import '../../../shared/screens/professional_consultation_screen.dart';
import '../../../shared/ui/app_ui.dart';
import '../providers/doctor_appointments_provider.dart';
import '../providers/doctor_prescriptions_provider.dart';
import '../providers/doctor_profile_provider.dart';
import '../widgets/doctor_ui.dart';
import 'doctor_prescriptions.dart';
import 'prescription_details.dart';

/// The Appointments tab: requests to answer, what's coming, what's done.
/// The appointments tab, shared by doctors and physiotherapists (the
/// server scopes appointments by role). Defaults are the doctor's.
class DoctorAppointments extends ConsumerStatefulWidget {
  final String title;

  /// "appointment" or "session".
  final String noun;

  /// The screen an appointment opens.
  final Widget Function(Map<String, dynamic> appointment)? detailsBuilder;

  const DoctorAppointments({
    super.key,
    this.title = 'Appointments',
    this.noun = 'appointment',
    this.detailsBuilder,
  });

  @override
  ConsumerState<DoctorAppointments> createState() => _DoctorAppointmentsState();
}

enum _Tab { requests, upcoming, past }

class _DoctorAppointmentsState extends ConsumerState<DoctorAppointments> {
  _Tab _tab = _Tab.upcoming;
  String? _type; // null = all
  final Set<String> _busy = {};
  bool _pickedInitialTab = false;

  Future<void> _refresh() =>
      ref.read(doctorAppointmentsProvider.notifier).load(silent: true);

  Future<void> _accept(Map<String, dynamic> a) async {
    final id = '${a['_id']}';
    setState(() => _busy.add(id));
    try {
      await ref.read(doctorAppointmentsProvider.notifier).accept(id);
      _toast('Accepted — ${patientName(a)} is on your schedule');
    } catch (e) {
      _toast(doctorError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _decline(Map<String, dynamic> a) async {
    final ok = await AppModal.confirm(
      context,
      title: 'Decline this request?',
      message:
          '${patientName(a)} is told you can’t take the appointment on ${dayLabel(apptStart(a))} at ${timeLabel(apptStart(a))}.',
      confirmLabel: 'Decline',
      cancelLabel: 'Keep',
    );
    if (!ok || !mounted) return;
    final id = '${a['_id']}';
    setState(() => _busy.add(id));
    try {
      await ref.read(doctorAppointmentsProvider.notifier).decline(id);
      _toast('Request declined');
    } catch (e) {
      _toast(doctorError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  void _open(Map<String, dynamic> a) => Navigator.of(context).push(
    AppPageRoute(
      builder: (_) =>
          widget.detailsBuilder?.call(a) ??
          AppointmentDetailsScreen(appointment: a),
    ),
  );

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppType.sans(fontSize: AppType.caption, color: Colors.white),
        ),
        backgroundColor: error ? AppColors.error : AppColors.textStrong,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(doctorAppointmentsProvider);
    // Open on Requests the first time there's something to answer.
    if (!_pickedInitialTab && state.hasLoaded) {
      _pickedInitialTab = true;
      if (state.requests.isNotEmpty) _tab = _Tab.requests;
    }

    final source = switch (_tab) {
      _Tab.requests => state.requests,
      _Tab.upcoming => [...state.today.where(_notDone), ...state.upcoming],
      _Tab.past => state.past,
    };
    final list = _type == null
        ? source
        : source.where((a) => apptType(a) == _type).toList();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: AppScreenHeader(
                title: widget.title,
                subtitle: state.requests.isEmpty
                    ? 'Your schedule and history'
                    : '${state.requests.length} waiting for your answer',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _Segmented(
                value: _tab,
                requests: state.requests.length,
                onChanged: (t) => setState(() => _tab = t),
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final t in const [null, 'clinic', 'video', 'home'])
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: AppFilterChip(
                        label: t == null ? 'All types' : apptTypeInfo(t).label,
                        selected: _type == t,
                        onTap: () => setState(() => _type = t),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 2,
              child: AnimatedOpacity(
                opacity: state.isRefreshing ? 1 : 0,
                duration: AppMotion.fast,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: ModuleAccent.of(context).color,
                  backgroundColor: Colors.transparent,
                ),
              ),
            ),
            Expanded(child: _body(state, list)),
          ],
        ),
      ),
    );
  }

  static bool _notDone(Map<String, dynamic> a) =>
      const {'confirmed', 'in_progress', 'rescheduled'}.contains(apptStatus(a));

  Widget _body(DoctorAppointmentsState state, List<Map<String, dynamic>> list) {
    if (state.isLoading && !state.hasLoaded) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: const [AppListSkeleton(count: 5)],
      );
    }
    if (state.error != null && !state.hasLoaded) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: AppErrorBanner(message: state.error!, onRetry: _refresh),
      );
    }

    final rows = <Widget>[];
    if (list.isEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: AppEmptyState(
            icon: switch (_tab) {
              _Tab.requests => LucideIcons.inbox,
              _Tab.upcoming => LucideIcons.calendarCheck,
              _Tab.past => LucideIcons.history,
            },
            text: switch (_tab) {
              _Tab.requests => 'No requests waiting. New bookings appear here.',
              _Tab.upcoming =>
                'Nothing scheduled. Accepted ${widget.noun}s appear here.',
              _Tab.past => 'No past ${widget.noun}s in the last 60 days.',
            },
          ),
        ),
      );
    } else {
      String? lastDay;
      for (final (i, a) in list.indexed) {
        final day = dayLabel(apptStart(a));
        if (_tab != _Tab.requests && day != lastDay) {
          rows.add(
            Padding(
              padding: EdgeInsets.fromLTRB(2, i == 0 ? 4 : 16, 0, 8),
              child: Text(
                day,
                style: AppType.sans(
                  fontSize: AppType.small,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          );
          lastDay = day;
        }
        final id = '${a['_id']}';
        rows.add(
          AppEntrance(
            key: ValueKey('appt-$id'),
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DoctorAppointmentCard(
                appointment: a,
                showDay: _tab == _Tab.requests,
                onTap: () => _open(a),
                actions: _tab == _Tab.requests
                    ? Row(
                        children: [
                          Expanded(
                            child: AppSecondaryButton(
                              label: 'Decline',
                              color: AppColors.error,
                              onPressed: _busy.contains(id)
                                  ? null
                                  : () => _decline(a),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: AppButton(
                              label: 'Accept',
                              icon: LucideIcons.check,
                              compact: true,
                              loading: _busy.contains(id),
                              onPressed: _busy.contains(id)
                                  ? null
                                  : () => _accept(a),
                            ),
                          ),
                        ],
                      )
                    : null,
              ),
            ),
          ),
        );
      }
    }

    return RefreshIndicator(
      color: ModuleAccent.of(context).color,
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: rows,
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  final _Tab value;
  final int requests;
  final ValueChanged<_Tab> onChanged;
  const _Segmented({
    required this.value,
    required this.requests,
    required this.onChanged,
  });

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
            alignment: Alignment(-1 + i * 1.0, 0),
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
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(t),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            switch (t) {
                              _Tab.requests => 'Requests',
                              _Tab.upcoming => 'Upcoming',
                              _Tab.past => 'Past',
                            },
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
                          if (t == _Tab.requests && requests > 0) ...[
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.warning,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$requests',
                                style: AppType.sans(
                                  fontSize: AppType.micro,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
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

// ─────────────────────────── Details ───────────────────────────

/// One appointment: who, when, why, and what to do next. Always re-reads the
/// appointment on open and after a consultation, so its status is current.
class AppointmentDetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> appointment;

  /// Replaces the Prescription section — the physio module shows its
  /// treatment course, exercise plan and assessment here instead. Receives
  /// the current appointment (re-read after every action).
  final Widget Function(BuildContext context, Map<String, dynamic> appointment)?
  careSection;

  /// "appointment" or "session", for button labels.
  final String noun;

  const AppointmentDetailsScreen({
    super.key,
    required this.appointment,
    this.careSection,
    this.noun = 'appointment',
  });

  @override
  ConsumerState<AppointmentDetailsScreen> createState() =>
      _AppointmentDetailsScreenState();
}

class _AppointmentDetailsScreenState
    extends ConsumerState<AppointmentDetailsScreen> {
  late Map<String, dynamic> _a = widget.appointment;
  bool _busy = false;
  bool _chatLoading = false;

  String get _id => '${_a['_id'] ?? ''}';

  @override
  void initState() {
    super.initState();
    Future.microtask(_reload);
  }

  Future<void> _reload() async {
    if (_id.isEmpty) return;
    try {
      final fresh = await ref
          .read(doctorAppointmentsProvider.notifier)
          .refreshOne(_id);
      if (fresh != null && mounted) setState(() => _a = fresh);
    } catch (_) {
      // Keep what the list handed over; it's still accurate enough to act on.
    }
    await _loadPrescription();
  }

  /// Asks the prescriptions provider for this visit's prescription; the
  /// screen then reads it from the provider, so issuing or editing it from
  /// anywhere shows up here too.
  Future<void> _loadPrescription() async {
    try {
      await ref.read(doctorPrescriptionsProvider.notifier).forAppointment(_id);
    } catch (_) {
      // Not fatal: the section just offers to write one.
    }
  }

  /// The current (not cancelled or superseded) prescription for this visit.
  Map<String, dynamic>? _rxFor(DoctorPrescriptionsState s) {
    for (final rx in s.items) {
      final appt = rx['appointmentId'];
      final apptId = appt is Map ? '${appt['_id']}' : '${appt ?? ''}';
      final status = '${rx['status'] ?? ''}';
      if (apptId == _id && status != 'cancelled' && status != 'superseded') {
        return rx;
      }
    }
    return null;
  }

  Future<void> _run(
    Future<Map<String, dynamic>?> Function() action,
    String done,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final updated = await action();
      if (!mounted) return;
      if (updated != null) setState(() => _a = {..._a, ...updated});
      _toast(done);
    } catch (e) {
      _toast(doctorError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept() => _run(
    () => ref.read(doctorAppointmentsProvider.notifier).accept(_id),
    'Accepted — added to your schedule',
  );

  Future<void> _decline() async {
    final ok = await AppModal.confirm(
      context,
      title: 'Decline this request?',
      message: '${patientName(_a)} is told you can’t take this appointment.',
      confirmLabel: 'Decline',
      cancelLabel: 'Keep',
    );
    if (!ok) return;
    await _run(
      () => ref.read(doctorAppointmentsProvider.notifier).decline(_id),
      'Request declined',
    );
  }

  Future<void> _cancel() async {
    final reason = await showAppSheet<String>(
      context,
      builder: (_) => const _CancelSheet(),
    );
    if (reason == null) return;
    await _run(
      () => ref
          .read(doctorAppointmentsProvider.notifier)
          .cancel(_id, reason: reason),
      'Appointment cancelled — the patient has been told',
    );
  }

  Future<void> _noShow() async {
    final ok = await AppModal.confirm(
      context,
      title: 'Mark as no-show?',
      message:
          '${patientName(_a)} didn’t turn up. The slot is closed and the visit won’t count as completed.',
      confirmLabel: 'Mark no-show',
      cancelLabel: 'Back',
    );
    if (!ok) return;
    await _run(
      () => ref.read(doctorAppointmentsProvider.notifier).markNoShow(_id),
      'Marked as no-show',
    );
  }

  Future<void> _consult() async {
    await Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => ProfessionalConsultationScreen(appointment: _a),
      ),
    );
    // Whatever happened in there (started, ended, prescribed), read it back.
    await _reload();
  }

  Future<void> _writePrescription() async {
    final p = apptPatient(_a);
    final saved = await Navigator.of(context).push<bool>(
      AppPageRoute(
        builder: (_) => CreatePrescriptionScreen(
          initialPatientId: p['_id']?.toString(),
          initialPatientName: patientName(_a),
          initialAppointmentId: _id,
        ),
      ),
    );
    if (saved == true || mounted) await _loadPrescription();
  }

  Future<void> _call() async {
    final phone = '${apptPatient(_a)['phone'] ?? ''}'.replaceAll(' ', '');
    if (phone.isEmpty) return;
    if (!await launchUrl(Uri(scheme: 'tel', path: phone))) {
      _toast('No dialler available', error: true);
    }
  }

  Future<void> _chat() async {
    final p = apptPatient(_a);
    final patientId = '${p['_id'] ?? ''}';
    if (patientId.isEmpty || _chatLoading) return;
    setState(() => _chatLoading = true);
    try {
      final doctorId = await ref
          .read(doctorProfileProvider.notifier)
          .doctorIdOrLoad();
      final sessionId = await ref
          .read(doctorAppointmentsProvider.notifier)
          .chatSession(patientId: patientId, appointmentId: _id);
      if (!mounted) return;
      await Navigator.of(context).push(
        AppPageRoute(
          builder: (_) => AppChatScreen(
            sessionId: sessionId,
            patientName: patientName(_a),
            patientId: patientId,
            professionalId: doctorId,
            professionalType: 'doctor',
          ),
        ),
      );
    } catch (e) {
      _toast(
        e is StateError
            ? e.message
            : doctorError(e, fallback: 'Couldn’t open the chat.'),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _chatLoading = false);
    }
  }

  Future<void> _maps() async {
    final loc = _a['location'];
    Uri? uri;
    if (loc is Map && loc['coordinates'] is List) {
      final c = loc['coordinates'] as List;
      if (c.length == 2) {
        uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=${c[1]},${c[0]}',
        );
      }
    }
    final address = '${_a['address'] ?? ''}'.trim();
    uri ??= address.isEmpty
        ? null
        : Uri.parse(
            'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}',
          );
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppType.sans(fontSize: AppType.caption, color: Colors.white),
        ),
        backgroundColor: error ? AppColors.error : AppColors.textStrong,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rx = _rxFor(ref.watch(doctorPrescriptionsProvider));
    final status = apptStatus(_a);
    final start = apptStart(_a);
    final end = apptEnd(_a);
    final p = apptPatient(_a);
    final type = apptType(_a);
    final symptoms = (_a['symptoms'] is List)
        ? (_a['symptoms'] as List)
              .map((e) => '$e')
              .where((e) => e.isNotEmpty)
              .toList()
        : const <String>[];
    final reason = '${_a['reason'] ?? _a['notes'] ?? ''}'.trim();
    final address = '${_a['address'] ?? ''}'.trim();
    final started = start != null && DateTime.now().isAfter(start);
    final accent = ModuleAccent.of(context);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleSpacing: 0,
        title: Text(
          widget.noun == 'session' ? 'Session' : 'Appointment',
          style: AppType.sans(
            fontSize: AppType.title,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: ApptStatusTag(status)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                color: accent.color,
                onRefresh: _reload,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    // When — the thing a doctor checks first.
                    AppEntrance(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: accent.veryLight,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dayLabel(start),
                                    style: AppType.sans(
                                      fontSize: AppType.small,
                                      fontWeight: FontWeight.w600,
                                      color: accent.color,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    end == null || end == start
                                        ? timeLabel(start)
                                        : '${timeLabel(start)} – ${timeLabel(end)}',
                                    style: AppType.sans(
                                      fontSize: AppType.figure,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textStrong,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  ApptTypeTag(type),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  appRupees(apptFee(_a)),
                                  style: AppType.sans(
                                    fontSize: AppType.title,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textStrong,
                                  ),
                                ),
                                Text(
                                  apptPaid(_a)
                                      ? 'Paid online'
                                      : type == 'clinic'
                                      ? 'Collect at clinic'
                                      : 'Not paid yet',
                                  style: AppType.sans(
                                    fontSize: AppType.caption,
                                    fontWeight: FontWeight.w600,
                                    color: apptPaid(_a)
                                        ? accent.color
                                        : AppColors.warning,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const AppSectionTitle('Patient'),
                    AppEntrance(
                      index: 1,
                      child: AppGroup(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                            child: Row(
                              children: [
                                DoctorAvatar(name: patientName(_a), size: 42),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        patientName(_a),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppType.sans(
                                          fontSize: AppType.title,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textStrong,
                                        ),
                                      ),
                                      Text(
                                        [
                                          if (p['age'] != null)
                                            '${p['age']} yrs',
                                          if ('${p['gender'] ?? ''}'.isNotEmpty)
                                            capitalised('${p['gender']}'),
                                          if ('${p['phone'] ?? ''}'.isNotEmpty)
                                            '${p['phone']}',
                                        ].join(' · '),
                                        style: AppType.sans(
                                          fontSize: AppType.caption,
                                          color: AppColors.textTertiary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                _RoundAction(
                                  icon: LucideIcons.messageCircle,
                                  label: 'Chat with patient',
                                  loading: _chatLoading,
                                  onTap: _chat,
                                ),
                                const SizedBox(width: 6),
                                _RoundAction(
                                  icon: LucideIcons.phone,
                                  label: 'Call patient',
                                  onTap: '${p['phone'] ?? ''}'.isEmpty
                                      ? null
                                      : _call,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const AppSectionTitle('Visit'),
                    AppEntrance(
                      index: 2,
                      child: AppGroup(
                        children: [
                          _row(
                            LucideIcons.stethoscope,
                            'Symptoms',
                            symptoms.isEmpty
                                ? 'Not shared'
                                : symptoms.join(', '),
                            muted: symptoms.isEmpty,
                          ),
                          if (reason.isNotEmpty) ...[
                            const AppHairline(),
                            _row(
                              LucideIcons.notebookPen,
                              'Patient’s note',
                              reason,
                            ),
                          ],
                          if (type == 'home' && address.isNotEmpty) ...[
                            const AppHairline(),
                            InkWell(
                              onTap: _maps,
                              child: _row(
                                LucideIcons.mapPin,
                                'Visit address',
                                address,
                                trailing: Icon(
                                  LucideIcons.navigation,
                                  size: 16,
                                  color: accent.color,
                                ),
                              ),
                            ),
                          ],
                          if ('${_a['appointmentNumber'] ?? ''}'
                              .isNotEmpty) ...[
                            const AppHairline(),
                            _row(
                              LucideIcons.hash,
                              'Booking',
                              '${_a['appointmentNumber']}',
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (widget.careSection != null) ...[
                      const SizedBox(height: 20),
                      widget.careSection!(context, _a),
                    ] else if (const {
                      'confirmed',
                      'in_progress',
                      'completed',
                    }.contains(status)) ...[
                      const SizedBox(height: 20),
                      const AppSectionTitle('Prescription'),
                      AppEntrance(
                        index: 3,
                        child: AppGroup(
                          children: [
                            InkWell(
                              onTap: rx == null
                                  ? _writePrescription
                                  : () => Navigator.of(context)
                                        .push(
                                          AppPageRoute(
                                            builder: (_) =>
                                                PrescriptionDetailsScreen(
                                                  prescription: rx,
                                                ),
                                          ),
                                        )
                                        .then((_) => _loadPrescription()),
                              child: _row(
                                rx == null
                                    ? LucideIcons.filePlus2
                                    : LucideIcons.fileText,
                                rx == null
                                    ? 'Write prescription'
                                    : '${rx['prescriptionNumber'] ?? 'Prescription'}',
                                rx == null
                                    ? 'Medicines, tests and advice for this visit'
                                    : _rxSummary(rx),
                                strongTitle: true,
                                trailing: const Icon(
                                  LucideIcons.chevronRight,
                                  size: 16,
                                  color: AppColors.textDisabled,
                                ),
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
            _actionBar(status, started),
          ],
        ),
      ),
    );
  }

  String _rxSummary(Map<String, dynamic> rx) {
    final dx = rx['diagnosis'] is List
        ? (rx['diagnosis'] as List).map((e) => '$e').join(', ')
        : '';
    final meds = rx['medicines'] is List ? (rx['medicines'] as List).length : 0;
    final status = '${rx['status'] ?? ''}';
    return [
      if (status == 'draft') 'Draft',
      if (dx.isNotEmpty) dx,
      '$meds medicine${meds == 1 ? '' : 's'}',
    ].join(' · ');
  }

  Widget _row(
    IconData icon,
    String title,
    String value, {
    bool muted = false,
    bool strongTitle = false,
    Widget? trailing,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: AppColors.textTertiary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppType.sans(
                  fontSize: strongTitle ? AppType.body : AppType.caption,
                  fontWeight: strongTitle ? FontWeight.w600 : FontWeight.w500,
                  color: strongTitle
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppType.sans(
                  fontSize: strongTitle ? AppType.caption : AppType.body,
                  color: muted || strongTitle
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing],
      ],
    ),
  );

  Widget _actionBar(String status, bool started) {
    Widget bar(Widget child) => Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: child,
    );
    Widget pair(Widget left, Widget right) => Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: right),
      ],
    );

    switch (status) {
      case 'pending':
        return bar(
          pair(
            AppSecondaryButton(
              label: 'Decline',
              color: AppColors.error,
              onPressed: _busy ? null : _decline,
            ),
            AppButton(
              label: 'Accept',
              icon: LucideIcons.check,
              loading: _busy,
              onPressed: _busy ? null : _accept,
            ),
          ),
        );
      case 'confirmed':
      case 'rescheduled':
        return bar(
          pair(
            started
                ? AppSecondaryButton(
                    label: 'No-show',
                    color: AppColors.error,
                    onPressed: _busy ? null : _noShow,
                  )
                : AppSecondaryButton(
                    label: 'Cancel',
                    color: AppColors.error,
                    onPressed: _busy ? null : _cancel,
                  ),
            AppButton(
              label: apptType(_a) == 'video'
                  ? (widget.noun == 'session'
                        ? 'Start video session'
                        : 'Start video consult')
                  : (widget.noun == 'session'
                        ? 'Start session'
                        : 'Start consultation'),
              icon: apptType(_a) == 'video'
                  ? LucideIcons.video
                  : LucideIcons.stethoscope,
              loading: _busy,
              onPressed: _busy ? null : _consult,
            ),
          ),
        );
      case 'in_progress':
        return bar(
          AppButton(
            label: widget.noun == 'session'
                ? 'Continue session'
                : 'Continue consultation',
            icon: LucideIcons.stethoscope,
            onPressed: _consult,
          ),
        );
      case 'completed':
        return bar(
          AppSecondaryButton(
            label: widget.noun == 'session'
                ? 'Open session notes'
                : 'Open consultation notes',
            icon: LucideIcons.notebookText,
            onPressed: _consult,
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context).color;
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap == null || loading
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        radius: 22,
        child: Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            color: AppColors.bg,
            shape: BoxShape.circle,
          ),
          child: loading
              ? Padding(
                  padding: const EdgeInsets.all(11),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accent,
                  ),
                )
              : Icon(
                  icon,
                  size: 17,
                  color: onTap == null ? AppColors.textDisabled : accent,
                ),
        ),
      ),
    );
  }
}

/// Why the doctor is cancelling — the patient sees it. Owns its controller.
class _CancelSheet extends StatefulWidget {
  const _CancelSheet();

  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  static const _reasons = [
    'I’m unavailable at this time',
    'Emergency at the clinic',
    'Patient asked to cancel',
  ];
  String? _picked;
  final _other = TextEditingController();

  @override
  void initState() {
    super.initState();
    _other.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  String get _reason =>
      _picked == 'other' ? _other.text.trim() : (_picked ?? '');

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cancel appointment',
          style: AppType.sans(
            fontSize: AppType.title,
            fontWeight: FontWeight.w700,
            color: AppColors.textStrong,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'The patient sees this reason. A prepaid fee is handled by our refund policy.',
          style: AppType.sans(
            fontSize: AppType.caption,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 14),
        for (final r in [..._reasons, 'other'])
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: AppFilterChip(
              block: true,
              label: r == 'other' ? 'Another reason' : r,
              selected: _picked == r,
              onTap: () => setState(() => _picked = r),
            ),
          ),
        if (_picked == 'other')
          AppTextField(
            label: 'Reason',
            controller: _other,
            dense: true,
            textCapitalization: TextCapitalization.sentences,
            margin: const EdgeInsets.only(top: 6),
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: AppSecondaryButton(
                label: 'Back',
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: AppButton(
                label: 'Cancel appointment',
                onPressed: _reason.isEmpty
                    ? null
                    : () => Navigator.pop(context, _reason),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
