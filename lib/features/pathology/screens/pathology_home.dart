import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../auth/providers/auth_provider.dart';
import '../../dashboard/providers/dashboard_provider.dart';

class PathologyHome extends ConsumerStatefulWidget {
  const PathologyHome({super.key});

  @override
  ConsumerState<PathologyHome> createState() => _PathologyHomeState();
}

class _PathologyHomeState extends ConsumerState<PathologyHome> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(pathologyDashboardProvider.notifier).loadDashboard();
      ref.read(pathologyDashboardProvider.notifier).loadAppointments();
    });
  }

  Future<void> _refresh() async {
    await ref.read(pathologyDashboardProvider.notifier).loadDashboard();
    await ref.read(pathologyDashboardProvider.notifier).loadAppointments();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final dashData = ref.watch(pathologyDashboardProvider);
    final stats = dashData.stats;

    final totalTests = stats['totalTests'] ?? stats['tests'] ?? '--';
    final earnings = stats['totalEarnings'] ?? stats['earnings'] ?? '--';
    final pending = stats['pendingTests'] ?? stats['pending'] ?? '--';
    final homeCollection = stats['homeCollections'] ?? stats['homeCollection'] ?? '--';

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: AppTheme.pathologyAccent,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Welcome back 👋', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppTheme.textSecondary)),
                    const SizedBox(height: 4),
                    Text(user?.name ?? 'Lab', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                  ])),
                  Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
                    child: Badge(smallSize: 8, child: const Icon(Iconsax.notification, size: 22, color: AppTheme.textPrimary))),
                ]),
                const SizedBox(height: 24),

                if (dashData.isLoading && stats.isEmpty)
                  const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: AppTheme.pathologyAccent)))
                else ...[
                  GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.3,
                    children: [
                      StatCard(title: 'Total Tests', value: _fmt(totalTests), icon: Iconsax.microscope, color: AppTheme.pathologyAccent),
                      StatCard(title: 'Earnings', value: _fmtCurrency(earnings), icon: Iconsax.money_recive, color: AppTheme.primary),
                      StatCard(title: 'Pending', value: _fmt(pending), icon: Iconsax.clock, color: AppTheme.warning),
                      StatCard(title: 'Home Collection', value: _fmt(homeCollection), icon: Iconsax.home, color: AppTheme.accent),
                    ]),
                  const SizedBox(height: 20),

                  Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Weekly Tests', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                      const SizedBox(height: 20),
                      SizedBox(height: 180, child: BarChart(BarChartData(alignment: BarChartAlignment.spaceAround, maxY: 15,
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) {
                            const d = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                            return Padding(padding: const EdgeInsets.only(top: 8), child: Text(d[v.toInt()], style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textTertiary)));
                          }, reservedSize: 28)),
                          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        gridData: const FlGridData(show: false), borderData: FlBorderData(show: false),
                        barGroups: _buildWeeklyBars(stats),
                      ))),
                      const SizedBox(height: 12),
                      Row(children: [_legend(AppTheme.pathologyAccent, 'Lab Tests'), const SizedBox(width: 16), _legend(AppTheme.primary, 'Home Collection')]),
                    ])),
                  const SizedBox(height: 20),

                  Text('Quick Actions', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  const SizedBox(height: 12),
                  _actionCard(Iconsax.microscope, 'Manage Test Catalog', 'Add/update lab tests & pricing', AppTheme.pathologyGradient),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _quickAction(Iconsax.calendar, 'Set Test Slots', AppTheme.primary)),
                    const SizedBox(width: 10),
                    Expanded(child: _quickAction(Iconsax.home, 'Home Collection', AppTheme.pathologyAccent)),
                  ]),
                  const SizedBox(height: 10),
                  _actionButton(Iconsax.document_upload, 'Upload Reports', 'Upload test results', AppTheme.accent),
                  const SizedBox(height: 20),

                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Recent Orders', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                    TextButton(onPressed: () {}, child: Text('View All', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.pathologyAccent))),
                  ]),
                  const SizedBox(height: 8),
                  ..._buildOrderCards(dashData.appointments),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<BarChartGroupData> _buildWeeklyBars(Map<String, dynamic> stats) {
    final weekly = stats['weeklyTests'] ?? stats['weekly'];
    if (weekly is List && weekly.length >= 7) {
      return List.generate(7, (i) {
        final lab = (weekly[i] is Map ? weekly[i]['lab'] ?? 0 : weekly[i]) as num;
        final home = (weekly[i] is Map ? weekly[i]['home'] ?? 0 : 0) as num;
        return BarChartGroupData(x: i, barRods: [
          BarChartRodData(toY: lab.toDouble(), color: AppTheme.pathologyAccent, width: 10, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
          BarChartRodData(toY: home.toDouble(), color: AppTheme.primary, width: 10, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
        ]);
      });
    }
    return List.generate(7, (i) => BarChartGroupData(x: i, barRods: [
      BarChartRodData(toY: 0, color: AppTheme.pathologyAccent.withValues(alpha: 0.3), width: 10, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
      BarChartRodData(toY: 0, color: AppTheme.primary.withValues(alpha: 0.3), width: 10, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
    ]));
  }

  Widget _legend(Color c, String l) => Row(children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 6), Text(l, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
  ]);

  Widget _actionCard(IconData icon, String t, String s, LinearGradient g) => Container(
    padding: const EdgeInsets.all(16), decoration: BoxDecoration(gradient: g, borderRadius: BorderRadius.circular(14)),
    child: Row(children: [
      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 22, color: Colors.white)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
        Text(s, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: Colors.white70)),
      ])),
      const Icon(Iconsax.arrow_right_3, color: Colors.white),
    ]));

  Widget _quickAction(IconData i, String l, Color c) => Container(
    padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withValues(alpha: 0.15))),
    child: Column(children: [
      Icon(i, size: 24, color: c), const SizedBox(height: 8),
      Text(l, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: c), textAlign: TextAlign.center),
    ]));

  Widget _actionButton(IconData i, String t, String s, Color c) => Container(
    padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: c.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withValues(alpha: 0.15))),
    child: Row(children: [
      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(i, size: 22, color: c)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        Text(s, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
      ])),
      Icon(Iconsax.arrow_right_3, color: c),
    ]));

  List<Widget> _buildOrderCards(List<Map<String, dynamic>> appointments) {
    if (appointments.isEmpty) {
      return [Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
        child: Center(child: Text('No recent orders', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppTheme.textSecondary))),
      )];
    }
    return appointments.take(5).map((o) {
      final name = o['patientId']?['name'] ?? o['patientName'] ?? 'Patient';
      final status = o['status'] ?? 'pending';
      final fee = o['consultationFee'] ?? o['totalAmount'] ?? 0;
      final type = o['type'] == 'home' ? 'Home Collection' : 'Lab Visit';
      return Container(
        margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.pathologyAccent.withValues(alpha: 0.1))),
        child: Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(gradient: AppTheme.pathologyGradient, borderRadius: BorderRadius.circular(12)),
            child: const Center(child: Icon(Iconsax.microscope, size: 22, color: Colors.white))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            Text(type, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₹$fee', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.pathologyAccent)),
            const SizedBox(height: 4),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: status == 'completed' ? AppTheme.success.withValues(alpha: 0.1) : AppTheme.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6)),
              child: Text(status, style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w600,
                color: status == 'completed' ? AppTheme.success : AppTheme.warning))),
          ]),
        ]),
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
