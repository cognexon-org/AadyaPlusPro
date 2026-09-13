import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../auth/providers/auth_provider.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import 'new_sale.dart';
import 'prescription_queue.dart';
import 'stock_alert.dart';

class PharmacyHome extends ConsumerStatefulWidget {
  const PharmacyHome({super.key});

  @override
  ConsumerState<PharmacyHome> createState() => _PharmacyHomeState();
}

class _PharmacyHomeState extends ConsumerState<PharmacyHome> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(pharmacyDashboardProvider.notifier).loadAll());
  }

  Future<void> _refresh() async {
    await ref.read(pharmacyDashboardProvider.notifier).loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final dashData = ref.watch(pharmacyDashboardProvider);
    final profile = dashData.profile;

    final stats = dashData.stats;

    final appointmentsCount = dashData.medicines.length; // all medicines
    final medicines = profile['totalMedicines'] ?? stats['totalMedicines'] ?? (appointmentsCount > 0 ? appointmentsCount.toString() : '--');
    final revenue = stats['totalSales'] ?? profile['todayRevenue'] ?? profile['revenue'] ?? '--';
    final lowStock = stats['lowStockCount'] ?? profile['lowStock'] ?? '--';
    final salesCount = stats['salesCount'] ?? profile['totalOrders'] ?? '--';

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: AppTheme.accent,
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
                    Text(user?.name ?? 'Pharmacy', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                  ])),
                  Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
                    child: Badge(smallSize: 8, child: const Icon(Iconsax.notification, size: 22, color: AppTheme.textPrimary))),
                ]),
                const SizedBox(height: 24),

                if (dashData.isLoading && profile.isEmpty)
                  const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: AppTheme.accent)))
                else ...[
                  GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.3,
                    children: [
                      StatCard(title: 'Medicines', value: _fmt(medicines), icon: Iconsax.box, color: AppTheme.accent),
                      StatCard(title: "Revenue", value: _fmtCurrency(revenue), icon: Iconsax.money_recive, color: AppTheme.primary),
                      StatCard(title: 'Low Stock', value: _fmt(lowStock), icon: Iconsax.warning_2, color: AppTheme.warning),
                      StatCard(title: 'Sales', value: _fmt(salesCount), icon: Iconsax.document_text, color: AppTheme.info),
                    ]),
                  const SizedBox(height: 20),

                  // Chart
                  Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('Weekly Overview', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                        Row(children: [_legend(AppTheme.accent, 'Sales'), const SizedBox(width: 12), _legend(AppTheme.primary, 'Prescriptions')]),
                      ]),
                      const SizedBox(height: 20),
                      SizedBox(height: 180, child: BarChart(BarChartData(alignment: BarChartAlignment.spaceAround, maxY: 50000,
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
                        barGroups: _buildWeeklyBars(profile),
                      ))),
                    ])),
                  const SizedBox(height: 20),

                  // Quick Actions
                  Text('Quick Actions', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.2,
                    children: [
                      _qa(Iconsax.bag_2, 'New Sale', AppTheme.pharmacyGradient, true, () {
                        Navigator.push(context, MaterialPageRoute(builder: (c) => const NewSaleScreen()));
                      }),
                      _qa2(Iconsax.document_text, 'Prescriptions', AppTheme.primary, () {
                        Navigator.push(context, MaterialPageRoute(builder: (c) => const PrescriptionQueue()));
                      }),
                      _qa2(Iconsax.warning_2, 'Stock Alert', AppTheme.warning, () {
                        Navigator.push(context, MaterialPageRoute(builder: (c) => const StockAlertScreen()));
                      }),
                      _qa2(Iconsax.truck, 'Place Order', AppTheme.success, () {}),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Verification status
                  if (profile['verificationStatus'] != null)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: profile['verificationStatus'] == 'approved' ? AppTheme.success.withValues(alpha: 0.06) : AppTheme.warning.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: (profile['verificationStatus'] == 'approved' ? AppTheme.success : AppTheme.warning).withValues(alpha: 0.2)),
                      ),
                      child: Row(children: [
                        Icon(profile['verificationStatus'] == 'approved' ? Iconsax.verify5 : Iconsax.clock, size: 20,
                          color: profile['verificationStatus'] == 'approved' ? AppTheme.success : AppTheme.warning),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Pharmacy Status', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                          Text(profile['verificationStatus'] == 'approved' ? 'Your pharmacy is verified and active' : 'Verification pending - admin review in progress',
                            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
                        ])),
                      ]),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<BarChartGroupData> _buildWeeklyBars(Map<String, dynamic> profile) {
    final weekly = profile['weeklySales'] ?? profile['weekly'];
    if (weekly is List && weekly.length >= 7) {
      return List.generate(7, (i) {
        final sales = (weekly[i] is Map ? weekly[i]['sales'] ?? 0 : weekly[i]) as num;
        final presc = (weekly[i] is Map ? weekly[i]['prescriptions'] ?? 0 : 0) as num;
        return BarChartGroupData(x: i, barRods: [
          BarChartRodData(toY: sales.toDouble(), color: AppTheme.accent, width: 10, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
          BarChartRodData(toY: presc.toDouble(), color: AppTheme.primary, width: 10, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
        ]);
      });
    }
    return List.generate(7, (i) => BarChartGroupData(x: i, barRods: [
      BarChartRodData(toY: 0, color: AppTheme.accent.withValues(alpha: 0.3), width: 10, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
      BarChartRodData(toY: 0, color: AppTheme.primary.withValues(alpha: 0.3), width: 10, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
    ]));
  }

  Widget _legend(Color c, String l) => Row(children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 6), Text(l, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary))]);

  Widget _qa(IconData i, String l, LinearGradient g, bool grad, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(12), decoration: BoxDecoration(gradient: g, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
          child: Icon(i, size: 18, color: Colors.white)),
        const SizedBox(width: 10),
        Text(l, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
      ])),
  );

  Widget _qa2(IconData i, String l, Color c, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withValues(alpha: 0.15))),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
          child: Icon(i, size: 18, color: c)),
        const SizedBox(width: 10),
        Expanded(child: Text(l, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: c))),
      ])),
  );

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
