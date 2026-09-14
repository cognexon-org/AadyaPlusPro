import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/network/api_service.dart';
import '../../../core/theme/app_theme.dart';
import 'pathology_staff.dart';

class PathologyHome extends StatefulWidget {
  const PathologyHome({super.key});
  @override
  State<PathologyHome> createState() => _PathologyHomeState();
}

class _PathologyHomeState extends State<PathologyHome> {
  bool _loading = false;
  Map<String, dynamic> _data = {};

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await ApiService().getDiagnosticsMerchantDashboard();
      if (mounted) setState(() => _data = Map<String, dynamic>.from(r.data as Map));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Diagnostics dashboard failed: $e'))); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final stats = Map<String, dynamic>.from((_data['stats'] as Map?) ?? const {});
    final lab = Map<String, dynamic>.from((_data['lab'] as Map?) ?? const {});
    final recent = (_data['recent'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(child: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${lab['labName'] ?? 'Diagnostics'}', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
            Text('Diagnostics merchant operations', style: GoogleFonts.plusJakartaSans(color: AppTheme.textSecondary)),
          ])),
          IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PathologyStaffScreen())), icon: const Icon(Icons.people_outline), tooltip: 'Field staff'),
        ]),
        if (_loading) const LinearProgressIndicator(),
        const SizedBox(height: 18),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _stat('Today', stats['todayOrders'] ?? 0, Icons.today, AppTheme.primary),
          _stat('Pending', stats['pending'] ?? 0, Icons.pending_actions, AppTheme.warning),
          _stat('Completed month', stats['completedMonth'] ?? 0, Icons.task_alt, AppTheme.success),
          _stat('Home collections', stats['upcomingHomeCollections'] ?? 0, Icons.home_work_outlined, AppTheme.pathologyAccent),
        ]),
        const SizedBox(height: 16),
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(gradient: AppTheme.pathologyGradient, borderRadius: BorderRadius.circular(16)), child: Row(children: [
          const Icon(Icons.currency_rupee, color: Colors.white), const SizedBox(width: 10),
          Expanded(child: Text('Paid revenue this month', style: GoogleFonts.plusJakartaSans(color: Colors.white70))),
          Text('₹${stats['monthlyPaidRevenue'] ?? 0}', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
        ])),
        const SizedBox(height: 20),
        Text('Recent diagnostic orders', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (recent.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('No recent orders.'))),
        ...recent.map((o) {
          final patient = o['patientId'] is Map ? o['patientId'] as Map : const {};
          return Card(child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.science_outlined)),
            title: Text('${patient['name'] ?? 'Patient'}'),
            subtitle: Text('${o['labTestNumber'] ?? ''} • ${_label('${o['status'] ?? 'requested'}')}'),
            trailing: Text('₹${o['totalAmount'] ?? 0}'),
          ));
        }),
      ]))),
    );
  }

  Widget _stat(String label, dynamic value, IconData icon, Color color) => Container(width: 155, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: color), const SizedBox(height: 8), Text('$value', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800)), Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textSecondary))]));
  String _label(String v) => v.split('_').map((e) => e.isEmpty ? e : '${e[0].toUpperCase()}${e.substring(1)}').join(' ');
}
