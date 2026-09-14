import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/network/api_service.dart';
import '../../../core/theme/app_theme.dart';
import 'pathology_order_detail.dart';

class PathologyOrders extends StatefulWidget {
  const PathologyOrders({super.key});
  @override
  State<PathologyOrders> createState() => _PathologyOrdersState();
}

class _PathologyOrdersState extends State<PathologyOrders> {
  bool _loading = false;
  String _status = 'all';
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final query = <String, dynamic>{'limit': 100};
      if (_status != 'all') query['status'] = _status;
      final r = await ApiService().getDiagnosticsMerchantOrders(queryParams: query);
      final d = Map<String, dynamic>.from(r.data as Map);
      if (mounted) setState(() => _orders = (d['orders'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load diagnostic orders: $e'))); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.surface,
    body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 8), child: Text('Diagnostic Orders', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w800))),
      SizedBox(height: 42, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: ['all','requested','scheduled','sample_collected','processing','ready_for_review','completed','cancelled'].map((s) => Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(_label(s)), selected: _status == s, onSelected: (_) { setState(() => _status = s); _load(); }))).toList())),
      if (_loading) const LinearProgressIndicator(),
      Expanded(child: RefreshIndicator(onRefresh: _load, child: _orders.isEmpty ? ListView(children: const [SizedBox(height: 80), Center(child: Text('No diagnostic orders found.'))]) : ListView.builder(padding: const EdgeInsets.all(16), itemCount: _orders.length, itemBuilder: (_, i) => _card(_orders[i])))),
    ])),
  );

  Widget _card(Map<String, dynamic> o) {
    final patient = o['patientId'] is Map ? o['patientId'] as Map : const {};
    final tests = (o['tests'] as List? ?? const []).map((e) => e is Map ? '${e['testName'] ?? ''}' : '').where((e) => e.isNotEmpty).join(', ');
    final home = o['type'] == 'home_collection';
    return Card(child: ListTile(
      contentPadding: const EdgeInsets.all(14),
      leading: CircleAvatar(backgroundColor: AppTheme.pathologyAccent.withValues(alpha: .12), child: const Icon(Icons.science_outlined, color: AppTheme.pathologyAccent)),
      title: Text('${patient['name'] ?? 'Patient'}', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
      subtitle: Text('${tests.isEmpty ? 'Lab tests' : tests}\n${home ? 'Home collection • ${_label('${o['collectionStatus'] ?? 'unassigned'}')}' : 'Lab visit'} • ${_label('${o['status'] ?? 'requested'}')}'),
      isThreeLine: true,
      trailing: Text('₹${o['totalAmount'] ?? 0}', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
      onTap: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => PathologyOrderDetail(orderId: '${o['_id']}'))); await _load(); },
    ));
  }
  String _label(String v) => v == 'all' ? 'All' : v.split('_').map((e) => e.isEmpty ? e : '${e[0].toUpperCase()}${e.substring(1)}').join(' ');
}
