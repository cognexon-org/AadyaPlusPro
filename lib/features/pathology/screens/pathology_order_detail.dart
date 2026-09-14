import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/network/api_service.dart';
import '../../../core/theme/app_theme.dart';

class PathologyOrderDetail extends StatefulWidget {
  final String orderId;
  const PathologyOrderDetail({super.key, required this.orderId});
  @override
  State<PathologyOrderDetail> createState() => _PathologyOrderDetailState();
}

class _PathologyOrderDetailState extends State<PathologyOrderDetail> {
  bool _loading = false;
  Map<String, dynamic> _order = {};
  List<Map<String, dynamic>> _staff = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await Future.wait([ApiService().getDiagnosticsMerchantOrder(widget.orderId), ApiService().getDiagnosticsStaff()]);
      final orderData = Map<String, dynamic>.from(r[0].data as Map);
      final staffData = Map<String, dynamic>.from(r[1].data as Map);
      if (!mounted) return;
      setState(() {
        _order = Map<String, dynamic>.from((orderData['order'] as Map?) ?? const {});
        _staff = (staffData['staff'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).where((e) => e['role'] == 'phlebotomist' && e['isActive'] != false).toList();
      });
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load order: $e'))); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _assign() async {
    if (_staff.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add an active phlebotomist first.'))); return; }
    String id = '${_staff.first['_id']}';
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(title: const Text('Assign phlebotomist'), content: DropdownButtonFormField<String>(value: id, items: _staff.map((s) => DropdownMenuItem(value: '${s['_id']}', child: Text('${s['name']}'))).toList(), onChanged: (v) => setS(() => id = v ?? id)), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Assign'))])));
    if (ok != true) return;
    await _perform(() => ApiService().assignDiagnosticsCollector(widget.orderId, id), 'Collector assigned');
  }

  Future<void> _collection(String status) async => _perform(() => ApiService().updateDiagnosticsCollectionStatus(widget.orderId, status), 'Collection updated');
  Future<void> _status(String status) async => _perform(() => ApiService().updateDiagnosticsOrderStatus(widget.orderId, status), 'Order status updated');

  Future<void> _payment() async {
    String method = 'cash';
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(title: const Text('Record offline payment'), content: DropdownButtonFormField<String>(value: method, items: const [DropdownMenuItem(value: 'cash', child: Text('Cash')), DropdownMenuItem(value: 'card', child: Text('Card')), DropdownMenuItem(value: 'upi', child: Text('UPI'))], onChanged: (v) => setS(() => method = v ?? method)), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mark paid'))])));
    if (ok != true) return;
    await _perform(() => ApiService().recordDiagnosticsOfflinePayment(widget.orderId, amount: num.tryParse('${_order['totalAmount']}') ?? 0, method: method), 'Payment recorded');
  }

  Future<void> _uploadReport() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf','jpg','jpeg','png']);
    final path = result?.files.single.path;
    if (path == null) return;
    await _perform(() => ApiService().uploadDiagnosticsReport(widget.orderId, path), 'Report uploaded and released');
  }

  Future<void> _perform(Future<dynamic> Function() op, String success) async {
    try { await op(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success))); await _load(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }

  @override
  Widget build(BuildContext context) {
    final patient = _order['patientId'] is Map ? _order['patientId'] as Map : const {};
    final tests = (_order['tests'] as List? ?? const []).map((e) => e is Map ? '${e['testName'] ?? ''}' : '').where((e) => e.isNotEmpty).toList();
    final home = _order['type'] == 'home_collection';
    final status = '${_order['status'] ?? 'requested'}';
    final collection = '${_order['collectionStatus'] ?? 'unassigned'}';
    final assigned = _order['assignedPhlebotomistId'] is Map ? _order['assignedPhlebotomistId'] as Map : const {};
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: Text('${_order['labTestNumber'] ?? 'Diagnostic Order'}')),
      body: _loading && _order.isEmpty ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
        _card('Patient', [
          Text('${patient['name'] ?? 'Patient'}', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800)),
          Text('${patient['phone'] ?? ''}', style: const TextStyle(color: AppTheme.textSecondary)),
        ]),
        _card('Tests', [Text(tests.isEmpty ? 'No test names' : tests.join(', ')), const SizedBox(height: 6), Text('Amount ₹${_order['totalAmount'] ?? 0} • Payment ${_label('${_order['paymentStatus'] ?? 'pending'}')}')]),
        _card('Workflow', [
          Text('Order: ${_label(status)}'),
          if (home) Text('Collection: ${_label(collection)}'),
          if (home) Text('Phlebotomist: ${assigned['name'] ?? 'Not assigned'}'),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (home && collection == 'unassigned') OutlinedButton(onPressed: _assign, child: const Text('Assign collector')),
            if (home && collection == 'assigned') OutlinedButton(onPressed: () => _collection('en_route'), child: const Text('En route')),
            if (home && collection == 'en_route') OutlinedButton(onPressed: () => _collection('arrived'), child: const Text('Arrived')),
            if (home && ['assigned','en_route','arrived'].contains(collection)) FilledButton(onPressed: () => _collection('collected'), child: const Text('Sample collected')),
            if (home && collection == 'collected') OutlinedButton(onPressed: () => _collection('delivered_to_lab'), child: const Text('Delivered to lab')),
            if (!home && ['requested','scheduled'].contains(status)) FilledButton(onPressed: () => _status('sample_collected'), child: const Text('Sample collected')),
            if (status == 'sample_collected') FilledButton(onPressed: () => _status('processing'), child: const Text('Start processing')),
            if (status == 'processing') FilledButton(onPressed: () => _status('ready_for_review'), child: const Text('Ready for review')),
          ]),
          if (status == 'ready_for_review') ...[
            const SizedBox(height: 8),
            Text('Completion is report-driven: upload the signed report to release it to the patient.', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _uploadReport, icon: const Icon(Icons.upload_file), label: const Text('Upload & release report'))),
          ],
        ]),
        if (_order['paymentStatus'] != 'paid' && status != 'cancelled') _card('Payment', [SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _payment, icon: const Icon(Icons.payments_outlined), label: const Text('Record cash/card/UPI payment')))]),
        if ((_order['statusHistory'] as List? ?? const []).isNotEmpty) _card('Audit timeline', (_order['statusHistory'] as List).reversed.take(12).map<Widget>((e) { final m = e is Map ? e : const {}; return ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(_label('${m['status'] ?? ''}')), subtitle: Text('${m['note'] ?? ''}')); }).toList()),
      ])),
    );
  }

  Widget _card(String title, List<Widget> children) => Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800)), const SizedBox(height: 8), ...children]));
  String _label(String v) => v.split('_').map((e) => e.isEmpty ? e : '${e[0].toUpperCase()}${e.substring(1)}').join(' ');
}
