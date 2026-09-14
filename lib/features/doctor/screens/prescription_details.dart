import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/theme/app_theme.dart';

class PrescriptionDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> prescription;

  const PrescriptionDetailsScreen({super.key, required this.prescription});

  String _listText(dynamic value, {String fallback = 'N/A'}) {
    if (value is List) {
      final text = value.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).join(', ');
      return text.isEmpty ? fallback : text;
    }
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String _date(dynamic value) {
    if (value == null) return 'N/A';
    try {
      final d = DateTime.parse(value.toString()).toLocal();
      return '${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return value.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rx = prescription;
    final patient = rx['patientId'];
    final patientName = patient is Map ? (patient['name'] ?? 'Patient').toString() : 'Patient';
    final patientId = patient is Map ? (patient['_id'] ?? '').toString() : (patient?.toString() ?? '');
    final status = (rx['status'] ?? 'draft').toString();
    final medicines = rx['medicines'] is List ? rx['medicines'] as List : const [];
    final exercises = rx['exercises'] is List ? rx['exercises'] as List : const [];
    final labTests = rx['labTests'] is List ? rx['labTests'] as List : const [];
    final advice = rx['advice'] is List ? rx['advice'] as List : const [];
    final diagnosis = _listText(rx['diagnosis']);
    final issuedOn = _date(rx['issuedAt'] ?? rx['createdAt']);
    final followUpDate = rx['followUpDate'];

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text('Prescription Details', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 25,
                        backgroundColor: AppTheme.primary,
                        child: Text(
                          patientName.isEmpty ? 'P' : patientName[0].toUpperCase(),
                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(patientName, style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700)),
                            Text('Patient ID: $patientId', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textTertiary)),
                          ],
                        ),
                      ),
                      _statusChip(status),
                    ],
                  ),
                  const Divider(height: 28),
                  _infoRow(Iconsax.calendar, status == 'draft' ? 'Created' : 'Issued', issuedOn),
                  const SizedBox(height: 10),
                  _infoRow(Iconsax.health, 'Diagnosis', diagnosis, isBold: true),
                  if (rx['prescriptionNumber'] != null) ...[
                    const SizedBox(height: 10),
                    _infoRow(Iconsax.document_text, 'Rx No.', rx['prescriptionNumber'].toString()),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            _sectionTitle(Iconsax.health, 'Medicines'),
            const SizedBox(height: 10),
            if (medicines.isEmpty)
              _emptyState('No medicines prescribed')
            else
              ...medicines.asMap().entries.map((entry) {
                final raw = entry.value;
                final med = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
                return _medicineCard(entry.key + 1, med);
              }),
            if (exercises.isNotEmpty) ...[
              const SizedBox(height: 24),
              _sectionTitle(Iconsax.activity, 'Exercises'),
              const SizedBox(height: 10),
              ...exercises.map((raw) {
                final ex = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
                return _textCard(
                  (ex['name'] ?? 'Exercise').toString(),
                  [
                    if (ex['sets'] != null) 'Sets: ${ex['sets']}',
                    if (ex['reps'] != null) 'Reps: ${ex['reps']}',
                    if (ex['duration'] != null) 'Duration: ${ex['duration']}',
                    if ((ex['instructions'] ?? '').toString().isNotEmpty) ex['instructions'].toString(),
                  ].join(' • '),
                );
              }),
            ],
            if (labTests.isNotEmpty) ...[
              const SizedBox(height: 24),
              _sectionTitle(Iconsax.document, 'Recommended tests'),
              const SizedBox(height: 10),
              _textCard('Tests', labTests.map((e) => e is Map ? (e['testName'] ?? e['name'] ?? e.toString()) : e).join(', ')),
            ],
            if (advice.isNotEmpty) ...[
              const SizedBox(height: 24),
              _sectionTitle(Iconsax.note, 'Advice'),
              const SizedBox(height: 10),
              ...advice.map((e) {
                final text = e is Map ? (e['advice'] ?? e['text'] ?? e.toString()).toString() : e.toString();
                return _textCard('Advice', text);
              }),
            ],
            if (followUpDate != null) ...[
              const SizedBox(height: 24),
              _sectionTitle(Iconsax.calendar_tick, 'Follow-up'),
              const SizedBox(height: 10),
              _textCard('Follow-up date', _date(followUpDate)),
            ],
            if (status == 'draft') ...[
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Draft prescription — issue it from the consultation workspace before the patient can view it.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(IconData icon, String title) => Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.primary),
          const SizedBox(width: 8),
          Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      );

  Widget _statusChip(String status) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: (status == 'issued' ? AppTheme.success : AppTheme.warning).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          status.toUpperCase(),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: status == 'issued' ? AppTheme.success : AppTheme.warning,
          ),
        ),
      );

  Widget _infoRow(IconData icon, String label, String value, {bool isBold = false}) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppTheme.textTertiary),
          const SizedBox(width: 8),
          Text('$label: ', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textSecondary)),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      );

  Widget _medicineCard(int index, Map<String, dynamic> med) {
    final name = (med['medicineName'] ?? med['name'] ?? 'Medicine').toString();
    final details = [
      if ((med['dosage'] ?? '').toString().isNotEmpty) 'Dose: ${med['dosage']}',
      if ((med['frequency'] ?? '').toString().isNotEmpty) 'Frequency: ${med['frequency']}',
      if ((med['duration'] ?? '').toString().isNotEmpty) 'Duration: ${med['duration']}',
    ].join(' • ');
    return _textCard('$index. $name', [details, med['instructions']].where((e) => e != null && e.toString().trim().isNotEmpty).join('\n'));
  }

  Widget _textCard(String title, String body) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
            if (body.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(body, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary, height: 1.4)),
            ],
          ],
        ),
      );

  Widget _emptyState(String message) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Text(message, textAlign: TextAlign.center, style: GoogleFonts.plusJakartaSans(color: AppTheme.textSecondary)),
      );
}
