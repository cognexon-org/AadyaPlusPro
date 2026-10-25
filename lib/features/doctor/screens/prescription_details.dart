import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../shared/ui/app_ui.dart';
import '../providers/doctor_prescriptions_provider.dart';
import '../widgets/doctor_ui.dart';
import '../widgets/prescription_cancel_sheet.dart';
import '../widgets/prescription_ui.dart';
import 'doctor_prescriptions.dart';

/// One prescription, read top to bottom the way it prints, with the actions
/// its status allows: a draft can be edited or issued; an issued one shared
/// as a PDF or cancelled.
class PrescriptionDetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> prescription;

  const PrescriptionDetailsScreen({super.key, required this.prescription});

  @override
  ConsumerState<PrescriptionDetailsScreen> createState() =>
      _PrescriptionDetailsScreenState();
}

class _PrescriptionDetailsScreenState
    extends ConsumerState<PrescriptionDetailsScreen> {
  /// What the caller handed over; the provider's copy wins once it has one.
  late Map<String, dynamic> _seed = Map<String, dynamic>.from(
    widget.prescription,
  );
  late final String _id = rxId(_seed);

  /// Handed only an id (e.g. from a notification): nothing to paint yet.
  late bool _waiting = !_rx.containsKey('status');
  String? _loadError;
  String? _busy; // 'issue' | 'cancel' | 'pdf'
  String? _actionError;

  DoctorPrescriptionsNotifier get _rxs =>
      ref.read(doctorPrescriptionsProvider.notifier);

  Map<String, dynamic> get _rx =>
      ref.read(doctorPrescriptionsProvider).byId(_id) ?? _seed;
  String get _status => rxStatus(_rx);

  @override
  void initState() {
    super.initState();
    if (_id.isNotEmpty) _load();
  }

  /// The list hands over what it has; the full record (address, doctor,
  /// appointment) comes from GET /prescription/:id.
  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final rx = await _rxs.fetch(_id);
      if (!mounted) return;
      setState(() {
        _seed = rx;
        _waiting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = doctorError(
          e,
          fallback: 'Couldn’t refresh this prescription.',
        );
      });
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textStrong,
        content: Text(
          message,
          style: AppType.sans(fontSize: AppType.caption, color: Colors.white),
        ),
      ),
    );
  }

  Future<void> _edit() async {
    final ok = await Navigator.of(context).push<bool>(
      AppPageRoute(builder: (_) => CreatePrescriptionScreen(prescription: _rx)),
    );
    if (ok == true && mounted) _load();
  }

  Future<void> _issue() async {
    if (rxStrings(_rx['diagnosis']).isEmpty) {
      setState(
        () => _actionError =
            'Add at least one diagnosis before issuing. Tap Edit to add it.',
      );
      return;
    }
    final go = await AppModal.confirm(
      context,
      title: 'Issue this prescription?',
      message:
          '${rxPatientName(_rx)} will be notified and can download it. You can still cancel it later.',
      confirmLabel: 'Issue',
      cancelLabel: 'Not yet',
      icon: LucideIcons.send,
      destructive: false,
    );
    if (!go || !mounted) return;
    await _run('issue', () async {
      final rx = await _rxs.issue(_id);
      _seed = {..._seed, ...rx};
      _toast('Prescription issued. The patient has been notified.');
    });
  }

  Future<void> _cancel() async {
    final reason = await showRxCancelSheet(context);
    if (reason == null || !mounted) return;
    final go = await AppModal.confirm(
      context,
      title: 'Cancel ${rxNumber(_rx)}?',
      message:
          'Pharmacies will no longer dispense against it and the patient will see it as cancelled. This can’t be undone.',
      confirmLabel: 'Cancel prescription',
      cancelLabel: 'Keep it',
    );
    if (!go || !mounted) return;
    await _run('cancel', () async {
      final rx = await _rxs.cancel(_id, reason);
      _seed = {..._seed, ...rx};
      _toast('Prescription cancelled.');
    });
  }

  Future<void> _sharePdf() async {
    await _run('pdf', () async {
      final bytes = await _rxs.pdfBytes(_id);
      final dir = await getTemporaryDirectory();
      final number = rxNumber(_rx).replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
      final file = File(
        '${dir.path}/${number.isEmpty ? 'prescription' : number}.pdf',
      );
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: 'Prescription ${rxNumber(_rx)}',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    }, fallback: 'Couldn’t prepare the PDF.');
  }

  Future<void> _run(
    String what,
    Future<void> Function() action, {
    String fallback = 'Something went wrong. Please try again.',
  }) async {
    if (_busy != null) return;
    setState(() {
      _busy = what;
      _actionError = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _actionError = doctorError(e, fallback: fallback));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  // ─────────────────────────── Build ───────────────────────────

  @override
  Widget build(BuildContext context) {
    // Rebuild when this prescription changes anywhere (editor, list).
    ref.watch(doctorPrescriptionsProvider.select((s) => s.byId(_id)));
    final when = rxWhen(_rx);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: rxAppBar(
        context,
        title: _waiting ? 'Prescription' : rxNumber(_rx),
        subtitle: _waiting
            ? null
            : _status == 'draft'
            ? 'Drafted ${rxFullDate(when)}'
            : 'Issued ${rxFullDate(when)}',
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              color: ModuleAccent.of(context).color,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                children: [
                  if (_loadError != null)
                    AppErrorBanner(message: _loadError!, onRetry: _load),
                  if (_waiting)
                    if (_loadError == null)
                      const AppDetailSkeleton()
                    else
                      const SizedBox.shrink()
                  else
                    ..._sections(),
                ],
              ),
            ),
          ),
          if (!_waiting) ?_actions(),
        ],
      ),
    );
  }

  List<Widget> _sections() {
    final patient = rxPatient(_rx);
    final appt = rxMap(_rx['appointmentId']);
    final diagnosis = rxStrings(_rx['diagnosis']);
    final symptoms = rxStrings(_rx['symptoms']);
    final meds = rxMaps(_rx['medicines']);
    final tests = rxMaps(_rx['labTests']);
    final exercises = rxMaps(_rx['exercises']);
    final advice = rxMaps(_rx['advice'])
        .map((a) => '${a['advice'] ?? ''}'.trim())
        .where((a) => a.isNotEmpty)
        .toList();
    final patientNote = '${_rx['patientInstructions'] ?? ''}'.trim();
    final testNote = '${_rx['testInstructions'] ?? ''}'.trim();
    final notes = '${_rx['notes'] ?? ''}'.trim();
    final followUp = rxDate(_rx['followUpDate']);
    final followUpNote = '${_rx['followUpInstructions'] ?? ''}'.trim();
    const gap = SizedBox(height: 22);

    final blocks = <Widget>[
      _statusStrip(),
      gap,
      const AppSectionTitle('Patient'),
      AppGroup(
        children: [
          RxPatientRow(name: rxPatientName(_rx), meta: rxPatientMeta(patient)),
          if (appt.isNotEmpty) ...[
            const AppHairline(),
            RxInfoRow('Visit', _visit(appt)),
          ],
        ],
      ),
      gap,
      const AppSectionTitle('Diagnosis'),
      AppGroup(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: diagnosis.isEmpty
                ? _muted('No diagnosis added yet.', warn: _status == 'draft')
                : Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [for (final d in diagnosis) _pill(d)],
                    ),
                  ),
          ),
          if (symptoms.isNotEmpty) ...[
            const AppHairline(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: _labelled('Symptoms', symptoms.join(', ')),
            ),
          ],
        ],
      ),
      gap,
      AppSectionTitle(
        meds.isEmpty ? 'Medicines' : 'Medicines (${meds.length})',
      ),
      AppGroup(
        children: meds.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: _muted('No medicines prescribed.'),
                ),
              ]
            : [
                for (final (i, m) in meds.indexed) ...[
                  if (i > 0) const AppHairline(),
                  _medicine(i + 1, m),
                ],
              ],
      ),
      if (tests.isNotEmpty || testNote.isNotEmpty) ...[
        gap,
        const AppSectionTitle('Lab tests'),
        AppGroup(
          children: [
            for (final (i, t) in tests.indexed) ...[
              if (i > 0) const AppHairline(),
              _iconRow(
                LucideIcons.flaskConical,
                '${t['testName'] ?? 'Test'}',
                [
                  if (t['fastingRequired'] == true) 'Fasting required',
                  '${t['instructions'] ?? ''}'.trim(),
                ].where((e) => e.isNotEmpty).join(' · '),
              ),
            ],
            if (testNote.isNotEmpty) ...[
              if (tests.isNotEmpty) const AppHairline(),
              _iconRow(LucideIcons.info, testNote, ''),
            ],
          ],
        ),
      ],
      if (exercises.isNotEmpty) ...[
        gap,
        AppSectionTitle('Exercises (${exercises.length})'),
        AppGroup(
          children: [
            for (final (i, e) in exercises.indexed) ...[
              if (i > 0) const AppHairline(),
              _iconRow(
                LucideIcons.activity,
                '${e['name'] ?? 'Exercise'}',
                [
                  if (e['sets'] != null && e['reps'] != null)
                    '${e['sets']} × ${e['reps']}',
                  '${e['frequency'] ?? ''}'.trim(),
                  '${e['duration'] ?? ''}'.trim(),
                  '${e['instructions'] ?? ''}'.trim(),
                ].where((x) => x.isNotEmpty).join(' · '),
              ),
            ],
          ],
        ),
      ],
      if (advice.isNotEmpty || patientNote.isNotEmpty || notes.isNotEmpty) ...[
        gap,
        const AppSectionTitle('Advice'),
        AppGroup(
          children: [
            for (final (i, a) in advice.indexed) ...[
              if (i > 0) const AppHairline(),
              _iconRow(LucideIcons.circleCheck, a, ''),
            ],
            if (patientNote.isNotEmpty) ...[
              if (advice.isNotEmpty) const AppHairline(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: _labelled('Instructions', patientNote),
              ),
            ],
            if (notes.isNotEmpty) ...[
              if (advice.isNotEmpty || patientNote.isNotEmpty)
                const AppHairline(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: _labelled('Clinical notes', notes),
              ),
            ],
          ],
        ),
      ],
      if (followUp != null || followUpNote.isNotEmpty) ...[
        gap,
        const AppSectionTitle('Follow-up'),
        AppGroup(
          children: [
            if (followUp != null)
              _iconRow(
                LucideIcons.calendarClock,
                rxFullDate(followUp),
                _relative(followUp),
              ),
            if (followUpNote.isNotEmpty) ...[
              if (followUp != null) const AppHairline(),
              _iconRow(LucideIcons.messageSquareText, followUpNote, ''),
            ],
          ],
        ),
      ],
      gap,
      const AppSectionTitle('Record'),
      AppGroup(children: _record()),
    ];

    var i = 0;
    return [
      for (final b in blocks)
        b is SizedBox ? b : AppEntrance(index: i++, child: b),
    ];
  }

  List<Widget> _record() {
    final issued = rxDate(_rx['issuedAt']);
    final expires = rxDate(_rx['expiresAt']);
    final version = int.tryParse('${_rx['version'] ?? 1}') ?? 1;
    final pharmacy = '${_rx['pharmacyStatus'] ?? ''}';
    final rows = <Widget>[
      RxInfoRow('Rx number', rxNumber(_rx)),
      RxInfoRow(
        'Status',
        rxStatusLabel(_status),
        valueColor: rxStatusColor(context, _status),
      ),
      RxInfoRow('Created', rxDateTime(rxDate(_rx['createdAt']))),
      if (issued != null) RxInfoRow('Issued', rxDateTime(issued)),
      if (expires != null)
        RxInfoRow(
          'Valid until',
          rxFullDate(expires),
          valueColor: expires.isBefore(DateTime.now())
              ? AppColors.warning
              : null,
        )
      else
        RxInfoRow('Validity', '${_rx['validityDays'] ?? 30} days from issue'),
      if (_status == 'issued' && pharmacy.isNotEmpty)
        RxInfoRow('Pharmacy', switch (pharmacy) {
          'not_dispensed' => 'Not dispensed yet',
          'partially_dispensed' => 'Partly dispensed',
          'fully_dispensed' => 'Fully dispensed',
          'cancelled' => 'Cancelled',
          _ => rxCap(pharmacy.replaceAll('_', ' ')),
        }),
      if (version > 1) RxInfoRow('Version', '$version'),
    ];
    return [
      for (final (i, r) in rows.indexed) ...[if (i > 0) const AppHairline(), r],
    ];
  }

  Widget _statusStrip() {
    final accent = ModuleAccent.of(context);
    final expires = rxDate(_rx['expiresAt']);
    final (Color bg, Color fg, IconData icon, String text) = switch (_status) {
      'draft' => (
        AppColors.warningBg,
        AppColors.warning,
        LucideIcons.filePen,
        'The patient can’t see it until you issue it.',
      ),
      'issued' => (
        accent.veryLight,
        accent.color,
        LucideIcons.fileCheck,
        expires == null
            ? 'Issued to the patient.'
            : 'Issued to the patient. Valid until ${rxFullDate(expires)}.',
      ),
      'cancelled' => (
        AppColors.errorBg,
        AppColors.error,
        LucideIcons.fileX,
        'Cancelled${rxDate(_rx['cancelledAt']) == null ? '' : ' on ${rxFullDate(rxDate(_rx['cancelledAt']))}'}. ${'${_rx['cancellationReason'] ?? ''}'.trim()}'
            .trim(),
      ),
      _ => (
        AppColors.panel,
        AppColors.textSecondary,
        LucideIcons.history,
        'Superseded by a newer version of this prescription.',
      ),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rxStatusLabel(_status),
                  style: AppType.sans(
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: AppType.sans(
                    fontSize: AppType.caption,
                    color: AppColors.textPrimary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget? _actions() {
    final error = _actionError == null
        ? null
        : AppErrorBanner(message: _actionError!);
    Widget? row;
    if (_status == 'draft') {
      row = Row(
        children: [
          Expanded(
            child: AppSecondaryButton(
              label: 'Edit',
              icon: LucideIcons.pencil,
              onPressed: _busy != null ? null : _edit,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AppButton(
              label: 'Issue',
              icon: LucideIcons.send,
              loading: _busy == 'issue',
              onPressed: _busy != null ? null : _issue,
            ),
          ),
        ],
      );
    } else if (_status == 'issued') {
      row = Row(
        children: [
          Expanded(
            child: AppSecondaryButton(
              label: 'Cancel',
              icon: LucideIcons.ban,
              color: AppColors.error,
              onPressed: _busy != null ? null : _cancel,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AppButton(
              label: 'Share PDF',
              icon: LucideIcons.share2,
              loading: _busy == 'pdf',
              onPressed: _busy != null ? null : _sharePdf,
            ),
          ),
        ],
      );
    } else if (_status == 'superseded') {
      row = AppSecondaryButton(
        label: _busy == 'pdf' ? 'Preparing…' : 'Share PDF',
        icon: LucideIcons.share2,
        onPressed: _busy != null ? null : _sharePdf,
      );
    }
    if (row == null) return null;
    return RxBottomBar(above: error, child: row);
  }

  // ─────────────────────────── Pieces ───────────────────────────

  static String _relative(DateTime d) {
    final now = DateTime.now();
    final days = DateTime(
      d.year,
      d.month,
      d.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days == 0) return 'Today';
    if (days == 1) return 'Tomorrow';
    if (days == -1) return 'Yesterday';
    return days > 0 ? 'In $days days' : '${-days} days ago';
  }

  static String _visit(Map<String, dynamic> appt) {
    final start = apptStart(appt);
    return [
      if (start != null) '${dayLabel(start)}, ${timeLabel(start)}',
      apptTypeInfo(apptType(appt)).label,
    ].join(' · ');
  }

  Widget _medicine(int n, Map<String, dynamic> m) {
    final accent = ModuleAccent.of(context);
    final line = rxDosageLine(m);
    final instructions = '${m['instructions'] ?? ''}'.trim();
    final generic = '${m['genericName'] ?? ''}'.trim();
    final qty = m['quantity'];
    final unit = '${m['unit'] ?? ''}'.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.light,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$n',
              style: AppType.sans(
                fontSize: AppType.micro,
                fontWeight: FontWeight.w700,
                color: accent.color,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rxMedicineName(m),
                  style: AppType.sans(
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textStrong,
                  ),
                ),
                if (generic.isNotEmpty)
                  Text(
                    generic,
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      color: AppColors.textTertiary,
                    ),
                  ),
                if (line.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    line,
                    style: AppType.sans(
                      fontSize: AppType.small,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
                if (instructions.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    instructions,
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (qty != null && '$qty'.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              'Qty $qty${unit.isEmpty ? '' : ' $unit'}',
              style: AppType.sans(
                fontSize: AppType.caption,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _iconRow(IconData icon, String text, String sub) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: AppColors.textTertiary),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text,
                style: AppType.sans(
                  fontSize: AppType.body,
                  color: AppColors.textPrimary,
                  height: 1.35,
                ),
              ),
              if (sub.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: AppType.sans(
                    fontSize: AppType.caption,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  Widget _labelled(String label, String value) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: AppType.sans(
          fontSize: AppType.caption,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        style: AppType.sans(
          fontSize: AppType.body,
          color: AppColors.textPrimary,
          height: 1.4,
        ),
      ),
    ],
  );

  Widget _pill(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.bg,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: AppType.sans(
        fontSize: AppType.small,
        fontWeight: FontWeight.w600,
        color: AppColors.textStrong,
      ),
    ),
  );

  Widget _muted(String text, {bool warn = false}) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      text,
      style: AppType.sans(
        fontSize: AppType.small,
        color: warn ? AppColors.warning : AppColors.textTertiary,
      ),
    ),
  );
}
