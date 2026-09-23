import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import 'package:intl/intl.dart';
import 'physio_transaction_details.dart';

class PhysioEarnings extends ConsumerStatefulWidget {
  const PhysioEarnings({super.key});

  @override
  ConsumerState<PhysioEarnings> createState() => _PhysioEarningsState();
}

class _PhysioEarningsState extends ConsumerState<PhysioEarnings> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(physioDashboardProvider.notifier).loadEarnings());
  }

  Future<void> _refresh() async {
    await ref.read(physioDashboardProvider.notifier).loadEarnings();
  }

  @override
  Widget build(BuildContext context) {
    final dashData = ref.watch(physioDashboardProvider);
    final earnings = dashData.earnings;

    final total = earnings['totalEarnings'] ?? 0;
    final transactions = earnings['transactions'] as List? ?? [];
    final totals = earnings['totals'] as Map? ?? {};
    
    final monthly = totals['monthlyEarnings'] ?? 0;
    final commission = totals['commissionRate'] ?? 12;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text('Earnings & Payments', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white, foregroundColor: AppTheme.textPrimary, elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppTheme.physioAccent,
        child: dashData.isLoading && earnings.isEmpty
            ? const Center(child: CircularProgressIndicator(color: AppTheme.physioAccent))
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Main Balance Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: AppTheme.physioGradient,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(color: AppTheme.physioAccent.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Total Portfolio Value', style: GoogleFonts.manrope(fontSize: 14, color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.w500)),
                              const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 24),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(_fmtLargeCurrency(total), style: GoogleFonts.manrope(fontSize: 36, fontWeight: FontWeight.w800, color: Colors.white)),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              _buildMiniStat('Monthly', _fmtCurrency(monthly)),
                              const SizedBox(width: 16),
                              _buildMiniStat('Rate', '$commission%'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Analytics Section
                    Text('Performance Analysis', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.border)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Earnings Trend', style: GoogleFonts.manrope(fontSize: 13, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 180,
                            child: BarChart(BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: _getMaxY(earnings),
                              titlesData: FlTitlesData(
                                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, _) {
                                  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'];
                                  if (v.toInt() >= 0 && v.toInt() < m.length) {
                                    return Padding(padding: const EdgeInsets.only(top: 8), child: Text(m[v.toInt()], style: GoogleFonts.manrope(fontSize: 11, color: AppTheme.textTertiary)));
                                  }
                                  return const SizedBox();
                                }, reservedSize: 28)),
                                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              gridData: const FlGridData(show: false),
                              borderData: FlBorderData(show: false),
                              barGroups: _buildBars(earnings),
                            )),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Transactions Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Recent Transactions', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                        const Icon(CupertinoIcons.sort_down, size: 20, color: AppTheme.textTertiary),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (transactions.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(40),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.border)),
                        child: Column(
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 48, color: AppTheme.textTertiary.withValues(alpha: 0.2)),
                            const SizedBox(height: 12),
                            Text('No transaction record found', style: GoogleFonts.manrope(fontSize: 14, color: AppTheme.textSecondary)),
                          ],
                        ),
                      )
                    else
                      ...transactions.map((t) => _buildTransactionCard(t, commission)),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.manrope(fontSize: 11, color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w500)),
        Text(value, style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
      ],
    );
  }

  Widget _buildTransactionCard(dynamic t, num commissionRate) {
    final patient = t['patientId'];
    final name = patient is Map ? (patient['name'] ?? 'Patient') : 'Patient';
    final amount = t['professionalEarning'] ?? t['amount'] ?? 0;
    final fee = t['consultationFee'] ?? 0;
    final date = t['createdAt'] ?? '';
    
    String dateStr = '---';
    try {
      if (date.isNotEmpty) {
        final dt = DateTime.parse(date);
        dateStr = DateFormat('dd MMM').format(dt);
      }
    } catch (_) {}

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PhysioTransactionDetails(
              transaction: t,
              commissionRate: commissionRate,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(CupertinoIcons.arrow_down_left, color: AppTheme.success, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                  Text('Consultation Fee: ₹$fee', style: GoogleFonts.manrope(fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('₹$amount', style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.success)),
                Text(dateStr, style: GoogleFonts.manrope(fontSize: 11, color: AppTheme.textTertiary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<BarChartGroupData> _buildBars(Map<String, dynamic> earnings) {
    final breakdown = earnings['monthlyBreakdown'] as List? ?? [];
    return List.generate(6, (i) {
      double val = 0;
      if (i < breakdown.length && breakdown[i] is num) {
        val = (breakdown[i] as num).toDouble();
      }
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(toY: val, color: AppTheme.physioAccent, width: 20, borderRadius: const BorderRadius.vertical(top: Radius.circular(6))),
        ],
      );
    });
  }

  double _getMaxY(Map<String, dynamic> earnings) {
    final breakdown = earnings['monthlyBreakdown'] as List? ?? [];
    double max = 1000;
    for (var v in breakdown) {
      if (v is num && v > max) max = v.toDouble();
    }
    return max * 1.2;
  }

  String _fmtCurrency(dynamic v) {
    if (v is num) return '₹${v.toStringAsFixed(0)}';
    return '₹0';
  }

  String _fmtLargeCurrency(dynamic v) {
    if (v is num) {
      if (v >= 100000) return '₹${(v / 100000).toStringAsFixed(2)}L';
      if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
      return '₹${v.toStringAsFixed(0)}';
    }
    return '₹0';
  }
}
