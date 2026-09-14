import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/network/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/pharmacy_store_provider.dart';

class PharmacyOrders extends ConsumerStatefulWidget {
  const PharmacyOrders({super.key});

  @override
  ConsumerState<PharmacyOrders> createState() => _PharmacyOrdersState();
}

class _PharmacyOrdersState extends ConsumerState<PharmacyOrders> {
  final _api = ApiService();
  final _search = TextEditingController();
  List<Map<String, dynamic>> _orders = const [];
  bool _loading = true;
  String? _filter;
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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final storeId = ref.read(pharmacyStoreProvider).selectedStoreId;
    if (storeId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.getMerchantOrders(queryParams: {
        'limit': 100,
        if (_filter != null) 'status': _filter,
        if (_search.text.trim().isNotEmpty) 'q': _search.text.trim(),
      });
      final data = response.data;
      if (!mounted) return;
      setState(() {
        _orders = _maps(data is Map ? data['orders'] : data);
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
    if (store.selectedStoreId != null && store.selectedStoreId != _loadedStoreId && !_loading) {
      Future.microtask(_load);
    }
    const statuses = <String?>[null, 'prescription_review', 'placed', 'confirmed', 'packing', 'ready_to_ship', 'shipped', 'out_for_delivery', 'delivered', 'cancelled'];
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('E-Pharmacy Orders', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
              const SizedBox(height: 12),
              const PharmacyStoreSelector(compact: true),
              const SizedBox(height: 10),
              TextField(
                controller: _search,
                onSubmitted: (_) => _load(),
                decoration: InputDecoration(hintText: 'Search order number', prefixIcon: const Icon(Iconsax.search_normal, size: 18), suffixIcon: IconButton(onPressed: _load, icon: const Icon(Iconsax.refresh, size: 18))),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: statuses.map((s) => Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: ChoiceChip(
                    label: Text(s == null ? 'All' : _label(s)),
                    selected: _filter == s,
                    onSelected: (_) {
                      setState(() => _filter = s);
                      _load();
                    },
                  ),
                )).toList()),
              ),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: AppTheme.error)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _orders.isEmpty
                            ? ListView(children: const [SizedBox(height: 120), Center(child: Text('No online orders for this branch'))])
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                                itemCount: _orders.length,
                                itemBuilder: (_, i) => _orderCard(_orders[i]),
                              ),
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _orderCard(Map<String, dynamic> order) {
    final patient = _map(order['patientId']);
    final status = order['orderStatus']?.toString() ?? 'placed';
    final rx = order['prescriptionStatus']?.toString() ?? 'not_required';
    final id = order['_id']?.toString() ?? '';
    final next = _nextStatus(status);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(order['orderNumber']?.toString() ?? 'Online order', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w800)),
            Text(patient['name']?.toString() ?? 'Patient', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textSecondary)),
          ])),
          Text('₹${_money(order['totalAmount'])}', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800, color: AppTheme.success)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 7, runSpacing: 6, children: [
          _pill(_label(status), _statusColor(status)),
          _pill(order['paymentStatus']?.toString() ?? 'pending', order['paymentStatus'] == 'paid' ? AppTheme.success : AppTheme.warning),
          if (order['prescriptionRequired'] == true) _pill('Rx: ${_label(rx)}', rx == 'approved' ? AppTheme.success : rx == 'rejected' ? AppTheme.error : AppTheme.accent),
        ]),
        const SizedBox(height: 10),
        Text('${(order['items'] as List?)?.length ?? 0} line item(s) · ${order['paymentMethod'] ?? ''}', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textSecondary)),
        if (rx == 'pending_review') ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: id.isEmpty ? null : () => _reviewRx(id, false), child: const Text('Reject Rx'))),
            const SizedBox(width: 8),
            Expanded(child: ElevatedButton(onPressed: id.isEmpty ? null : () => _reviewRx(id, true), child: const Text('Approve Rx'))),
          ]),
        ] else if (status == 'placed') ...[
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: id.isEmpty ? null : () => _confirm(id), icon: const Icon(Iconsax.tick_circle, size: 17), label: const Text('Confirm & allocate stock'))),
        ] else if (next != null) ...[
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: id.isEmpty ? null : () => _advance(id, next), child: Text('Move to ${_label(next)}'))),
        ],
        const SizedBox(height: 6),
        Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => _showDetails(order), child: const Text('View details'))),
      ]),
    );
  }

  Future<void> _reviewRx(String id, bool approved) async {
    final notes = await _prompt(approved ? 'Approval notes (optional)' : 'Reason for rejection');
    if (!approved && (notes == null || notes.trim().isEmpty)) return;
    await _run(() => _api.reviewMerchantPrescription(id, approved: approved, reason: notes), approved ? 'Prescription approved' : 'Prescription rejected');
  }

  Future<void> _confirm(String id) async => _run(() => _api.confirmMerchantOrder(id), 'Order confirmed and stock allocated');
  Future<void> _advance(String id, String status) async => _run(() => _api.updateMerchantOrderStatus(id, status), 'Order moved to ${_label(status)}');

  Future<void> _run(Future<Response> Function() action, String success) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      await _load();
    } on DioException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_message(e)), backgroundColor: AppTheme.error));
    }
  }

  Future<String?> _prompt(String title) async {
    final c = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, minLines: 2, maxLines: 4),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Continue'))],
      ),
    );
    c.dispose();
    return result;
  }

  void _showDetails(Map<String, dynamic> order) {
    final items = _maps(order['items']);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(shrinkWrap: true, children: [
          Text(order['orderNumber']?.toString() ?? 'Order', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          ...items.map((item) => ListTile(contentPadding: EdgeInsets.zero, title: Text(item['medicineName']?.toString() ?? 'Medicine'), subtitle: Text('Qty ${item['quantity'] ?? 0}'), trailing: Text('₹${_money(item['totalAmount'])}'))),
          const Divider(),
          Text('Delivery: ${_address(_map(order['deliveryAddress']))}', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
          if (order['prescriptionReviewNotes'] != null) ...[const SizedBox(height: 8), Text('Rx notes: ${order['prescriptionReviewNotes']}')],
        ]),
      )),
    );
  }

  static String? _nextStatus(String status) {
    const map = {
      'confirmed': 'packing',
      'packing': 'ready_to_ship',
      'ready_to_ship': 'shipped',
      'shipped': 'out_for_delivery',
      'out_for_delivery': 'delivered',
    };
    return map[status];
  }

  static Widget _pill(String text, Color color) => Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(8)), child: Text(text, style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: color)));
  static Color _statusColor(String s) => s == 'delivered' ? AppTheme.success : s == 'cancelled' ? AppTheme.error : s == 'prescription_review' ? AppTheme.accent : AppTheme.primary;
  static String _label(String s) => s.split('_').map((x) => x.isEmpty ? x : '${x[0].toUpperCase()}${x.substring(1)}').join(' ');
  static String _money(dynamic value) => (num.tryParse(value?.toString() ?? '') ?? 0).toStringAsFixed(0);
  static Map<String, dynamic> _map(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  static List<Map<String, dynamic>> _maps(dynamic value) => value is List ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
  static String _address(Map<String, dynamic> a) => [a['line1'], a['line2'], a['city'], a['state'], a['pincode']].where((e) => e != null && e.toString().trim().isNotEmpty).join(', ');
  static String _message(DioException e) {
    final d = e.response?.data;
    if (d is Map) return d['message']?.toString() ?? d['error']?.toString() ?? 'Request failed';
    return e.message ?? 'Request failed';
  }
}
