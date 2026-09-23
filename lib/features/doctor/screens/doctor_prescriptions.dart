import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_service.dart';
import 'prescription_details.dart';

class DoctorPrescriptions extends ConsumerStatefulWidget {
  const DoctorPrescriptions({super.key});

  @override
  ConsumerState<DoctorPrescriptions> createState() => _DoctorPrescriptionsState();
}

class _DoctorPrescriptionsState extends ConsumerState<DoctorPrescriptions> with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late TabController _tabController;
  List<Map<String, dynamic>> _prescriptions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPrescriptions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPrescriptions() async {
    setState(() => _loading = true);
    try {
      final res = await _api.getPrescriptions(queryParams: {'limit': 100});
      final data = res.data;
      final list = data is Map ? (data['data'] ?? data['prescriptions'] ?? []) : data;
      if (list is List) {
        _prescriptions = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _openCreatePrescription() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreatePrescriptionScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text('Prescriptions', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white, foregroundColor: AppTheme.textPrimary, elevation: 0, surfaceTintColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelStyle: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600),
          unselectedLabelStyle: GoogleFonts.manrope(fontSize: 14),
          labelColor: AppTheme.primary, unselectedLabelColor: AppTheme.textTertiary,
          indicatorColor: AppTheme.primary, indicatorWeight: 3,
          tabs: const [Tab(text: 'All Prescriptions'), Tab(text: 'Write New')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: List
          _loading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : RefreshIndicator(
                  onRefresh: _loadPrescriptions,
                  child: _prescriptions.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 80),
                          Center(child: Column(children: [
                            Icon(CupertinoIcons.doc_text, size: 56, color: AppTheme.textTertiary.withValues(alpha: 0.4)),
                            const SizedBox(height: 16),
                            Text('No prescriptions yet', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                            const SizedBox(height: 8),
                            Text('Write a new prescription to get started', style: GoogleFonts.manrope(fontSize: 13, color: AppTheme.textTertiary)),
                          ])),
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _prescriptions.length,
                          itemBuilder: (_, i) => _prescriptionCard(_prescriptions[i]),
                        ),
                ),
          // Tab 2: Create
          const CreatePrescriptionScreen(embedded: true),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreatePrescription,
        backgroundColor: AppTheme.primary,
        icon: const Icon(CupertinoIcons.doc_text, color: Colors.white),
        label: Text('New', style: GoogleFonts.manrope(fontWeight: FontWeight.w600, color: Colors.white)),
      ),
    );
  }

  Widget _prescriptionCard(Map<String, dynamic> rx) {
    final patient = rx['patientId'];
    final patientName = patient is Map ? (patient['name'] ?? 'Patient') : 'Patient';
    final diagnosisRaw = rx['diagnosis'];
    String diagnosis = 'N/A';
    if (diagnosisRaw is List) {
      diagnosis = diagnosisRaw.join(', ');
    } else if (diagnosisRaw != null) {
      diagnosis = diagnosisRaw.toString();
    }
    final meds = rx['medicines'] ?? rx['medications'] ?? [];
    final date = rx['createdAt'] ?? rx['date'] ?? '';
    final formattedDate = _formatDate(date);

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PrescriptionDetailsScreen(prescription: rx),
        ));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(gradient: AppTheme.doctorGradient, borderRadius: BorderRadius.circular(10)),
              child: Center(child: Text(patientName[0], style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(patientName, style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
              Text(diagnosis, style: GoogleFonts.manrope(fontSize: 12, color: AppTheme.textSecondary)),
            ])),
            Text(formattedDate, style: GoogleFonts.manrope(fontSize: 11, color: AppTheme.textTertiary)),
          ]),
          if (meds is List && meds.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6, runSpacing: 6,
              children: meds.take(3).map((m) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(8)),
                child: Text(m is Map ? (m['medicineName'] ?? m['name'] ?? m['medicine'] ?? '') : m.toString(),
                  style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.primary)),
              )).toList(),
            ),
            if (meds.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('+${meds.length - 3} more', style: GoogleFonts.manrope(fontSize: 11, color: AppTheme.textTertiary)),
              ),
          ],
        ]),
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date is String && date.isNotEmpty) {
      try {
        final dt = DateTime.parse(date);
        return '${dt.day}/${dt.month}/${dt.year}';
      } catch (_) {}
    }
    return '';
  }
}

class CreatePrescriptionScreen extends ConsumerStatefulWidget {
  final bool embedded;
  final String? initialPatientId;
  final String? initialPatientName;
  final String? initialAppointmentId;

  const CreatePrescriptionScreen({
    this.embedded = false,
    this.initialPatientId,
    this.initialPatientName,
    this.initialAppointmentId,
    super.key,
  });

