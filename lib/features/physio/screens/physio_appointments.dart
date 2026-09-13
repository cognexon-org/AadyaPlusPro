import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/theme/app_theme.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import 'physio_appointment_details.dart';

class PhysioAppointments extends ConsumerStatefulWidget {
  const PhysioAppointments({super.key});

  @override
  ConsumerState<PhysioAppointments> createState() => _PhysioAppointmentsState();
}

class _PhysioAppointmentsState extends ConsumerState<PhysioAppointments> {
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(physioDashboardProvider.notifier).loadAppointments());
  }

  Future<void> _refresh() async {
    await ref.read(physioDashboardProvider.notifier).loadAppointments(status: _filter);
  }

  @override
  Widget build(BuildContext context) {
    final dashData = ref.watch(physioDashboardProvider);
    final appointments = dashData.appointments.where((a) {
      if (_filter == 'all') return true;
      return a['status'] == _filter;
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Appointments', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                const SizedBox(height: 4),
                Text('Manage your therapy sessions', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textSecondary)),
              ]),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildFilters(),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: dashData.isLoading && appointments.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.physioAccent))
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: appointments.isEmpty
                          ? ListView(children: [
                              const SizedBox(height: 80),
                              Center(child: Column(children: [
                                Icon(Iconsax.calendar, size: 48, color: AppTheme.textTertiary.withValues(alpha: 0.5)),
                                const SizedBox(height: 12),
                                Text('No sessions found', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppTheme.textSecondary)),
                              ])),
                            ])
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              itemCount: appointments.length,
                              itemBuilder: (ctx, i) => _card(appointments[i]),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ['all', 'pending', 'confirmed', 'completed'].map((opt) {
          final sel = _filter == opt;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () { setState(() => _filter = opt); _refresh(); },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? AppTheme.physioAccent : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: sel ? AppTheme.physioAccent : AppTheme.divider),
                ),
                child: Text(opt == 'all' ? 'All' : opt[0].toUpperCase() + opt.substring(1),
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w500, color: sel ? Colors.white : AppTheme.textSecondary)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _card(Map<String, dynamic> apt) {
    final name = apt['patientId']?['name'] ?? apt['patientName'] ?? 'Patient';
    final status = (apt['status'] ?? 'pending').toString();
    final type = apt['type'] == 'home' ? 'Home Visit' : 'Clinic';
    final time = apt['startTime'] ?? '';
    final date = apt['appointmentDate'] ?? '';

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => PhysioAppointmentDetails(appointment: apt)));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
        child: Column(children: [
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(gradient: AppTheme.physioGradient, borderRadius: BorderRadius.circular(12)),
              child: Center(child: Text(name[0].toUpperCase(), style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
              Text(type, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (status == 'confirmed' ? AppTheme.physioAccent : status == 'completed' ? AppTheme.success : AppTheme.warning).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(status.toUpperCase(), style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600,
                color: status == 'confirmed' ? AppTheme.physioAccent : status == 'completed' ? AppTheme.success : AppTheme.warning)),
            ),
          ]),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Iconsax.calendar, size: 14, color: AppTheme.textTertiary), const SizedBox(width: 4),
          Text(_fmtDate(date), style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(width: 14),
          const Icon(Iconsax.clock, size: 14, color: AppTheme.textTertiary), const SizedBox(width: 4),
          Text(time, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
        ]),
        if (status == 'pending') ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => _action(apt['_id'] ?? '', 'rejected'),
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.error, side: const BorderSide(color: AppTheme.error)),
              child: Text('Reject', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600)),
            )),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(
              onPressed: () => _action(apt['_id'] ?? '', 'accepted'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.physioAccent, foregroundColor: Colors.white, elevation: 0),
              child: Text('Accept', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600)),
            )),
          ]),
        ],
      ]),
      ),
    );
  }

  Future<void> _action(String id, String status) async {
    if (id.isEmpty) return;
    await ref.read(appointmentActionsProvider.notifier).updateStatus(id, status);
    _refresh();
  }

  String _fmtDate(dynamic d) {
    if (d is String && d.isNotEmpty) {
      try {
        final dt = DateTime.parse(d);
        final now = DateTime.now();
        if (dt.day == now.day && dt.month == now.month) return 'Today';
        return '${dt.day}/${dt.month}';
      } catch (_) {}
    }
    return d?.toString() ?? '';
  }
}
