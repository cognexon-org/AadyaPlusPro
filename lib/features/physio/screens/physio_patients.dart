import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import 'physio_patient_details.dart';

class PhysioPatients extends ConsumerStatefulWidget {
  const PhysioPatients({super.key});

  @override
  ConsumerState<PhysioPatients> createState() => _PhysioPatientsState();
}

class _PhysioPatientsState extends ConsumerState<PhysioPatients> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(physioDashboardProvider.notifier).loadPatients());
  }

  Future<void> _refresh() async {
    await ref.read(physioDashboardProvider.notifier).loadPatients();
  }

  @override
  Widget build(BuildContext context) {
    final dashData = ref.watch(physioDashboardProvider);
    // Patients stored in recentTransactions field
    final patients = dashData.recentTransactions;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('My Patients', style: GoogleFonts.manrope(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                const SizedBox(height: 4),
                Text('${patients.length} patients', style: GoogleFonts.manrope(fontSize: 13, color: AppTheme.textSecondary)),
              ]),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search patients...', prefixIcon: const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Icon(CupertinoIcons.search, size: 18, color: AppTheme.textTertiary)),
                  filled: true, fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: dashData.isLoading && patients.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.physioAccent))
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: patients.isEmpty
                          ? ListView(children: [
                              const SizedBox(height: 80),
                              Center(child: Column(children: [
                                Icon(CupertinoIcons.person_2, size: 48, color: AppTheme.textTertiary.withValues(alpha: 0.5)),
                                const SizedBox(height: 12),
                                Text('No patients yet', style: GoogleFonts.manrope(fontSize: 14, color: AppTheme.textSecondary)),
                              ])),
                            ])
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              itemCount: patients.length,
                              itemBuilder: (ctx, i) {
                                final p = patients[i];
                                final name = p['name'] ?? p['patientId']?['name'] ?? 'Patient';
                                final phone = p['phone'] ?? '';
                                final sessions = p['totalVisits'] ?? p['totalSessions'] ?? p['sessions'] ?? 0;
                                return GestureDetector(
                                  onTap: () {
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => PhysioPatientDetails(patient: p)));
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
                                    child: Row(children: [
                                      Container(
                                        width: 44, height: 44,
                                        decoration: BoxDecoration(gradient: AppTheme.physioGradient, borderRadius: BorderRadius.circular(12)),
                                        child: Center(child: Text(name[0].toUpperCase(), style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white))),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text(name, style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                                        if (phone.isNotEmpty) Text(phone, style: GoogleFonts.manrope(fontSize: 12, color: AppTheme.textSecondary)),
                                        Row(children: [
                                          const Icon(CupertinoIcons.chart_bar_square, size: 12, color: AppTheme.textTertiary),
                                          const SizedBox(width: 4),
                                          Text('$sessions sessions', style: GoogleFonts.manrope(fontSize: 11, color: AppTheme.textTertiary)),
                                        ]),
                                      ])),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(border: Border.all(color: AppTheme.physioAccent.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(8)),
                                        child: Text('View', style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.physioAccent)),
                                      ),
                                    ]),
                                  ),
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
