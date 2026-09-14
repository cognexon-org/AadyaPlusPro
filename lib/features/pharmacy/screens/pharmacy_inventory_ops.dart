import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/network/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/pharmacy_store_provider.dart';

class PharmacyInventoryOps extends ConsumerStatefulWidget {
  const PharmacyInventoryOps({super.key});
  @override
  ConsumerState<PharmacyInventoryOps> createState() => _PharmacyInventoryOpsState();
}

class _PharmacyInventoryOpsState extends ConsumerState<PharmacyInventoryOps> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = false;
  List<Map<String, dynamic>> _transfers = [];
  List<Map<String, dynamic>> _returns = [];
  List<Map<String, dynamic>> _stores = [];
  List<Map<String, dynamic>> _medicines = [];
  List<Map<String, dynamic>> _sales = [];
  Map<String, dynamic> _valuation = {};
  String? _loadedStoreId;

  @override
  void initState() { super.initState(); _tabs = TabController(length: 3, vsync: this); Future.microtask(_load); }
  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  List<Map<String, dynamic>> _list(dynamic data, String key) {
    if (data is Map && data[key] is List) return (data[key] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return [];
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await ref.read(pharmacyStoreProvider.notifier).initialize();
      final r = await Future.wait([
        ApiService().getStockTransfers(), ApiService().getPharmacyReturns(), ApiService().getPharmacyStores(),
        ApiService().getMedicines(queryParams: {'limit': 200, 'isActive': 'true'}), ApiService().getPharmacySales(queryParams: {'limit': 100}), ApiService().getInventoryValuation(),
      ]);
      if (!mounted) return;
      setState(() {
        _loadedStoreId = ref.read(pharmacyStoreProvider).selectedStoreId;
        _transfers = _list(r[0].data, 'transfers');
        _returns = _list(r[1].data, 'returns');
        _stores = _list(r[2].data, 'stores');
        _medicines = _list(r[3].data, 'medicines');
        _sales = _list(r[4].data, 'sales');
        _valuation = Map<String, dynamic>.from(r[5].data as Map);
      });
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Inventory operation load failed: $e'))); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _newTransfer() async {
    final selected = ref.read(pharmacyStoreProvider).selectedStoreId;
    final destinations = _stores.where((s) => '${s['_id']}' != selected).toList();
    if (destinations.isEmpty || _medicines.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A second branch and medicine are required.'))); return; }
    String dest = '${destinations.first['_id']}', med = '${_medicines.first['_id']}'; final qty = TextEditingController(text: '1');
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(title: const Text('New Stock Transfer'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      DropdownButtonFormField<String>(value: dest, items: destinations.map((s) => DropdownMenuItem(value: '${s['_id']}', child: Text('${s['name'] ?? s['code']}'))).toList(), onChanged: (v) => setS(() => dest = v ?? dest), decoration: const InputDecoration(labelText: 'Destination branch')),
      DropdownButtonFormField<String>(value: med, items: _medicines.map((m) => DropdownMenuItem(value: '${m['_id']}', child: Text('${m['medicineName'] ?? m['name']}'))).toList(), onChanged: (v) => setS(() => med = v ?? med), decoration: const InputDecoration(labelText: 'Medicine')),
      TextField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity')),
    ]), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create'))])));
    if (ok != true) return;
    try { await ApiService().createStockTransfer({'destinationStoreId': dest, 'items': [{'medicineId': med, 'quantity': int.tryParse(qty.text) ?? 1}]}); await _load(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }

  Future<void> _transferAction(Map<String, dynamic> row, String action) async {
    try { await ApiService().stockTransferAction('${row['_id']}', action); await _load(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }

  Future<void> _newReturn() async {
    final eligible = _sales.where((s) => ['dispensed','partially_returned'].contains('${s['status']}') && (s['items'] as List? ?? const []).isNotEmpty).toList();
    if (eligible.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No eligible dispensed sale with items found.'))); return; }
    Map<String, dynamic> sale = eligible.first;
    final qty = TextEditingController(text: '1'), reason = TextEditingController(); bool restock = true;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(title: const Text('Create Sales Return'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      DropdownButtonFormField<String>(value: '${sale['_id']}', items: eligible.map((s) => DropdownMenuItem(value: '${s['_id']}', child: Text('${s['saleNumber'] ?? s['invoiceNumber'] ?? s['_id']}'))).toList(), onChanged: (v) => setS(() => sale = eligible.firstWhere((s) => '${s['_id']}' == v)), decoration: const InputDecoration(labelText: 'Sale')),
      TextField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Return quantity (first sale line)')),
      TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason')),
      SwitchListTile(value: restock, onChanged: (v) => setS(() => restock = v), title: const Text('Restockable')),
    ]), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Process return'))])));
    if (ok != true) return;
    final item = Map<String, dynamic>.from((sale['items'] as List).first as Map);
    try {
      await ApiService().createPharmacyReturn({'saleId': sale['_id'], 'items': [{'saleItemId': item['_id'], 'quantity': int.tryParse(qty.text) ?? 1, 'reason': reason.text.trim(), 'restockable': restock}], 'refundMethod': 'cash'});
      await _load();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(pharmacyStoreProvider);
    if (store.selectedStoreId != null && store.selectedStoreId != _loadedStoreId && !_loading) Future.microtask(_load);
    return Scaffold(
    backgroundColor: AppTheme.surface,
    appBar: AppBar(title: const Text('Inventory Operations'), bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Transfers'), Tab(text: 'Returns'), Tab(text: 'Valuation')])),
    floatingActionButton: FloatingActionButton.extended(onPressed: () => _tabs.index == 1 ? _newReturn() : _newTransfer(), icon: const Icon(Icons.add), label: Text(_tabs.index == 1 ? 'Return' : 'Transfer')),
    body: Column(children: [const Padding(padding: EdgeInsets.all(12), child: PharmacyStoreSelector()), if (_loading) const LinearProgressIndicator(), Expanded(child: TabBarView(controller: _tabs, children: [_transferTab(), _returnTab(), _valuationTab()]))]),
  );
  }

  Widget _transferTab() => RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(12), children: _transfers.isEmpty ? const [Padding(padding: EdgeInsets.all(30), child: Center(child: Text('No stock transfers')))] : _transfers.map((t) {
    final status = '${t['status'] ?? 'requested'}';
    final current = ref.read(pharmacyStoreProvider).selectedStoreId;
    final sourceId = _entityId(t['sourceStoreId']);
    final destinationId = _entityId(t['destinationStoreId']);
    final isSource = current != null && current == sourceId;
    final isDestination = current != null && current == destinationId;
    return Card(child: ListTile(title: Text('${t['transferNumber'] ?? 'Transfer'}', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)), subtitle: Text('${_entityName(t['sourceStoreId'], 'Source')} → ${_entityName(t['destinationStoreId'], 'Destination')}\n$status'), isThreeLine: true, trailing: PopupMenuButton<String>(onSelected: (a) => _transferAction(t, a), itemBuilder: (_) => [
      if (status == 'requested' && isSource) const PopupMenuItem(value: 'approve', child: Text('Approve')),
      if (status == 'approved' && isSource) const PopupMenuItem(value: 'dispatch', child: Text('Dispatch')),
      if (status == 'dispatched' && isDestination) const PopupMenuItem(value: 'receive', child: Text('Receive')),
      if ((status == 'requested' || status == 'approved') && isSource) const PopupMenuItem(value: 'cancel', child: Text('Cancel')),
    ]))); }).toList()));

  Widget _returnTab() => RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(12), children: _returns.isEmpty ? const [Padding(padding: EdgeInsets.all(30), child: Center(child: Text('No returns')))] : _returns.map((r) => Card(child: ListTile(title: Text('${r['returnNumber'] ?? 'Return'}'), subtitle: Text('Refund ₹${r['totalRefund'] ?? 0} • ${r['status'] ?? ''}')))).toList()));

  Widget _valuationTab() {
    final totals = Map<String, dynamic>.from((_valuation['totals'] as Map?) ?? const {});
    final rows = _list(_valuation, 'rows');
    return RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(12), children: [
      Wrap(spacing: 10, runSpacing: 10, children: [
        _stat('Cost', '₹${totals['costValue'] ?? 0}'), _stat('Retail', '₹${totals['retailValue'] ?? 0}'), _stat('Units', '${totals['units'] ?? 0}'), _stat('Expired cost', '₹${totals['expiredCostValue'] ?? 0}'),
      ]), const SizedBox(height: 12),
      ...rows.take(100).map((r) => Card(child: ListTile(title: Text('${r['medicineName'] ?? 'Medicine'}'), subtitle: Text('Batch ${r['batchNumber'] ?? '-'} • Qty ${r['availableQuantity'] ?? 0}'), trailing: Text('₹${r['costValue'] ?? 0}')))),
    ]));
  }

  String _entityId(dynamic value) => value is Map ? '${value['_id'] ?? ''}' : '${value ?? ''}';
  String _entityName(dynamic value, String fallback) => value is Map ? '${value['name'] ?? value['code'] ?? fallback}' : fallback;

  Widget _stat(String l, String v) => Container(width: 160, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l, style: const TextStyle(color: AppTheme.textSecondary)), const SizedBox(height: 4), Text(v, style: const TextStyle(fontWeight: FontWeight.bold))]));
}
