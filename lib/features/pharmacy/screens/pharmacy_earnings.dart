import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../dashboard/providers/dashboard_provider.dart';

class PharmacyEarnings extends ConsumerStatefulWidget {
  const PharmacyEarnings({super.key});

  @override
  ConsumerState<PharmacyEarnings> createState() => _PharmacyEarningsState();
}

class _PharmacyEarningsState extends ConsumerState<PharmacyEarnings> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(pharmacyDashboardProvider.notifier).loadEarnings());
  }

  @override
  Widget build(BuildContext context) {
    final dashData = ref.watch(pharmacyDashboardProvider);
    final earnings = dashData.earnings;
    
    final stats = dashData.stats;
    final totalRevenue = stats['totalSales'] ?? 0;
    
    final report = (earnings['report'] as List?) ?? [];
    
    return Scaffold(backgroundColor: AppTheme.surface, body: SafeArea(child: 
      dashData.isLoading && earnings.isEmpty 
        ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
        : SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Earnings', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
      const SizedBox(height: 20),
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: AppTheme.pharmacyGradient, borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppTheme.accent.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))]),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Total Revenue', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.white70)),
              const SizedBox(height: 4),
              Text('₹${_fmt(totalRevenue)}', style: GoogleFonts.plusJakartaSans(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white)),
            ]),
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
              child: const Icon(Iconsax.money_recive, size: 28, color: Colors.white)),
          ]),
          const SizedBox(height: 16),
          // We can populate more stats if needed here
        ])),
      const SizedBox(height: 20),
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Monthly Sales', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          const SizedBox(height: 20),
          SizedBox(height: 200, child: BarChart(BarChartData(alignment: BarChartAlignment.spaceAround, maxY: 600000,
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) {
                const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'];
                return Padding(padding: const EdgeInsets.only(top: 8), child: Text(m[v.toInt()], style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textTertiary)));
              }, reservedSize: 28)),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: const FlGridData(show: false), borderData: FlBorderData(show: false),
            barGroups: [_b(0, 380000), _b(1, 420000), _b(2, 480000), _b(3, 567000), _b(4, 510000), _b(5, 540000)],
          ))),
        ])),
      const SizedBox(height: 20),
      Text('Recent Sales (Top Customers)', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
      const SizedBox(height: 12),
      earnings['topCustomers'] == null || (earnings['topCustomers'] as List).isEmpty
        ? Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
            child: Center(child: Text('No earning records yet', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppTheme.textSecondary))),
          )
        : Column(
            children: (earnings['topCustomers'] as List).take(8).map((t) {
              final name = t['customerName'] ?? 'Customer';
              final totalSpent = t['totalSpent'] ?? 0;
              final visits = t['totalVisits'] ?? 1;

              return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
                child: Row(children: [
                  Container(width: 40, height: 40, decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Iconsax.money_recive, size: 20, color: AppTheme.success)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                    Text('$visits total visits', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('₹${_fmt(totalSpent)}', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.success)),
                  ]),
                ]));
            }).toList(),
          ),
    ]))));
  }

  String _fmt(dynamic v) {
    if (v is num) return v.toStringAsFixed(0);
    return v?.toString() ?? '0';
  }

  Widget _s(String l, String v) => Expanded(child: Container(padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
    child: Column(children: [Text(l, style: GoogleFonts.plusJakartaSans(fontSize: 10, color: Colors.white70)), const SizedBox(height: 4),
      Text(v, style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white))])));

  BarChartGroupData _b(int x, double y) => BarChartGroupData(x: x, barRods: [
    BarChartRodData(toY: y, color: AppTheme.accent, width: 22, borderRadius: const BorderRadius.vertical(top: Radius.circular(6)))]);
}
