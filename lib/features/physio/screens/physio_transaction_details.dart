import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';

class PhysioTransactionDetails extends StatelessWidget {
  final Map<String, dynamic> transaction;
  final num commissionRate;

  const PhysioTransactionDetails({
    super.key,
    required this.transaction,
    required this.commissionRate,
  });

  @override
  Widget build(BuildContext context) {
    final patient = transaction['patientId'];
    final name = patient is Map ? (patient['name'] ?? 'Patient') : 'Patient';
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
    final statusColor = status == 'paid' || status == 'completed' ? AppTheme.success : AppTheme.warning;
    final txId = transaction['_id'] ?? transaction['id'] ?? 'N/A';

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text('Transaction Details', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Hero Amount Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.border),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.textPrimary.withValues(alpha: 0.03),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  )
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(CupertinoIcons.money_dollar_circle, size: 32, color: AppTheme.success),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '+₹${earning.toStringAsFixed(2)}',
                    style: GoogleFonts.manrope(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.success,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Net Professional Earning',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          status.toUpperCase(),
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Patient Section
            _buildSection(
              title: 'Source Details',
              icon: CupertinoIcons.person,
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: AppTheme.physioGradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        name.isNotEmpty ? name[0] : 'P',
                        style: GoogleFonts.manrope(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          'Physiotherapy Session',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Financial Breakdown
            _buildSection(
              title: 'Earnings Breakdown',
              icon: CupertinoIcons.chart_pie,
              child: Column(
                children: [
                  _buildDetailRow('Session Fee', '₹${gross.toStringAsFixed(2)}'),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1),
                  ),
                  _buildDetailRow(
                    'Platform Commission (${commissionRate.toInt()}%)',
                    '- ₹${commission.toStringAsFixed(2)}',
                    valueColor: AppTheme.error,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1, thickness: 1.5),
                  ),
                  _buildDetailRow(
                    'Net Net Payout',
                    '₹${earning.toStringAsFixed(2)}',
                    isBold: true,
                    valueColor: AppTheme.success,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Transaction Info
            _buildSection(
              title: 'Transaction Reference',
              icon: CupertinoIcons.info_circle,
              child: Column(
                children: [
                  _buildDetailRow('Reference ID', txId, isSmall: true),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
                  _buildDetailRow('Date', date, isSmall: true),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
                  _buildDetailRow('Time', time, isSmall: true),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
                  _buildDetailRow('Payment Mode', 'Online', isSmall: true),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Help Text
            Text(
              'If you have any issues with this transaction,\nplease contact Aadya Plus Support.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 12,
                color: AppTheme.textTertiary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.physioAccent),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isBold = false, bool isSmall = false, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: isSmall ? 12 : 13,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.manrope(
            fontSize: isSmall ? 12 : 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: valueColor ?? AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}
