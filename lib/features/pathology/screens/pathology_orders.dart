import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_service.dart';
import '../../dashboard/providers/dashboard_provider.dart';

class PathologyOrders extends ConsumerStatefulWidget {
  const PathologyOrders({super.key});

  @override
  ConsumerState<PathologyOrders> createState() => _PathologyOrdersState();
}

class _PathologyOrdersState extends ConsumerState<PathologyOrders> {
  final TextEditingController _searchController = TextEditingController();
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(pathologyDashboardProvider.notifier).loadTests());
  }

  Future<void> _refresh() async {
    await ref.read(pathologyDashboardProvider.notifier).loadTests();
  }

  Future<void> _updateStatus(String id, String status) async {
    try {
      await ApiService().updatePathologyTestStatus(id, status);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status updated to ${status.toUpperCase()}'), backgroundColor: AppTheme.success),
        );
        _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dashData = ref.watch(pathologyDashboardProvider);
    // Tests are stored in recentTransactions (from loadTests())
    final allTests = dashData.recentTransactions;

    final filtered = allTests.where((t) {
      final patientName = (t['patientId'] is Map ? t['patientId']['name'] : '') ?? '';
      final matchSearch = patientName.toString().toLowerCase().contains(_searchController.text.toLowerCase());
      if (_filter == 'all') return matchSearch;
      return matchSearch && t['status'] == _filter;
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
                Text('Test Orders', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                Text('${allTests.length} total orders', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textSecondary)),
              ]),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search by patient name...',
                  prefixIcon: const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Icon(Iconsax.search_normal, size: 18, color: AppTheme.textTertiary)),
                  filled: true, fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: ['all', 'scheduled', 'sample_collected', 'processing', 'completed', 'cancelled'].map((opt) {
                    final sel = _filter == opt;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _filter = opt),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: sel ? AppTheme.pathologyAccent : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: sel ? AppTheme.pathologyAccent : AppTheme.divider),
                          ),
                          child: Text(opt == 'all' ? 'All' : _fmtStatus(opt),
                              style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w500, color: sel ? Colors.white : AppTheme.textSecondary)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: dashData.isLoading && allTests.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.pathologyAccent))
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: filtered.isEmpty
                          ? ListView(children: [
                              const SizedBox(height: 80),
                              Center(child: Column(children: [
                                Icon(Iconsax.microscope, size: 48, color: AppTheme.textTertiary.withValues(alpha: 0.5)),
                                const SizedBox(height: 12),
                                Text('No orders found', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppTheme.textSecondary)),
                              ])),
                            ])
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) => _testCard(filtered[i]),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _testCard(Map<String, dynamic> t) {
    final patientInfo = t['patientId'];
    final patientName = patientInfo is Map ? (patientInfo['name'] ?? 'Patient') : 'Patient';
    final tests = (t['tests'] as List?) ?? [];
    final testNames = tests.isNotEmpty
        ? tests.map((x) => x is Map ? (x['testName'] ?? '') : '').where((s) => s.isNotEmpty).join(', ')
        : 'Lab Tests';
    final total = t['totalAmount'] ?? t['consultationFee'] ?? 0;
    final isHome = t['type'] == 'home';
    final status = t['status']?.toString() ?? 'scheduled';
    final id = t['_id']?.toString() ?? '';

    Color statusColor = AppTheme.warning;
    if (status == 'completed') statusColor = AppTheme.success;
    if (status == 'sample_collected') statusColor = AppTheme.primary;
    if (status == 'processing') statusColor = AppTheme.pathologyAccent;
    if (status == 'cancelled') statusColor = AppTheme.error;
    if (status == 'requested') statusColor = AppTheme.info;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6)],
      ),
      child: Column(children: [
        Row(children: [
          Container(width: 44, height: 44,
            decoration: BoxDecoration(gradient: AppTheme.pathologyGradient, borderRadius: BorderRadius.circular(12)),
            child: const Center(child: Icon(Iconsax.microscope, size: 22, color: Colors.white))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(patientName, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            Text(testNames, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
          ])),
          Text('₹$total', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.pathologyAccent)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Icon(isHome ? Iconsax.home : Iconsax.hospital, size: 13, color: AppTheme.textTertiary),
          const SizedBox(width: 4),
          Text(isHome ? 'Home Collection' : 'Lab Visit', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
          const Spacer(),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(_fmtStatus(status), style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor))),
        ]),
        if (status == 'scheduled' && id.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => _updateStatus(id, 'cancelled'),
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.error, side: const BorderSide(color: AppTheme.error), padding: const EdgeInsets.symmetric(vertical: 8)),
              child: Text('Cancel', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600)),
            )),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(
              onPressed: () => _updateStatus(id, 'sample_collected'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.pathologyAccent, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 8)),
              child: Text('Collect Sample', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600)),
            )),
          ]),
        ],
        if (status == 'sample_collected' && id.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () => _updateStatus(id, 'completed'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success, foregroundColor: Colors.white, elevation: 0),
            child: Text('Mark Completed', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600)),
          )),
        ],
      ]),
    );
  }

  String _fmtStatus(String s) {
    switch (s) {
      case 'requested': return 'Requested';
      case 'sample_collected': return 'Sample Collected';
      case 'processing': return 'Processing';
      case 'scheduled': return 'Scheduled';
      case 'completed': return 'Completed';
      case 'cancelled': return 'Cancelled';
      default: return s.isNotEmpty ? (s[0].toUpperCase() + s.substring(1)) : s;
    }
  }
}
