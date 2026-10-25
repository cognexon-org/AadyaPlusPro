import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../providers/doctor_prescriptions_provider.dart';
import '../widgets/doctor_ui.dart';
import '../widgets/prescription_appointment_sheet.dart';
import '../widgets/prescription_medicine_row.dart';
import '../widgets/prescription_ui.dart';
import 'prescription_details.dart';

// ═════════════════════════════════ List ═════════════════════════════════

/// Every prescription this doctor has written: drafts to finish, issued ones
/// to share, cancelled ones for the record.
class DoctorPrescriptions extends ConsumerStatefulWidget {
  const DoctorPrescriptions({super.key});

  @override
  ConsumerState<DoctorPrescriptions> createState() =>
      _DoctorPrescriptionsState();
}

class _DoctorPrescriptionsState extends ConsumerState<DoctorPrescriptions> {
  static const _filters = [
    ('all', 'All'),
    ('draft', 'Drafts'),
    ('issued', 'Issued'),
    ('cancelled', 'Cancelled'),
  ];

  final _search = TextEditingController();
  Timer? _debounce;

  String _filter = 'all';
  String _query = '';

  DoctorPrescriptionsNotifier get _rx =>
      ref.read(doctorPrescriptionsProvider.notifier);

  @override
  void initState() {
    super.initState();
    // Already in memory: show it and re-read quietly.
    Future.microtask(() {
      if (!mounted) return;
      final s = ref.read(doctorPrescriptionsProvider);
      if (s.hasLoaded) {
        _rx.load(silent: true);
      } else {
        _rx.load();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = v.trim().toLowerCase());
    });
  }

  int _count(List<Map<String, dynamic>> all, String f) =>
      f == 'all' ? all.length : all.where((r) => rxStatus(r) == f).length;

  List<Map<String, dynamic>> _visible(List<Map<String, dynamic>> all) =>
      all.where((rx) {
        if (_filter != 'all' && rxStatus(rx) != _filter) return false;
        if (_query.isEmpty) return true;
        return rxPatientName(rx).toLowerCase().contains(_query) ||
            '${rx['prescriptionNumber'] ?? ''}'.toLowerCase().contains(_query);
      }).toList();

  // Saves, issues and cancels land in the provider, so the list is current
  // when these return without a reload.
  Future<void> _create() => Navigator.of(
    context,
  ).push<bool>(AppPageRoute(builder: (_) => const CreatePrescriptionScreen()));

