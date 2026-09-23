import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/pharmacy_type.dart';
import '../../../core/network/api_service.dart';
import '../theme/pharmacy_colors.dart';
import '../providers/pharmacy_store_provider.dart';
import '../widgets/pharmacy_ui.dart';

class PharmacyProcurement extends ConsumerStatefulWidget {
  const PharmacyProcurement({super.key});
  @override
  ConsumerState<PharmacyProcurement> createState() =>
      _PharmacyProcurementState();
}

class _PharmacyProcurementState extends ConsumerState<PharmacyProcurement>
    with SingleTickerProviderStateMixin {
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
    _tabs.addListener(() => setState(() {}));
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await ref.read(pharmacyStoreProvider.notifier).initialize();
      final r = await Future.wait([
        ApiService().getSuppliers(queryParams: {'limit': 100}),
        ApiService().getPurchaseOrders(queryParams: {'limit': 100}),
        ApiService().getGoodsReceipts(),
        ApiService().getMedicines(
          queryParams: {'limit': 200, 'isActive': 'true'},
        ),
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
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pharmacyErrorMessage(e, fallback: 'Couldn\'t load procurement.'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: PharmacyColors.error,
          ),
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _list(dynamic data, String key) {
    if (data is Map && data[key] is List)
      return (data[key] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    if (data is List)
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return [];
  }

  Future<void> _addSupplier() async {
    final name = TextEditingController(),
        phone = TextEditingController(),
        company = TextEditingController(),
        gst = TextEditingController();
    final ok = await showPharmacySheet<bool>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'New Supplier',
            style: PharmacyType.sans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: PharmacyColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PharmacyTextField(
                    label: 'Supplier name',
                    controller: name,
                    icon: CupertinoIcons.person,
                    required: true,
                  ),
                  PharmacyTextField(
                    label: 'Company',
                    controller: company,
                    icon: CupertinoIcons.building_2_fill,
                  ),
                  PharmacyTextField(
                    label: 'Phone',
                    controller: phone,
                    icon: CupertinoIcons.phone,
                    isNum: true,
                    required: true,
                  ),
                  PharmacyTextField(
                    label: 'GST number',
                    controller: gst,
                    icon: CupertinoIcons.doc_text,
                    margin: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: PharmacySecondaryButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.pop(ctx, false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PharmacyButton(
                  label: 'Add Supplier',
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty || phone.text.trim().isEmpty)
      return;
    try {
      await ApiService().createSupplier({
        'name': name.text.trim(),
        'companyName': company.text.trim(),
        'phone': phone.text.trim(),
        if (gst.text.trim().isNotEmpty) 'gstNumber': gst.text.trim(),
      });
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pharmacyErrorMessage(
                e,
                fallback: 'Something went wrong. Please try again.',
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: PharmacyColors.error,
          ),
        );
    }
  }

  Future<void> _createPo() async {
    if (_suppliers.isEmpty || _medicines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a supplier and medicine first.')),
      );
      return;
    }
    String supplierId = '${_suppliers.first['_id']}';
    String medicineId = '${_medicines.first['_id']}';
    final qty = TextEditingController(text: '1'),
        cost = TextEditingController(),
        sell = TextEditingController(),
        notes = TextEditingController();
    final ok = await showPharmacySheet<bool>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create Purchase Order',
              style: PharmacyType.sans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: PharmacyColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PharmacyDropdownField<String>(
                      label: 'Supplier',
                      value: supplierId,
                      icon: CupertinoIcons.person,
                      items: _suppliers
                          .map(
                            (s) => DropdownMenuItem(
                              value: '${s['_id']}',
                              child: Text(
                                '${s['name'] ?? s['companyName'] ?? 'Supplier'}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setS(() => supplierId = v ?? supplierId),
                    ),
                    PharmacyDropdownField<String>(
                      label: 'Medicine',
                      value: medicineId,
                      icon: Icons.medication_outlined,
                      items: _medicines
                          .map(
                            (m) => DropdownMenuItem(
                              value: '${m['_id']}',
                              child: Text(
                                '${m['medicineName'] ?? m['name'] ?? 'Medicine'}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setS(() => medicineId = v ?? medicineId),
                    ),
                    PharmacyTextField(
                      label: 'Quantity',
                      controller: qty,
                      icon: CupertinoIcons.number,
                      isNum: true,
                    ),
                    PharmacyTextField(
                      label: 'Purchase price (₹)',
                      controller: cost,
                      icon: CupertinoIcons.money_dollar,
                      isDecimal: true,
                    ),
                    PharmacyTextField(
                      label: 'Selling price (₹)',
                      controller: sell,
                      icon: CupertinoIcons.tag,
                      isDecimal: true,
                    ),
                    PharmacyTextField(
                      label: 'Expected delivery notes',
                      controller: notes,
                      icon: CupertinoIcons.doc_text,
                      margin: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: PharmacySecondaryButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.pop(ctx, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PharmacyButton(
                    label: 'Create PO',
                    onPressed: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ApiService().createPurchaseOrder({
        'supplierId': supplierId,
        'items': [
          {
            'medicineId': medicineId,
            'quantity': int.tryParse(qty.text) ?? 1,
            'purchasePrice': double.tryParse(cost.text) ?? 0,
            if (sell.text.trim().isNotEmpty)
              'sellingPrice': double.tryParse(sell.text) ?? 0,
          },
        ],
        'notes': notes.text.trim(),
      });
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pharmacyErrorMessage(
                e,
                fallback: 'Something went wrong. Please try again.',
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: PharmacyColors.error,
          ),
        );
    }
  }

  Future<void> _poAction(Map<String, dynamic> po, String action) async {
    final id = '${po['_id']}';
    try {
      if (action == 'approve') await ApiService().approvePurchaseOrder(id);
      if (action == 'order') await ApiService().markPurchaseOrderOrdered(id);
      if (action == 'receive') await _receivePo(po);
      if (action != 'receive') await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pharmacyErrorMessage(
                e,
                fallback: 'Something went wrong. Please try again.',
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: PharmacyColors.error,
          ),
        );
    }
  }

  Future<void> _receivePo(Map<String, dynamic> po) async {
    final items = (po['items'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    if (items.isEmpty) return;

    // One set of controllers per PO line so every item can be received in a
    // single GRN, not just the first — a multi-item PO previously lost every
    // line after the first because only `items.first` was ever submitted.
    final lineControllers = items.map((item) {
      final remaining =
          ((num.tryParse('${item['quantity']}') ?? 0) -
                  (num.tryParse(
                        '${item['receivedQuantity'] ?? item['received_quantity'] ?? 0}',
                      ) ??
                      0))
              .toInt();
      return {
        'item': item,
        'qty': TextEditingController(text: remaining > 0 ? '$remaining' : '0'),
        'damaged': TextEditingController(text: '0'),
        'batch': TextEditingController(
          text:
              'BATCH-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}',
        ),
        'expiry': TextEditingController(
          text: DateTime.now()
              .add(const Duration(days: 365))
              .toIso8601String()
              .split('T')
              .first,
        ),
      };
    }).toList();
    final invoice = TextEditingController();

    final ok = await showPharmacySheet<bool>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Receive ${po['orderNumber'] ?? po['order_number'] ?? 'PO'}',
            style: PharmacyType.sans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: PharmacyColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in lineControllers) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        '${(line['item'] as Map)['medicineName'] ?? (line['item'] as Map)['medicine_name'] ?? 'Item'}',
                        style: PharmacyType.sans(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                          color: PharmacyColors.textPrimary,
                        ),
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: PharmacyTextField(
                            label: 'Received qty',
                            controller: line['qty'] as TextEditingController,
                            icon: CupertinoIcons.arrow_down_doc,
                            isNum: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: PharmacyTextField(
                            label: 'Damaged qty',
                            controller:
                                line['damaged'] as TextEditingController,
                            icon: CupertinoIcons.exclamationmark_triangle,
                            isNum: true,
                          ),
                        ),
                      ],
                    ),
                    PharmacyTextField(
                      label: 'Batch number',
                      controller: line['batch'] as TextEditingController,
                      icon: CupertinoIcons.number,
                    ),
                    PharmacyTextField(
                      label: 'Expiry (YYYY-MM-DD)',
                      controller: line['expiry'] as TextEditingController,
                      icon: CupertinoIcons.calendar,
                    ),
                    const Divider(height: 20, color: PharmacyColors.border),
                  ],
                  PharmacyTextField(
                    label: 'Supplier invoice',
                    controller: invoice,
                    icon: CupertinoIcons.doc_text,
                    margin: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: PharmacySecondaryButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.pop(ctx, false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PharmacyButton(
                  label: 'Receive Stock',
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (ok != true) return;

    final receivedItems = <Map<String, dynamic>>[];
    final damagedItems = <Map<String, dynamic>>[];
    for (final line in lineControllers) {
      final itemId = '${(line['item'] as Map)['_id']}';
      final receivedQty =
          int.tryParse((line['qty'] as TextEditingController).text) ?? 0;
      final damagedQty =
          int.tryParse((line['damaged'] as TextEditingController).text) ?? 0;
      if (receivedQty > 0) {
        receivedItems.add({
          'itemId': itemId,
          'quantity': receivedQty,
          'batchNumber': (line['batch'] as TextEditingController).text.trim(),
          'expiryDate': (line['expiry'] as TextEditingController).text.trim(),
        });
      }
      if (damagedQty > 0) {
        damagedItems.add({'itemId': itemId, 'quantity': damagedQty});
      }
    }
    if (receivedItems.isEmpty) return;

    await ApiService().receivePurchaseOrder('${po['_id']}', {
      'receivedItems': receivedItems,
      'damagedItems': damagedItems,
      if (invoice.text.trim().isNotEmpty)
        'supplierInvoiceNumber': invoice.text.trim(),
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(pharmacyStoreProvider);
    if (store.selectedStoreId != null &&
        store.selectedStoreId != _loadedStoreId &&
        !_loading)
      Future.microtask(_load);
    return Scaffold(
      backgroundColor: PharmacyColors.bg,
      appBar: AppBar(
        backgroundColor: PharmacyColors.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: PharmacyColors.textPrimary),
        title: Text(
          'Procurement & GRN',
          style: PharmacyType.sans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: PharmacyColors.textPrimary,
          ),
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: PharmacyColors.green,
          unselectedLabelColor: PharmacyColors.textSecondary,
          indicatorColor: PharmacyColors.green,
          labelStyle: PharmacyType.sans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: PharmacyType.sans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Purchase Orders'),
            Tab(text: 'Suppliers'),
            Tab(text: 'GRNs'),
          ],
        ),
      ),
      floatingActionButton: _tabs.index == 2
          ? null
          : FloatingActionButton(
              backgroundColor: PharmacyColors.green,
              elevation: 2,
              onPressed: () => _tabs.index == 1 ? _addSupplier() : _createPo(),
              child: const Icon(CupertinoIcons.add, color: Colors.white),
            ),
      body: SafeArea(
        // An AppBar already covers the status bar; this is here for
        // the bottom inset, so content and buttons clear the device
        // gesture bar.
        top: false,
        child: Column(
          children: [
            if (_loading)
              // A 2px bar over a blank page says "wait" without saying what
              // for. A skeleton in the shape of the incoming list does both.
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: PharmacyListSkeleton(count: 4),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [_ordersTab(), _suppliersTab(), _grnTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ordersTab() => RefreshIndicator(
    color: PharmacyColors.green,
    onRefresh: _load,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      children: _orders.isEmpty
          ? const [
              PharmacyEmptyStateInline(
                icon: CupertinoIcons.doc_text,
                text: 'No purchase orders',
              ),
            ]
          : _orders.map((po) {
              final status = '${po['status'] ?? 'draft'}';
              return PharmacyCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${po['orderNumber'] ?? po['order_number'] ?? 'Purchase order'}',
                            style: PharmacyType.sans(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                              color: PharmacyColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${(po['supplierId'] is Map ? po['supplierId']['name'] : 'Supplier')} · ₹${po['totalAmount'] ?? po['total_amount'] ?? 0}',
                            style: PharmacyType.sans(
                              fontSize: 11.5,
                              color: PharmacyColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          PharmacyStatusPill(
                            text: status,
                            color: PharmacyColors.info,
                            background: PharmacyColors.infoBg,
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) => _poAction(po, v),
                      itemBuilder: (_) => [
                        if (status == 'draft' || status == 'pending')
                          const PopupMenuItem(
                            value: 'approve',
                            child: Text('Approve'),
                          ),
                        if (status == 'approved')
                          const PopupMenuItem(
                            value: 'order',
                            child: Text('Mark ordered'),
                          ),
                        if ([
                          'approved',
                          'ordered',
                          'partially_received',
                        ].contains(status))
                          const PopupMenuItem(
                            value: 'receive',
                            child: Text('Receive / GRN'),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
    ),
  );

  Widget _suppliersTab() => RefreshIndicator(
    color: PharmacyColors.green,
    onRefresh: _load,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      children: _suppliers.isEmpty
          ? const [
              PharmacyEmptyStateInline(
                icon: CupertinoIcons.person_2,
                text: 'No suppliers',
              ),
            ]
          : _suppliers
                .map(
                  (s) => PharmacyCard(
                    child: Row(
                      children: [
                        Icon(
                          Icons.local_shipping_outlined,
                          size: 18,
                          color: PharmacyColors.textSecondary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${s['name'] ?? 'Supplier'}',
                                style: PharmacyType.sans(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                  color: PharmacyColors.textPrimary,
                                ),
                              ),
                              Text(
                                '${s['companyName'] ?? ''} ${s['phone'] ?? ''}'
                                    .trim(),
                                style: PharmacyType.sans(
                                  fontSize: 11.5,
                                  color: PharmacyColors.textSecondary,
                                ),
                              ),
                              if ((s['gstNumber'] ?? '').toString().isNotEmpty)
                                Text(
                                  'GST: ${s['gstNumber']}',
                                  style: PharmacyType.sans(
                                    fontSize: 11,
                                    color: PharmacyColors.textTertiary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const Icon(
                          CupertinoIcons.chevron_right,
                          size: 15,
                          color: PharmacyColors.textTertiary,
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
    ),
  );

  Widget _grnTab() => RefreshIndicator(
    color: PharmacyColors.green,
    onRefresh: _load,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: _grns.isEmpty
          ? const [
              PharmacyEmptyStateInline(
                icon: Icons.receipt_long_outlined,
                text: 'No goods receipts',
              ),
            ]
          : _grns
                .map(
                  (g) => PharmacyCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${g['grnNumber'] ?? g['receiptNumber'] ?? 'GRN'}',
                                style: PharmacyType.sans(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                  color: PharmacyColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Damaged ₹${g['damagedValue'] ?? 0}',
                                style: PharmacyType.sans(
                                  fontSize: 11.5,
                                  color: PharmacyColors.error,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '₹${g['acceptedValue'] ?? 0}',
                          style: PharmacyType.sans(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: PharmacyColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
    ),
  );
}
