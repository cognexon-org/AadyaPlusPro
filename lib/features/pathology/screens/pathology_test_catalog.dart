import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/network/api_service.dart';
import '../../../core/theme/app_theme.dart';

class PathologyTestCatalog extends StatefulWidget {
  const PathologyTestCatalog({super.key});
  @override
  State<PathologyTestCatalog> createState() => _PathologyTestCatalogState();
}

class _PathologyTestCatalogState extends State<PathologyTestCatalog> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = false;
  List<Map<String, dynamic>> _tests = [], _packages = [];
  @override
  void initState() { super.initState(); _tabs = TabController(length: 2, vsync: this); _load(); }
  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try { final r = await ApiService().getDiagnosticsCatalog(); final d = Map<String, dynamic>.from(r.data as Map); if (mounted) setState(() { _tests = (d['tests'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList(); _packages = (d['packages'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList(); }); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Catalog load failed: $e'))); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _addTest() async {
    final code = TextEditingController(), name = TextEditingController(), price = TextEditingController(), sample = TextEditingController(), tat = TextEditingController(); bool fasting = false, home = true;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(title: const Text('Add Test'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: code, decoration: const InputDecoration(labelText: 'Test code *')),
      TextField(controller: name, decoration: const InputDecoration(labelText: 'Test name *')),
      TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price *')),
      TextField(controller: sample, decoration: const InputDecoration(labelText: 'Sample type')),
      TextField(controller: tat, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Report TAT (hours)')),
      CheckboxListTile(value: fasting, onChanged: (v) => setS(() => fasting = v ?? false), title: const Text('Fasting required'), contentPadding: EdgeInsets.zero),
      CheckboxListTile(value: home, onChanged: (v) => setS(() => home = v ?? true), title: const Text('Home collection eligible'), contentPadding: EdgeInsets.zero),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create'))])));
    if (ok != true || code.text.trim().isEmpty || name.text.trim().isEmpty) return;
    try { await ApiService().createDiagnosticsCatalogTest({'testCode': code.text.trim(), 'testName': name.text.trim(), 'price': double.tryParse(price.text) ?? 0, 'sampleType': sample.text.trim(), 'reportTime': int.tryParse(tat.text) ?? 0, 'fastingRequired': fasting, 'homeCollectionEligible': home}); await _load(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }

  Future<void> _addPackage() async {
    final active = _tests.where((t) => t['isActive'] != false && '${t['testCode'] ?? ''}'.isNotEmpty).toList();
    if (active.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Create a test first.'))); return; }
    final code = TextEditingController(), name = TextEditingController(), price = TextEditingController(); final selected = <String>{'${active.first['testCode']}'};
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(title: const Text('Add Package'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: code, decoration: const InputDecoration(labelText: 'Package code *')),
      TextField(controller: name, decoration: const InputDecoration(labelText: 'Package name *')),
      TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price *')),
      const SizedBox(height: 8), const Align(alignment: Alignment.centerLeft, child: Text('Tests')),
      ...active.map((t) { final c = '${t['testCode']}'; return CheckboxListTile(value: selected.contains(c), onChanged: (v) => setS(() { if (v == true) selected.add(c); else selected.remove(c); }), title: Text('${t['testName']} ($c)'), contentPadding: EdgeInsets.zero); }),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create'))])));
    if (ok != true || code.text.trim().isEmpty || name.text.trim().isEmpty || selected.isEmpty) return;
    try { await ApiService().createDiagnosticsPackage({'packageCode': code.text.trim(), 'packageName': name.text.trim(), 'price': double.tryParse(price.text) ?? 0, 'testCodes': selected.toList()}); await _load(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }

  Future<void> _deactivate(Map<String, dynamic> row, bool package) async {
    try { if (package) await ApiService().deleteDiagnosticsPackage('${row['_id']}'); else await ApiService().deleteDiagnosticsCatalogTest('${row['_id']}'); await _load(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.surface,
    appBar: AppBar(title: const Text('Diagnostics Catalog'), bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Tests'), Tab(text: 'Packages')])),
    floatingActionButton: FloatingActionButton.extended(onPressed: () => _tabs.index == 0 ? _addTest() : _addPackage(), icon: const Icon(Icons.add), label: Text(_tabs.index == 0 ? 'Test' : 'Package')),
    body: Column(children: [if (_loading) const LinearProgressIndicator(), Expanded(child: TabBarView(controller: _tabs, children: [_list(_tests, false), _list(_packages, true)]))]),
  );

  Widget _list(List<Map<String, dynamic>> rows, bool package) => RefreshIndicator(onRefresh: _load, child: rows.isEmpty ? ListView(children: [const SizedBox(height: 100), Center(child: Text(package ? 'No packages configured.' : 'No tests configured.'))]) : ListView.builder(padding: const EdgeInsets.all(16), itemCount: rows.length, itemBuilder: (_, i) { final r = rows[i]; return Card(child: ListTile(
    title: Text('${package ? r['packageName'] : r['testName']}', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
    subtitle: Text('${package ? r['packageCode'] : r['testCode']} • ₹${r['price'] ?? 0}${package ? ' • ${(r['testCodes'] as List? ?? const []).length} tests' : ' • ${r['sampleType'] ?? ''}'}'),
    trailing: r['isActive'] == false ? const Text('Inactive') : IconButton(onPressed: () => _deactivate(r, package), icon: const Icon(Icons.visibility_off_outlined)),
  )); }));
}
