import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/network/api_service.dart';
import '../../features/doctor/screens/doctor_prescriptions.dart';
import '../../features/doctor/screens/prescription_details.dart';
import '../../features/doctor/widgets/doctor_ui.dart';
import '../../features/physio/screens/physio_exercise_plan_editor.dart';
import '../ui/app_ui.dart';
import 'app_web_view.dart';

/// The consultation workspace shared by doctors and physiotherapists. The
/// consultation session (not Appointment.status) drives the lifecycle: the
/// server says whether the professional can start, join or end right now.
///
/// Pops `true` once the consultation has been ended, so the caller can
/// refresh the appointment.
class ProfessionalConsultationScreen extends StatefulWidget {
  final Map<String, dynamic> appointment;

  const ProfessionalConsultationScreen({super.key, required this.appointment});

  @override
  State<ProfessionalConsultationScreen> createState() =>
      _ProfessionalConsultationScreenState();
}

class _ProfessionalConsultationScreenState
    extends State<ProfessionalConsultationScreen> {
  static const _outcomes = {
    'resolved': 'Resolved',
    'improved': 'Improved',
    'ongoing': 'Ongoing',
    'referred': 'Referred',
    'emergency_referral': 'Emergency referral',
  };

  final _api = ApiService();
  final _notes = TextEditingController();
  final _advice = TextEditingController();
  final _followUpNotes = TextEditingController();

  late Map<String, dynamic> _appointment = Map.of(widget.appointment);
  Map<String, dynamic>? _session;
  Map<String, dynamic>? _prescription;
  List<String> _complaints = [];
  List<String> _diagnoses = [];
  String _outcome = 'unknown';
  bool _followUpRequired = false;
  DateTime? _followUpDate;

  bool _loading = true;
  bool _busy = false;
  bool _ended = false;
  bool _dirty = false;
  String? _error;
  bool _diagnosisMissing = false;

  String get _id => '${_appointment['_id'] ?? ''}';
  bool get _isVideo => apptType(_appointment) == 'video';

  /// Physio sessions get a home exercise programme instead of a medicine
  /// prescription, and "session" wording.
  bool get _isPhysio =>
      '${_appointment['professionalType'] ?? ''}' == 'physio' ||
      _appointment['physioId'] != null;

  @override
  void initState() {
    super.initState();
    for (final c in [_notes, _advice, _followUpNotes]) {
      c.addListener(_markDirty);
    }
    _load();
  }

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  @override
  void dispose() {
    _notes.dispose();
    _advice.dispose();
    _followUpNotes.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final res = await _api.getConsultationByAppointment(_id);
      _merge(res.data, hydrate: true);
      await _loadPrescription();
      _error = null;
    } catch (e) {
      _error = doctorError(e, fallback: 'Couldn’t load the consultation.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Never fatal: a missing or unreadable prescription just shows as none.
  Future<void> _loadPrescription() async {
    try {
      final res = await _api.getPrescriptionByAppointment(_id);
      final raw = res.data is Map ? res.data['prescription'] : null;
      _prescription = raw is Map ? Map<String, dynamic>.from(raw) : null;
    } catch (_) {
      _prescription = null;
    }
  }

  void _merge(dynamic raw, {bool hydrate = false}) {
    if (raw is! Map) return;
    if (raw['appointment'] is Map) {
      _appointment = Map<String, dynamic>.from(raw['appointment'] as Map);
    }
    if (raw['session'] is Map) {
      _session = Map<String, dynamic>.from(raw['session'] as Map);
      if (hydrate || !_dirty) _hydrate(_session!['clinicalSummary']);
    }
  }

  void _hydrate(dynamic raw) {
    if (raw is! Map) return;
    List<String> list(dynamic v) => v is List
        ? v.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList()
        : '${v ?? ''}'
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
    _complaints = list(raw['chiefComplaint']);
    _diagnoses = list(raw['diagnosis']);
    _notes.text = '${raw['notes'] ?? ''}';
    _advice.text = '${raw['advice'] ?? ''}';
    _followUpNotes.text = '${raw['followUpNotes'] ?? ''}';
    _outcome = '${raw['outcome'] ?? 'unknown'}';
    _followUpRequired = raw['followUpRequired'] == true;
    _followUpDate = DateTime.tryParse(
      '${raw['followUpDate'] ?? ''}',
    )?.toLocal();
    _dirty = false;
  }

  Map<String, dynamic> _summary() => {
    'chiefComplaint': _complaints,
    'diagnosis': _diagnoses,
    'notes': _notes.text.trim(),
    'advice': _advice.text.trim(),
    'outcome': _outcome,
    'followUpRequired': _followUpRequired,
    if (_followUpRequired && _followUpDate != null)
      'followUpDate': _followUpDate!.toUtc().toIso8601String(),
    'followUpNotes': _followUpNotes.text.trim(),
  };

  Future<void> _run(Future<void> Function() op, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await op();
      _toast(done);
    } catch (e) {
      _toast(doctorError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() => _run(() async {
    final res = await _api.startConsultation(_id);
    _merge(res.data);
  }, 'Consultation started');

  Future<void> _joinVideo() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final res = await _api.joinConsultation(_id);
      final url = res.data is Map ? '${res.data['joinUrl'] ?? ''}' : '';
      if (url.isEmpty) throw StateError('The video room isn’t ready yet.');
      if (!mounted) return;
      await Navigator.of(context).push(
        AppPageRoute(
          builder: (_) => AppWebView(
            url: url,
            title: 'Video · ${patientName(_appointment)}',
          ),
        ),
      );
      try {
        await _api.leaveConsultation(_id);
      } catch (_) {}
      await _load(quiet: true);
    } catch (e) {
      _toast(
        e is DioException
            ? doctorErrorMessage(e)
            : '$e'.replaceFirst('Bad state: ', ''),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _run(() async {
    final res = await _api.updateConsultationSummary(_id, _summary());
    _merge(res.data);
    _dirty = false;
  }, 'Notes saved');

  Future<void> _end() async {
    if (_diagnoses.isEmpty) {
      setState(() => _diagnosisMissing = true);
      _toast('Add at least one diagnosis before ending.', error: true);
      return;
    }
    final ok = await AppModal.confirm(
      context,
      title: _isPhysio ? 'End session?' : 'End consultation?',
      message:
          'The visit is marked completed and these notes are locked. You can still write the prescription afterwards.',
      confirmLabel: (_isPhysio ? 'End session' : 'End consultation'),
      cancelLabel: 'Keep working',
      destructive: false,
    );
    if (!ok) return;
    await _run(() async {
      final res = await _api.endConsultation(_id, _summary());
      _merge(res.data, hydrate: true);
      _ended = true;
    }, 'Consultation completed');
  }

  Future<void> _openPrescription() async {
    if (_isPhysio) {
      final p = apptPatient(_appointment);
      await Navigator.of(context).push<bool>(
        AppPageRoute(
          builder: (_) => PhysioExercisePlanEditor(
            patientId: '${p['_id'] ?? ''}',
            patientName: patientName(_appointment),
            appointmentId: _id,
          ),
        ),
      );
      return;
    }
    final rx = _prescription;
    if (rx != null) {
      await Navigator.of(context).push(
        AppPageRoute(
          builder: (_) => PrescriptionDetailsScreen(prescription: rx),
        ),
      );
    } else {
      final p = apptPatient(_appointment);
      await Navigator.of(context).push<bool>(
        AppPageRoute(
          builder: (_) => CreatePrescriptionScreen(
            initialPatientId: p['_id']?.toString(),
            initialPatientName: patientName(_appointment),
            initialAppointmentId: _id,
          ),
        ),
      );
    }
    await _loadPrescription();
    if (mounted) setState(() {});
  }

  Future<void> _pickFollowUp() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      initialDate: _followUpDate ?? now.add(const Duration(days: 7)),
      helpText: 'Follow-up date',
    );
    if (picked != null && mounted) {
      setState(() {
        _followUpDate = picked;
        _dirty = true;
      });
    }
  }

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: AppType.sans(fontSize: AppType.caption, color: Colors.white),
        ),
        backgroundColor: error ? AppColors.error : AppColors.textStrong,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ─────────────────────────── State of the session ───────────────────────

  String get _status => '${_session?['status'] ?? 'scheduled'}';
  bool get _isEnded =>
      _ended || _status == 'ended' || apptStatus(_appointment) == 'completed';
  bool get _canStart => _session?['canStart'] == true;
  bool get _canJoin => _session?['canJoin'] == true;
  bool get _canEnd => _session?['canEnd'] == true;
  bool get _paymentRequired => _session?['paymentRequired'] == true;

  /// One line saying where things stand and why the button is (or isn't)
  /// there — "Status: scheduled" used to leave doctors guessing.
  ({String title, String detail, IconData icon, Color color}) _stage() {
    final accent = ModuleAccent.of(context).color;
    if (_isEnded) {
      return (
        title: 'Consultation completed',
        detail: 'Notes are locked. Write or review the prescription below.',
        icon: LucideIcons.circleCheckBig,
        color: accent,
      );
    }
    if (_status == 'cancelled' || _status == 'no_show') {
      return (
        title: _status == 'no_show' ? 'Marked as no-show' : 'Cancelled',
        detail: 'This visit can’t be started.',
        icon: LucideIcons.ban,
        color: AppColors.error,
      );
    }
    if (_status == 'in_progress' || _status == 'professional_ready') {
      return (
        title: 'In consultation',
        detail: _isVideo
            ? 'Rejoin the video room any time. End when you’re done.'
            : 'Write your notes, then end the consultation.',
        icon: LucideIcons.activity,
        color: accent,
      );
    }
    if (_paymentRequired) {
      return (
        title: 'Waiting for payment',
        detail: 'The patient has to pay before a video consultation can start.',
        icon: LucideIcons.wallet,
        color: AppColors.warning,
      );
    }
    if (_status == 'patient_waiting') {
      return (
        title: 'Patient is waiting',
        detail: 'Start the consultation when you’re ready.',
        icon: LucideIcons.userCheck,
        color: AppColors.warning,
      );
    }
    final start = apptStart(_appointment);
    if (!_canStart && start != null && DateTime.now().isBefore(start)) {
      final opens = start.subtract(const Duration(minutes: 15));
      return (
        title: 'Scheduled · ${dayLabel(start)} ${timeLabel(start)}',
        detail: 'You can start from ${timeLabel(opens)}, 15 minutes before.',
        icon: LucideIcons.clock,
        color: AppColors.textSecondary,
      );
    }
    return (
      title: 'Ready to start',
      detail: _isVideo
          ? 'Start, then join the video room.'
          : 'Start when the patient is with you.',
      icon: LucideIcons.playCircle,
      color: accent,
    );
  }

  // ─────────────────────────── Build ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_isEnded);
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
          titleSpacing: 0,
          title: Text(
            _isPhysio ? 'Session' : 'Consultation',
            style: AppType.sans(
              fontSize: AppType.title,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _busy ? null : () => _load(quiet: true),
              icon: const Icon(LucideIcons.rotateCw, size: 19),
            ),
          ],
        ),
        body: SafeArea(
          child: _loading
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: const [AppDetailSkeleton(rows: 6)],
                )
              : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: AppErrorBanner(message: _error!, onRetry: _load),
                )
              : Column(
                  children: [
                    Expanded(child: _content()),
                    _actionBar(),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _content() {
    final stage = _stage();
    final p = apptPatient(_appointment);
    final locked = _isEnded;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      children: [
        Row(
          children: [
            DoctorAvatar(name: patientName(_appointment), size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patientName(_appointment),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.sans(
                      fontSize: AppType.heading,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textStrong,
                    ),
                  ),
                  Text(
                    [
                      apptTypeInfo(apptType(_appointment)).label,
                      timeLabel(apptStart(_appointment)),
                      if (p['age'] != null) '${p['age']} yrs',
                      if ('${p['gender'] ?? ''}'.isNotEmpty)
                        capitalised('${p['gender']}'),
                    ].join(' · '),
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: AppMotion.medium,
          child: Container(
            key: ValueKey(stage.title),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(stage.icon, size: 18, color: stage.color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stage.title,
                        style: AppType.sans(
                          fontSize: AppType.body,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textStrong,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        stage.detail,
                        style: AppType.sans(
                          fontSize: AppType.small,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        AppSectionTitle(locked ? 'Clinical notes · locked' : 'Clinical notes'),
        _ChipsInput(
          label: 'Chief complaints',
          hint: 'e.g. Fever, Cough — press enter after each',
          values: _complaints,
          enabled: !locked,
          onChanged: (v) => setState(() {
            _complaints = v;
            _dirty = true;
          }),
        ),
        const SizedBox(height: 14),
        _ChipsInput(
          label: 'Diagnosis *',
          hint: 'e.g. Acute pharyngitis',
          values: _diagnoses,
          enabled: !locked,
          error: _diagnosisMissing && _diagnoses.isEmpty
              ? 'Add at least one diagnosis to end the consultation'
              : null,
          onChanged: (v) => setState(() {
            _diagnoses = v;
            _dirty = true;
          }),
        ),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Examination & notes',
          controller: _notes,
          hint: 'Findings, vitals, observations',
          maxLines: 4,
          readOnly: locked,
          textCapitalization: TextCapitalization.sentences,
          margin: const EdgeInsets.only(bottom: 14),
        ),
        AppTextField(
          label: 'Advice for the patient',
          controller: _advice,
          hint: 'Rest, diet, precautions',
          maxLines: 3,
          readOnly: locked,
          textCapitalization: TextCapitalization.sentences,
          margin: const EdgeInsets.only(bottom: 14),
        ),
        Text(
          'Outcome',
          style: AppType.sans(
            fontSize: AppType.caption,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final e in _outcomes.entries)
              AppFilterChip(
                label: e.value,
                selected: _outcome == e.key,
                onTap: locked
                    ? () {}
                    : () => setState(() {
                        _outcome = _outcome == e.key ? 'unknown' : e.key;
                        _dirty = true;
                      }),
              ),
          ],
        ),
        const SizedBox(height: 18),
        AppGroup(
          children: [
            AppSwitchRow(
              label: 'Follow-up needed',
              subtitle: _followUpRequired && _followUpDate != null
                  ? 'On ${DateFormat('EEE d MMM').format(_followUpDate!)}'
                  : 'Ask the patient to come back',
              value: _followUpRequired,
              enabled: !locked,
              onChanged: (v) => setState(() {
                _followUpRequired = v;
                _dirty = true;
              }),
            ),
          ],
        ),
        if (_followUpRequired) ...[
          const SizedBox(height: 12),
          AppPickerField(
            label: 'Follow-up date',
            valueText: _followUpDate == null
                ? 'Select date'
                : DateFormat('EEE d MMM yyyy').format(_followUpDate!),
            onTap: locked ? () {} : _pickFollowUp,
            margin: const EdgeInsets.only(bottom: 12),
          ),
          AppTextField(
            label: 'Follow-up instructions',
            controller: _followUpNotes,
            hint: 'What to bring or check next time',
            maxLines: 2,
            readOnly: locked,
            margin: EdgeInsets.zero,
          ),
        ],
        const SizedBox(height: 22),
        AppSectionTitle(_isPhysio ? 'Home programme' : 'Prescription'),
        AppGroup(
          children: [
            InkWell(
              onTap: _busy ? null : _openPrescription,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Row(
                  children: [
                    Icon(
                      _prescription == null
                          ? LucideIcons.filePlus2
                          : LucideIcons.fileText,
                      size: 17,
                      color: ModuleAccent.of(context).color,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isPhysio
                                ? 'Assign exercises'
                                : _prescription == null
                                ? 'Write prescription'
                                : '${_prescription!['prescriptionNumber'] ?? 'Prescription'}',
                            style: AppType.sans(
                              fontSize: AppType.body,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            _isPhysio
                                ? 'Sets, reps and hold for practice at home'
                                : _prescription == null
                                ? 'Medicines, tests and advice for this visit'
                                : '${_prescription!['status'] == 'draft' ? 'Draft — not sent yet' : 'Sent to patient'} · ${(_prescription!['medicines'] is List) ? (_prescription!['medicines'] as List).length : 0} medicines',
                            style: AppType.sans(
                              fontSize: AppType.caption,
                              color: _prescription?['status'] == 'draft'
                                  ? AppColors.warning
                                  : AppColors.textTertiary,
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
            ),
          ],
        ),
      ],
    );
  }

  Widget _actionBar() {
    Widget bar(Widget child) => Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: child,
    );

    if (_isEnded) {
      return bar(
        AppButton(
          label: _isPhysio
              ? 'Assign exercises'
              : _prescription == null
              ? 'Write prescription'
              : 'View prescription',
          icon: LucideIcons.fileText,
          onPressed: _busy ? null : _openPrescription,
        ),
      );
    }

    final save = AppSecondaryButton(
      label: _dirty ? 'Save notes' : 'Saved',
      icon: LucideIcons.save,
      onPressed: _busy || !_dirty ? null : _save,
    );

    if (_canEnd || _canJoin) {
      return bar(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isVideo && _canJoin) ...[
              AppButton(
                label: 'Join video room',
                icon: LucideIcons.video,
                loading: _busy,
                onPressed: _busy ? null : _joinVideo,
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(child: save),
                const SizedBox(width: 10),
                Expanded(
                  child: _isVideo && _canJoin
                      ? AppSecondaryButton(
                          label: (_isPhysio
                              ? 'End session'
                              : 'End consultation'),
                          color: AppColors.error,
                          onPressed: _busy || !_canEnd ? null : _end,
                        )
                      : AppButton(
                          label: (_isPhysio
                              ? 'End session'
                              : 'End consultation'),
                          icon: LucideIcons.circleCheckBig,
                          loading: _busy,
                          onPressed: _busy || !_canEnd ? null : _end,
                        ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return bar(
      Row(
        children: [
          Expanded(child: save),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: AppButton(
              label: 'Start consultation',
              icon: LucideIcons.play,
              loading: _busy,
              onPressed: _busy || !_canStart ? null : _start,
            ),
          ),
        ],
      ),
    );
  }
}

/// A list of short terms entered one at a time, shown as removable chips.
/// Owns its text controller.
class _ChipsInput extends StatefulWidget {
  final String label;
  final String hint;
  final List<String> values;
  final bool enabled;
  final String? error;
  final ValueChanged<List<String>> onChanged;
  const _ChipsInput({
    required this.label,
    required this.hint,
    required this.values,
    required this.onChanged,
    this.enabled = true,
    this.error,
  });

  @override
  State<_ChipsInput> createState() => _ChipsInputState();
}

class _ChipsInputState extends State<_ChipsInput> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _add() {
    final parts = _text.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !widget.values.contains(e));
    if (parts.isEmpty) return;
    widget.onChanged([...widget.values, ...parts]);
    _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: AppType.sans(
            fontSize: AppType.caption,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        if (widget.values.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final v in widget.values)
                Container(
                  padding: EdgeInsets.fromLTRB(
                    10,
                    6,
                    widget.enabled ? 4 : 10,
                    6,
                  ),
                  decoration: BoxDecoration(
                    color: accent.veryLight,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        v,
                        style: AppType.sans(
                          fontSize: AppType.small,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textStrong,
                        ),
                      ),
                      if (widget.enabled)
                        InkResponse(
                          radius: 14,
                          onTap: () => widget.onChanged(
                            widget.values.where((e) => e != v).toList(),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                              LucideIcons.x,
                              size: 13,
                              color: accent.color,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (widget.enabled)
          AppTextField(
            label: '',
            controller: _text,
            hint: widget.hint,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _add(),
            errorText: widget.error,
            margin: EdgeInsets.zero,
            trailing: IconButton(
              tooltip: 'Add',
              icon: Icon(LucideIcons.plus, size: 18, color: accent.color),
              onPressed: _add,
            ),
          )
        else if (widget.values.isEmpty)
          Text(
            '—',
            style: AppType.sans(
              fontSize: AppType.body,
              color: AppColors.textTertiary,
            ),
          ),
      ],
    );
  }
}
