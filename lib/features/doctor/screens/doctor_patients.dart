import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_service.dart';
import 'patient_history.dart';

class DoctorPatients extends ConsumerStatefulWidget {
  const DoctorPatients({super.key});

  @override
  ConsumerState<DoctorPatients> createState() => _DoctorPatientsState();
}

class _DoctorPatientsState extends ConsumerState<DoctorPatients> {
  List<Map<String, dynamic>> _patients = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  Future<void> _loadPatients() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      // Doctor patients come from appointments - extract unique patients
      final response = await ApiService().getDoctorAppointments();
      final data = response.data;
      final appointments = _extractList(data);

      // Group by patient to get unique patients
      final Map<String, Map<String, dynamic>> patientMap = {};
      for (final apt in appointments) {
        final patientId = apt['patientId'];
        final id = patientId is Map ? (patientId['_id'] ?? '') : (patientId?.toString() ?? '');
        if (id.isEmpty) continue;

        if (!patientMap.containsKey(id)) {
          patientMap[id] = {
            'id': id,
            'name': patientId is Map ? (patientId['name'] ?? 'Patient') : 'Patient',
            'phone': patientId is Map ? (patientId['phone'] ?? '') : '',
            'email': patientId is Map ? (patientId['email'] ?? '') : '',
            'visits': 1,
            'lastVisit': apt['appointmentDate'] ?? '',
          };
        } else {
          patientMap[id]!['visits'] = (patientMap[id]!['visits'] as int) + 1;
        }
      }

      setState(() {
        _patients = patientMap.values.toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  List<Map<String, dynamic>> _extractList(dynamic data) {
    if (data == null) return [];
    if (data is List) return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (data is Map) {
      for (final key in ['data', 'appointments', 'patients']) {
        if (data[key] is List) return (data[key] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Patients', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                  const SizedBox(height: 4),
                  Text('${_patients.length} patients', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search patients...', prefixIcon: const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Icon(Iconsax.search_normal, size: 18, color: AppTheme.textTertiary)),
                  filled: true, fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : RefreshIndicator(
                      onRefresh: _loadPatients,
                      child: _patients.isEmpty
                          ? ListView(children: [
                              const SizedBox(height: 80),
                              Center(child: Column(children: [
                                Icon(Iconsax.people, size: 48, color: AppTheme.textTertiary.withValues(alpha: 0.5)),
                                const SizedBox(height: 12),
                                Text(_error ?? 'No patients yet', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppTheme.textSecondary)),
                              ])),
                            ])
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              itemCount: _patients.length,
                              itemBuilder: (context, i) {
                                final p = _patients[i];
                                return GestureDetector(
                                  onTap: () {
                                    final patientId = p['id']?.toString() ?? '';
                                    if (patientId.isNotEmpty) {
                                      Navigator.of(context).push(MaterialPageRoute(
                                        builder: (_) => PatientHistoryScreen(
                                          patientId: patientId,
                                          patientName: p['name'] ?? 'Patient',
                                        ),
                                      ));
                                    }
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 44, height: 44,
                                          decoration: BoxDecoration(gradient: AppTheme.doctorGradient, borderRadius: BorderRadius.circular(12)),
                                          child: Center(child: Text((p['name'] ?? 'P')[0], style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white))),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(p['name'] ?? 'Patient', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                                              const SizedBox(height: 2),
                                              Text(p['phone'] ?? '', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  const Icon(Iconsax.chart_square, size: 12, color: AppTheme.textTertiary),
                                                  const SizedBox(width: 4),
                                                  Text('${p['visits']} visits', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textTertiary)),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(8)),
                                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                                            const Icon(Iconsax.arrow_right_3, size: 14, color: AppTheme.primary),
                                            const SizedBox(width: 4),
                                            Text('History', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                                          ]),
                                        ),
                                      ],
                                    ),
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
