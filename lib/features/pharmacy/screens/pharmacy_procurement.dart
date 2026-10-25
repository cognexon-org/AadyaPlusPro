import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/pharmacy_type.dart';
import '../theme/pharmacy_colors.dart';
import '../providers/pharmacy_procurement_provider.dart';
import '../widgets/pharmacy_ui.dart';
import 'pharmacy_orders.dart' show orderStatusLabel;

class PharmacyProcurement extends ConsumerStatefulWidget {
  const PharmacyProcurement({super.key});
  @override
  ConsumerState<PharmacyProcurement> createState() =>
      _PharmacyProcurementState();
}

class _PharmacyProcurementState extends ConsumerState<PharmacyProcurement> {
  /// 0 = orders, 1 = suppliers, 2 = receipts.
  int _tab = 0;
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _grns = [];
  List<Map<String, dynamic>> _medicines = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final cached = ref.read(pharmacyProcurementProvider);
      ref
          .read(pharmacyProcurementProvider.notifier)
          .loadProcurement(silent: !cached.isEmpty);
    });
  }

  Future<void> _load() => ref
      .read(pharmacyProcurementProvider.notifier)
      .loadProcurement(force: true);

  void _toast(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showError(Object e) => _toast(
    pharmacyErrorMessage(
      e,
      fallback: 'Something went wrong. Please try again.',
    ),
    PharmacyColors.error,
  );

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
            'New supplier',
            style: PharmacyType.sans(
              fontSize: 15,
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
                    icon: LucideIcons.user,
                    required: true,
                  ),
                  PharmacyTextField(
                    label: 'Company',
                    controller: company,
                    icon: LucideIcons.building2,
                  ),
                  PharmacyTextField(
                    label: 'Phone',
                    controller: phone,
                    icon: LucideIcons.phone,
                    isNum: true,
                    required: true,
                  ),
                  PharmacyTextField(
                    label: 'GST number',
                    controller: gst,
                    icon: LucideIcons.fileText,
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
    if (ok != true) return;
    // This used to return silently, so a supplier with no phone simply never
    // appeared and nobody was told why.
    if (name.text.trim().isEmpty || phone.text.trim().isEmpty) {
      _toast('Supplier name and phone are required.', PharmacyColors.warning);
      return;
    }
    try {
      await ref.read(pharmacyProcurementProvider.notifier).createSupplier({
        'name': name.text.trim(),
        'companyName': company.text.trim(),
        'phone': phone.text.trim(),
        if (gst.text.trim().isNotEmpty) 'gstNumber': gst.text.trim(),
      });
      _toast('Supplier added', PharmacyColors.success);
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _createPo() async {
    if (_suppliers.isEmpty || _medicines.isEmpty) {
      _toast('Add a supplier and medicine first.', PharmacyColors.warning);
      return;
    }
    String supplierId = '${_suppliers.first['_id']}';
    // A real order to a distributor has many lines; this sheet used to allow
    // exactly one, so a 20-item order meant 20 separate POs.
    final lines = <_PoLine>[_PoLine('${_medicines.first['_id']}')];
    final notes = TextEditingController();
    String? error;

    String? validate() {
      final seen = <String>{};
      for (final line in lines) {
        final qty = int.tryParse(line.qty.text.trim()) ?? 0;
        final name = _medicineName(line.medicineId);
        if (qty <= 0) return 'Enter a quantity for $name.';
        if ((double.tryParse(line.cost.text.trim()) ?? 0) <= 0) {
          return 'Enter the purchase price for $name.';
        }
        if (!seen.add(line.medicineId)) {
          return '$name is on the order twice — combine the lines.';
        }
      }
      return null;
    }

    final ok = await showPharmacySheet<bool>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'New purchase order',
              style: PharmacyType.sans(
                fontSize: 15,
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
                      icon: LucideIcons.user,
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
                    for (var i = 0; i < lines.length; i++) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'ITEM ${i + 1}',
                              style: PharmacyType.sans(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.4,
                                color: PharmacyColors.textTertiary,
                              ),
                            ),
                          ),
                          if (lines.length > 1)
                            IconButton(
                              tooltip: 'Remove item',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(
                                LucideIcons.circleMinus,
                                size: 18,
                                color: PharmacyColors.error,
                              ),
                              onPressed: () => setS(() {
                                lines.removeAt(i).dispose();
                                error = null;
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      PharmacyDropdownField<String>(
                        label: 'Medicine',
                        value: lines[i].medicineId,
                        icon: LucideIcons.pill,
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
                        onChanged: (v) => setS(
                          () => lines[i].medicineId = v ?? lines[i].medicineId,
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: PharmacyTextField(
                              label: 'Qty',
                              controller: lines[i].qty,
                              isNum: true,
                              required: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: PharmacyTextField(
                              label: 'Cost (₹)',
                              controller: lines[i].cost,
                              isDecimal: true,
                              required: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: PharmacyTextField(
                              label: 'MRP/Sell (₹)',
                              controller: lines[i].sell,
                              isDecimal: true,
                            ),
                          ),
                        ],
                      ),
                    ],
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setS(() {
                          lines.add(_PoLine('${_medicines.first['_id']}'));
                          error = null;
                        }),
                        icon: const Icon(
                          LucideIcons.plus,
                          size: 16,
                          color: PharmacyColors.green,
                        ),
                        label: Text(
                          'Add another item',
                          style: PharmacyType.sans(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: PharmacyColors.green,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    PharmacyTextField(
                      label: 'Expected delivery notes',
                      controller: notes,
                      icon: LucideIcons.fileText,
                      margin: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: PharmacyType.sans(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: PharmacyColors.error,
                ),
              ),
            ],
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
                    label: lines.length == 1
                        ? 'Create PO'
                        : 'Create PO (${lines.length} items)',
                    onPressed: () {
                      final problem = validate();
                      if (problem != null) {
                        setS(() => error = problem);
                        return;
                      }
                      Navigator.pop(ctx, true);
                    },
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
      await ref.read(pharmacyProcurementProvider.notifier).createPurchaseOrder({
        'supplierId': supplierId,
        'items': [
          for (final line in lines)
            {
              'medicineId': line.medicineId,
              'quantity': int.tryParse(line.qty.text.trim()) ?? 1,
              'purchasePrice': double.tryParse(line.cost.text.trim()) ?? 0,
              if (line.sell.text.trim().isNotEmpty)
                'sellingPrice': double.tryParse(line.sell.text.trim()) ?? 0,
            },
        ],
        'notes': notes.text.trim(),
      });
      _toast('Purchase order created', PharmacyColors.success);
    } catch (e) {
      _showError(e);
    }
  }

  String _medicineName(String id) {
    for (final m in _medicines) {
      if ('${m['_id']}' == id) {
        return '${m['medicineName'] ?? m['name'] ?? 'this medicine'}';
      }
    }
    return 'this medicine';
  }

  Future<void> _poAction(Map<String, dynamic> po, String action) async {
    final id = '${po['_id']}';
    final notifier = ref.read(pharmacyProcurementProvider.notifier);
    try {
      switch (action) {
        case 'approve':
          await notifier.approvePurchaseOrder(id);
          _toast('Purchase order approved', PharmacyColors.success);
        case 'order':
          await notifier.markPurchaseOrderOrdered(id);
          _toast('Marked as ordered', PharmacyColors.success);
        case 'receive':
          await _receivePo(po);
        case 'cancel':
          final proceed = await PharmacyDialog.confirm(
            context,
            title: 'Cancel this purchase order?',
            message:
                '${po['orderNumber'] ?? 'This order'} will be closed and cannot be received against. This cannot be undone.',
            confirmLabel: 'Cancel PO',
            cancelLabel: 'Keep',
          );
          if (!proceed) return;
          await notifier.cancelPurchaseOrder(id);
          _toast('Purchase order cancelled', PharmacyColors.success);
        case 'payment':
          await _recordPayment(po);
      }
    } catch (e) {
      _showError(e);
    }
  }

  /// Records money paid to the supplier against this PO. The server caps the
  /// running total at the order value, so the outstanding amount is offered
  /// as the default.
  Future<void> _recordPayment(Map<String, dynamic> po) async {
    final total = num.tryParse('${po['totalAmount'] ?? 0}') ?? 0;
    final paid = num.tryParse('${po['paidAmount'] ?? 0}') ?? 0;
    final due = (total - paid).clamp(0, double.infinity);
    final amount = TextEditingController(
      text: due == due.roundToDouble() ? '${due.toInt()}' : '$due',
    );
    final ok = await showPharmacySheet<bool>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Record payment',
            style: PharmacyType.sans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: PharmacyColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${po['orderNumber'] ?? 'Purchase order'} · ${pharmacyRupees(paid)} paid of ${pharmacyRupees(total)}',
            style: PharmacyType.sans(
              fontSize: 11.5,
              color: PharmacyColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          PharmacyTextField(
            label: 'Amount paid to supplier (₹)',
            controller: amount,
            icon: LucideIcons.indianRupee,
            isDecimal: true,
            required: true,
            margin: EdgeInsets.zero,
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
                  label: 'Record',
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (ok != true) return;
    final value = double.tryParse(amount.text.trim()) ?? 0;
    if (value <= 0) {
      _toast('Enter an amount above zero.', PharmacyColors.warning);
      return;
    }
    await ref
        .read(pharmacyProcurementProvider.notifier)
        .recordPurchasePayment('${po['_id']}', value);
    _toast(
      'Payment of ${pharmacyRupees(value)} recorded',
      PharmacyColors.success,
    );
  }

  Future<void> _receivePo(Map<String, dynamic> po) async {
    final items = (po['items'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (items.isEmpty) return;

    // One set of inputs per PO line so every item can be received in a single
    // GRN. Batch number and expiry start empty on purpose: they are printed on
    // the strip and must be read off it. Pre-filling a generated batch and a
    // one-year expiry let a receipt go through with invented values, and FEFO
    // dispensing then trusted that made-up date.
    final lines = items.map((item) {
      final remaining =
          ((num.tryParse('${item['quantity']}') ?? 0) -
                  (num.tryParse(
                        '${item['receivedQuantity'] ?? item['received_quantity'] ?? 0}',
                      ) ??
                      0))
              .toInt();
      return _GrnLine(
        item: item,
        qty: TextEditingController(text: remaining > 0 ? '$remaining' : '0'),
        damaged: TextEditingController(text: '0'),
        batch: TextEditingController(),
      );
    }).toList();
    final invoice = TextEditingController();
    String? error;

    String? validate() {
      var anyReceived = false;
      for (final line in lines) {
        final received = int.tryParse(line.qty.text.trim()) ?? 0;
        if (received <= 0) continue;
        anyReceived = true;
        if (line.batch.text.trim().isEmpty) {
          return 'Enter the batch number for ${line.name}.';
        }
        if (line.expiry == null) {
          return 'Pick the expiry date for ${line.name}.';
        }
      }
      return anyReceived
          ? null
          : 'Enter a received quantity for at least one item.';
    }

    final ok = await showPharmacySheet<bool>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Receive ${po['orderNumber'] ?? po['order_number'] ?? 'PO'}',
              style: PharmacyType.sans(
                fontSize: 15,
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
                    for (final line in lines) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          line.name,
                          style: PharmacyType.sans(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
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
                              controller: line.qty,
                              icon: LucideIcons.fileDown,
                              isNum: true,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: PharmacyTextField(
                              label: 'Damaged qty',
                              controller: line.damaged,
                              icon: LucideIcons.triangleAlert,
                              isNum: true,
                            ),
                          ),
                        ],
                      ),
                      PharmacyTextField(
                        label: 'Batch number',
                        controller: line.batch,
                        icon: LucideIcons.hash,
                        hint: 'As printed on the pack',
                        required: true,
                      ),
                      PharmacyPickerField(
                        label: 'Expiry date',
                        required: true,
                        valueText: line.expiry == null
                            ? 'Select expiry date'
                            : DateFormat('d MMM yyyy').format(line.expiry!),
                        onTap: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate:
                                line.expiry ??
                                now.add(const Duration(days: 365)),
                            firstDate: now.add(const Duration(days: 1)),
                            lastDate: now.add(const Duration(days: 3650)),
                          );
                          if (picked != null) {
                            setS(() {
                              line.expiry = picked;
                              error = null;
                            });
                          }
                        },
                      ),
                      const Divider(height: 20, color: PharmacyColors.border),
                    ],
                    PharmacyTextField(
                      label: 'Supplier invoice',
                      controller: invoice,
                      icon: LucideIcons.fileText,
                      margin: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: PharmacyType.sans(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: PharmacyColors.error,
                ),
              ),
            ],
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
                    onPressed: () {
                      final problem = validate();
                      if (problem != null) {
                        setS(() => error = problem);
                        return;
                      }
                      Navigator.pop(ctx, true);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final receivedItems = <Map<String, dynamic>>[];
    final damagedItems = <Map<String, dynamic>>[];
    for (final line in lines) {
      final itemId = '${line.item['_id']}';
      final receivedQty = int.tryParse(line.qty.text.trim()) ?? 0;
      final damagedQty = int.tryParse(line.damaged.text.trim()) ?? 0;
      if (receivedQty > 0) {
        receivedItems.add({
          'itemId': itemId,
          'quantity': receivedQty,
          'batchNumber': line.batch.text.trim(),
          'expiryDate': DateFormat('yyyy-MM-dd').format(line.expiry!),
        });
      }
      if (damagedQty > 0) {
        damagedItems.add({'itemId': itemId, 'quantity': damagedQty});
      }
    }
    if (receivedItems.isEmpty) return;

    await ref
        .read(pharmacyProcurementProvider.notifier)
        .receivePurchaseOrder('${po['_id']}', {
          'receivedItems': receivedItems,
          'damagedItems': damagedItems,
          if (invoice.text.trim().isNotEmpty)
            'supplierInvoiceNumber': invoice.text.trim(),
        });
    _toast('Stock received', PharmacyColors.success);
  }

  @override
  Widget build(BuildContext context) {
    final procState = ref.watch(pharmacyProcurementProvider);
    _suppliers = procState.suppliers;
    _orders = procState.orders;
    _grns = procState.grns;
    _medicines = procState.medicines;
    final isLoading = procState.isLoading && procState.isEmpty;

    return Scaffold(
      backgroundColor: PharmacyColors.bg,
      appBar: AppBar(
        backgroundColor: PharmacyColors.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: PharmacyColors.textPrimary),
        title: Text(
          'Procurement',
          style: PharmacyType.sans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: PharmacyColors.textStrong,
          ),
        ),
      ),
      floatingActionButton: _tab == 2
          ? null
          : PharmacyFab(
              label: _tab == 1 ? 'Add supplier' : 'New order',
              icon: LucideIcons.plus,
              onPressed: () => _tab == 1 ? _addSupplier() : _createPo(),
            ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: PharmacyColors.green,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              PharmacyEntrance(child: _summary()),
              const SizedBox(height: 18),
              PharmacyEntrance(index: 1, child: _segmented()),
              const SizedBox(height: 20),
              if (isLoading)
                const PharmacyListSkeleton(count: 4)
              else if (procState.error != null && procState.isEmpty)
                PharmacyErrorBanner(message: procState.error!, onRetry: _load)
              else
                AnimatedSwitcher(
                  duration: PharmacyMotion.medium,
                  switchInCurve: PharmacyMotion.enter,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.02),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(_tab),
                    child: switch (_tab) {
                      0 => _ordersView(),
                      1 => _suppliersView(),
                      _ => _receiptsView(),
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────── Summary ─────────────────────────────

  static const _open = {'draft', 'pending', 'approved'};
  static const _transit = {'ordered', 'partially_received'};

  static num _n(dynamic v) => num.tryParse('${v ?? 0}') ?? 0;
  static String _status(Map<String, dynamic> po) =>
      '${po['status'] ?? 'draft'}';

  /// What the store still owes its suppliers across live orders.
  num get _toPay => _orders
      .where((po) => !{'cancelled', 'returned'}.contains(_status(po)))
      .fold<num>(
        0,
        (sum, po) =>
            sum + (_n(po['totalAmount']) - _n(po['paidAmount'])).clamp(0, 1e12),
      );

  Widget _summary() {
    final live = _orders
        .where(
          (po) => _open.contains(_status(po)) || _transit.contains(_status(po)),
        )
        .length;
    Widget cell(String label, String value, {Color? tone}) => Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: PharmacyColors.panel,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: PharmacyType.number(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: tone ?? PharmacyColors.textStrong,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: _caption, maxLines: 1),
          ],
        ),
      ),
    );
    return Row(
      children: [
        cell('Open orders', '$live'),
        const SizedBox(width: 8),
        cell(
          'To pay',
          pharmacyRupees(_toPay),
          tone: _toPay > 0 ? PharmacyColors.warning : null,
        ),
        const SizedBox(width: 8),
        cell('Suppliers', '${_suppliers.length}'),
      ],
    );
  }

  /// Orders / Suppliers / Receipts — the white thumb slides between them.
  Widget _segmented() {
    const labels = ['Orders', 'Suppliers', 'Receipts'];
    return Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: PharmacyColors.panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: PharmacyMotion.medium,
            curve: PharmacyMotion.enter,
            alignment: Alignment(-1 + _tab * 1.0, 0),
            child: FractionallySizedBox(
              widthFactor: 1 / 3,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: PharmacyColors.bg,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: PharmacyColors.shadowElevated,
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _tab = i),
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: PharmacyMotion.medium,
                        style: PharmacyType.sans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: _tab == i
                              ? PharmacyColors.textStrong
                              : PharmacyColors.textSecondary,
                        ),
                        child: Text(labels[i]),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ──────────────────────────── Orders ─────────────────────────────

  Widget _ordersView() {
    if (_orders.isEmpty) {
      return PharmacyEmptyStateInline(
        icon: LucideIcons.clipboardList,
        text: 'No purchase orders yet.\nRaise one to restock from a supplier.',
        action: SizedBox(
          width: 170,
          child: PharmacyButton(
            label: 'New order',
            icon: LucideIcons.plus,
            onPressed: _createPo,
          ),
        ),
      );
    }
    final groups = <(String, List<Map<String, dynamic>>)>[
      (
        'Needs approval',
        _orders.where((po) => _open.contains(_status(po))).toList(),
      ),
      (
        'On the way',
        _orders.where((po) => _transit.contains(_status(po))).toList(),
      ),
      (
        'Completed',
        _orders
            .where(
              (po) =>
                  !_open.contains(_status(po)) &&
                  !_transit.contains(_status(po)),
            )
            .toList(),
      ),
    ].where((g) => g.$2.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, (title, list)) in groups.indexed) ...[
          if (i > 0) const SizedBox(height: 22),
          PharmacySectionTitle('$title (${list.length})'),
          PharmacyGroup(
            children: [
              for (var j = 0; j < list.length; j++) ...[
                if (j > 0) const PharmacyHairline(),
                _poRow(list[j]),
              ],
            ],
          ),
        ],
      ],
    );
  }

  static Color _statusTone(String status) => switch (status) {
    'cancelled' || 'returned' => PharmacyColors.error,
    'received' => PharmacyColors.textSecondary,
    'draft' || 'pending' => PharmacyColors.warning,
    _ => PharmacyColors.greenDark,
  };

  String _supplierName(Map<String, dynamic> po) {
    final s = po['supplierId'];
    if (s is Map) return '${s['name'] ?? s['companyName'] ?? 'Supplier'}';
    for (final sup in _suppliers) {
      if ('${sup['_id']}' == '$s') return '${sup['name'] ?? 'Supplier'}';
    }
    return 'Supplier';
  }

  Widget _poRow(Map<String, dynamic> po) {
    final status = _status(po);
    final total = _n(po['totalAmount'] ?? po['total_amount']);
    final paid = _n(po['paidAmount'] ?? po['paid_amount']);
    final items = (po['items'] as List? ?? const []).length;
    final settled =
        '${po['paymentStatus']}' == 'paid' || (total > 0 && paid >= total);

    return PharmacyPressable(
      scale: 0.99,
      onTap: () => _openPo(po),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _supplierName(po),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _body.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        pharmacyRupees(total),
                        style: PharmacyType.number(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: PharmacyColors.textStrong,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        orderStatusLabel(status),
                        style: _caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: _statusTone(status),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '  ·  ${po['orderNumber'] ?? po['order_number'] ?? 'PO'}'
                          '${items > 0 ? '  ·  $items ${items == 1 ? 'item' : 'items'}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _caption,
                        ),
                      ),
                      Text(
                        settled
                            ? 'Paid'
                            : paid > 0
                            ? '${pharmacyRupees(paid)} paid'
                            : 'Unpaid',
                        style: _caption.copyWith(
                          color: settled
                              ? PharmacyColors.textSecondary
                              : PharmacyColors.warning,
                        ),
                      ),
                    ],
                  ),
                  if (!settled &&
                      paid > 0 &&
                      total > 0 &&
                      status != 'cancelled') ...[
                    const SizedBox(height: 8),
                    _thinBar(paid / total),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              LucideIcons.chevronRight,
              size: 17,
              color: PharmacyColors.textDisabled,
            ),
          ],
        ),
      ),
    );
  }

  Widget _thinBar(num fraction) {
    final f = fraction.clamp(0, 1).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Container(
        height: 4,
        color: PharmacyColors.bg,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: PharmacyMotion.reduced(context) ? f : 0, end: f),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (_, v, _) => Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: v,
              child: Container(color: PharmacyColors.green),
            ),
          ),
        ),
      ),
    );
  }

  /// One purchase order in full, with its next step as a real button —
  /// the actions used to hide behind a ⋮ menu on each card.
  Future<void> _openPo(Map<String, dynamic> po) async {
    final status = _status(po);
    final total = _n(po['totalAmount'] ?? po['total_amount']);
    final paid = _n(po['paidAmount'] ?? po['paid_amount']);
    final items = (po['items'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final anyReceived = items.any((i) => _n(i['receivedQuantity']) > 0);
    final canCancel =
        !{'received', 'cancelled', 'returned'}.contains(status) && !anyReceived;
    final canPay =
        status != 'cancelled' &&
        '${po['paymentStatus']}' != 'paid' &&
        paid < total;
    final next = switch (status) {
      'draft' || 'pending' => ('approve', 'Approve order', LucideIcons.check),
      'approved' => ('order', 'Mark as ordered', LucideIcons.send),
      'ordered' || 'partially_received' => (
        'receive',
        'Receive stock',
        LucideIcons.packageCheck,
      ),
      _ => null,
    };

    final action = await showPharmacySheet<String>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _supplierName(po),
                      style: PharmacyType.sans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: PharmacyColors.textStrong,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${po['orderNumber'] ?? po['order_number'] ?? 'Purchase order'}',
                      style: _caption,
                    ),
                  ],
                ),
              ),
              Text(
                orderStatusLabel(status),
                style: _caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: _statusTone(status),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (items.isNotEmpty) ...[
                    PharmacyGroup(
                      children: [
                        for (var i = 0; i < items.length; i++) ...[
                          if (i > 0) const PharmacyHairline(),
                          _itemRow(items[i]),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  PharmacyGroup(
                    children: [
                      _kv('Order total', pharmacyRupees(total), strong: true),
                      const PharmacyHairline(),
                      _kv('Paid to supplier', pharmacyRupees(paid)),
                      const PharmacyHairline(),
                      _kv(
                        'Balance',
                        pharmacyRupees((total - paid).clamp(0, 1e12)),
                        tone: total - paid > 0 ? PharmacyColors.warning : null,
                      ),
                    ],
                  ),
                  if ('${po['notes'] ?? ''}'.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('${po['notes']}', style: _caption),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (next != null)
            PharmacyButton(
              label: next.$2,
              icon: next.$3,
              onPressed: () => Navigator.pop(ctx, next.$1),
            ),
          if (canPay || canCancel) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (canPay)
                  Expanded(
                    child: PharmacySecondaryButton(
                      label: 'Record payment',
                      onPressed: () => Navigator.pop(ctx, 'payment'),
                    ),
                  ),
                if (canPay && canCancel) const SizedBox(width: 8),
                if (canCancel)
                  Expanded(
                    child: PharmacySecondaryButton(
                      label: 'Cancel order',
                      color: PharmacyColors.error,
                      onPressed: () => Navigator.pop(ctx, 'cancel'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
    if (action != null && mounted) await _poAction(po, action);
  }

  Widget _itemRow(Map<String, dynamic> item) {
    final ordered = _n(item['quantity']).toInt();
    final received = _n(
      item['receivedQuantity'] ?? item['received_quantity'],
    ).toInt();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item['medicineName'] ?? item['medicine_name'] ?? 'Item'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _body,
                ),
                Text(
                  '$ordered × ${pharmacyRupees(item['purchasePrice'] ?? item['unit_cost'])}',
                  style: _caption,
                ),
              ],
            ),
          ),
          if (received > 0)
            Text(
              received >= ordered ? 'Received' : '$received of $ordered in',
              style: _caption.copyWith(
                color: received >= ordered
                    ? PharmacyColors.greenDark
                    : PharmacyColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  Widget _kv(String label, String value, {bool strong = false, Color? tone}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(child: Text(label, style: _body)),
            Text(
              value,
              style: PharmacyType.number(
                fontSize: 13,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
                color:
                    tone ??
                    (strong
                        ? PharmacyColors.textStrong
                        : PharmacyColors.textSecondary),
              ),
            ),
          ],
        ),
      );

  // ─────────────────────────── Suppliers ───────────────────────────

  Widget _suppliersView() {
    if (_suppliers.isEmpty) {
      return PharmacyEmptyStateInline(
        icon: LucideIcons.users,
        text: 'No suppliers yet.\nAdd the distributors you buy from.',
        action: SizedBox(
          width: 170,
          child: PharmacyButton(
            label: 'Add supplier',
            icon: LucideIcons.plus,
            onPressed: _addSupplier,
          ),
        ),
      );
    }
    return PharmacyGroup(
      children: [
        for (var i = 0; i < _suppliers.length; i++) ...[
          if (i > 0) const PharmacyHairline(),
          _supplierRow(_suppliers[i]),
        ],
      ],
    );
  }

  Widget _supplierRow(Map<String, dynamic> s) {
    final name = '${s['name'] ?? 'Supplier'}';
    final phone = '${s['phone'] ?? ''}'.trim();
    final detail = [
      '${s['companyName'] ?? ''}'.trim(),
      phone,
    ].where((e) => e.isNotEmpty).join('  ·  ');
    final gst = '${s['gstNumber'] ?? ''}'.trim();
    final openWith = _orders
        .where(
          (po) =>
              _supplierName(po) == name &&
              (_open.contains(_status(po)) || _transit.contains(_status(po))),
        )
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: PharmacyColors.bg,
              shape: BoxShape.circle,
            ),
            child: Text(
              name.isEmpty ? '?' : name[0].toUpperCase(),
              style: PharmacyType.sans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: PharmacyColors.textHeading,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _body.copyWith(fontWeight: FontWeight.w600),
                ),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _caption,
                  ),
                if (gst.isNotEmpty || openWith > 0)
                  Text(
                    [
                      if (gst.isNotEmpty) 'GST $gst',
                      if (openWith > 0)
                        '$openWith open ${openWith == 1 ? 'order' : 'orders'}',
                    ].join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _caption.copyWith(
                      fontSize: 11.5,
                      color: PharmacyColors.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
          if (phone.isNotEmpty)
            PharmacyPressable(
              semanticLabel: 'Call $name',
              onTap: () async {
                final ok = await launchUrl(
                  Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'\s'), '')),
                );
                if (!ok) _toast('No dialler available', PharmacyColors.error);
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: PharmacyColors.bg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.phone,
                  size: 16,
                  color: PharmacyColors.greenDark,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────── Receipts ────────────────────────────

  Widget _receiptsView() {
    if (_grns.isEmpty) {
      return const PharmacyEmptyStateInline(
        icon: LucideIcons.packageCheck,
        text:
            'No goods received yet.\nReceive stock against an order that is on the way.',
      );
    }
    return PharmacyGroup(
      children: [
        for (var i = 0; i < _grns.length; i++) ...[
          if (i > 0) const PharmacyHairline(),
          _grnRow(_grns[i]),
        ],
      ],
    );
  }

  Widget _grnRow(Map<String, dynamic> g) {
    final damaged = _n(g['damagedValue']);
    final po = g['purchaseOrderId'];
    final when = DateTime.tryParse(
      '${g['receivedDate'] ?? g['createdAt'] ?? ''}',
    )?.toLocal();
    final meta = [
      if (po is Map && po['orderNumber'] != null) '${po['orderNumber']}',
      if (when != null) DateFormat('d MMM yyyy').format(when),
    ].join('  ·  ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(
            LucideIcons.packageCheck,
            size: 18,
            color: PharmacyColors.textHeading,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${g['grnNumber'] ?? g['receiptNumber'] ?? 'Receipt'}',
                  style: _body.copyWith(fontWeight: FontWeight.w600),
                ),
                if (meta.isNotEmpty) Text(meta, style: _caption),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                pharmacyRupees(g['acceptedValue']),
                style: PharmacyType.number(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: PharmacyColors.textStrong,
                ),
              ),
              if (damaged > 0)
                Text(
                  '${pharmacyRupees(damaged)} damaged',
                  style: _caption.copyWith(color: PharmacyColors.error),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static final _body = PharmacyType.sans(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: PharmacyColors.textPrimary,
  );
  static final _caption = PharmacyType.sans(
    fontSize: 11.5,
    color: PharmacyColors.textSecondary,
  );
}

/// One PO line's inputs on the receive sheet.
class _GrnLine {
  final Map<String, dynamic> item;
  final TextEditingController qty;
  final TextEditingController damaged;
  final TextEditingController batch;
  DateTime? expiry;

  _GrnLine({
    required this.item,
    required this.qty,
    required this.damaged,
    required this.batch,
  });

  String get name =>
      '${item['medicineName'] ?? item['medicine_name'] ?? 'Item'}';
}

/// One line on the create-PO sheet.
class _PoLine {
  String medicineId;
  final qty = TextEditingController(text: '1');
  final cost = TextEditingController();
  final sell = TextEditingController();

  _PoLine(this.medicineId);

  void dispose() {
    qty.dispose();
    cost.dispose();
    sell.dispose();
  }
}
