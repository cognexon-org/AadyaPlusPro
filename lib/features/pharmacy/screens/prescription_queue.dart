import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../dashboard/providers/dashboard_provider.dart';

class PrescriptionQueue extends ConsumerStatefulWidget {
  const PrescriptionQueue({super.key});

  @override
  ConsumerState<PrescriptionQueue> createState() => _PrescriptionQueueState();
}

class _PrescriptionQueueState extends ConsumerState<PrescriptionQueue> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(pharmacyDashboardProvider.notifier).loadPrescriptions());
  }

  @override
  Widget build(BuildContext context) {
    final dashData = ref.watch(pharmacyDashboardProvider);
    final prescriptions = dashData.prescriptions;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Prescription Queue', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                  Text('View and dispense medications', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search prescriptions...',
                  prefixIcon: const Icon(Iconsax.search_normal, size: 18, color: AppTheme.textTertiary),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
                ),
              ),
            ),
            
            const SizedBox(height: 12),
            
            dashData.isLoading && prescriptions.isEmpty
                ? const Expanded(child: Center(child: CircularProgressIndicator(color: AppTheme.accent)))
                : prescriptions.isEmpty
                    ? Expanded(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Iconsax.document_text, size: 48, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              Text('No prescriptions found', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppTheme.textSecondary)),
                            ],
                          ),
                        ),
                      )
                    : Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: prescriptions.length,
                          itemBuilder: (context, index) {
                            final p = prescriptions[index];
                            final patientName = p['patientId']?['name'] ?? 'Unknown Patient';
                            final doctorName = p['doctorId']?['name'] ?? p['physioId']?['name'] ?? 'Doctor';
                            final date = p['issuedAt'] != null 
                              ? DateFormat('dd MMM yyyy').format(DateTime.parse(p['issuedAt']))
                              : 'Date N/A';
                            final status = p['status'] ?? 'issued';
                            final items = (p['medicines'] as List?) ?? [];
                            final prescriptionNumber = p['prescriptionNumber'] ?? 'PRES-${p['_id'].toString().substring(0, 6).toUpperCase()}';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(prescriptionNumber, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.accent)),
                                      _statusBadge(status),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(color: AppTheme.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                                        child: const Center(child: Icon(Iconsax.user, size: 20, color: AppTheme.accent)),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(patientName, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                                            Text('Prescribed by Dr. $doctorName', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 24),
                                  Text('Medicines (${items.length})', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                                  const SizedBox(height: 8),
                                  ...items.take(3).map((item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.circle, size: 6, color: AppTheme.accent),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(item['medicineName'] ?? 'Med', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary))),
                                      ],
                                    ),
                                  )),
                                  if (items.length > 3)
                                    Text('+ ${items.length - 3} more', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.accent, fontWeight: FontWeight.w500)),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(date, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textTertiary)),
                                      ElevatedButton(
                                        onPressed: () {
                                          // Navigate to dispensing detail screen
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.accent,
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: Text('Dispense', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color color;
    switch (status.toLowerCase()) {
      case 'issued':
        color = AppTheme.info;
        break;
      case 'partially_dispensed':
        color = AppTheme.warning;
        break;
      case 'fully_dispensed':
        color = AppTheme.success;
        break;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(status.toUpperCase(), style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
