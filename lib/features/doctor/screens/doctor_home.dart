import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../auth/providers/auth_provider.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import 'doctor_availability.dart';
import 'doctor_prescriptions.dart';
import 'doctor_calendar.dart';
import 'doctor_schedule.dart';

class DoctorHome extends ConsumerStatefulWidget {
  const DoctorHome({super.key});

  @override
  ConsumerState<DoctorHome> createState() => _DoctorHomeState();
}

class _DoctorHomeState extends ConsumerState<DoctorHome> {
  @override
  void initState() {
    super.initState();
    // Load all dashboard data on init
    Future.microtask(() {
      ref.read(doctorDashboardProvider.notifier).loadAll();
    });
  }

  Future<void> _refresh() async {
    await ref.read(doctorDashboardProvider.notifier).loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final dashData = ref.watch(doctorDashboardProvider);
    final stats = dashData.stats;

    // Extract stats with fallbacks
    final totalAppointments = stats['totalAppointments'] ?? stats['appointmentsToday'] ?? stats['appointments'] ?? '--';
    final totalEarnings = stats['totalEarnings'] ?? stats['earnings'] ?? stats['monthlyEarnings'] ?? '--';
    final totalPatients = stats['totalPatients'] ?? stats['patients'] ?? stats['totalConsultations'] ?? '--';
    final avgRating = stats['averageRating'] ?? stats['rating'] ?? '--';

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: AppTheme.primary,
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
                          Text(
                            'Welcome back 👋',
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user?.name ?? 'Doctor',
                            style: GoogleFonts.manrope(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Badge(
                        smallSize: 8,
                        child: const Icon(CupertinoIcons.bell, size: 22, color: AppTheme.textPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Loading indicator
                if (dashData.isLoading && stats.isEmpty)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  ))
                else ...[
                  // Error banner
                  if (dashData.error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(CupertinoIcons.exclamationmark_triangle, size: 18, color: AppTheme.warning),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Using cached data. ${dashData.error}',
                              style: GoogleFonts.manrope(fontSize: 12, color: AppTheme.warning),
                            ),
                          ),
                          GestureDetector(
                            onTap: _refresh,
                            child: const Icon(CupertinoIcons.refresh, size: 18, color: AppTheme.warning),
                          ),
                        ],
                      ),
                    ),

