import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/network/api_service.dart';
import '../../../core/theme/app_theme.dart';

class PathologyStaffScreen extends StatefulWidget {
  const PathologyStaffScreen({super.key});
  @override
  State<PathologyStaffScreen> createState() => _PathologyStaffScreenState();
}

class _PathologyStaffScreenState extends State<PathologyStaffScreen> {
  bool _loading = false;
  List<Map<String, dynamic>> _staff = [];
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() => _loading = true);
    try { final r = await ApiService().getDiagnosticsStaff(); final d = Map<String, dynamic>.from(r.data as Map); if (mounted) setState(() => _staff = (d['staff'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList()); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _create() async {
    final name = TextEditingController(), phone = TextEditingController(), code = TextEditingController(), pins = TextEditingController(); String role = 'phlebotomist';
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(title: const Text('Add Diagnostics Staff'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: name, decoration: const InputDecoration(labelText: 'Name *')),
      TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone *')),
      TextField(controller: code, decoration: const InputDecoration(labelText: 'Employee code')),
      DropdownButtonFormField<String>(value: role, items: const [DropdownMenuItem(value: 'phlebotomist', child: Text('Phlebotomist')), DropdownMenuItem(value: 'technician', child: Text('Technician')), DropdownMenuItem(value: 'receptionist', child: Text('Receptionist'))], onChanged: (v) => setS(() => role = v ?? role), decoration: const InputDecoration(labelText: 'Role')),
      TextField(controller: pins, decoration: const InputDecoration(labelText: 'Service pincodes, comma separated')),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add'))])));
    if (ok != true || name.text.trim().isEmpty || phone.text.trim().isEmpty) return;
    try {
      await ApiService().createDiagnosticsStaff({'name': name.text.trim(), 'phone': phone.text.trim(), 'role': role, if (code.text.trim().isNotEmpty) 'employeeCode': code.text.trim(), 'servicePincodes': pins.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()});
      await _load();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }

  Future<void> _deactivate(Map<String, dynamic> s) async { try { await ApiService().deleteDiagnosticsStaff('${s['_id']}'); await _load(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); } }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.surface, appBar: AppBar(title: const Text('Diagnostics Staff')),
    floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.person_add_alt_1), label: const Text('Add staff')),
    body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
      if (_loading) const LinearProgressIndicator(),
      if (!_loading && _staff.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('No staff configured.'))),
      ..._staff.map((s) => Card(child: ListTile(
        leading: CircleAvatar(child: Text('${s['name'] ?? '?'}'.substring(0, 1).toUpperCase())),
        title: Text('${s['name'] ?? 'Staff'}', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        subtitle: Text('${s['role'] ?? ''} • ${s['phone'] ?? ''}\n${(s['servicePincodes'] as List? ?? const []).join(', ')}'), isThreeLine: true,
        trailing: s['isActive'] == false ? const Text('Inactive') : IconButton(onPressed: () => _deactivate(s), icon: const Icon(Icons.person_off_outlined)),
      ))),
      const SizedBox(height: 80),
    ])),
  );
}
