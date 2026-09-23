import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/network/api_service.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/app_dialog.dart';
import '../../features/doctor/screens/doctor_prescriptions.dart';
import '../../features/doctor/screens/prescription_details.dart';
import 'app_web_view.dart';

/// Professional-side Patch-4 consultation workspace shared by doctors and
/// physiotherapists. It deliberately uses the consultation session as the
/// lifecycle source of truth instead of mutating Appointment.status directly.
class ProfessionalConsultationScreen extends StatefulWidget {
  final Map<String, dynamic> appointment;

  const ProfessionalConsultationScreen({super.key, required this.appointment});

  @override
  State<ProfessionalConsultationScreen> createState() =>
      _ProfessionalConsultationScreenState();
}

class _ProfessionalConsultationScreenState
    extends State<ProfessionalConsultationScreen> {
  final ApiService _api = ApiService();
  final _chiefComplaintController = TextEditingController();
  final _diagnosisController = TextEditingController();
  final _notesController = TextEditingController();
  final _adviceController = TextEditingController();
  final _followUpNotesController = TextEditingController();

  Map<String, dynamic>? _appointment;
  Map<String, dynamic>? _session;
  Map<String, dynamic>? _prescription;
  bool _loading = true;
  bool _busy = false;
  bool _followUpRequired = false;
  DateTime? _followUpDate;
  String _outcome = 'unknown';
  String? _error;

  String get _appointmentId =>
      (_appointment?['_id'] ?? widget.appointment['_id'] ?? '').toString();

  bool get _isVideo =>
      (_appointment?['type'] ?? widget.appointment['type']) == 'video';

  Map<String, dynamic> get _patient {
    final raw = _appointment?['patientId'] ?? widget.appointment['patientId'];
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  @override
  void initState() {
    super.initState();
    _appointment = Map<String, dynamic>.from(widget.appointment);
    _load();
  }

  @override
  void dispose() {
    _chiefComplaintController.dispose();
    _diagnosisController.dispose();
    _notesController.dispose();
    _adviceController.dispose();
    _followUpNotesController.dispose();
    super.dispose();
  }

  Future<void> _load({bool keepBusy = false}) async {
    if (!keepBusy && mounted) setState(() => _loading = true);
    try {
      final response = await _api.getConsultationByAppointment(_appointmentId);
      final data = Map<String, dynamic>.from(response.data as Map);
      final appointment = data['appointment'];
      final session = data['session'];
      if (appointment is Map) {
        _appointment = Map<String, dynamic>.from(appointment);
      }
      if (session is Map) {
        _session = Map<String, dynamic>.from(session);
        _hydrateSummary(_session!['clinicalSummary']);
      }
      await _loadPrescription();
      _error = null;
    } on DioException catch (e) {
      _error = _message(e);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted && !keepBusy) setState(() => _loading = false);
    }
  }

  void _hydrateSummary(dynamic raw) {
    if (raw is! Map) return;
    final summary = Map<String, dynamic>.from(raw);
    if (_chiefComplaintController.text.isEmpty) {
      _chiefComplaintController.text = _listText(summary['chiefComplaint']);
    }
    if (_diagnosisController.text.isEmpty) {
      _diagnosisController.text = _listText(summary['diagnosis']);
    }
    if (_notesController.text.isEmpty) {
      _notesController.text = summary['notes']?.toString() ?? '';
    }
    if (_adviceController.text.isEmpty) {
      _adviceController.text = summary['advice']?.toString() ?? '';
    }
    if (_followUpNotesController.text.isEmpty) {
      _followUpNotesController.text =
          summary['followUpNotes']?.toString() ?? '';
    }
    _outcome = summary['outcome']?.toString() ?? _outcome;
    _followUpRequired = summary['followUpRequired'] == true;
    if (_followUpDate == null && summary['followUpDate'] != null) {
      _followUpDate = DateTime.tryParse(summary['followUpDate'].toString());
    }
  }

  Future<void> _loadPrescription() async {
    try {
      final response = await _api.getPrescriptionByAppointment(_appointmentId);
      final raw = response.data is Map ? response.data['prescription'] : null;
      _prescription = raw is Map ? Map<String, dynamic>.from(raw) : null;
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
      _prescription = null;
    }
  }

  Future<void> _start() async {
    await _run(() async {
      final response = await _api.startConsultation(_appointmentId);
      _mergeResponse(response.data);
    }, success: 'Consultation started');
  }

  Future<void> _joinVideo() async {
    setState(() => _busy = true);
    try {
      final response = await _api.joinConsultation(_appointmentId);
      final data = Map<String, dynamic>.from(response.data as Map);
      final joinUrl = data['joinUrl']?.toString() ?? '';
      if (joinUrl.isEmpty) throw StateError('Video room is not available');
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AppWebView(
            url: joinUrl,
            title: 'Consultation: ${_patient['name'] ?? 'Patient'}',
          ),
        ),
      );
      try {
        await _api.leaveConsultation(_appointmentId);
      } catch (_) {}
      await _load(keepBusy: true);
    } on DioException catch (e) {
      _show(_message(e), error: true);
    } catch (e) {
      _show(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _summaryPayload() => {
    'chiefComplaint': _csv(_chiefComplaintController.text),
    'diagnosis': _csv(_diagnosisController.text),
    'notes': _notesController.text.trim(),
    'advice': _adviceController.text.trim(),
    'outcome': _outcome,
    'followUpRequired': _followUpRequired,
    if (_followUpRequired && _followUpDate != null)
      'followUpDate': _followUpDate!.toUtc().toIso8601String(),
    'followUpNotes': _followUpNotesController.text.trim(),
  };

  Future<void> _saveNotes() async {
    await _run(() async {
      final response = await _api.updateConsultationSummary(
        _appointmentId,
        _summaryPayload(),
      );
      _mergeResponse(response.data);
    }, success: 'Clinical notes saved');
  }

  Future<void> _endConsultation() async {
    final diagnosis = _csv(_diagnosisController.text);
    if (diagnosis.isEmpty) {
      _show(
        'Add at least one diagnosis before ending the consultation.',
        error: true,
      );
      return;
    }

    final confirmed = await AppDialog.confirm(
      context,
      title: 'End consultation?',
      message:
          'This completes the appointment and locks the clinical consultation summary.',
      icon: CupertinoIcons.checkmark_seal,
      confirmLabel: 'End consultation',
    );
    if (!confirmed) return;

    await _run(() async {
      final response = await _api.endConsultation(
        _appointmentId,
        _summaryPayload(),
      );
      _mergeResponse(response.data);
    }, success: 'Consultation completed');
  }

  Future<void> _openPrescriptionEditor() async {
    final patient = _patient;
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreatePrescriptionScreen(
          initialPatientId: patient['_id']?.toString(),
          initialPatientName: patient['name']?.toString() ?? 'Patient',
          initialAppointmentId: _appointmentId,
        ),
      ),
    );
    if (result == true) {
      await _loadPrescription();
      if (mounted) setState(() {});
    }
  }

  Future<void> _issuePrescription() async {
    final id = _prescription?['_id']?.toString();
    if (id == null || id.isEmpty) return;
    await _run(() async {
      final response = await _api.issuePrescription(id);
      final raw = response.data is Map ? response.data['prescription'] : null;
      if (raw is Map) _prescription = Map<String, dynamic>.from(raw);
    }, success: 'Prescription issued to patient');
  }

  Future<void> _run(
    Future<void> Function() operation, {
    required String success,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
      if (mounted) {
        _show(success);
        setState(() {});
      }
    } on DioException catch (e) {
      _show(_message(e), error: true);
    } catch (e) {
      _show(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _mergeResponse(dynamic raw) {
    if (raw is! Map) return;
    final data = Map<String, dynamic>.from(raw);
    if (data['appointment'] is Map) {
      _appointment = Map<String, dynamic>.from(data['appointment'] as Map);
    }
    if (data['session'] is Map) {
      _session = Map<String, dynamic>.from(data['session'] as Map);
      _hydrateSummary(_session!['clinicalSummary']);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    final session = _session ?? const <String, dynamic>{};
    final patient = _patient;
    final status = session['status']?.toString() ?? 'scheduled';
    final canStart = session['canStart'] == true;
    final canJoin = session['canJoin'] == true;
    final canEnd = session['canEnd'] == true;
    final paymentRequired = session['paymentRequired'] == true;
    final isEnded = status == 'ended' || _appointment?['status'] == 'completed';

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(
          'Consultation',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _busy ? null : () => _load(),
            icon: const Icon(CupertinoIcons.refresh),
          ),
        ],
      ),
      body: _error != null
          ? _errorState()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _headerCard(patient, status, paymentRequired),
                  const SizedBox(height: 16),
                  _lifecycleCard(
                    status: status,
                    canStart: canStart,
                    canJoin: canJoin,
                    canEnd: canEnd,
                    isEnded: isEnded,
                  ),
                  const SizedBox(height: 16),
                  _clinicalCard(isEnded),
                  const SizedBox(height: 16),
                  _prescriptionCard(isEnded),
                  const SizedBox(height: 28),
                ],
              ),
            ),
    );
  }

  Widget _headerCard(
    Map<String, dynamic> patient,
    String status,
    bool paymentRequired,
  ) {
    final name = patient['name']?.toString() ?? 'Patient';
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                foregroundColor: AppTheme.primary,
                child: Text(name.isEmpty ? 'P' : name[0].toUpperCase()),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: _titleStyle()),
                    Text(
                      '${_appointment?['type'] ?? 'clinic'} consultation • ${_appointment?['startTime'] ?? ''}',
                      style: _subStyle(),
                    ),
                  ],
                ),
              ),
              _statusChip(status),
            ],
          ),
          if (paymentRequired) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'The patient must complete payment before this video consultation can start.',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: AppTheme.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _lifecycleCard({
    required String status,
    required bool canStart,
    required bool canJoin,
    required bool canEnd,
    required bool isEnded,
  }) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Consultation controls', style: _sectionStyle()),
          const SizedBox(height: 12),
          if (isEnded)
            const _InfoBanner(
              icon: CupertinoIcons.checkmark_circle,
              text:
                  'This consultation is completed. Clinical notes are locked.',
              color: AppTheme.success,
            )
          else ...[
            if (canStart)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _start,
                  icon: const Icon(CupertinoIcons.play, size: 18),
                  label: const Text('Start consultation'),
                ),
              ),
            if (_isVideo) ...[
              if (canStart) const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: !_busy && canJoin ? _joinVideo : null,
                  icon: const Icon(CupertinoIcons.video_camera, size: 18),
                  label: Text(
                    canJoin ? 'Join secure video room' : 'Video room not ready',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text('Status: ${status.replaceAll('_', ' ')}', style: _subStyle()),
            if (canEnd) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _endConsultation,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                  ),
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text('End & complete consultation'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _clinicalCard(bool isEnded) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Clinical summary', style: _sectionStyle()),
          const SizedBox(height: 12),
          _field(
            _chiefComplaintController,
            'Chief complaint',
            'Comma-separated complaints',
            enabled: !isEnded,
          ),
          _field(
            _diagnosisController,
            'Diagnosis',
            'Comma-separated diagnoses',
            enabled: !isEnded,
          ),
          _field(
            _notesController,
            'Clinical notes',
            'Examination/findings/notes',
            enabled: !isEnded,
            maxLines: 4,
          ),
          _field(
            _adviceController,
            'Advice',
            'Care advice and precautions',
            enabled: !isEnded,
            maxLines: 3,
          ),
          DropdownButtonFormField<String>(
            value: _outcome,
            decoration: const InputDecoration(labelText: 'Outcome'),
            items:
                const [
                      'unknown',
                      'resolved',
                      'improved',
                      'ongoing',
                      'referred',
                      'emergency_referral',
                    ]
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.replaceAll('_', ' ')),
                      ),
                    )
                    .toList(),
            onChanged: isEnded
                ? null
                : (value) => setState(() => _outcome = value ?? 'unknown'),
          ),
          const SizedBox(height: 10),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _followUpRequired,
            onChanged: isEnded
                ? null
                : (value) => setState(() => _followUpRequired = value),
            title: const Text('Follow-up required'),
          ),
          if (_followUpRequired) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Follow-up date'),
              subtitle: Text(
                _followUpDate == null
                    ? 'Not selected'
                    : '${_followUpDate!.day}/${_followUpDate!.month}/${_followUpDate!.year}',
              ),
              trailing: const Icon(CupertinoIcons.calendar),
              onTap: isEnded ? null : _pickFollowUpDate,
            ),
            _field(
              _followUpNotesController,
              'Follow-up instructions',
              'What should happen at follow-up?',
              enabled: !isEnded,
              maxLines: 2,
            ),
          ],
          if (!isEnded)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _saveNotes,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Save clinical notes'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _prescriptionCard(bool isEnded) {
    final rx = _prescription;
    final status = rx?['status']?.toString() ?? '';
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Prescription / therapy plan',
                  style: _sectionStyle(),
                ),
              ),
              if (rx != null) _statusChip(status),
            ],
          ),
          const SizedBox(height: 12),
          if (rx == null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _openPrescriptionEditor,
                icon: const Icon(CupertinoIcons.doc_text, size: 18),
                label: const Text('Create prescription'),
              ),
            )
          else ...[
            Text(
              rx['prescriptionNumber']?.toString() ?? 'Prescription',
              style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(_listText(rx['diagnosis']), style: _subStyle()),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            PrescriptionDetailsScreen(prescription: rx),
                      ),
                    ),
                    icon: const Icon(CupertinoIcons.eye, size: 16),
                    label: const Text('View'),
                  ),
                ),
                if (status == 'draft') ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : _issuePrescription,
                      icon: const Icon(CupertinoIcons.paperplane, size: 16),
                      label: const Text('Issue'),
                    ),
                  ),
                ],
              ],
            ),
          ],
          if (isEnded && rx == null) ...[
            const SizedBox(height: 10),
            Text(
              'You can still create an appointment-linked prescription after completing the consultation.',
              style: _subStyle(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.border),
    ),
    child: child,
  );

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    bool enabled = true,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label, hintText: hint),
    ),
  );

  Widget _statusChip(String status) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: AppTheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      status.replaceAll('_', ' ').toUpperCase(),
      style: GoogleFonts.manrope(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: AppTheme.primary,
      ),
    ),
  );

  TextStyle _titleStyle() => GoogleFonts.manrope(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppTheme.textPrimary,
  );

  TextStyle _sectionStyle() => GoogleFonts.manrope(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppTheme.textPrimary,
  );

  TextStyle _subStyle() =>
      GoogleFonts.manrope(fontSize: 12, color: AppTheme.textSecondary);

  Future<void> _pickFollowUpDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: _followUpDate ?? DateTime.now().add(const Duration(days: 7)),
    );
    if (picked != null && mounted) setState(() => _followUpDate = picked);
  }

  Widget _errorState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            CupertinoIcons.exclamationmark_triangle,
            color: AppTheme.error,
            size: 42,
          ),
          const SizedBox(height: 12),
          Text(
            _error ?? 'Unable to load consultation',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    ),
  );

  void _show(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? AppTheme.error : AppTheme.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _message(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      return (data['error'] ?? data['message'] ?? 'Request failed').toString();
    }
    return e.message ?? 'Request failed';
  }

  List<String> _csv(String value) => value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

  String _listText(dynamic value) {
    if (value is List) return value.map((item) => item.toString()).join(', ');
    return value?.toString() ?? '';
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _InfoBanner({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