                  // Stats Grid
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.3,
                    children: [
                      StatCard(
                        title: 'Appointments',
                        value: _formatStat(totalAppointments),
                        icon: CupertinoIcons.calendar_badge_plus,
                        color: AppTheme.primary,
                      ),
                      StatCard(
                        title: 'Total Earnings',
                        value: _formatEarnings(totalEarnings),
                        icon: CupertinoIcons.money_dollar_circle,
                        color: AppTheme.success,
                      ),
                      StatCard(
                        title: 'Patients',
                        value: _formatStat(totalPatients),
                        icon: CupertinoIcons.person_2,
                        color: AppTheme.accent,
                      ),
                      StatCard(
                        title: 'Avg. Rating',
                        value: _formatRating(avgRating),
                        icon: CupertinoIcons.star,
                        color: AppTheme.warning,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Weekly Chart
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Weekly Appointments',
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'This Week',
                                style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primary),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 180,
                          child: BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: 10,
                              barTouchData: BarTouchData(enabled: true),
                              titlesData: FlTitlesData(
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (value, meta) {
                                      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(days[value.toInt()], style: GoogleFonts.manrope(fontSize: 11, color: AppTheme.textTertiary)),
                                      );
                                    },
                                    reservedSize: 28,
                                  ),
                                ),
                                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              gridData: const FlGridData(show: false),
                              borderData: FlBorderData(show: false),
                              barGroups: _buildWeeklyBars(stats),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Quick Actions
                  Text('Quick Actions', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _quickAction(CupertinoIcons.calendar, 'Availability', AppTheme.primary, () {
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DoctorAvailability()));
                      })),
                      const SizedBox(width: 12),
                      Expanded(child: _quickAction(CupertinoIcons.doc_text, 'Prescriptions', AppTheme.accent, () {
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DoctorPrescriptions()));
                      })),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: _quickAction(CupertinoIcons.calendar_badge_plus, 'Calendar', AppTheme.success, () {
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DoctorCalendar()));
                      })),
                      const SizedBox(width: 12),
                      Expanded(child: _quickAction(CupertinoIcons.clock, 'Schedule', const Color(0xFF7C3AED), () {
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DoctorSchedule()));
                      })),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Upcoming appointments from API
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Upcoming Appointments', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                      TextButton(
                        onPressed: () {},
                        child: Text('View All', style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._buildAppointmentCards(dashData.appointments),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<BarChartGroupData> _buildWeeklyBars(Map<String, dynamic> stats) {
    // Try to extract weekly data from backend response
    final weeklyData = stats['weeklyAppointments'] ?? stats['weekly'];
    if (weeklyData is List && weeklyData.length >= 7) {
      return List.generate(7, (i) {
        final val = (weeklyData[i] is num) ? weeklyData[i].toDouble() : 0.0;
        return BarChartGroupData(x: i, barRods: [
          BarChartRodData(toY: val, color: AppTheme.primary, width: 18, borderRadius: const BorderRadius.vertical(top: Radius.circular(6))),
        ]);
      });
    }
    // Fallback: show empty bars
    return List.generate(7, (i) => BarChartGroupData(x: i, barRods: [
      BarChartRodData(toY: 0, color: AppTheme.primary.withValues(alpha: 0.3), width: 18, borderRadius: const BorderRadius.vertical(top: Radius.circular(6))),
    ]));
  }

  Widget _quickAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 8),
            Text(label, style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w600, color: color), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAppointmentCards(List<Map<String, dynamic>> appointments) {
    if (appointments.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
          child: Center(
            child: Column(
              children: [
                Icon(CupertinoIcons.calendar, size: 40, color: AppTheme.textTertiary.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                Text('No upcoming appointments', style: GoogleFonts.manrope(fontSize: 14, color: AppTheme.textSecondary)),
              ],
            ),
          ),
        ),
      ];
    }

    return appointments.take(5).map((apt) {
      final patientName = apt['patientId']?['name'] ?? apt['patientName'] ?? 'Patient';
      final status = apt['status'] ?? 'pending';
      final type = apt['type'] ?? 'clinic';
      final reason = apt['reason'] ?? apt['symptoms']?.toString() ?? 'Consultation';
      final fee = apt['consultationFee'] ?? apt['totalAmount'] ?? 0;
      final date = apt['appointmentDate'] ?? '';
      final time = apt['startTime'] ?? '';

      final statusColor = status == 'confirmed' || status == 'accepted'
          ? AppTheme.primary
          : status == 'pending'
              ? AppTheme.warning
              : AppTheme.success;

      final typeIcon = type == 'video'
          ? CupertinoIcons.video_camera
          : type == 'home'
              ? CupertinoIcons.house
              : Icons.local_hospital_outlined;

      return Container(
        margin: const EdgeInsets.only(bottom: 10),
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
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(gradient: AppTheme.doctorGradient, borderRadius: BorderRadius.circular(12)),
                  child: Center(child: Text(patientName[0], style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(patientName, style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                      const SizedBox(height: 2),
                      Text(reason, style: GoogleFonts.manrope(fontSize: 12, color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(status, style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(CupertinoIcons.calendar, size: 14, color: AppTheme.textTertiary),
                const SizedBox(width: 6),
                Text(_formatDate(date), style: GoogleFonts.manrope(fontSize: 12, color: AppTheme.textSecondary)),
                const SizedBox(width: 14),
                const Icon(CupertinoIcons.clock, size: 14, color: AppTheme.textTertiary),
                const SizedBox(width: 6),
                Text(time, style: GoogleFonts.manrope(fontSize: 12, color: AppTheme.textSecondary)),
                const SizedBox(width: 14),
                Icon(typeIcon, size: 14, color: AppTheme.textTertiary),
                const SizedBox(width: 6),
                Text(type, style: GoogleFonts.manrope(fontSize: 12, color: AppTheme.textSecondary)),
                const Spacer(),
                Text('₹$fee', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primary)),
              ],
            ),
          ],
        ),
      );
    }).toList();
  }

  String _formatStat(dynamic value) {
    if (value is num) return value.toStringAsFixed(0);
    return value?.toString() ?? '--';
  }

  String _formatEarnings(dynamic value) {
    if (value is num) {
      if (value >= 100000) return '₹${(value / 100000).toStringAsFixed(1)}L';
      if (value >= 1000) return '₹${(value / 1000).toStringAsFixed(1)}K';
      return '₹$value';
    }
    if (value is String && value.startsWith('₹')) return value;
    return value?.toString() ?? '₹0';
  }

  String _formatRating(dynamic value) {
    if (value is num) return value.toStringAsFixed(1);
    return value?.toString() ?? '--';
  }

  String _formatDate(dynamic date) {
    if (date is String && date.isNotEmpty) {
      try {
        final dt = DateTime.parse(date);
        final now = DateTime.now();
        if (dt.year == now.year && dt.month == now.month && dt.day == now.day) return 'Today';
        if (dt.year == now.year && dt.month == now.month && dt.day == now.day + 1) return 'Tomorrow';
        return '${dt.day}/${dt.month}';
      } catch (_) {}
    }
    return date?.toString() ?? '';
  }
}
