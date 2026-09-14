import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/network/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/pharmacy_store_provider.dart';
import 'pharmacy_procurement.dart';
import 'pharmacy_inventory_ops.dart';
import 'pharmacy_online_settings.dart';
import 'prescription_queue.dart';

class PharmacyHome extends ConsumerStatefulWidget {
  const PharmacyHome({super.key});

  @override
  ConsumerState<PharmacyHome> createState() => _PharmacyHomeState();
}

class _PharmacyHomeState extends ConsumerState<PharmacyHome> {
  final ApiService _api = ApiService();
  Map<String, dynamic> _stats = const {};
  List<Map<String, dynamic>> _sales = const [];
  bool _loading = true;
  String? _error;
  String? _loadedStoreId;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(pharmacyStoreProvider.notifier).initialize();
      if (mounted) await _load();
    });
  }

  Future<void> _load() async {
    final storeId = ref.read(pharmacyStoreProvider).selectedStoreId;
    if (storeId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.getPharmacyInventoryDashboard();
      final data = _map(response.data);
      if (!mounted) return;
      setState(() {
        _stats = _map(data['stats']);
        _sales = _maps(data['recentSales']);
        _loadedStoreId = storeId;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(pharmacyStoreProvider);
    if (store.selectedStoreId != null &&
        store.selectedStoreId != _loadedStoreId &&
        !_loading) {
      Future.microtask(_load);
    }

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('Pharmacy ERP', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
              const SizedBox(height: 4),
              Text('Branch-scoped inventory, procurement and online fulfillment', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
              const SizedBox(height: 14),
              const PharmacyStoreSelector(),
              if (store.error != null) ...[
                const SizedBox(height: 8),
                Text(store.error!, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.error)),
              ],
              const SizedBox(height: 16),
              if (_loading)
                const LinearProgressIndicator()
              else if (_error != null)
                _errorCard(_error!)
              else ...[
                Row(children: [
                  Expanded(child: _stat('Today revenue', '₹${_money(_stats['todayRevenue'])}', Iconsax.money_recive, AppTheme.success)),
                  const SizedBox(width: 10),
                  Expanded(child: _stat('Gross profit', '₹${_money(_stats['todayGrossProfit'])}', Iconsax.chart_2, AppTheme.primary)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _stat('Low stock', '${_stats['lowStock'] ?? 0}', Iconsax.warning_2, AppTheme.warning)),
                  const SizedBox(width: 10),
                  Expanded(child: _stat('Pending POs', '${_stats['pendingOrders'] ?? 0}', Iconsax.document_text, AppTheme.accent)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _stat('Inventory cost', '₹${_money(_stats['inventoryCostValue'])}', Iconsax.box, AppTheme.textSecondary)),
                  const SizedBox(width: 10),
                  Expanded(child: _stat('Retail value', '₹${_money(_stats['inventoryRetailValue'])}', Iconsax.tag, AppTheme.pharmacyAccent)),
                ]),
              ],
              const SizedBox(height: 22),
              Text('Operations', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.65,
                children: [
                  _action('Procurement & GRN', Iconsax.receipt_item, () => _open(const PharmacyProcurement())),
                  _action('Transfers & Returns', Iconsax.arrange_circle, () => _open(const PharmacyInventoryOps())),
                  _action('Prescription Queue', Iconsax.note_2, () => _open(const PrescriptionQueue())),
                  _action('Online Store', Iconsax.shop, () => _open(const PharmacyOnlineSettings())),
                ],
              ),
              const SizedBox(height: 22),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Recent POS sales', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                Text('${_stats['todayTransactions'] ?? 0} today', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
              ]),
              const SizedBox(height: 10),
              if (_sales.isEmpty)
                _empty('No sales in this branch yet')
              else
                ..._sales.take(6).map((sale) => _saleTile(sale)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String title, String value, IconData icon, Color color) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
        child: Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 18, color: color)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppTheme.textSecondary)),
            const SizedBox(height: 3),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
          ])),
        ]),
      );

  Widget _action(String label, IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
          child: Row(children: [
            Container(width: 38, height: 38, decoration: BoxDecoration(gradient: AppTheme.pharmacyGradient, borderRadius: BorderRadius.circular(11)), child: Icon(icon, size: 19, color: Colors.white)),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textPrimary))),
          ]),
        ),
      );

  Widget _saleTile(Map<String, dynamic> sale) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
        child: Row(children: [
          const Icon(Iconsax.receipt_2, size: 18, color: AppTheme.pharmacyAccent),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(sale['invoiceNumber']?.toString() ?? sale['saleNumber']?.toString() ?? 'Sale', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700)),
            Text(sale['customerName']?.toString() ?? 'Customer', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textSecondary)),
          ])),
          Text('₹${_money((sale['totalAmount'] ?? 0) - (sale['returnedAmount'] ?? 0))}', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.success)),
        ]),
      );

  Widget _errorCard(String text) => Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: AppTheme.error.withValues(alpha: .06), borderRadius: BorderRadius.circular(12)), child: Text(text, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.error)));
  Widget _empty(String text) => Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)), child: Center(child: Text(text, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary))));

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) await _load();
  }

  static Map<String, dynamic> _map(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  static List<Map<String, dynamic>> _maps(dynamic value) => value is List ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
  static String _money(dynamic value) => (num.tryParse(value?.toString() ?? '') ?? 0).toStringAsFixed(0);
  static String _message(DioException e) {
    final d = e.response?.data;
    if (d is Map) return d['message']?.toString() ?? d['error']?.toString() ?? 'Request failed';
    return e.message ?? 'Request failed';
  }
}