  Future<void> _open(Map<String, dynamic> rx) => Navigator.of(context).push(
    AppPageRoute(builder: (_) => PrescriptionDetailsScreen(prescription: rx)),
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(doctorPrescriptionsProvider);
    final all = state.items;
    final error = state.error;
    final loading = !state.hasLoaded && error == null;
    final visible = _visible(all);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: rxAppBar(context, title: 'Prescriptions'),
      floatingActionButton: AppFab(
        label: 'New prescription',
        icon: LucideIcons.plus,
        onPressed: _create,
      ),
      body: RefreshIndicator(
        color: ModuleAccent.of(context).color,
        onRefresh: () => _rx.load(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
          children: [
            AppSearchField(
              controller: _search,
              hint: 'Search patient or Rx number',
              onChanged: _onSearch,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final (key, label) = _filters[i];
                  final n = _count(all, key);
                  return AppFilterChip(
                    label: loading || n == 0 ? label : '$label  $n',
                    selected: _filter == key,
                    onTap: () => setState(() => _filter = key),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            if (error != null)
              AppErrorBanner(message: error, onRetry: () => _rx.load()),
            if (loading)
              const AppListSkeleton(count: 5)
            else if (visible.isEmpty && error == null)
              AppEmptyState(
                icon: LucideIcons.fileText,
                text: all.isEmpty
                    ? 'No prescriptions yet.\nWrite one after a consultation, or tap New prescription.'
                    : _query.isNotEmpty
                    ? 'No prescriptions match “${_search.text.trim()}”.'
                    : 'Nothing in ${_filters.firstWhere((f) => f.$1 == _filter).$2.toLowerCase()}.',
              )
            else
              for (final (i, rx) in visible.indexed)
                Padding(
                  key: ValueKey(rxId(rx)),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppEntrance(
                    index: i,
                    child: _RxRow(rx: rx, onTap: () => _open(rx)),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _RxRow extends StatelessWidget {
  final Map<String, dynamic> rx;
  final VoidCallback onTap;
  const _RxRow({required this.rx, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = rxStatus(rx);
    final name = rxPatientName(rx);
    final diagnosis = rxStrings(rx['diagnosis']);
    final meds = rxMaps(rx['medicines']).length;
    final muted = status == 'cancelled' || status == 'superseded';
    final summary = [
      if (diagnosis.isNotEmpty)
        diagnosis.length > 1
            ? '${diagnosis.first} +${diagnosis.length - 1}'
            : diagnosis.first
      else
        'No diagnosis yet',
      meds == 0 ? 'No medicines' : '$meds medicine${meds == 1 ? '' : 's'}',
    ].join(' · ');

    return AppPressable(
      scale: 0.985,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DoctorAvatar(name: name, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.sans(
                            fontSize: AppType.title,
                            fontWeight: FontWeight.w700,
                            color: muted
                                ? AppColors.textSecondary
                                : AppColors.textStrong,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      RxStatusTag(status),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${rxNumber(rx)} · ${dayLabel(rxWhen(rx))}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.sans(
                      fontSize: AppType.small,
                      color: diagnosis.isEmpty
                          ? AppColors.textTertiary
                          : AppColors.textSecondary,
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
}

// ════════════════════════════════ Editor ════════════════════════════════

/// Writes a new prescription, or edits a draft ([prescription]).
///
/// Opened from an appointment or consultation with the `initial*` ids, the
/// patient is fixed; opened from the list, the doctor picks the appointment.
/// Pops `true` once saved.
class CreatePrescriptionScreen extends ConsumerStatefulWidget {
  /// Legacy: once shown inside a tab. When true the screen resets after a
  /// save instead of closing.
  final bool embedded;
  final String? initialPatientId;
  final String? initialPatientName;
  final String? initialAppointmentId;

  /// An existing draft (or issued prescription, to revise) to edit.
  final Map<String, dynamic>? prescription;

  const CreatePrescriptionScreen({
    this.embedded = false,
    this.initialPatientId,
    this.initialPatientName,
    this.initialAppointmentId,
    this.prescription,
    super.key,
  });

  @override
  ConsumerState<CreatePrescriptionScreen> createState() =>
      _CreatePrescriptionScreenState();
}

class _CreatePrescriptionScreenState
    extends ConsumerState<CreatePrescriptionScreen> {
  static const _testSuggestions = [
    'CBC',
    'Blood sugar (fasting)',
    'HbA1c',
    'Lipid profile',
    'Thyroid profile',
    'Urine routine',
  ];

  final _scroll = ScrollController();
  final _patientKey = GlobalKey();
  final _diagnosisKey = GlobalKey();
  final _medicinesKey = GlobalKey();

  final _advice = TextEditingController();
  final _notes = TextEditingController();
  final _followUpNote = TextEditingController();

  // Patient / appointment
  String? _appointmentId;
  String _patientName = '';
  String _patientMeta = '';
  String _visitLine = '';
  List<String> _apptSymptoms = const [];

  /// The prescription this editor saves into, once there is one: the draft
  /// being edited, the draft created by an earlier attempt, or the issued
  /// one being revised.
  Map<String, dynamic>? _current;

  List<String> _diagnosis = [];
  List<String> _symptoms = [];
  List<String> _tests = [];
  Map<String, Map<String, dynamic>> _testSource = {};
  List<Map<String, dynamic>> _adviceSource = [];
  final List<RxMedicineDraft> _meds = [];
  DateTime? _followUp;

  bool _checking = false;
  String? _saving; // 'draft' | 'issue'
  String? _error;
  bool _tried = false;
  bool _issueTried = false;
  bool _lastIssue = false;

  DoctorPrescriptionsNotifier get _rx =>
      ref.read(doctorPrescriptionsProvider.notifier);

  bool get _locked =>
      widget.prescription != null || widget.initialAppointmentId != null;

  @override
  void initState() {
    super.initState();
    final rx = widget.prescription;
    if (rx != null) {
      _fill(rx);
      final appt = rxMap(rx['appointmentId']);
      _appointmentId = appt.isNotEmpty
          ? '${appt['_id']}'
          : '${rx['appointmentId'] ?? ''}';
      _patientName = rxPatientName(rx);
      _patientMeta = rxPatientMeta(rxPatient(rx));
      if (appt.isNotEmpty) _visitLine = _visit(appt);
    } else {
      _appointmentId = widget.initialAppointmentId;
      _patientName = (widget.initialPatientName ?? '').trim();
      if (_appointmentId != null && _appointmentId!.isNotEmpty) {
        _checking = true;
        _checkExisting(_appointmentId!);
      }
    }
    if (_meds.isEmpty) _addMedicine(rebuild: false);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _advice.dispose();
    _notes.dispose();
    _followUpNote.dispose();
    for (final m in _meds) {
      m.dispose();
    }
    super.dispose();
  }

  // ─────────────────────────── Data ───────────────────────────

  static String _visit(Map<String, dynamic> appt) {
    final start = apptStart(appt);
    return [
      if (start != null) '${dayLabel(start)}, ${timeLabel(start)}',
      apptTypeInfo(apptType(appt)).label,
    ].join(' · ');
  }

  /// Loads a saved prescription's contents into the form.
  void _fill(Map<String, dynamic> rx) {
    _current = rx;
    _diagnosis = rxStrings(rx['diagnosis']);
    _symptoms = rxStrings(rx['symptoms']);
    final tests = rxMaps(rx['labTests']);
    _tests = [
      for (final t in tests)
        if ('${t['testName'] ?? ''}'.trim().isNotEmpty)
          '${t['testName']}'.trim(),
    ];
    _testSource = {
      for (final t in tests) '${t['testName'] ?? ''}'.trim().toLowerCase(): t,
    };
    _adviceSource = rxMaps(rx['advice']);
    _advice.text = _adviceSource
        .map((a) => '${a['advice'] ?? ''}'.trim())
        .where((a) => a.isNotEmpty)
        .join('\n');
    _notes.text = '${rx['notes'] ?? ''}'.trim();
    _followUp = rxDate(rx['followUpDate']);
    _followUpNote.text = '${rx['followUpInstructions'] ?? ''}'.trim();
    for (final m in _meds) {
      m.dispose();
    }
    _meds.clear();
    for (final m in rxMaps(rx['medicines'])) {
      _meds.add(_watch(RxMedicineDraft(m)));
    }
    final p = rxPatient(rx);
    if (p.isNotEmpty) {
      _patientName = rxPatientName(rx);
      _patientMeta = rxPatientMeta(p);
    }
  }

  bool get _formEmpty =>
      _diagnosis.isEmpty &&
      _symptoms.isEmpty &&
      _tests.isEmpty &&
      _advice.text.trim().isEmpty &&
      _notes.text.trim().isEmpty &&
      _meds.every((m) => m.isBlank);

  /// An appointment can have only one current (draft or issued)
  /// prescription. Find it so saving continues it instead of hitting 409.
  Future<void> _checkExisting(String appointmentId) async {
    try {
      final rx = await _rx.forAppointment(appointmentId);
      if (!mounted || appointmentId != _appointmentId) return;
      setState(() {
        if (rx != null && {'draft', 'issued'}.contains(rxStatus(rx))) {
          if (_formEmpty) {
            _fill(rx);
            if (_meds.isEmpty) _addMedicine(rebuild: false);
          } else {
            _current = rx;
          }
        }
        _checking = false;
      });
    } catch (e) {
      // 404 just means there's nothing yet.
      if (!mounted) return;
      setState(() => _checking = false);
    }
    // The patient's details come with the appointment.
    _loadAppointment(appointmentId);
  }

  Future<void> _loadAppointment(String id) async {
    if (_visitLine.isNotEmpty && _patientMeta.isNotEmpty) return;
    try {
      final appt = await _rx.appointment(id);
      if (!mounted || appt == null || id != _appointmentId) return;
      setState(() => _useAppointment(appt));
    } catch (_) {
      // Name from the caller is enough to write against.
    }
  }

  void _useAppointment(Map<String, dynamic> appt) {
    final p = apptPatient(appt);
    if (p.isNotEmpty) {
      _patientName = patientName(appt);
      _patientMeta = rxPatientMeta(p);
    }
    _visitLine = _visit(appt);
    _apptSymptoms = rxStrings(appt['symptoms']);
  }

  Future<void> _pickAppointment() async {
    final appt = await showRxAppointmentPicker(context);
    if (appt == null || !mounted) return;
    final id = '${appt['_id']}';
    setState(() {
      _appointmentId = id;
      _current = null;
      _useAppointment(appt);
      _checking = true;
      _error = null;
    });
    _checkExisting(id);
  }

  RxMedicineDraft _watch(RxMedicineDraft d) {
    d.name.addListener(() {
      if (d.nameError != null && d.name.text.trim().isNotEmpty && mounted) {
        setState(() => d.nameError = null);
      }
    });
    return d;
  }

  void _addMedicine({bool rebuild = true}) {
    final d = _watch(RxMedicineDraft());
    if (rebuild) {
      setState(() => _meds.add(d));
    } else {
      _meds.add(d);
    }
  }

  void _removeMedicine(RxMedicineDraft d) {
    setState(() => _meds.remove(d));
    // Dispose after the row has left the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) => d.dispose());
  }

  // ─────────────────────────── Save ───────────────────────────

  String? get _patientError => _tried && (_appointmentId ?? '').isEmpty
      ? 'Choose the appointment this prescription is for.'
      : null;

  String? get _diagnosisError => _issueTried && _diagnosis.isEmpty
      ? 'Add at least one diagnosis to issue.'
      : null;

  bool _validate({required bool issue}) {
    _tried = true;
    _issueTried = issue;
    var firstKey = (_appointmentId ?? '').isEmpty ? _patientKey : null;
    if (issue && _diagnosis.isEmpty) firstKey ??= _diagnosisKey;
    for (final m in _meds) {
      m.nameError = !m.isBlank && m.name.text.trim().isEmpty
          ? 'Enter the medicine name.'
          : null;
      if (m.nameError != null) firstKey ??= _medicinesKey;
    }
    setState(() {});
    if (firstKey?.currentContext != null) {
      Scrollable.ensureVisible(
        firstKey!.currentContext!,
        duration: AppMotion.medium,
        curve: AppMotion.enter,
        alignment: 0.05,
      );
    }
    return firstKey == null;
  }

  Map<String, dynamic> _payload() {
    final adviceLines = _advice.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return {
      'diagnosis': _diagnosis,
      'symptoms': _symptoms,
      'notes': _notes.text.trim(),
      'medicines': [
        for (final m in _meds)
          if (!m.isBlank) m.toJson(),
      ],
      'labTests': [
        for (final t in _tests)
          {...?_testSource[t.toLowerCase()], 'testName': t},
      ],
      'advice': [
        for (final (i, line) in adviceLines.indexed)
          {if (i < _adviceSource.length) ..._adviceSource[i], 'advice': line},
      ],
      'followUpDate': _followUp == null
          ? null
          : DateTime(
              _followUp!.year,
              _followUp!.month,
              _followUp!.day,
              12,
            ).toIso8601String(),
      'followUpInstructions': _followUpNote.text.trim(),
    };
  }

  Future<void> _save({required bool issue}) async {
    if (_saving != null) return;
    FocusScope.of(context).unfocus();
    if (!_validate(issue: issue)) return;
    setState(() {
      _saving = issue ? 'issue' : 'draft';
      _lastIssue = issue;
      _error = null;
    });
    final payload = _payload();
    try {
      // Kept before issuing so a retry issues the draft already created.
      final rx = _current = await _rx.saveDraft(
        payload,
        appointmentId: _appointmentId,
        current: _current,
      );
      if (issue) _current = await _rx.issue(rxId(rx));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.textStrong,
          content: Text(
            issue
                ? 'Prescription issued. The patient has been notified.'
                : 'Draft saved.',
            style: AppType.sans(fontSize: AppType.caption, color: Colors.white),
          ),
        ),
      );
      if (widget.embedded) {
        _reset();
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = doctorError(
          e,
          fallback: issue
              ? 'Couldn’t issue the prescription.'
              : 'Couldn’t save the draft.',
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  void _reset() {
    setState(() {
      _current = null;
      if (widget.initialAppointmentId == null) {
        _appointmentId = null;
        _patientName = '';
        _patientMeta = '';
        _visitLine = '';
      }
      _diagnosis = [];
      _symptoms = [];
      _tests = [];
      _advice.clear();
      _notes.clear();
      _followUp = null;
      _followUpNote.clear();
      for (final m in _meds) {
        m.dispose();
      }
      _meds.clear();
      _addMedicine(rebuild: false);
      _tried = false;
      _issueTried = false;
    });
  }

  Future<void> _pickFollowUp() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _followUp ?? now.add(const Duration(days: 7)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _followUp = picked);
  }

  // ─────────────────────────── Build ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final editing = _current != null && rxStatus(_current!) == 'draft';
    final revising = _current != null && rxStatus(_current!) == 'issued';
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: rxAppBar(
        context,
        title: editing
            ? 'Edit draft'
            : revising
            ? 'Revise prescription'
            : 'Write prescription',
        subtitle: _patientName.isEmpty ? null : _patientName,
      ),
      body: Column(
        children: [
          Expanded(
            child: _checking
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: const [AppFormSkeleton(fields: 6)],
                  )
                : GestureDetector(
                    onTap: () => FocusScope.of(context).unfocus(),
                    behavior: HitTestBehavior.translucent,
                    child: ListView(
                      controller: _scroll,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                      children: _form(editing: editing, revising: revising),
                    ),
                  ),
          ),
          RxBottomBar(
            above: _error == null
                ? null
                : AppErrorBanner(
                    message: _error!,
                    onRetry: () => _save(issue: _lastIssue),
                  ),
            child: Row(
              children: [
                Expanded(
                  child: AppSecondaryButton(
                    label: _saving == 'draft' ? 'Saving…' : 'Save draft',
                    icon: LucideIcons.save,
                    onPressed: _saving != null || _checking
                        ? null
                        : () => _save(issue: false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppButton(
                    label: 'Issue',
                    icon: LucideIcons.send,
                    loading: _saving == 'issue',
                    onPressed: _saving != null || _checking
                        ? null
                        : () => _save(issue: true),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _form({required bool editing, required bool revising}) {
    final gap = const SizedBox(height: 24);
    return [
      if (editing || revising) ...[
        _Note(
          icon: revising ? LucideIcons.history : LucideIcons.filePen,
          text: revising
              ? 'This visit already has ${rxNumber(_current!)} issued. Issuing again replaces it with this revised version.'
              : 'Continuing the saved draft ${rxNumber(_current!)}.',
        ),
        const SizedBox(height: 16),
      ],

      // Patient
      KeyedSubtree(
        key: _patientKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSectionTitle(
              'Patient',
              action: !_locked && (_appointmentId ?? '').isNotEmpty
                  ? 'Change'
                  : null,
              onAction: _pickAppointment,
            ),
            if ((_appointmentId ?? '').isNotEmpty)
              AppGroup(
                children: [
                  RxPatientRow(
                    name: _patientName.isEmpty ? 'Patient' : _patientName,
                    meta: [
                      _patientMeta,
                      _visitLine,
                    ].where((e) => e.isNotEmpty).join('\n'),
                  ),
                ],
              )
            else ...[
              AppPickerField(
                label: 'Appointment',
                valueText: 'Choose a patient’s appointment',
                icon: LucideIcons.userSearch,
                required: true,
                margin: EdgeInsets.zero,
                onTap: _pickAppointment,
              ),
              if (_patientError != null) _FieldError(_patientError!),
            ],
          ],
        ),
      ),
      gap,

      // Diagnosis
      KeyedSubtree(
        key: _diagnosisKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSectionTitle('Diagnosis'),
            RxChipsInput(
              label: 'Add diagnosis',
              hint: 'e.g. Acute pharyngitis',
              values: _diagnosis,
              required: true,
              errorText: _diagnosisError,
              onChanged: (v) => setState(() => _diagnosis = v),
            ),
          ],
        ),
      ),
      gap,

      const AppSectionTitle('Symptoms'),
      RxChipsInput(
        label: 'Add symptom',
        hint: 'e.g. Fever for 3 days',
        values: _symptoms,
        suggestions: _apptSymptoms,
        onChanged: (v) => setState(() => _symptoms = v),
      ),
      gap,

      // Medicines
      KeyedSubtree(
        key: _medicinesKey,
        child: AppSectionTitle(
          _meds.where((m) => !m.isBlank).isEmpty
              ? 'Medicines'
              : 'Medicines (${_meds.where((m) => !m.isBlank).length})',
          action: 'Add',
          onAction: _addMedicine,
        ),
      ),
      for (final (i, m) in _meds.indexed)
        Padding(
          key: ValueKey('med-${m.id}'),
          padding: const EdgeInsets.only(bottom: 10),
          child: RxMedicineRow(
            draft: m,
            number: i + 1,
            onRemove: _meds.length == 1 && m.isBlank
                ? null
                : () => _removeMedicine(m),
          ),
        ),
      AppSecondaryButton(
        label: 'Add another medicine',
        icon: LucideIcons.plus,
        onPressed: _addMedicine,
      ),
      gap,

      const AppSectionTitle('Lab tests'),
      RxChipsInput(
        label: 'Add test',
        hint: 'e.g. CBC',
        values: _tests,
        suggestions: _testSuggestions,
        onChanged: (v) => setState(() => _tests = v),
      ),
      gap,

      const AppSectionTitle('Advice and notes'),
      AppTextField(
        label: 'Advice for the patient',
        controller: _advice,
        hint: 'One per line, e.g. Drink plenty of fluids',
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
      ),
      AppTextField(
        label: 'Clinical notes',
        controller: _notes,
        hint: 'Printed on the prescription',
        maxLines: 3,
        margin: EdgeInsets.zero,
        textCapitalization: TextCapitalization.sentences,
      ),
      gap,

      AppSectionTitle(
        'Follow-up',
        action: _followUp == null ? null : 'Clear',
        onAction: () => setState(() => _followUp = null),
      ),
      AppPickerField(
        label: 'Date',
        valueText: _followUp == null
            ? 'No follow-up'
            : '${DateFormat('EEE d MMM yyyy').format(_followUp!)} · ${dayLabel(_followUp)}',
        onTap: _pickFollowUp,
        margin: const EdgeInsets.only(bottom: 8),
      ),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final (label, days) in const [
            ('In 3 days', 3),
            ('1 week', 7),
            ('2 weeks', 14),
            ('1 month', 30),
          ])
            Builder(
              builder: (_) {
                final now = DateTime.now();
                final d = DateTime(now.year, now.month, now.day + days);
                return RxQuickChip(
                  label: label,
                  selected:
                      _followUp != null && DateUtils.isSameDay(_followUp, d),
                  onTap: () => setState(() => _followUp = d),
                );
              },
            ),
        ],
      ),
      const SizedBox(height: 14),
      AppTextField(
        label: 'Follow-up instructions',
        controller: _followUpNote,
        hint: 'e.g. Come back with the CBC report',
        maxLines: 2,
        margin: EdgeInsets.zero,
        textCapitalization: TextCapitalization.sentences,
      ),
    ];
  }
}

class _Note extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Note({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.veryLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: accent.color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppType.sans(
                fontSize: AppType.caption,
                color: AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldError extends StatelessWidget {
  final String text;
  const _FieldError(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, left: 2),
    child: Text(
      text,
      style: AppType.sans(fontSize: 11, color: AppColors.error),
    ),
  );
}
