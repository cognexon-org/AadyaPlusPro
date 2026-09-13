import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../auth/providers/auth_provider.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import 'physio_availability.dart';
import 'physio_exercises.dart';
import 'physio_appointment_details.dart';
import 'physio_appointments.dart';

class PhysioHome extends ConsumerStatefulWidget {
  const PhysioHome({super.key});

  @override
  ConsumerState<PhysioHome> createState() => _PhysioHomeState();
}

class _PhysioHomeState extends ConsumerState<PhysioHome> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(physioDashboardProvider.notifier).loadAll());
  }

  Future<void> _refresh() async {
    await ref.read(physioDashboardProvider.notifier).loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final dashData = ref.watch(physioDashboardProvider);
    final stats = dashData.stats;

    final upcoming = stats['totalAppointments'] ?? stats['upcoming'] ?? '--';
    final earnings = stats['totalEarnings'] ?? stats['earnings'] ?? '--';
    final patients = stats['totalPatients'] ?? stats['patients'] ?? '--';
    final homeVisits = stats['homeVisits'] ?? '--';

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: AppTheme.physioAccent,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Welcome back 👋', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppTheme.textSecondary)),
                          const SizedBox(height: 4),
                          Text(user?.name ?? 'Physiotherapist', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
                      child: Badge(smallSize: 8, child: const Icon(Iconsax.notification, size: 22, color: AppTheme.textPrimary)),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                if (dashData.isLoading && stats.isEmpty)
                  const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: AppTheme.physioAccent)))
                else ...[
                  // Stats Grid
                  GridView.count(
                    crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.3,
                    children: [
                      StatCard(title: 'Upcoming', value: _fmt(upcoming), icon: Iconsax.calendar_tick, color: AppTheme.physioAccent),
                      StatCard(title: 'Earnings', value: _fmtCurrency(earnings), icon: Iconsax.money_recive, color: AppTheme.success),
                      StatCard(title: 'Patients', value: _fmt(patients), icon: Iconsax.people, color: AppTheme.accent),
                      StatCard(title: 'Home Visits', value: _fmt(homeVisits), icon: Iconsax.home, color: AppTheme.warning),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Weekly Chart
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Weekly Performance', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                            Container(
                               padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                               decoration: BoxDecoration(color: AppTheme.physioAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                               child: Text('This Week', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.physioAccent)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 180,
                          child: BarChart(BarChartData(
                            alignment: BarChartAlignment.spaceAround, maxY: 10,
                            titlesData: FlTitlesData(
                              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) {
                                const d = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                                if (v.toInt() >= 0 && v.toInt() < 7) {
                                  return Padding(padding: const EdgeInsets.only(top: 8), child: Text(d[v.toInt()], style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textTertiary)));
                                }
                                return const SizedBox();
                              }, reservedSize: 28)),
                              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                            gridData: const FlGridData(show: false), borderData: FlBorderData(show: false),
                            barGroups: _buildWeeklyBars(stats),
                          )),
                        ),
                        const SizedBox(height: 12),
                        Row(children: [
                          _legend(AppTheme.physioAccent, 'Clinic'),
                          const SizedBox(width: 16),
                          _legend(AppTheme.primary, 'Home Visit'),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Quick Actions
                  Text('Quick Actions', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _quickAction(Iconsax.calendar, 'Availability', AppTheme.physioAccent, () {
                      Navigator.push(context, MaterialPageRoute(builder: (c) => const PhysioAvailability()));
                    })),
                    const SizedBox(width: 12),
                    Expanded(child: _quickAction(Iconsax.activity, 'Exercises', AppTheme.primary, () {
                      Navigator.push(context, MaterialPageRoute(builder: (c) => const PhysioExercises()));
                    })),
                  ]),
                  const SizedBox(height: 24),

                  // Upcoming Sessions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Upcoming Sessions', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                      TextButton(
                        onPressed: () {
                           Navigator.push(context, MaterialPageRoute(builder: (c) => const PhysioAppointments()));
                        }, 
                        child: Text('View All', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.physioAccent)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._buildSessionCards(dashData.appointments),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<BarChartGroupData> _buildWeeklyBars(Map<String, dynamic> stats) {
    final weekly = stats['weeklySessions'] ?? stats['weekly'];
    if (weekly is List && weekly.length >= 7) {
      return List.generate(7, (i) {
        final clinic = (weekly[i] is Map ? weekly[i]['clinic'] ?? 0 : weekly[i]) as num;
        final home = (weekly[i] is Map ? weekly[i]['home'] ?? 0 : 0) as num;
        return BarChartGroupData(x: i, barRods: [
          BarChartRodData(toY: clinic.toDouble(), color: AppTheme.physioAccent, width: 10, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
          BarChartRodData(toY: home.toDouble(), color: AppTheme.primary, width: 10, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
        ]);
      });
    }
    return List.generate(7, (i) => BarChartGroupData(x: i, barRods: [
      BarChartRodData(toY: 0, color: AppTheme.physioAccent.withValues(alpha: 0.3), width: 10, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
      BarChartRodData(toY: 0, color: AppTheme.primary.withValues(alpha: 0.3), width: 10, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
    ]));
  }

  Widget _legend(Color color, String label) {
    return Row(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 6),
      Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textSecondary)),
    ]);
  }

  Widget _quickAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.12))),
        child: Column(children: [
          Icon(icon, size: 24, color: color),
          const SizedBox(height: 8),
          Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: color), textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  List<Widget> _buildSessionCards(List<Map<String, dynamic>> appointments) {
    if (appointments.isEmpty) {
      return [Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
        child: Column(
          children: [
            Icon(Iconsax.calendar, size: 32, color: AppTheme.textTertiary.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text('No upcoming sessions', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppTheme.textSecondary)),
          ],
        ),
      )];
    }
    return appointments.take(3).map((apt) {
      final name = apt['patientId']?['name'] ?? apt['patientName'] ?? 'Patient';
      final time = apt['startTime'] ?? '--:--';
      final type = (apt['type'] ?? 'clinic').toString();
      final status = (apt['status'] ?? 'pending').toString();
      
      final statusColor = status == 'confirmed' || status == 'accepted' ? AppTheme.physioAccent : status == 'pending' ? AppTheme.warning : AppTheme.success;

      return GestureDetector(
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (c) => PhysioAppointmentDetails(appointment: apt)));
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(gradient: AppTheme.physioGradient, borderRadius: BorderRadius.circular(14)),
              child: Center(child: Text(name[0], style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(type == 'home' ? Iconsax.home : Iconsax.hospital, size: 12, color: AppTheme.textTertiary),
                  const SizedBox(width: 4),
                  Text('$time • ${type.toUpperCase()}', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(status.toUpperCase(), style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
            ),
          ]),
        ),
      );
    }).toList();
  }

  String _fmt(dynamic v) => v is num ? v.toStringAsFixed(0) : v?.toString() ?? '--';
  String _fmtCurrency(dynamic v) {
    if (v is num) {
      if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(1)}L';
      if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(0)}K';
      return '₹${v.toStringAsFixed(0)}';
    }
    return v?.toString() ?? '₹0';
  }
}
