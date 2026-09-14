import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/network/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/pharmacy_store_provider.dart';

class PharmacyProcurement extends ConsumerStatefulWidget {
  const PharmacyProcurement({super.key});
  @override
  ConsumerState<PharmacyProcurement> createState() => _PharmacyProcurementState();
}

class _PharmacyProcurementState extends ConsumerState<PharmacyProcurement> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = false;
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _grns = [];
  List<Map<String, dynamic>> _medicines = [];
  String? _loadedStoreId;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    Future.microtask(_load);
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await ref.read(pharmacyStoreProvider.notifier).initialize();
      final r = await Future.wait([
        ApiService().getSuppliers(queryParams: {'limit': 100}),
        ApiService().getPurchaseOrders(queryParams: {'limit': 100}),
        ApiService().getGoodsReceipts(),
        ApiService().getMedicines(queryParams: {'limit': 200, 'isActive': 'true'}),
      ]);
      if (!mounted) return;
      setState(() {
        _loadedStoreId = ref.read(pharmacyStoreProvider).selectedStoreId;
        _suppliers = _list(r[0].data, 'suppliers');
        _orders = _list(r[1].data, 'purchaseOrders');
        if (_orders.isEmpty) _orders = _list(r[1].data, 'orders');
        _grns = _list(r[2].data, 'grns');
        _medicines = _list(r[3].data, 'medicines');
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Procurement load failed: $e')));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  List<Map<String, dynamic>> _list(dynamic data, String key) {
    if (data is Map && data[key] is List) return (data[key] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (data is List) return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return [];
  }

  Future<void> _addSupplier() async {
    final name = TextEditingController(), phone = TextEditingController(), company = TextEditingController(), gst = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('New Supplier'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Supplier name *')),
        TextField(controller: company, decoration: const InputDecoration(labelText: 'Company')),
        TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone *')),
        TextField(controller: gst, decoration: const InputDecoration(labelText: 'GST number')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create'))],
    ));
    if (ok != true || name.text.trim().isEmpty || phone.text.trim().isEmpty) return;
    try {
      await ApiService().createSupplier({'name': name.text.trim(), 'companyName': company.text.trim(), 'phone': phone.text.trim(), if (gst.text.trim().isNotEmpty) 'gstNumber': gst.text.trim()});
      await _load();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }

  Future<void> _createPo() async {
    if (_suppliers.isEmpty || _medicines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a supplier and medicine first.'))); return;
    }
    String supplierId = '${_suppliers.first['_id']}';
    String medicineId = '${_medicines.first['_id']}';
    final qty = TextEditingController(text: '1'), cost = TextEditingController(), sell = TextEditingController(), notes = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      title: const Text('Create Purchase Order'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: supplierId, items: _suppliers.map((s) => DropdownMenuItem(value: '${s['_id']}', child: Text('${s['name'] ?? s['companyName'] ?? 'Supplier'}'))).toList(), onChanged: (v) => setS(() => supplierId = v ?? supplierId), decoration: const InputDecoration(labelText: 'Supplier')),
        DropdownButtonFormField<String>(value: medicineId, items: _medicines.map((m) => DropdownMenuItem(value: '${m['_id']}', child: Text('${m['medicineName'] ?? m['name'] ?? 'Medicine'}'))).toList(), onChanged: (v) => setS(() => medicineId = v ?? medicineId), decoration: const InputDecoration(labelText: 'Medicine')),
        TextField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity')),
        TextField(controller: cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Purchase price')),
        TextField(controller: sell, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Selling price')),
        TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create draft'))],
    )));
    if (ok != true) return;
    try {
      await ApiService().createPurchaseOrder({
        'supplierId': supplierId,
        'items': [{'medicineId': medicineId, 'quantity': int.tryParse(qty.text) ?? 1, 'purchasePrice': double.tryParse(cost.text) ?? 0, if (sell.text.trim().isNotEmpty) 'sellingPrice': double.tryParse(sell.text) ?? 0}],
        'notes': notes.text.trim(),
      });
      await _load();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }

  Future<void> _poAction(Map<String, dynamic> po, String action) async {
    final id = '${po['_id']}';
    try {
      if (action == 'approve') await ApiService().approvePurchaseOrder(id);
      if (action == 'order') await ApiService().markPurchaseOrderOrdered(id);
      if (action == 'receive') await _receivePo(po);
      if (action != 'receive') await _load();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }

  Future<void> _receivePo(Map<String, dynamic> po) async {
    final items = (po['items'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (items.isEmpty) return;
    final first = items.first;
    final remaining = ((num.tryParse('${first['quantity']}') ?? 0) - (num.tryParse('${first['receivedQuantity'] ?? first['received_quantity'] ?? 0}') ?? 0)).toInt();
    final qty = TextEditingController(text: remaining > 0 ? '$remaining' : '1');
    final damaged = TextEditingController(text: '0');
    final batch = TextEditingController(text: 'BATCH-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}');
    final expiry = TextEditingController(text: DateTime.now().add(const Duration(days: 365)).toIso8601String().split('T').first);
    final invoice = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text('Receive ${po['orderNumber'] ?? po['order_number'] ?? 'PO'}'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Receiving first outstanding PO line: ${first['medicineName'] ?? first['medicine_name'] ?? ''}'),
        TextField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Received quantity')),
        TextField(controller: damaged, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Damaged quantity')),
        TextField(controller: batch, decoration: const InputDecoration(labelText: 'Batch number')),
        TextField(controller: expiry, decoration: const InputDecoration(labelText: 'Expiry YYYY-MM-DD')),
        TextField(controller: invoice, decoration: const InputDecoration(labelText: 'Supplier invoice')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create GRN'))],
    ));
    if (ok != true) return;
    final itemId = '${first['_id']}';
    final receivedQty = int.tryParse(qty.text) ?? 0;
    final damagedQty = int.tryParse(damaged.text) ?? 0;
    if (receivedQty <= 0) return;
    await ApiService().receivePurchaseOrder('${po['_id']}', {
      'receivedItems': [{'itemId': itemId, 'quantity': receivedQty, 'batchNumber': batch.text.trim(), 'expiryDate': expiry.text.trim(), if (invoice.text.trim().isNotEmpty) 'invoiceNumber': invoice.text.trim()}],
      'damagedItems': damagedQty > 0 ? [{'itemId': itemId, 'quantity': damagedQty}] : <Map<String, dynamic>>[],
      if (invoice.text.trim().isNotEmpty) 'supplierInvoiceNumber': invoice.text.trim(),
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(pharmacyStoreProvider);
    if (store.selectedStoreId != null && store.selectedStoreId != _loadedStoreId && !_loading) Future.microtask(_load);
    return Scaffold(
    backgroundColor: AppTheme.surface,
    appBar: AppBar(title: const Text('Procurement & GRN'), bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Purchase Orders'), Tab(text: 'Suppliers'), Tab(text: 'GRNs')])),
    floatingActionButton: FloatingActionButton.extended(onPressed: () => _tabs.index == 1 ? _addSupplier() : _createPo(), icon: const Icon(Icons.add), label: Text(_tabs.index == 1 ? 'Supplier' : 'PO')),
    body: Column(children: [
      const Padding(padding: EdgeInsets.all(12), child: PharmacyStoreSelector()),
      if (_loading) const LinearProgressIndicator(),
      Expanded(child: TabBarView(controller: _tabs, children: [_ordersTab(), _suppliersTab(), _grnTab()])),
    ]),
  );
  }

  Widget _ordersTab() => RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(12), children: _orders.isEmpty ? const [Padding(padding: EdgeInsets.all(30), child: Center(child: Text('No purchase orders')))] : _orders.map((po) {
    final status = '${po['status'] ?? 'draft'}';
    return Card(child: ListTile(
      title: Text('${po['orderNumber'] ?? po['order_number'] ?? 'Purchase order'}', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
      subtitle: Text('${(po['supplierId'] is Map ? po['supplierId']['name'] : 'Supplier')} • ₹${po['totalAmount'] ?? po['total_amount'] ?? 0}\n$status'),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(onSelected: (v) => _poAction(po, v), itemBuilder: (_) => [
        if (status == 'draft' || status == 'pending') const PopupMenuItem(value: 'approve', child: Text('Approve')),
        if (status == 'approved') const PopupMenuItem(value: 'order', child: Text('Mark ordered')),
        if (['approved','ordered','partially_received'].contains(status)) const PopupMenuItem(value: 'receive', child: Text('Receive / GRN')),
      ]),
    ));
  }).toList()));

  Widget _suppliersTab() => RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(12), children: _suppliers.isEmpty ? const [Padding(padding: EdgeInsets.all(30), child: Center(child: Text('No suppliers')))] : _suppliers.map((s) => Card(child: ListTile(title: Text('${s['name'] ?? 'Supplier'}'), subtitle: Text('${s['companyName'] ?? ''} ${s['phone'] ?? ''}')))).toList()));

  Widget _grnTab() => RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(12), children: _grns.isEmpty ? const [Padding(padding: EdgeInsets.all(30), child: Center(child: Text('No goods receipts')))] : _grns.map((g) => Card(child: ListTile(title: Text('${g['grnNumber'] ?? g['receiptNumber'] ?? 'GRN'}'), subtitle: Text('Accepted ₹${g['acceptedValue'] ?? 0} • Damaged ₹${g['damagedValue'] ?? 0}')))).toList()));
}
