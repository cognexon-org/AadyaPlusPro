import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/pharmacy_type.dart';
import '../../../core/network/api_service.dart';
import '../theme/pharmacy_colors.dart';
import '../providers/pharmacy_store_provider.dart';
import '../widgets/pharmacy_ui.dart';

class PharmacyInventoryOps extends ConsumerStatefulWidget {
  const PharmacyInventoryOps({super.key});
  @override
  ConsumerState<PharmacyInventoryOps> createState() =>
      _PharmacyInventoryOpsState();
}

class _PharmacyInventoryOpsState extends ConsumerState<PharmacyInventoryOps>
    with SingleTickerProviderStateMixin {
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

  List<Map<String, dynamic>> _list(dynamic data, String key) {
    if (data is Map && data[key] is List)
      return (data[key] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    return [];
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await ref.read(pharmacyStoreProvider.notifier).initialize();
      final r = await Future.wait([
        ApiService().getStockTransfers(),
        ApiService().getPharmacyReturns(),
        ApiService().getPharmacyStores(),
        ApiService().getMedicines(
          queryParams: {'limit': 200, 'isActive': 'true'},
        ),
        ApiService().getPharmacySales(queryParams: {'limit': 100}),
        ApiService().getInventoryValuation(),
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
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pharmacyErrorMessage(
                e,
                fallback: 'Couldn\'t load transfers and returns.',
              ),
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

  Future<void> _newTransfer() async {
    final selected = ref.read(pharmacyStoreProvider).selectedStoreId;
    final destinations = _stores
        .where((s) => '${s['_id']}' != selected)
        .toList();
    if (destinations.isEmpty || _medicines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A second branch and medicine are required.'),
        ),
      );
      return;
    }
    String dest = '${destinations.first['_id']}',
        med = '${_medicines.first['_id']}';
    final qty = TextEditingController(text: '1');
    final ok = await showPharmacySheet<bool>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create Transfer',
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
                      label: 'To Branch',
                      value: dest,
                      icon: Icons.storefront_outlined,
                      items: destinations
                          .map(
                            (s) => DropdownMenuItem(
                              value: '${s['_id']}',
                              child: Text('${s['name'] ?? s['code']}'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setS(() => dest = v ?? dest),
                    ),
                    PharmacyDropdownField<String>(
                      label: 'Medicine',
                      value: med,
                      icon: Icons.medication_outlined,
                      items: _medicines
                          .map(
                            (m) => DropdownMenuItem(
                              value: '${m['_id']}',
                              child: Text('${m['medicineName'] ?? m['name']}'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setS(() => med = v ?? med),
                    ),
                    PharmacyTextField(
                      label: 'Quantity',
                      controller: qty,
                      icon: CupertinoIcons.number,
                      isNum: true,
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
                    label: 'Create Transfer',
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
      await ApiService().createStockTransfer({
        'destinationStoreId': dest,
        'items': [
          {'medicineId': med, 'quantity': int.tryParse(qty.text) ?? 1},
        ],
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

  Future<void> _transferAction(Map<String, dynamic> row, String action) async {
    try {
      await ApiService().stockTransferAction('${row['_id']}', action);
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

  Future<void> _newReturn() async {
    final eligible = _sales
        .where(
          (s) =>
              ['dispensed', 'partially_returned'].contains('${s['status']}') &&
              (s['items'] as List? ?? const []).isNotEmpty,
        )
        .toList();
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No eligible dispensed sale with items found.'),
        ),
      );
      return;
    }
    Map<String, dynamic> sale = eligible.first;
    final qty = TextEditingController(text: '1'),
        reason = TextEditingController();
    bool restock = true;
    final ok = await showPharmacySheet<bool>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create Sale Return',
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
                      label: 'Select Sale',
                      value: '${sale['_id']}',
                      icon: Icons.receipt_long_outlined,
                      items: eligible
                          .map(
                            (s) => DropdownMenuItem(
                              value: '${s['_id']}',
                              child: Text(
                                '${s['saleNumber'] ?? s['invoiceNumber'] ?? s['_id']}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setS(
                        () => sale = eligible.firstWhere(
                          (s) => '${s['_id']}' == v,
                        ),
                      ),
                    ),
                    PharmacyTextField(
                      label: 'Return Quantity',
                      controller: qty,
                      icon: CupertinoIcons.number,
                      isNum: true,
                    ),
                    PharmacyTextField(
                      label: 'Reason',
                      controller: reason,
                      icon: CupertinoIcons.doc_text,
                    ),
                    PharmacySwitchRow(
                      label: 'Restockable',
                      value: restock,
                      onChanged: (v) => setS(() => restock = v),
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
                    label: 'Process Return',
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
    final item = Map<String, dynamic>.from(
      (sale['items'] as List).first as Map,
    );
    try {
      await ApiService().createPharmacyReturn({
        'saleId': sale['_id'],
        'items': [
          {
            'saleItemId': item['_id'],
            'quantity': int.tryParse(qty.text) ?? 1,
            'reason': reason.text.trim(),
            'restockable': restock,
          },
        ],
        'refundMethod': 'cash',
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
          'Transfers & Returns',
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
          tabs: const [
            Tab(text: 'Transfers'),
            Tab(text: 'Returns'),
            Tab(text: 'Valuation'),
          ],
        ),
      ),
      floatingActionButton: _tabs.index == 2
          ? null
          : FloatingActionButton(
              backgroundColor: PharmacyColors.green,
              elevation: 2,
              onPressed: () => _tabs.index == 1 ? _newReturn() : _newTransfer(),
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
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: PharmacyListSkeleton(count: 4),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [_transferTab(), _returnTab(), _valuationTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _transferTab() => RefreshIndicator(
    color: PharmacyColors.green,
    onRefresh: _load,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      children: _transfers.isEmpty
          ? const [
              PharmacyEmptyStateInline(
                icon: CupertinoIcons.arrow_2_circlepath,
                text: 'No stock transfers',
              ),
            ]
          : _transfers.map((t) {
              final status = '${t['status'] ?? 'requested'}';
              final current = ref.read(pharmacyStoreProvider).selectedStoreId;
              final sourceId = _entityId(t['sourceStoreId']);
              final destinationId = _entityId(t['destinationStoreId']);
              final isSource = current != null && current == sourceId;
              final isDestination = current != null && current == destinationId;
              return PharmacyCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${t['transferNumber'] ?? 'Transfer'}',
                            style: PharmacyType.sans(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                              color: PharmacyColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_entityName(t['sourceStoreId'], 'Source')} → ${_entityName(t['destinationStoreId'], 'Destination')}',
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
                      onSelected: (a) => _transferAction(t, a),
                      itemBuilder: (_) => [
                        if (status == 'requested' && isSource)
                          const PopupMenuItem(
                            value: 'approve',
                            child: Text('Approve'),
                          ),
                        if (status == 'approved' && isSource)
                          const PopupMenuItem(
                            value: 'dispatch',
                            child: Text('Dispatch'),
                          ),
                        if (status == 'dispatched' && isDestination)
                          const PopupMenuItem(
                            value: 'receive',
                            child: Text('Receive'),
                          ),
                        if ((status == 'requested' || status == 'approved') &&
                            isSource)
                          const PopupMenuItem(
                            value: 'cancel',
                            child: Text('Cancel'),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
    ),
  );

  Widget _returnTab() => RefreshIndicator(
    color: PharmacyColors.green,
    onRefresh: _load,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      children: _returns.isEmpty
          ? const [
              PharmacyEmptyStateInline(
                icon: CupertinoIcons.arrow_uturn_left,
                text: 'No returns',
              ),
            ]
          : _returns
                .map(
                  (r) => PharmacyCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${r['returnNumber'] ?? 'Return'}',
                                style: PharmacyType.sans(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                  color: PharmacyColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              PharmacyStatusPill(
                                text: '${r['status'] ?? ''}',
                                color: PharmacyColors.textSecondary,
                                background: PharmacyColors.bgSecondary,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '₹${r['totalRefund'] ?? 0}',
                          style: PharmacyType.sans(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: PharmacyColors.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
    ),
  );

  Widget _valuationTab() {
    final totals = Map<String, dynamic>.from(
      (_valuation['totals'] as Map?) ?? const {},
    );
    final rows = _list(_valuation, 'rows');
    return RefreshIndicator(
      color: PharmacyColors.green,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.9,
            children: [
              PharmacyMetricTile(
                label: 'Cost',
                value: '₹${totals['costValue'] ?? 0}',
                color: PharmacyColors.green,
              ),
              PharmacyMetricTile(
                label: 'Retail',
                value: '₹${totals['retailValue'] ?? 0}',
                color: PharmacyColors.success,
              ),
              PharmacyMetricTile(
                label: 'Units',
                value: '${totals['units'] ?? 0}',
              ),
              PharmacyMetricTile(
                label: 'Expired cost',
                value: '₹${totals['expiredCostValue'] ?? 0}',
                color: PharmacyColors.error,
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...rows
              .take(100)
              .map(
                (r) => PharmacyCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${r['medicineName'] ?? 'Medicine'}',
                              style: PharmacyType.sans(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                                color: PharmacyColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Batch ${r['batchNumber'] ?? '-'} · Qty ${r['availableQuantity'] ?? 0}',
                              style: PharmacyType.sans(
                                fontSize: 11.5,
                                color: PharmacyColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '₹${r['costValue'] ?? 0}',
                        style: PharmacyType.sans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: PharmacyColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  String _entityId(dynamic value) =>
      value is Map ? '${value['_id'] ?? ''}' : '${value ?? ''}';
  String _entityName(dynamic value, String fallback) =>
      value is Map ? '${value['name'] ?? value['code'] ?? fallback}' : fallback;
}
