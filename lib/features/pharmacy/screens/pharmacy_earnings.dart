import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/network/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/pharmacy_store_provider.dart';

class PharmacyEarnings extends ConsumerStatefulWidget {
  const PharmacyEarnings({super.key});
  @override
  ConsumerState<PharmacyEarnings> createState() => _PharmacyEarningsState();
}

class _PharmacyEarningsState extends ConsumerState<PharmacyEarnings> {
  bool _loading = false;
  Map<String, dynamic> _pnl = {};
  Map<String, dynamic> _valuation = {};
  String? _loadedStoreId;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await ref.read(pharmacyStoreProvider.notifier).initialize();
      final results = await Future.wait([
        ApiService().getPharmacyProfitLoss(),
        ApiService().getInventoryValuation(),
      ]);
      if (!mounted) return;
      setState(() {
        _loadedStoreId = ref.read(pharmacyStoreProvider).selectedStoreId;
        _pnl = Map<String, dynamic>.from(results[0].data as Map);
        _valuation = Map<String, dynamic>.from(results[1].data as Map);
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load branch finance: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _money(dynamic value) => '₹${(num.tryParse('$value') ?? 0).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(pharmacyStoreProvider);
    if (store.selectedStoreId != null && store.selectedStoreId != _loadedStoreId && !_loading) Future.microtask(_load);
    final totals = Map<String, dynamic>.from((_valuation['totals'] as Map?) ?? const {});
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Branch Finance', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
              const SizedBox(height: 12),
              const PharmacyStoreSelector(),
              const SizedBox(height: 18),
              if (_loading && _pnl.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
              if (_pnl.isNotEmpty) ...[
                _metric('Net Sales', _money(_pnl['netSales']), Icons.receipt_long, AppTheme.primary),
                _metric('Gross Profit', _money(_pnl['grossProfit']), Icons.trending_up, AppTheme.success),
                Row(children: [
                  Expanded(child: _small('Gross sales', _money(_pnl['grossSales']))),
                  const SizedBox(width: 10),
                  Expanded(child: _small('Returns', _money(_pnl['returns']))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _small('COGS', _money(_pnl['costOfGoods']))),
                  const SizedBox(width: 10),
                  Expanded(child: _small('Tax', _money(_pnl['taxCollected']))),
                ]),
                const SizedBox(height: 18),
              ],
              Text('Inventory Valuation', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _small('Cost value', _money(totals['costValue']))),
                const SizedBox(width: 10),
                Expanded(child: _small('Retail value', _money(totals['retailValue']))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _small('Units', '${totals['units'] ?? 0}')),
                const SizedBox(width: 10),
                Expanded(child: _small('Expired cost', _money(totals['expiredCostValue']))),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric(String label, String value, IconData icon, Color color) => Container(
    margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
    child: Row(children: [
      CircleAvatar(backgroundColor: color.withValues(alpha: .1), child: Icon(icon, color: color)),
      const SizedBox(width: 14),
      Expanded(child: Text(label, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: AppTheme.textSecondary))),
      Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
    ]),
  );

  Widget _small(String label, String value) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
      const SizedBox(height: 6),
      Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
    ]),
  );
}