  @override
  ConsumerState<CreatePrescriptionScreen> createState() => _CreatePrescriptionScreenState();
}

class _CreatePrescriptionScreenState extends ConsumerState<CreatePrescriptionScreen> {
  final ApiService _api = ApiService();
  final _diagnosisController = TextEditingController();
  final _notesController = TextEditingController();
  final _patientSearchController = TextEditingController();

  String? _selectedPatientId;
  String? _selectedAppointmentId;
  String _selectedPatientName = '';
  bool _saving = false;
  bool _searching = false;
  List<Map<String, dynamic>> _searchResults = [];

  final List<Map<String, String>> _medicines = [
    {'medicineName': '', 'dosage': '', 'duration': '', 'frequency': '', 'instructions': ''},
  ];

  @override
  void initState() {
    super.initState();
    _selectedPatientId = widget.initialPatientId;
    _selectedPatientName = widget.initialPatientName ?? '';
    _selectedAppointmentId = widget.initialAppointmentId;
  }

  @override
  void dispose() {
    _diagnosisController.dispose();
    _notesController.dispose();
    _patientSearchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _extractList(dynamic data) {
    if (data is List) {
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (data is Map) {
      for (final key in ['appointments', 'data', 'results']) {
        final value = data[key];
        if (value is List) {
          return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
    }
    return [];
  }

  Future<void> _searchAppointments(String query) async {
    if (query.trim().length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final response = await _api.getAppointments(
        queryParams: {
          'status': 'confirmed,accepted,in_progress,completed',
          'limit': 100,
          'sort': 'appointmentDate:desc',
        },
      );
      final q = query.trim().toLowerCase();
      final results = <Map<String, dynamic>>[];
      for (final appointment in _extractList(response.data)) {
        final patient = appointment['patientId'];
        if (patient is! Map || patient['_id'] == null) continue;
        final name = (patient['name'] ?? '').toString();
        final phone = (patient['phone'] ?? '').toString();
        if (!name.toLowerCase().contains(q) && !phone.toLowerCase().contains(q)) continue;
        results.add({
          'appointmentId': appointment['_id']?.toString(),
          'appointmentDate': appointment['appointmentDate'],
          'startTime': appointment['startTime'],
          'status': appointment['status'],
          'patient': Map<String, dynamic>.from(patient),
        });
      }
      if (mounted) setState(() => _searchResults = results);
    } catch (error) {
      if (mounted) _showSnack(_messageFromError(error));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectAppointment(Map<String, dynamic> result) {
    final patient = Map<String, dynamic>.from(result['patient'] as Map);
    setState(() {
      _selectedPatientId = patient['_id']?.toString();
      _selectedPatientName = (patient['name'] ?? 'Patient').toString();
      _selectedAppointmentId = result['appointmentId']?.toString();
      _searchResults = [];
      _patientSearchController.clear();
    });
  }

  void _clearAppointment() {
    setState(() {
      _selectedPatientId = null;
      _selectedPatientName = '';
      _selectedAppointmentId = null;
    });
  }

  void _addMedicine() {
    setState(() => _medicines.add({
      'medicineName': '',
      'dosage': '',
      'duration': '',
      'frequency': '',
      'instructions': '',
    }));
  }

  void _removeMedicine(int index) {
    setState(() {
      if (_medicines.length == 1) {
        _medicines[0] = {
          'medicineName': '',
          'dosage': '',
          'duration': '',
          'frequency': '',
          'instructions': '',
        };
      } else {
        _medicines.removeAt(index);
      }
    });
  }

  Future<void> _savePrescription({required bool issue}) async {
    if (_selectedAppointmentId == null || _selectedAppointmentId!.isEmpty) {
      _showSnack('Select an appointment before writing a prescription.');
      return;
    }
    final diagnosis = _diagnosisController.text.trim();
    if (diagnosis.isEmpty) {
      _showSnack('Please enter at least one diagnosis.');
      return;
    }

    final validMeds = _medicines
        .where((m) => (m['medicineName'] ?? '').trim().isNotEmpty)
        .map((m) => Map<String, dynamic>.from(m))
        .toList();

    setState(() => _saving = true);
    try {
      final create = await _api.createPrescription({
        'appointmentId': _selectedAppointmentId,
        'diagnosis': diagnosis.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        if (_notesController.text.trim().isNotEmpty)
          'advice': [
            {'advice': _notesController.text.trim()},
          ],
        'medicines': validMeds,
        'saveAsDraft': true,
      });
      final body = create.data;
      final rx = body is Map ? body['prescription'] : null;
      final id = rx is Map ? rx['_id']?.toString() : null;
      if (id == null || id.isEmpty) throw Exception('Prescription was created without an ID');

      if (issue) {
        await _api.issuePrescription(id);
      }

      if (!mounted) return;
      _showSnack(issue ? 'Prescription issued to the patient.' : 'Prescription draft saved.', isError: false);
      if (!widget.embedded) {
        Navigator.of(context).pop(true);
      } else {
        _resetForm();
      }
    } catch (error) {
      _showSnack(_messageFromError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetForm() {
    _diagnosisController.clear();
    _notesController.clear();
    _patientSearchController.clear();
    setState(() {
      _selectedPatientId = null;
      _selectedPatientName = '';
      _selectedAppointmentId = null;
      _searchResults = [];
      _medicines
        ..clear()
        ..add({
          'medicineName': '',
          'dosage': '',
          'duration': '',
          'frequency': '',
          'instructions': '',
        });
    });
  }

  String _messageFromError(Object error) {
    final text = error.toString();
    return text.replaceFirst('Exception: ', '').replaceFirst('DioException [bad response]: ', '');
  }

  void _showSnack(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.error : AppTheme.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _dateLabel(dynamic value) {
    if (value == null) return '';
    try {
      final date = DateTime.parse(value.toString()).toLocal();
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return value.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Appointment', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_selectedAppointmentId != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person, color: AppTheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_selectedPatientName, style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                        Text('Appointment $_selectedAppointmentId', style: GoogleFonts.manrope(fontSize: 10, color: AppTheme.textTertiary)),
                      ],
                    ),
                  ),
                  if (widget.initialAppointmentId == null)
                    IconButton(onPressed: _clearAppointment, icon: const Icon(CupertinoIcons.xmark_circle)),
                ],
              ),
            )
          else ...[
            TextField(
              controller: _patientSearchController,
              onChanged: _searchAppointments,
              decoration: InputDecoration(
                hintText: 'Search your patient appointments...',
                prefixIcon: const Icon(CupertinoIcons.search, size: 18),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
              ),
            ),
            if (_searchResults.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                constraints: const BoxConstraints(maxHeight: 230),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  itemBuilder: (_, index) {
                    final result = _searchResults[index];
                    final patient = Map<String, dynamic>.from(result['patient'] as Map);
                    final name = (patient['name'] ?? 'Patient').toString();
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(child: Text(name.isEmpty ? 'P' : name[0].toUpperCase())),
                      title: Text(name),
                      subtitle: Text(
                        '${_dateLabel(result['appointmentDate'])} ${result['startTime'] ?? ''} • ${result['status'] ?? ''}',
                      ),
                      onTap: () => _selectAppointment(result),
                    );
                  },
                ),
              ),
          ],
          const SizedBox(height: 20),
          Text('Diagnosis', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _diagnosisController,
            decoration: const InputDecoration(hintText: 'Comma-separated diagnoses'),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Medicines (optional)', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600)),
              TextButton.icon(onPressed: _addMedicine, icon: const Icon(CupertinoIcons.add_circled, size: 18), label: const Text('Add')),
            ],
          ),
          const SizedBox(height: 8),
          ..._medicines.asMap().entries.map((entry) {
            final index = entry.key;
            final medicine = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text('Medicine ${index + 1}', style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      IconButton(onPressed: () => _removeMedicine(index), icon: const Icon(CupertinoIcons.trash, size: 18, color: AppTheme.error)),
                    ],
                  ),
                  TextFormField(
                    initialValue: medicine['medicineName'],
                    decoration: const InputDecoration(hintText: 'Medicine name'),
                    onChanged: (v) => medicine['medicineName'] = v,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: medicine['dosage'],
                          decoration: const InputDecoration(hintText: 'Dosage'),
                          onChanged: (v) => medicine['dosage'] = v,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          initialValue: medicine['duration'],
                          decoration: const InputDecoration(hintText: 'Duration'),
                          onChanged: (v) => medicine['duration'] = v,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: medicine['frequency'],
                    decoration: const InputDecoration(hintText: 'Frequency'),
                    onChanged: (v) => medicine['frequency'] = v,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: medicine['instructions'],
                    decoration: const InputDecoration(hintText: 'Instructions'),
                    onChanged: (v) => medicine['instructions'] = v,
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 12),
          Text('Advice / Notes', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(controller: _notesController, maxLines: 3, decoration: const InputDecoration(hintText: 'Care instructions or notes')),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : () => _savePrescription(issue: false),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save Draft'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : () => _savePrescription(issue: true),
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send),
                  label: Text(_saving ? 'Saving...' : 'Issue'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text('Write Prescription', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: body,
    );
  }
}
