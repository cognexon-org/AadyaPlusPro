import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/network/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/pharmacy_store_provider.dart';

class PrescriptionQueue extends ConsumerStatefulWidget {
  const PrescriptionQueue({super.key});
  @override
  ConsumerState<PrescriptionQueue> createState() => _PrescriptionQueueState();
}

class _PrescriptionQueueState extends ConsumerState<PrescriptionQueue> {
  bool _loading = false;
  List<Map<String, dynamic>> _orders = [];
  String? _loadedStoreId;

  @override
  void initState() { super.initState(); Future.microtask(_load); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await ref.read(pharmacyStoreProvider.notifier).initialize();
      final r = await ApiService().getMerchantOrders(queryParams: {'prescriptionStatus': 'pending_review', 'limit': 100});
      final data = Map<String, dynamic>.from(r.data as Map);
      final rows = (data['orders'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (mounted) setState(() {
        _loadedStoreId = ref.read(pharmacyStoreProvider).selectedStoreId;
        _orders = rows.where((o) {
        final rx = '${o['prescriptionStatus'] ?? o['rxStatus'] ?? ''}'.toLowerCase();
        return rx.contains('pending') || rx.contains('review') || o['prescriptionRequired'] == true;
      }).toList();
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load prescription queue: $e')));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _review(String id, bool approved) async {
    String? note;
    if (!approved) {
      note = await showDialog<String>(context: context, builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(title: const Text('Reject prescription'), content: TextField(controller: c, decoration: const InputDecoration(labelText: 'Reason'), maxLines: 3), actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Reject')),
        ]);
      });
      if (note == null) return;
    }
    try {
      await ApiService().reviewMerchantPrescription(id, approved: approved, reason: note);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(approved ? 'Prescription approved' : 'Prescription rejected')));
      await _load();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(pharmacyStoreProvider);
    if (store.selectedStoreId != null && store.selectedStoreId != _loadedStoreId && !_loading) Future.microtask(_load);
    return Scaffold(
    backgroundColor: AppTheme.surface,
    appBar: AppBar(title: const Text('Prescription Queue')),
    body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
      const PharmacyStoreSelector(),
      const SizedBox(height: 14),
      if (_loading && _orders.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator())),
      if (!_loading && _orders.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('No prescriptions awaiting review.'))),
      ..._orders.map((o) {
        final id = '${o['_id'] ?? ''}';
        final items = (o['items'] as List? ?? const []);
        final number = o['orderNumber'] ?? o['order_number'] ?? id;
        return Card(
          child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Order $number', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('${items.length} item(s) • ₹${o['totalAmount'] ?? 0}', style: GoogleFonts.plusJakartaSans(color: AppTheme.textSecondary)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: id.isEmpty ? null : () => _review(id, false), child: const Text('Reject'))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(onPressed: id.isEmpty ? null : () => _review(id, true), child: const Text('Approve'))),
            ]),
          ])),
        );
      }),
    ])),
  );
  }
}
