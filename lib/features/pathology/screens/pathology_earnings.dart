import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../dashboard/providers/dashboard_provider.dart';

class PathologyEarnings extends ConsumerStatefulWidget {
  const PathologyEarnings({super.key});

  @override
  ConsumerState<PathologyEarnings> createState() => _PathologyEarningsState();
}

class _PathologyEarningsState extends ConsumerState<PathologyEarnings> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(pathologyDashboardProvider.notifier).loadEarnings());
  }

  @override
  Widget build(BuildContext context) {
    final dashData = ref.watch(pathologyDashboardProvider);
    final earningsData = dashData.earnings;
    final totals = earningsData['totals'] ?? {};
    final commissions = (earningsData['commissions'] as List?) ?? [];

    final totalRevenue = totals['totalProfessionalEarnings'] ?? 0;
    final pendingRevenue = totals['totalPending'] ?? 0;
    
    // Average test price (approx logic based on total/count)
    final count = totals['count'] ?? 0;
    final avgPrice = count > 0 ? ((totals['totalConsultationFees'] ?? 0) / count) : 0;
    
    final settings = earningsData['settings'] ?? {};
    final commissionRate = settings['defaultPathologyCommission'] ?? 15;

    return Scaffold(backgroundColor: AppTheme.surface, body: SafeArea(child: 
      dashData.isLoading && earningsData.isEmpty
        ? const Center(child: CircularProgressIndicator(color: AppTheme.pathologyAccent))
        : SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Earnings', style: GoogleFonts.manrope(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
      const SizedBox(height: 20),
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: AppTheme.pathologyGradient, borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppTheme.pathologyAccent.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))]),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Total Revenue', style: GoogleFonts.manrope(fontSize: 14, color: Colors.white70)),
              const SizedBox(height: 4),
              Text('₹${_fmt(totalRevenue)}', style: GoogleFonts.manrope(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white)),
            ]),
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
              child: const Icon(CupertinoIcons.money_dollar_circle, size: 28, color: Colors.white)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            _s('This Month', '₹${_fmt(totalRevenue)}'), const SizedBox(width: 12),
            _s('Pending', '₹${_fmt(pendingRevenue)}'), const SizedBox(width: 12),
            _s('Commission', '$commissionRate%'),
          ]),
        ])),
      const SizedBox(height: 20),
      // Earnings breakdown
      Row(children: [
        Expanded(child: _earningsBox('Avg. Test Price', '₹${_fmt(avgPrice)}', CupertinoIcons.chart_bar_alt_fill, AppTheme.primary)),
        const SizedBox(width: 12),
        Expanded(child: _earningsBox('Commission Rate', '$commissionRate%', CupertinoIcons.percent, AppTheme.pathologyAccent)),
      ]),
      const SizedBox(height: 20),
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Monthly Revenue', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          const SizedBox(height: 20),
          SizedBox(height: 200, child: BarChart(BarChartData(alignment: BarChartAlignment.spaceAround, maxY: 150000,
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) {
                const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'];
                return Padding(padding: const EdgeInsets.only(top: 8), child: Text(m[v.toInt()], style: GoogleFonts.manrope(fontSize: 11, color: AppTheme.textTertiary)));
              }, reservedSize: 28)),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: const FlGridData(show: false), borderData: FlBorderData(show: false),
            barGroups: [_b(0, 85000), _b(1, 95000), _b(2, 110000), _b(3, 120000), _b(4, 105000), _b(5, 130000)],
          ))),
        ])),
      const SizedBox(height: 20),
      Text('Recent Transactions', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
      const SizedBox(height: 12),
      
      commissions.isEmpty 
        ? Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
            child: Center(child: Text('No earning records yet', style: GoogleFonts.manrope(fontSize: 14, color: AppTheme.textSecondary))),
          )
        : Column(
            children: commissions.take(8).map((t) {
              final apt = t['appointmentId'] ?? {};
              final patient = t['patientId'] ?? {};
              final name = patient['name'] ?? 'Patient';
              final type = apt['type'] == 'home' ? 'Home Collection' : 'Lab Test';
              final earning = t['professionalEarning'] ?? 0;
              final dateStr = t['createdAt'];
              String dateStrFmt = 'Today';
              if (dateStr != null) {
                 try {
                   dateStrFmt = DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse(dateStr).toLocal());
                 } catch (_) {}
              }

              return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
                child: Row(children: [
                  Container(width: 40, height: 40, decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(CupertinoIcons.money_dollar_circle, size: 20, color: AppTheme.success)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$name - $type', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(dateStrFmt, style: GoogleFonts.manrope(fontSize: 11, color: AppTheme.textTertiary)),
                    ],
                  )),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('₹${_fmt(earning)}', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.success)),
                    Text(t['payoutStatus']?.toString().toUpperCase() ?? 'PENDING', style: GoogleFonts.manrope(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.warning)),
                  ]),
                ]));
            }).toList(),
          ),
      const SizedBox(height: 30),
    ]))));
  }

  String _fmt(dynamic v) {
    if (v is num) return v.toStringAsFixed(0);
    return v?.toString() ?? '0';
  }

  Widget _s(String l, String v) => Expanded(child: Container(padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
    child: Column(children: [
      Text(l, style: GoogleFonts.manrope(fontSize: 10, color: Colors.white70)), const SizedBox(height: 4),
      Text(v, style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
    ])));

  Widget _earningsBox(String l, String v, IconData i, Color c) => Container(padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(i, size: 22, color: c), const SizedBox(height: 8),
      Text(l, style: GoogleFonts.manrope(fontSize: 12, color: AppTheme.textSecondary)), const SizedBox(height: 4),
      Text(v, style: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
    ]));

  BarChartGroupData _b(int x, double y) => BarChartGroupData(x: x, barRods: [
    BarChartRodData(toY: y, color: AppTheme.pathologyAccent, width: 22, borderRadius: const BorderRadius.vertical(top: Radius.circular(6)))]);
}
