import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_service.dart';
import '../../../core/theme/app_theme.dart';

class PhysioExercisePlanDetail extends StatefulWidget {
  final String planId;
  const PhysioExercisePlanDetail({super.key, required this.planId});

  @override
  State<PhysioExercisePlanDetail> createState() => _PhysioExercisePlanDetailState();
}

class _PhysioExercisePlanDetailState extends State<PhysioExercisePlanDetail> {
  final ApiService _api = ApiService();
  bool _loading = true;
  Map<String, dynamic>? _plan;
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _logs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _api.getPhysioExercisePlan(widget.planId);
      final data = Map<String, dynamic>.from(res.data as Map);
      if (mounted) {
        setState(() {
          _plan = data['plan'] is Map ? Map<String, dynamic>.from(data['plan']) : null;
          _summary = data['summary'] is Map ? Map<String, dynamic>.from(data['summary']) : {};
          _logs = (data['progress'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        });
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not load plan')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setStatus(String status) async {
    try {
      await _api.updatePhysioExercisePlan(widget.planId, {'status': status});
      await _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update plan status')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final plan = _plan;
    if (plan == null) return const Scaffold(body: Center(child: Text('Exercise plan not found')));
    final exercises = plan['exercises'] as List? ?? const [];
    final patient = plan['patientId'] is Map ? Map<String, dynamic>.from(plan['patientId']) : <String, dynamic>{};
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(plan['title'] ?? 'Exercise plan', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        actions: [
          PopupMenuButton<String>(
            onSelected: _setStatus,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'active', child: Text('Mark active')),
              PopupMenuItem(value: 'completed', child: Text('Mark completed')),
              PopupMenuItem(value: 'cancelled', child: Text('Cancel plan')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppTheme.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(patient['name'] ?? 'Patient', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  _chip((plan['status'] ?? 'active').toString().toUpperCase()),
                  _chip('${exercises.length} exercises'),
                  _chip('${_summary['completedLogs'] ?? 0} completed logs'),
                ]),
                if ((plan['instructions'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(plan['instructions'], style: GoogleFonts.manrope(fontSize: 13, color: AppTheme.textSecondary)),
                ],
              ]),
            ),
            const SizedBox(height: 18),
            Text('Exercises', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            ...exercises.map((raw) {
              final item = Map<String, dynamic>.from(raw as Map);
              final ex = item['exerciseId'] is Map ? Map<String, dynamic>.from(item['exerciseId']) : <String, dynamic>{};
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(ex['name'] ?? 'Exercise', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('${item['sets'] ?? 0} sets • ${item['reps'] ?? 0} reps${(item['durationSec'] ?? 0) > 0 ? ' • ${item['durationSec']} sec' : ''}', style: GoogleFonts.manrope(fontSize: 12, color: AppTheme.textSecondary)),
                  if ((item['frequency'] ?? '').toString().isNotEmpty) Text(item['frequency'], style: GoogleFonts.manrope(fontSize: 12, color: AppTheme.physioAccent)),
                  if ((item['notes'] ?? '').toString().isNotEmpty) Text(item['notes'], style: GoogleFonts.manrope(fontSize: 12, color: AppTheme.textSecondary)),
                ]),
              );
            }),
            const SizedBox(height: 18),
            Text('Patient progress', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if (_logs.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: const Text('No exercise logs yet.'),
              )
            else
              ..._logs.take(25).map((log) {
                final ex = log['exerciseId'] is Map ? Map<String, dynamic>.from(log['exerciseId']) : <String, dynamic>{};
                final date = DateTime.tryParse(log['performedAt']?.toString() ?? '');
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: CircleAvatar(backgroundColor: AppTheme.physioAccent.withValues(alpha: .1), child: const Icon(CupertinoIcons.checkmark_circle, color: AppTheme.physioAccent)),
                  title: Text(ex['name'] ?? 'Exercise'),
                  subtitle: Text('${date == null ? '' : DateFormat('dd MMM, hh:mm a').format(date.toLocal())} • ${log['setsCompleted'] ?? 0} sets • ${log['repsCompleted'] ?? 0} reps'),
                  trailing: (log['painAfter'] != null) ? Text('Pain ${log['painAfter']}/10') : null,
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: AppTheme.physioAccent.withValues(alpha: .08), borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: GoogleFonts.manrope(fontSize: 11, color: AppTheme.physioAccent, fontWeight: FontWeight.w600)),
      );
}
