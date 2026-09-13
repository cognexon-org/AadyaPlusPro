import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/theme/app_theme.dart';

class PrescriptionDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> prescription;
  
  const PrescriptionDetailsScreen({super.key, required this.prescription});

  @override
  Widget build(BuildContext context) {
    final rx = prescription;
    final patient = rx['patientId'];
    final patientName = patient is Map ? (patient['name'] ?? 'Patient') : 'Patient';
    final patientId = patient is Map ? (patient['_id'] ?? '') : (patient?.toString() ?? '');
    
    final appointment = rx['appointmentId'];
    final diagnosisRaw = rx['diagnosis'];
    String diagnosis = 'N/A';
    if (diagnosisRaw is List) {
      diagnosis = diagnosisRaw.join(', ');
    } else if (diagnosisRaw != null) {
      diagnosis = diagnosisRaw.toString();
    }

    final notesRaw = rx['notes'] ?? rx['advice'];
    String notes = 'No additional notes provided.';
    if (notesRaw is List) {
      notes = notesRaw.map((e) => e is Map ? (e['advice'] ?? e.toString()) : e.toString()).join('\n');
    } else if (notesRaw != null && notesRaw.toString().isNotEmpty) {
      notes = notesRaw.toString();
    }
    final medicines = rx['medicines'] ?? [];
    
    String dateStr = 'N/A';
    if (rx['createdAt'] != null) {
      try {
        final d = DateTime.parse(rx['createdAt']);
        dateStr = '${d.day}/${d.month}/${d.year} at ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text('Prescription Details', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white, foregroundColor: AppTheme.textPrimary, elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Patient & Info Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.border)),
              child: Column(children: [
                Row(children: [
                  Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(gradient: AppTheme.doctorGradient, shape: BoxShape.circle),
                    child: Center(child: Text(patientName[0], style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white))),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(patientName, style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700)),
                    Text('Patient ID: $patientId', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textTertiary)),
                  ])),
                ]),
                const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1)),
                _infoRow(Iconsax.calendar, 'Issued On', dateStr),
                const SizedBox(height: 12),
                _infoRow(Iconsax.health, 'Diagnosis', diagnosis, isBold: true),
              ]),
            ),
            const SizedBox(height: 24),

            // Medicines
            Row(children: [
              const Icon(Iconsax.status_up, size: 20, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text('Prescribed Medicines', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            ]),
            const SizedBox(height: 12),
            if (medicines.isEmpty)
              _emptyState('No medicines listed')
            else
              ...medicines.asMap().entries.map((entry) => _medicineCard(entry.key + 1, entry.value)),
            
            const SizedBox(height: 24),

            // Notes
            Text('Doctor\'s Notes', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
              child: Text(notes, style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppTheme.textSecondary, height: 1.5)),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppTheme.border))),
        child: SafeArea(
          child: ElevatedButton.icon(
            onPressed: () {
              // Later: Export to PDF
            },
            icon: const Icon(Iconsax.printer, size: 18),
            label: Text('Print / Share PDF', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {bool isBold = false}) {
    return Row(children: [
      Icon(icon, size: 16, color: AppTheme.textTertiary),
      const SizedBox(width: 8),
      Text('$label: ', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textSecondary)),
      Expanded(child: Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: isBold ? FontWeight.w700 : FontWeight.w600, color: AppTheme.textPrimary))),
    ]);
  }

  Widget _medicineCard(int index, Map<String, dynamic> med) {
    final name = (med['name'] ?? med['medicineName'] ?? 'Unknown Medicine').toString();
    final dosage = (med['dosage'] ?? 'N/A').toString();
    final freq = (med['frequency'] ?? 'N/A').toString();
    final duration = (med['duration'] ?? 'N/A').toString();
    final instructions = (med['instructions'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Center(child: Text('$index', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary))),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          _medInfo('Dosage', dosage),
          _medInfo('Frequency', freq),
          _medInfo('Duration', duration),
        ]),
        if (instructions.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Iconsax.info_circle, size: 14, color: AppTheme.textTertiary),
            const SizedBox(width: 8),
            Expanded(child: Text(instructions, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary, fontStyle: FontStyle.italic))),
          ]),
        ],
      ]),
    );
  }

  Widget _medInfo(String label, String value) {
    return Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppTheme.textTertiary, fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
    ]));
  }

  Widget _emptyState(String msg) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
      child: Center(child: Text(msg, style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppTheme.textSecondary))),
    );
  }
}
