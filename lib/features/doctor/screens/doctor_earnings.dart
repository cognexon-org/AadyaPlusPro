import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_service.dart';

class DoctorEarnings extends ConsumerStatefulWidget {
  const DoctorEarnings({super.key});

  @override
  ConsumerState<DoctorEarnings> createState() => _DoctorEarningsState();
}

class _DoctorEarningsState extends ConsumerState<DoctorEarnings> {
  final ApiService _api = ApiService();
  bool _loading = true;

  double _totalEarnings = 0;
  double _monthlyEarnings = 0;
  double _pendingEarnings = 0;
  double _commissionRate = 20;

  List<Map<String, dynamic>> _transactions = [];
  Map<int, double> _monthlyBreakdown = {};

  String _timeFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadEarnings();
  }

  Future<void> _loadEarnings() async {
    setState(() => _loading = true);
    try {
      final res = await _api.getCommissions(queryParams: {'limit': 1000});
      final data = res.data;
      final list = data is Map ? (data['data'] ?? data['commissions'] ?? []) : data;

      if (list is List) {
        _transactions = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _transactions.sort((a, b) {
          final da = DateTime.tryParse(a['createdAt']?.toString() ?? '') ?? DateTime.now();
          final db = DateTime.tryParse(b['createdAt']?.toString() ?? '') ?? DateTime.now();
          return db.compareTo(da);
        });

        _calculateStats();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _calculateStats() {
    _totalEarnings = 0;
    _monthlyEarnings = 0;
    _pendingEarnings = 0;
    _monthlyBreakdown.clear();

    final now = DateTime.now();

    for (final t in _transactions) {
      final amount = (t['professionalEarning'] ?? t['amount'] ?? 0).toDouble();
      final status = (t['payoutStatus'] ?? 'pending').toString();
      final dt = DateTime.tryParse(t['createdAt']?.toString() ?? '') ?? now;

      _totalEarnings += amount;

      if (dt.year == now.year && dt.month == now.month) {
        _monthlyEarnings += amount;
      }

      if (status == 'pending') {
        _pendingEarnings += amount;
      }

      final monthKey = dt.month;
      _monthlyBreakdown[monthKey] = (_monthlyBreakdown[monthKey] ?? 0) + amount;
      
      _commissionRate = (t['commissionRate'] ?? 20).toDouble();
    }
  }

  Future<void> _refresh() async {
    await _loadEarnings();
  }

  List<Map<String, dynamic>> get _filteredTransactions {
    final now = DateTime.now();
    return _transactions.where((t) {
      final dt = DateTime.tryParse(t['createdAt']?.toString() ?? '') ?? now;
      if (_timeFilter == 'month') return dt.year == now.year && dt.month == now.month;
      if (_timeFilter == 'week') return now.difference(dt).inDays <= 7;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Earnings & Payouts', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                const SizedBox(height: 4),
                Text('Manage your commission and financial reports', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textSecondary)),
                const SizedBox(height: 20),

                if (_loading && _transactions.isEmpty)
                  const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: AppTheme.primary)))
                else ...[
                  // Earnings summary card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: AppTheme.doctorGradient,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: AppTheme.primary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Total Available Earnings', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: Colors.white70)),
                                const SizedBox(height: 4),
                                Text(_formatCurrency(_totalEarnings), style: GoogleFonts.plusJakartaSans(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white)),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
                              child: const Icon(Iconsax.money_recive, size: 28, color: Colors.white),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            _earningsStat('This Month', _formatCurrency(_monthlyEarnings)),
                            const SizedBox(width: 16),
                            _earningsStat('Pending', _formatCurrency(_pendingEarnings)),
                            const SizedBox(width: 16),
                            _earningsStat('Comm. Rate', '$_commissionRate%'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Monthly chart
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Earnings Overview', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 200,
                          child: BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: _getMaxY(),
                              barTouchData: BarTouchData(
                                enabled: true,
                                touchTooltipData: BarTouchTooltipData(
                                  // getTooltipColor: (_) => Colors.blueGrey,
                                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                    return BarTooltipItem('\₹${rod.toY.toInt()}', const TextStyle(color: Colors.white, fontWeight: FontWeight.bold));
                                  },
                                ),
                              ),
                              titlesData: FlTitlesData(
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (v, _) {
                                      final monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                                      final i = v.toInt() % 12;
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(monthNames[i], style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textTertiary)),
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
                              barGroups: _buildMonthlyBars(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Transactions Header & Filters
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Transaction Ledger', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                      _buildTimeFilterDropdown(),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (_filteredTransactions.isNotEmpty)
                    ..._filteredTransactions.map<Widget>((t) => _buildTransactionCard(t))
                  else
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Iconsax.receipt_square, size: 32, color: AppTheme.textTertiary.withValues(alpha: 0.5)),
                            const SizedBox(height: 12),
                            Text('No transactions found', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppTheme.textSecondary)),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeFilterDropdown() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _timeFilter,
          icon: const Icon(Iconsax.arrow_down_1, size: 14, color: AppTheme.primary),
          style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary),
          items: const [
            DropdownMenuItem(value: 'all', child: Text('All Time')),
            DropdownMenuItem(value: 'month', child: Text('This Month')),
            DropdownMenuItem(value: 'week', child: Text('This Week')),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _timeFilter = v);
          },
        ),
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> data) {
    final name = data['patientId'] is Map ? (data['patientId']['name'] ?? 'Patient') : 'Patient';
    final amount = (data['professionalEarning'] ?? data['amount'] ?? 0).toDouble();
    final commission = (data['platformCommission'] ?? data['commission'] ?? 0).toDouble();
    final date = data['createdAt'] ?? data['date'] ?? '';
    final status = (data['payoutStatus'] ?? 'pending').toString();

    final statusColor = status == 'paid' ? AppTheme.success : AppTheme.warning;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TransactionDetailsScreen(transaction: data, commissionRate: _commissionRate))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
        child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Iconsax.money_recive, size: 20, color: AppTheme.success),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                    const SizedBox(height: 2),
                    Text('Comm: ₹$commission (${_commissionRate.toInt()}%)', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('+₹$amount', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.success)),
                  const SizedBox(height: 2),
                  Text(_formatDate(date), style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textTertiary)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Payout Status', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textTertiary)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                child: Text(status.toUpperCase(), style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
              )
            ],
          )
        ],
      ),
    ));
  }

  Widget _earningsStat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
        child: Column(
          children: [
            Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 10, color: Colors.white70)),
            const SizedBox(height: 4),
            Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  List<BarChartGroupData> _buildMonthlyBars() {
    final nowMonth = DateTime.now().month;
    // Show last 6 months
    return List.generate(6, (i) {
      int m = nowMonth - 5 + i;
      if (m <= 0) m += 12;
      double val = _monthlyBreakdown[m] ?? 0;

      return BarChartGroupData(x: m - 1, barRods: [
        BarChartRodData(
          toY: val, 
          color: val > 0 ? AppTheme.primary : AppTheme.primary.withValues(alpha: 0.2), 
          width: 22, 
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6))
        ),
      ]);
    });
  }

  double _getMaxY() {
    double maxVal = 0;
    for (final v in _monthlyBreakdown.values) {
      if (v > maxVal) maxVal = v;
    }
    if (maxVal == 0) return 100; // default empty
    return maxVal * 1.2;
  }

  String _formatCurrency(dynamic amount) {
    if (amount == null) return '₹0';
    final formatter = NumberFormat('#,##,###.##');
    return '₹${formatter.format(amount)}';
  }

  String _formatDate(dynamic date) {
    if (date is String && date.isNotEmpty) {
      try {
        final dt = DateTime.parse(date);
        return DateFormat('MMM d, h:mm a').format(dt);
      } catch (_) {}
    }
    return '';
  }
}

class TransactionDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> transaction;
  final double commissionRate;

  const TransactionDetailsScreen({super.key, required this.transaction, required this.commissionRate});

  @override
  Widget build(BuildContext context) {
    final name = transaction['patientId'] is Map ? (transaction['patientId']['name'] ?? 'Patient') : 'Patient';
    final earning = (transaction['professionalEarning'] ?? transaction['amount'] ?? 0).toDouble();
    final commission = (transaction['platformCommission'] ?? transaction['commission'] ?? 0).toDouble();
    final gross = (transaction['consultationFee'] ?? transaction['totalAmount'] ?? (earning + commission)).toDouble();
    
    final dateStr = transaction['createdAt'] ?? transaction['date'] ?? '';
    String date = '';
    String time = '';
    if (dateStr.isNotEmpty) {
      try {
        final dt = DateTime.parse(dateStr);
        date = DateFormat('MMM d, yyyy').format(dt);
        time = DateFormat('h:mm a').format(dt);
      } catch (_) {}
    }

    final status = (transaction['payoutStatus'] ?? 'pending').toString();
    final statusColor = status == 'paid' ? AppTheme.success : AppTheme.warning;
    final txId = transaction['_id'] ?? 'N/A';

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text('Transaction Details', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 18)),
        backgroundColor: Colors.white, foregroundColor: AppTheme.textPrimary, elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Header amount
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.border)),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppTheme.success.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: const Icon(Iconsax.money_recive, size: 32, color: AppTheme.success),
                  ),
                  const SizedBox(height: 16),
                  Text('+₹$earning', style: GoogleFonts.plusJakartaSans(fontSize: 36, fontWeight: FontWeight.w800, color: AppTheme.success)),
                  const SizedBox(height: 4),
                  Text('Net Earnings added to wallet', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textSecondary)),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text('Payout Status: ${status.toUpperCase()}', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Patient
            _buildSection(
              title: 'Source / Patient',
              icon: Iconsax.user,
              child: Row(
                children: [
                  Container(width: 40, height: 40, decoration: BoxDecoration(gradient: AppTheme.doctorGradient, shape: BoxShape.circle), child: Center(child: Text(name[0], style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)))),
                  const SizedBox(width: 12),
                  Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Breakdown
            _buildSection(
              title: 'Earnings Breakdown',
              icon: Iconsax.chart,
              child: Column(
                children: [
                  _buildRow('Consultation Fee', '₹$gross'),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  _buildRow('Platform Commission (${commissionRate.toInt()}%)', '- ₹$commission', color: AppTheme.error),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  _buildRow('Net Payout Allowed', '₹$earning', color: AppTheme.success, isBold: true),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Meta Info
            _buildSection(
              title: 'Transaction Info',
              icon: Iconsax.info_circle,
              child: Column(
                children: [
                  _buildRow('Transaction ID', txId, isSmall: true),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  _buildRow('Date', date, isSmall: true),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  _buildRow('Time', time, isSmall: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, {Color? color, bool isBold = false, bool isSmall = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.plusJakartaSans(fontSize: isSmall ? 12 : 13, color: AppTheme.textSecondary)),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: GoogleFonts.plusJakartaSans(
              fontSize: isSmall ? 12 : 14,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
              color: color ?? AppTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

