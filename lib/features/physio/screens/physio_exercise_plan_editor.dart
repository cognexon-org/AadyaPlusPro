import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/network/api_service.dart';
import '../../../core/theme/app_theme.dart';

class PhysioExercisePlanEditor extends StatefulWidget {
  final String patientId;
  final String patientName;
  final String? appointmentId;

  const PhysioExercisePlanEditor({
    super.key,
    required this.patientId,
    required this.patientName,
    this.appointmentId,
  });

  @override
  State<PhysioExercisePlanEditor> createState() => _PhysioExercisePlanEditorState();
}

class _PhysioExercisePlanEditorState extends State<PhysioExercisePlanEditor> {
  final ApiService _api = ApiService();
  final TextEditingController _title = TextEditingController(text: 'Physiotherapy exercise plan');
  final TextEditingController _goals = TextEditingController();
  final TextEditingController _instructions = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<Map<String, dynamic>> _catalog = [];
  final Map<String, _PlanDose> _selected = {};

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    _title.dispose();
    _goals.dispose();
    _instructions.dispose();
    for (final dose in _selected.values) {
      dose.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    try {
      final res = await _api.getPhysioExercises();
      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : <String, dynamic>{};
      final list = data['exercises'] as List? ?? const [];
      if (mounted) setState(() => _catalog = list.map((e) => Map<String, dynamic>.from(e as Map)).toList());
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load exercise library');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle(Map<String, dynamic> exercise, bool enabled) {
    final id = exercise['_id'].toString();
    setState(() {
      if (enabled) {
        _selected[id] = _PlanDose.fromExercise(exercise);
      } else {
        _selected.remove(id)?.dispose();
      }
    });
  }

  Future<void> _save() async {
    if (_selected.isEmpty || _saving) {
      if (_selected.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select at least one exercise')));
      }
      return;
    }
    setState(() => _saving = true);
    try {
      final exercises = <Map<String, dynamic>>[];
      var index = 0;
      for (final entry in _selected.entries) {
        final dose = entry.value;
        exercises.add({
          'exerciseId': entry.key,
          'sets': int.tryParse(dose.sets.text) ?? 0,
          'reps': int.tryParse(dose.reps.text) ?? 0,
          'durationSec': int.tryParse(dose.duration.text) ?? 0,
          'frequency': dose.frequency.text.trim(),
          'notes': dose.notes.text.trim(),
          'sortOrder': index++,
        });
      }
      await _api.createPhysioPatientExercisePlan(widget.patientId, {
        'title': _title.text.trim().isEmpty ? 'Physiotherapy exercise plan' : _title.text.trim(),
        'goals': _goals.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        'instructions': _instructions.text.trim(),
        if (widget.appointmentId != null && widget.appointmentId!.isNotEmpty) 'appointmentId': widget.appointmentId,
        'exercises': exercises,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not assign exercise plan')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text('Plan for ${widget.patientName}', style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.physioAccent, padding: const EdgeInsets.symmetric(vertical: 15)),
            icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(CupertinoIcons.checkmark_circle),
            label: Text(_saving ? 'Assigning...' : 'Assign plan (${_selected.length})'),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
                      child: Column(children: [
                        TextField(controller: _title, decoration: const InputDecoration(labelText: 'Plan title')),
                        const SizedBox(height: 10),
                        TextField(controller: _goals, maxLines: 3, decoration: const InputDecoration(labelText: 'Goals (one per line)')),
                        const SizedBox(height: 10),
                        TextField(controller: _instructions, maxLines: 3, decoration: const InputDecoration(labelText: 'Overall instructions')),
                      ]),
                    ),
                    const SizedBox(height: 18),
                    Text('Select exercises', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    if (_catalog.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                        child: const Text('Your exercise library is empty. Create exercises from Exercise Library first.'),
                      )
                    else
                      ..._catalog.map(_exerciseTile),
                  ],
                ),
    );
  }

  Widget _exerciseTile(Map<String, dynamic> exercise) {
    final id = exercise['_id'].toString();
    final selected = _selected.containsKey(id);
    final dose = _selected[id];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: selected ? AppTheme.physioAccent : AppTheme.border)),
      child: Column(children: [
        CheckboxListTile(
          value: selected,
          onChanged: (v) => _toggle(exercise, v == true),
          activeColor: AppTheme.physioAccent,
          title: Text(exercise['name'] ?? 'Exercise', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
          subtitle: Text([exercise['bodyPart'], exercise['category']].where((e) => e != null && e.toString().isNotEmpty).join(' • ')),
        ),
        if (selected && dose != null) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              Row(children: [
                Expanded(child: _numberField(dose.sets, 'Sets')),
                const SizedBox(width: 8),
                Expanded(child: _numberField(dose.reps, 'Reps')),
                const SizedBox(width: 8),
                Expanded(child: _numberField(dose.duration, 'Seconds')),
              ]),
              const SizedBox(height: 10),
              TextField(controller: dose.frequency, decoration: const InputDecoration(labelText: 'Frequency')),
              const SizedBox(height: 10),
              TextField(controller: dose.notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Patient-specific notes')),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _numberField(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
      );
}

class _PlanDose {
  final TextEditingController sets;
  final TextEditingController reps;
  final TextEditingController duration;
  final TextEditingController frequency;
  final TextEditingController notes;

  _PlanDose({required this.sets, required this.reps, required this.duration, required this.frequency, required this.notes});

  factory _PlanDose.fromExercise(Map<String, dynamic> e) => _PlanDose(
        sets: TextEditingController(text: '${e['defaultSets'] ?? 0}'),
        reps: TextEditingController(text: '${e['defaultReps'] ?? 0}'),
        duration: TextEditingController(text: '${e['defaultDurationSec'] ?? 0}'),
        frequency: TextEditingController(text: e['defaultFrequency']?.toString() ?? ''),
        notes: TextEditingController(),
      );

  void dispose() {
    sets.dispose();
    reps.dispose();
    duration.dispose();
    frequency.dispose();
    notes.dispose();
  }
}
