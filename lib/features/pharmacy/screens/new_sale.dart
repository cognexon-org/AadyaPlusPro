import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/pharmacy_type.dart';
import '../theme/pharmacy_colors.dart';
import '../../../core/network/api_service.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../widgets/collect_payment_sheet.dart';
import '../widgets/pharmacy_ui.dart';

const _paymentMethods = ['cash', 'card', 'upi', 'other'];

class NewSaleScreen extends ConsumerStatefulWidget {
  const NewSaleScreen({super.key});

  @override
  ConsumerState<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends ConsumerState<NewSaleScreen> {
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _searchController = TextEditingController();
  final _prescriptionIdController = TextEditingController();

  final List<dynamic> _cart = [];
  bool _isLoading = false;
  bool _searchExpanded = true;
  String _paymentMethod = 'cash';

  @override
  void initState() {
    super.initState();
    // Don't assume another screen already loaded this — fetch fresh so the
    // list is never silently empty.
    Future.microtask(
      () => ref.read(pharmacyDashboardProvider.notifier).loadMedicines(),
    );
  }

  bool get _cartNeedsPrescription =>
      _cart.any((m) => m['prescriptionRequired'] == true);

  void _addToCart(dynamic medicine) {
    setState(() {
      final existingIndex = _cart.indexWhere(
        (m) => m['_id'] == medicine['_id'],
      );
      if (existingIndex >= 0) {
        if (_cart[existingIndex]['qty'] < medicine['quantity']) {
          _cart[existingIndex]['qty'] += 1;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot add more than available stock'),
              backgroundColor: PharmacyColors.error,
            ),
          );
        }
      } else {
        if (medicine['quantity'] > 0) {
          _cart.add({...medicine, 'qty': 1});
        }
      }
    });
  }

  void _updateCartQty(int index, int change) {
    setState(() {
      final medicine = _cart[index];
      final newQty = medicine['qty'] + change;
      if (newQty <= 0) {
        _cart.removeAt(index);
      } else if (newQty > medicine['quantity']) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Not enough stock available'),
            backgroundColor: PharmacyColors.error,
          ),
        );
      } else {
        _cart[index]['qty'] = newQty;
      }
    });
  }

  double _getCartTotal() {
    double total = 0;
    for (var item in _cart) {
      final price = (item['sellingPrice'] ?? item['price'] ?? 0) as num;
      total += price.toDouble() * item['qty'];
    }
    return total;
  }

  Widget _customerRow() {
    final name = _customerNameController.text.trim();
    final phone = _customerPhoneController.text.trim();
    final named = name.isNotEmpty;

    return Material(
      color: PharmacyColors.bg,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: _addCustomer,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 11, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: PharmacyColors.borderStrong),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: PharmacyColors.greenLight,
                  shape: BoxShape.circle,
                ),
                child: named
                    ? Text(
                        name[0].toUpperCase(),
                        style: PharmacyType.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: PharmacyColors.greenDark,
                        ),
                      )
                    : const Icon(
                        LucideIcons.userRound,
                        size: 17,
                        color: PharmacyColors.greenDark,
                      ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      named ? name : 'Walk-in customer',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PharmacyType.sans(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: PharmacyColors.textStrong,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      phone.isNotEmpty
                          ? phone
                          : 'Tap to choose or add a customer',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PharmacyType.sans(
                        fontSize: 11,
                        color: PharmacyColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (named)
                IconButton(
                  tooltip: 'Clear customer',
                  icon: const Icon(
                    LucideIcons.x,
                    size: 15,
                    color: PharmacyColors.textSecondary,
                  ),
                  onPressed: () => setState(() {
                    _customerNameController.clear();
                    _customerPhoneController.clear();
                  }),
                )
              else
                const Icon(
                  LucideIcons.chevronRight,
                  size: 15,
                  color: PharmacyColors.textDisabled,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Choosing who the bill is for: an existing customer, or a new one.
  ///
  /// "Existing" is derived from this branch's past sales — there is no
  /// customer record to look up — so a name typed at the counter last week is
  /// offered back rather than retyped.
  Future<void> _addCustomer() async {
    final chosen = await showPharmacySheet<Map<String, String>>(
      context,
      builder: (ctx) => _CustomerPickerSheet(
        initialName: _customerNameController.text,
        initialPhone: _customerPhoneController.text,
      ),
    );
    if (chosen == null) return;
    setState(() {
      _customerNameController.text = chosen['name'] ?? '';
      _customerPhoneController.text = chosen['phone'] ?? '';
    });
  }

  Future<void> _submitSale() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cart is empty'),
          backgroundColor: PharmacyColors.warning,
        ),
      );
      return;
    }

    final prescriptionId = _prescriptionIdController.text.trim();
    if (_cartNeedsPrescription && prescriptionId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This cart has a prescription-required medicine — enter the prescription ID first',
          ),
          backgroundColor: PharmacyColors.warning,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final items = _cart
          .map(
            (m) => {
              'medicineId': m['_id'],
              'medicineName': m['medicineName'] ?? m['name'],
              'quantity': m['qty'],
              'sellingPrice': m['sellingPrice'] ?? m['price'] ?? 0,
              'taxRate': 0,
            },
          )
          .toList();

      final payload = {
        'customerType': 'walkin',
        'customerName': _customerNameController.text.trim().isEmpty
            ? 'Walk-in Customer'
            : _customerNameController.text.trim(),
        'customerPhone': _customerPhoneController.text.trim(),
        'items': items,
        'paymentMethod': _paymentMethod,
        // createSale defaults paidAmount to the bill total, which would mark a
        // UPI sale paid before the customer has scanned anything — and the QR
        // request would then be refused as "already paid". Booking it as
        // outstanding lets the QR collect it and settle the bill for real.
        if (_paymentMethod == 'upi') 'paidAmount': 0,
        'notes': 'App POS',
        if (prescriptionId.isNotEmpty) 'prescriptionId': prescriptionId,
      };

      final createResponse = await ApiService().createPharmacySale(payload);
      final saleId = createResponse.data?['sale']?['_id'];

      // createPharmacySale only reserves a 'draft' sale — dispense is what
      // actually deducts stock (FEFO) and marks it 'dispensed' so it counts
      // as real revenue. Without this call, every sale from this screen
      // stayed a draft forever: invisible in reports/dashboard, stock never
      // moved.
      if (saleId != null) {
        await ApiService().dispensePharmacySale(saleId);
      }

      ref.read(pharmacyDashboardProvider.notifier).loadSales();
      ref.read(pharmacyDashboardProvider.notifier).loadMedicines();

      if (!mounted) return;

      // Billing by UPI means the money still has to be taken. Show the QR
      // straight away rather than leaving the cashier to find the bill again
      // and collect from there.
      // Walk-in UPI collection is commented out with the rest of the POS
      // side. Counter-QR collection against an *online order* is a merchant
      // flow and stays live in order_details_screen.
      const collected = true;
      // if (_paymentMethod == 'upi' && saleId != null) {
      //   collected = await showCollectPaymentSheet(
      //     context,
      //     saleId: '$saleId',
      //     amount: _getCartTotal(),
      //     reference: 'Counter sale',
      //   );
      // }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              collected
                  ? 'Sale completed successfully!'
                  : 'Sale saved with payment still due — collect it from the bill.',
            ),
            backgroundColor: collected
                ? PharmacyColors.success
                : PharmacyColors.warning,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
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
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _prescriptionIdController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashData = ref.watch(pharmacyDashboardProvider);
    final medicines = dashData.medicines;

    final searchQuery = _searchController.text.toLowerCase();
    final filteredMedicines = medicines.where((m) {
      final name = (m['medicineName'] ?? m['name'] ?? '')
          .toString()
          .toLowerCase();
      return name.contains(searchQuery);
    }).toList();

    return Scaffold(
      backgroundColor: PharmacyColors.bg,
      appBar: AppBar(
        backgroundColor: PharmacyColors.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: PharmacyColors.textPrimary),
        title: Text(
          'New Sale',
          style: PharmacyType.sans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: PharmacyColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  _customerRow(),
                  const SizedBox(height: 8),
                  PharmacySearchField(
                    controller: _searchController,
                    hint: 'Search medicine by name or barcode',
                    onSubmitted: () => setState(() {}),
                  ),
                  if (_cart.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Cart (${_cart.length})',
                      style: PharmacyType.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: PharmacyColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(_cart.length, (i) {
                      final cItem = _cart[i];
                      final name = cItem['medicineName'] ?? cItem['name'];
                      final price =
                          cItem['sellingPrice'] ?? cItem['price'] ?? 0;
                      return PharmacyCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          name,
                                          overflow: TextOverflow.ellipsis,
                                          style: PharmacyType.sans(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: PharmacyColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                      if (cItem['prescriptionRequired'] ==
                                          true) ...[
                                        const SizedBox(width: 6),
                                        const PharmacyStatusPill(
                                          text: 'Rx',
                                          color: PharmacyColors.warning,
                                          background: PharmacyColors.warningBg,
                                        ),
                                      ],
                                    ],
                                  ),
                                  Text(
                                    '₹$price',
                                    style: PharmacyType.sans(
                                      fontSize: 12,
                                      color: PharmacyColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => _updateCartQty(i, -1),
                              icon: const Icon(CupertinoIcons.minus, size: 15),
                              color: PharmacyColors.textSecondary,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                            ),
                            SizedBox(
                              width: 22,
                              child: Text(
                                '${cItem['qty']}',
                                textAlign: TextAlign.center,
                                style: PharmacyType.sans(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: PharmacyColors.textPrimary,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => _updateCartQty(i, 1),
                              icon: const Icon(CupertinoIcons.plus, size: 15),
                              color: PharmacyColors.green,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 56,
                              child: Text(
                                '₹${price * cItem['qty']}',
                                textAlign: TextAlign.right,
                                style: PharmacyType.sans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: PharmacyColors.textPrimary,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  setState(() => _cart.removeAt(i)),
                              icon: const Icon(
                                CupertinoIcons.xmark_circle_fill,
                                size: 16,
                              ),
                              color: PharmacyColors.textTertiary,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () =>
                        setState(() => _searchExpanded = !_searchExpanded),
                    child: Row(
                      children: [
                        Icon(
                          _searchExpanded
                              ? CupertinoIcons.chevron_up
                              : CupertinoIcons.add,
                          size: 14,
                          color: PharmacyColors.green,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Add More Items',
                          style: PharmacyType.sans(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: PharmacyColors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_searchExpanded) ...[
                    const SizedBox(height: 8),
                    if (filteredMedicines.isEmpty)
                      const PharmacyEmptyStateInline(
                        icon: Icons.medication_outlined,
                        text: 'No medicines match your search',
                      )
                    else
                      ...filteredMedicines.take(20).map((m) {
                        final name =
                            m['medicineName'] ?? m['name'] ?? 'Medicine';
                        final price = m['sellingPrice'] ?? m['price'] ?? 0;
                        final stock = m['quantity'] ?? 0;
                        return PharmacyCard(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: PharmacyType.sans(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: PharmacyColors.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      '$stock in stock · ₹$price',
                                      style: PharmacyType.sans(
                                        fontSize: 11.5,
                                        color: stock > 0
                                            ? PharmacyColors.textSecondary
                                            : PharmacyColors.error,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: stock > 0
                                    ? () => _addToCart(m)
                                    : null,
                                icon: Icon(
                                  CupertinoIcons.add_circled_solid,
                                  color: stock > 0
                                      ? PharmacyColors.green
                                      : PharmacyColors.textDisabled,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                  if (_cartNeedsPrescription) ...[
                    const SizedBox(height: 8),
                    PharmacyTextField(
                      label: 'Prescription ID',
                      controller: _prescriptionIdController,
                      icon: CupertinoIcons.doc_text,
                      required: true,
                      margin: EdgeInsets.zero,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Payment Method',
                    style: PharmacyType.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: PharmacyColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: _paymentMethods
                        .map(
                          (m) => Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _paymentChip(m),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: PharmacyColors.card,
                border: Border(top: BorderSide(color: PharmacyColors.border)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Amount',
                        style: PharmacyType.sans(
                          fontSize: 13.5,
                          color: PharmacyColors.textSecondary,
                        ),
                      ),
                      Text(
                        '₹${_getCartTotal().toStringAsFixed(2)}',
                        style: PharmacyType.sans(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: PharmacyColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  PharmacyButton(
                    label: 'Complete Sale',
                    loading: _isLoading,
                    onPressed: _submitSale,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentChip(String method) => PharmacyFilterChip(
    label: method[0].toUpperCase() + method.substring(1),
    selected: _paymentMethod == method,
    onTap: () => setState(() => _paymentMethod = method),
    block: true,
  );
}

/// Two tabs: customers this branch has billed before, and a form for a new
/// one. Lives in the New Sale flow only, so it is private to this file.
class _CustomerPickerSheet extends StatefulWidget {
  final String initialName;
  final String initialPhone;

  const _CustomerPickerSheet({
    required this.initialName,
    required this.initialPhone,
  });

  @override
  State<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<_CustomerPickerSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.initialPhone,
  );
  final TextEditingController _search = TextEditingController();

  List<Map<String, dynamic>> _customers = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _name.dispose();
    _phone.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService().getPharmacySaleCustomers(
        search: _search.text,
      );
      final data = res.data;
      if (!mounted) return;
      setState(() {
        _customers = data is Map && data['customers'] is List
            ? (data['customers'] as List)
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
            : const [];
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      final d = e.response?.data;
      setState(() {
        _loading = false;
        _error = d is Map
            ? (d['message'] ?? d['error'])?.toString() ??
                  "Couldn't load customers"
            : "Couldn't load customers";
      });
    }
  }

  void _pick(String name, String phone) =>
      Navigator.pop(context, {'name': name, 'phone': phone});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Customer',
          style: PharmacyType.sans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: PharmacyColors.textStrong,
          ),
        ),
        const SizedBox(height: 12),
        TabBar(
          controller: _tabs,
          labelColor: PharmacyColors.green,
          unselectedLabelColor: PharmacyColors.textSecondary,
          indicatorColor: PharmacyColors.green,
          indicatorSize: TabBarIndicatorSize.tab,
          labelStyle: PharmacyType.sans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: PharmacyType.sans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          tabs: const [
            Tab(text: 'Existing'),
            Tab(text: 'New customer'),
          ],
        ),
        const SizedBox(height: 12),
        // A fixed height because the sheet sizes to its content: an
        // unbounded TabBarView inside a min-size Column cannot lay out.
        SizedBox(
          height: 300,
          child: TabBarView(
            controller: _tabs,
            children: [_existingTab(), _newTab()],
          ),
        ),
      ],
    );
  }

  Widget _existingTab() {
    return Column(
      children: [
        PharmacySearchField(
          controller: _search,
          hint: 'Search by name or phone',
          onSubmitted: _load,
          onRefresh: _load,
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _loading
              ? const PharmacyListSkeleton(count: 3)
              : _error != null
              ? PharmacyErrorBanner(message: _error!, onRetry: _load)
              : _customers.isEmpty
              ? const PharmacyEmptyStateInline(
                  icon: LucideIcons.userRound,
                  text: 'No customers billed at this branch yet',
                )
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: _customers.length,
                  separatorBuilder: (_, _) =>
                      Container(height: 1, color: PharmacyColors.border),
                  itemBuilder: (_, i) => _customerTile(_customers[i]),
                ),
        ),
      ],
    );
  }

  Widget _customerTile(Map<String, dynamic> c) {
    final name = '${c['name'] ?? ''}'.trim();
    final phone = '${c['phone'] ?? ''}'.trim();
    final display = name.isEmpty ? phone : name;
    final visits = num.tryParse('${c['visits'] ?? 0}')?.toInt() ?? 0;

    return Material(
      color: PharmacyColors.bg,
      child: InkWell(
        onTap: () => _pick(name, phone),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: PharmacyColors.greenLight,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  display.isEmpty ? '?' : display[0].toUpperCase(),
                  style: PharmacyType.sans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: PharmacyColors.greenDark,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      display.isEmpty ? 'Customer' : display,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PharmacyType.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: PharmacyColors.textStrong,
                      ),
                    ),
                    if (phone.isNotEmpty && name.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        phone,
                        style: PharmacyType.number(
                          fontSize: 11,
                          color: PharmacyColors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                visits == 1 ? '1 bill' : '$visits bills',
                style: PharmacyType.sans(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: PharmacyColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _newTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PharmacyTextField(
            label: 'Name',
            controller: _name,
            icon: LucideIcons.userRound,
            dense: true,
          ),
          PharmacyTextField(
            label: 'Phone',
            controller: _phone,
            icon: LucideIcons.phone,
            isNum: true,
            dense: true,
            margin: EdgeInsets.zero,
          ),
          const SizedBox(height: 14),
          PharmacyButton(
            label: 'Use this customer',
            onPressed: () => _pick(_name.text.trim(), _phone.text.trim()),
          ),
          const SizedBox(height: 8),
          Text(
            'The customer is saved with the bill — there is no separate '
            'customer record, so they appear under Existing after their '
            'first purchase.',
            style: PharmacyType.sans(
              fontSize: 11,
              height: 1.45,
              color: PharmacyColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
