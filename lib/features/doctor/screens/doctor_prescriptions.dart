import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
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
        title: Text('Prescriptions', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white, foregroundColor: AppTheme.textPrimary, elevation: 0, surfaceTintColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelStyle: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600),
          unselectedLabelStyle: GoogleFonts.plusJakartaSans(fontSize: 14),
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
                            Icon(Iconsax.document_text, size: 56, color: AppTheme.textTertiary.withValues(alpha: 0.4)),
                            const SizedBox(height: 16),
                            Text('No prescriptions yet', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                            const SizedBox(height: 8),
                            Text('Write a new prescription to get started', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textTertiary)),
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
        icon: const Icon(Iconsax.document_text, color: Colors.white),
        label: Text('New', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: Colors.white)),
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
              child: Center(child: Text(patientName[0], style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(patientName, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
              Text(diagnosis, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
            ])),
            Text(formattedDate, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textTertiary)),
          ]),
          if (meds is List && meds.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6, runSpacing: 6,
              children: meds.take(3).map((m) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(8)),
                child: Text(m is Map ? (m['name'] ?? m['medicine'] ?? '') : m.toString(),
                  style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.primary)),
              )).toList(),
            ),
            if (meds.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('+${meds.length - 3} more', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textTertiary)),
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
  List<Map<String, dynamic>> _searchResults = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialPatientId != null) {
      _selectedPatientId = widget.initialPatientId;
      _selectedPatientName = widget.initialPatientName ?? 'Patient';
      _selectedAppointmentId = widget.initialAppointmentId;
    }
  }

  final List<Map<String, dynamic>> _medicines = [
    {'name': '', 'dosage': '', 'duration': '', 'frequency': '', 'instructions': ''},
  ];

  @override
  void dispose() {
    _diagnosisController.dispose();
    _notesController.dispose();
    _patientSearchController.dispose();
    super.dispose();
  }

  Future<void> _searchPatients(String query) async {
    if (query.length < 2) { setState(() => _searchResults = []); return; }
    setState(() => _searching = true);
    try {
      final res = await _api.getAppointments(queryParams: {'limit': 100});
      final data = res.data;
      final list = _extractList(data);
      final patients = <String, Map<String, dynamic>>{};
      for (final a in list) {
        final p = a['patientId'];
        if (p is Map && p['_id'] != null) {
          final name = (p['name'] ?? '').toString().toLowerCase();
          if (name.contains(query.toLowerCase())) {
            patients[p['_id']] = Map<String, dynamic>.from(p);
          }
        }
      }
      _searchResults = patients.values.toList();
    } catch (_) {}
    if (mounted) setState(() => _searching = false);
  }

  void _addMedicine() {
    setState(() {
      _medicines.add({'name': '', 'dosage': '', 'duration': '', 'frequency': '', 'instructions': ''});
    });
  }

  void _removeMedicine(int i) {
    if (_medicines.length <= 1) return;
    setState(() => _medicines.removeAt(i));
  }

  Future<void> _savePrescription() async {
    if (_selectedPatientId == null) { _showSnack('Please select a patient'); return; }
    if (_diagnosisController.text.trim().isEmpty) { _showSnack('Please enter diagnosis'); return; }
    final validMeds = _medicines.where((m) => (m['name'] as String).isNotEmpty).toList();
    if (validMeds.isEmpty) { _showSnack('Add at least one medicine'); return; }

    setState(() => _saving = true);
    try {
      await _api.createPrescription({
        'patientId': _selectedPatientId,
        if (_selectedAppointmentId != null) 'appointmentId': _selectedAppointmentId,
        'diagnosis': _diagnosisController.text.trim(),
        'notes': _notesController.text.trim(),
        'medicines': validMeds,
      });
      _showSnack('Prescription created!', isError: false);
      if (!widget.embedded && mounted) Navigator.of(context).pop(true);
      if (widget.embedded) {
        _diagnosisController.clear();
        _notesController.clear();
        _patientSearchController.clear();
        setState(() {
          _selectedPatientId = null;
          _selectedPatientName = '';
          _medicines.clear();
          _medicines.add({'name': '', 'dosage': '', 'duration': '', 'frequency': '', 'instructions': ''});
        });
      }
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: isError ? AppTheme.error : AppTheme.success,
      behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  List<Map<String, dynamic>> _extractList(dynamic data) {
    if (data == null) return [];
    if (data is List) return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (data is Map) {
      for (final key in ['data', 'appointments', 'patients', 'results']) {
        if (data[key] is List) return (data[key] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final body = SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Patient', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        const SizedBox(height: 8),
        if (_selectedPatientId != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2))),
            child: Row(children: [
              const Icon(Iconsax.user, size: 18, color: AppTheme.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(_selectedPatientName, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primary))),
              GestureDetector(onTap: () => setState(() { _selectedPatientId = null; _selectedPatientName = ''; }),
                child: const Icon(Iconsax.close_circle, size: 18, color: AppTheme.textTertiary)),
            ]),
          )
        else ...[
          TextField(
            controller: _patientSearchController,
            onChanged: _searchPatients,
            decoration: InputDecoration(
              hintText: 'Search patient by name...',
              prefixIcon: const Icon(Iconsax.search_normal, size: 18),
              suffixIcon: _searching ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))) : null,
            ),
          ),
          if (_searchResults.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 150),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
              child: ListView.builder(
                shrinkWrap: true, itemCount: _searchResults.length,
                itemBuilder: (_, i) {
                  final p = _searchResults[i];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(radius: 16, backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                      child: Text(p['name']?[0] ?? 'P', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary))),
                    title: Text(p['name'] ?? '', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500)),
                    subtitle: Text(p['phone'] ?? p['email'] ?? '', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textTertiary)),
                    onTap: () => setState(() {
                      _selectedPatientId = p['_id'];
                      _selectedPatientName = p['name'] ?? '';
                      _searchResults = [];
                      _patientSearchController.clear();
                    }),
                  );
                },
              ),
            ),
        ],
        const SizedBox(height: 20),
        Text('Diagnosis', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        const SizedBox(height: 8),
        TextField(controller: _diagnosisController, decoration: const InputDecoration(hintText: 'Enter diagnosis...')),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Medications', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          TextButton.icon(icon: const Icon(Iconsax.add_circle, size: 18), label: const Text('Add'), onPressed: _addMedicine),
        ]),
        const SizedBox(height: 8),
        ..._medicines.asMap().entries.map((entry) {
          final i = entry.key;
          final med = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
            child: Column(children: [
              Row(children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Center(child: Text('${i + 1}', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary))),
                ),
                const Spacer(),
                if (_medicines.length > 1)
                  GestureDetector(onTap: () => _removeMedicine(i), child: const Icon(Iconsax.trash, size: 18, color: AppTheme.error)),
              ]),
              const SizedBox(height: 10),
              TextField(
                decoration: const InputDecoration(hintText: 'Medicine name', isDense: true),
                onChanged: (v) => med['name'] = v,
                controller: TextEditingController(text: med['name'])..selection = TextSelection.fromPosition(TextPosition(offset: (med['name'] as String).length)),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(decoration: const InputDecoration(hintText: 'Dosage', isDense: true), onChanged: (v) => med['dosage'] = v)),
                const SizedBox(width: 8),
                Expanded(child: TextField(decoration: const InputDecoration(hintText: 'Duration', isDense: true), onChanged: (v) => med['duration'] = v)),
              ]),
              const SizedBox(height: 8),
              TextField(decoration: const InputDecoration(hintText: 'Frequency (e.g. Twice daily)', isDense: true), onChanged: (v) => med['frequency'] = v),
              const SizedBox(height: 8),
              TextField(decoration: const InputDecoration(hintText: 'Instructions', isDense: true), onChanged: (v) => med['instructions'] = v),
            ]),
          );
        }),
        const SizedBox(height: 12),
        Text('Additional Notes', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        const SizedBox(height: 8),
        TextField(controller: _notesController, maxLines: 3, decoration: const InputDecoration(hintText: 'Any additional notes...')),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _saving ? null : _savePrescription,
            icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Iconsax.document_upload),
            label: Text(_saving ? 'Creating...' : 'Create Prescription', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 40),
      ]),
    );

    if (widget.embedded) return body;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text('Write Prescription', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white, foregroundColor: AppTheme.textPrimary, elevation: 0, surfaceTintColor: Colors.white,
      ),
      body: body,
    );
  }
}
