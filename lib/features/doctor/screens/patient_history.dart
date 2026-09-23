import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_service.dart';
import 'doctor_appointments.dart';

class PatientHistoryScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  const PatientHistoryScreen({super.key, required this.patientId, required this.patientName});

  @override
  State<PatientHistoryScreen> createState() => _PatientHistoryScreenState();
}

class _PatientHistoryScreenState extends State<PatientHistoryScreen> with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late TabController _tabController;
  List<Map<String, dynamic>> _appointments = [];
  List<Map<String, dynamic>> _prescriptions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.getAppointmentsByPatient(widget.patientId),
        _api.getPrescriptionsByPatient(widget.patientId),
      ]);

      final apptData = results[0].data;
      final rxData = results[1].data;

      _appointments = _extractList(apptData);
      _prescriptions = _extractList(rxData);

      // Sort appointments by date descending
      _appointments.sort((a, b) {
        final da = DateTime.tryParse(a['appointmentDate']?.toString() ?? '') ?? DateTime(2000);
        final db = DateTime.tryParse(b['appointmentDate']?.toString() ?? '') ?? DateTime(2000);
        return db.compareTo(da);
      });
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> _extractList(dynamic data) {
    if (data == null) return [];
    if (data is List) return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (data is Map) {
      for (final key in ['data', 'appointments', 'prescriptions', 'results']) {
        if (data[key] is List) return (data[key] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(widget.patientName, style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white, foregroundColor: AppTheme.textPrimary, elevation: 0, surfaceTintColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          labelStyle: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600),
          labelColor: AppTheme.primary, unselectedLabelColor: AppTheme.textTertiary,
          indicatorColor: AppTheme.primary, indicatorWeight: 3,
          tabs: [
            Tab(text: 'Appointments (${_appointments.length})'),
            Tab(text: 'Prescriptions (${_prescriptions.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : TabBarView(
              controller: _tabController,
              children: [
                // Appointments tab
                _appointments.isEmpty
                    ? _emptyState(CupertinoIcons.calendar, 'No appointment history')
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _appointments.length,
                        itemBuilder: (_, i) => _appointmentCard(_appointments[i]),
                      ),
                // Prescriptions tab
                _prescriptions.isEmpty
                    ? _emptyState(CupertinoIcons.doc_text, 'No prescriptions')
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _prescriptions.length,
                        itemBuilder: (_, i) => _prescriptionCard(_prescriptions[i]),
                      ),
              ],
            ),
    );
  }

  Widget _emptyState(IconData icon, String message) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 48, color: AppTheme.textTertiary.withValues(alpha: 0.4)),
      const SizedBox(height: 12),
      Text(message, style: GoogleFonts.manrope(fontSize: 14, color: AppTheme.textSecondary)),
    ]));
  }

  Widget _appointmentCard(Map<String, dynamic> apt) {
    final status = apt['status'] ?? 'pending';
    final type = apt['type'] ?? 'clinic';
    final date = apt['appointmentDate'] ?? '';
    final time = apt['startTime'] ?? '';
    final reason = apt['reason'] ?? apt['symptoms']?.toString() ?? '';
    final fee = apt['consultationFee'] ?? apt['totalAmount'] ?? 0;

    final statusColor = status == 'completed' ? AppTheme.success
        : (status == 'confirmed' || status == 'accepted') ? AppTheme.primary
        : status == 'cancelled' ? AppTheme.error : AppTheme.warning;

    return GestureDetector(
      onTap: () async {
        final result = await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AppointmentDetailsScreen(appointment: apt)));
        if (result == true) _loadData();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
          Icon(type == 'video' ? CupertinoIcons.video_camera : type == 'home' ? CupertinoIcons.house : Icons.local_hospital_outlined, size: 18, color: AppTheme.primary),
          const SizedBox(width: 8),
          Text(_formatType(type), style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
            child: Text(status, style: GoogleFonts.manrope(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor)),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(CupertinoIcons.calendar, size: 14, color: AppTheme.textTertiary),
          const SizedBox(width: 6),
          Text(_formatDate(date), style: GoogleFonts.manrope(fontSize: 12, color: AppTheme.textSecondary)),
          if (time.isNotEmpty) ...[
            const SizedBox(width: 12),
            const Icon(CupertinoIcons.clock, size: 14, color: AppTheme.textTertiary),
            const SizedBox(width: 6),
            Text(time, style: GoogleFonts.manrope(fontSize: 12, color: AppTheme.textSecondary)),
          ],
          const Spacer(),
          Text('₹$fee', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primary)),
        ]),
        if (reason.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(reason, style: GoogleFonts.manrope(fontSize: 12, color: AppTheme.textTertiary), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ]),
    ));
  }

  Widget _prescriptionCard(Map<String, dynamic> rx) {
    final diagnosis = rx['diagnosis'] ?? '';
    final meds = rx['medicines'] ?? rx['medications'] ?? [];
    final date = rx['createdAt'] ?? rx['date'] ?? '';
    final notes = rx['notes'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(CupertinoIcons.doc_text, size: 18, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(diagnosis.isNotEmpty ? diagnosis : 'Prescription', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary))),
          Text(_formatDate(date), style: GoogleFonts.manrope(fontSize: 11, color: AppTheme.textTertiary)),
        ]),
        if (meds is List && meds.isNotEmpty) ...[
          const SizedBox(height: 10),
          ...meds.take(5).map((m) {
            final name = m is Map ? (m['name'] ?? '') : m.toString();
            final dosage = m is Map ? (m['dosage'] ?? '') : '';
            final freq = m is Map ? (m['frequency'] ?? '') : '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Container(width: 4, height: 4, decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                Expanded(child: Text('$name${dosage.isNotEmpty ? ' - $dosage' : ''}${freq.isNotEmpty ? ' ($freq)' : ''}',
                  style: GoogleFonts.manrope(fontSize: 12, color: AppTheme.textSecondary))),
              ]),
            );
          }),
        ],
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(notes, style: GoogleFonts.manrope(fontSize: 12, fontStyle: FontStyle.italic, color: AppTheme.textTertiary), maxLines: 2),
        ],
      ]),
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

  String _formatType(String type) {
    switch (type) {
      case 'video': return 'Video Consultation';
      case 'home': return 'Home Visit';
      default: return 'Clinic Visit';
    }
  }
}
