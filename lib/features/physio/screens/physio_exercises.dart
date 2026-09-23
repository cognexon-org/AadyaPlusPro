import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/network/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_dialog.dart';

class PhysioExercises extends StatefulWidget {
  const PhysioExercises({super.key});

  @override
  State<PhysioExercises> createState() => _PhysioExercisesState();
}

class _PhysioExercisesState extends State<PhysioExercises> {
  final ApiService _api = ApiService();
  final TextEditingController _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted)
      setState(() {
        _loading = true;
        _error = null;
      });
    try {
      final res = await _api.getPhysioExercises(
        queryParams: _search.text.trim().isEmpty
            ? null
            : {'search': _search.text.trim()},
      );
      final data = res.data is Map
          ? Map<String, dynamic>.from(res.data)
          : <String, dynamic>{};
      final list = data['exercises'] as List? ?? const [];
      if (mounted) {
        setState(() {
          _items = list
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load exercise library');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEditor([Map<String, dynamic>? current]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExerciseEditor(exercise: current),
    );
    if (saved == true) await _load();
  }

  Future<void> _archive(Map<String, dynamic> item) async {
    final ok = await AppDialog.confirm(
      context,
      title: 'Archive exercise?',
      message:
          '${item['name'] ?? 'This exercise'} will no longer be available for new plans.',
      icon: CupertinoIcons.archivebox,
      confirmLabel: 'Archive',
      destructive: true,
    );
    if (!ok) return;
    try {
      await _api.deletePhysioExercise(item['_id'].toString());
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not archive exercise')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(CupertinoIcons.back, color: AppTheme.textPrimary),
        ),
        title: Text(
          'Exercise Library',
          style: GoogleFonts.manrope(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: AppTheme.physioAccent,
        foregroundColor: Colors.white,
        icon: const Icon(CupertinoIcons.add),
        label: const Text('Exercise'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            TextField(
              controller: _search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Search exercise, body part or category',
                prefixIcon: const Icon(CupertinoIcons.search),
                suffixIcon: IconButton(
                  onPressed: _load,
                  icon: const Icon(CupertinoIcons.chevron_right),
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _messageCard(_error!, CupertinoIcons.exclamationmark_triangle)
            else if (_items.isEmpty)
              _messageCard(
                'Your exercise library is empty. Create your first exercise to assign it to a patient.',
                CupertinoIcons.waveform_path,
              )
            else
              ..._items.map(_exerciseCard),
          ],
        ),
      ),
    );
  }

  Widget _exerciseCard(Map<String, dynamic> item) {
    final instructions = item['instructions'] as List? ?? const [];
    final meta = [
      if ((item['bodyPart'] ?? '').toString().isNotEmpty)
        item['bodyPart'].toString(),
      if ((item['category'] ?? '').toString().isNotEmpty)
        item['category'].toString(),
      (item['difficulty'] ?? 'moderate').toString(),
    ].join(' • ');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.physioAccent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  CupertinoIcons.waveform_path,
                  color: AppTheme.physioAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['name'] ?? 'Exercise',
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (meta.isNotEmpty)
                      Text(
                        meta,
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) =>
                    value == 'edit' ? _openEditor(item) : _archive(item),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'archive', child: Text('Archive')),
                ],
              ),
            ],
          ),
          if ((item['description'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              item['description'],
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip('${item['defaultSets'] ?? 0} sets'),
              _chip('${item['defaultReps'] ?? 0} reps'),
              if ((item['defaultDurationSec'] ?? 0) > 0)
                _chip('${item['defaultDurationSec']} sec'),
              if ((item['defaultFrequency'] ?? '').toString().isNotEmpty)
                _chip(item['defaultFrequency'].toString()),
            ],
          ),
          if (instructions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '${instructions.length} instruction${instructions.length == 1 ? '' : 's'}',
              style: GoogleFonts.manrope(
                fontSize: 12,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: GoogleFonts.manrope(fontSize: 11, color: AppTheme.textSecondary),
    ),
  );

  Widget _messageCard(String text, IconData icon) => Container(
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppTheme.border),
    ),
    child: Column(
      children: [
        Icon(icon, size: 34, color: AppTheme.textTertiary),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(
            fontSize: 13,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    ),
  );
}

class _ExerciseEditor extends StatefulWidget {
  final Map<String, dynamic>? exercise;
  const _ExerciseEditor({this.exercise});

  @override
  State<_ExerciseEditor> createState() => _ExerciseEditorState();
}

class _ExerciseEditorState extends State<_ExerciseEditor> {
  final ApiService _api = ApiService();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _category;
  late final TextEditingController _bodyPart;
  late final TextEditingController _sets;
  late final TextEditingController _reps;
  late final TextEditingController _duration;
  late final TextEditingController _frequency;
  late final TextEditingController _equipment;
  late final TextEditingController _instructions;
  late final TextEditingController _precautions;
  String _difficulty = 'moderate';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final x = widget.exercise ?? const <String, dynamic>{};
    _name = TextEditingController(text: x['name']?.toString() ?? '');
    _description = TextEditingController(
      text: x['description']?.toString() ?? '',
    );
    _category = TextEditingController(text: x['category']?.toString() ?? '');
    _bodyPart = TextEditingController(text: x['bodyPart']?.toString() ?? '');
    _sets = TextEditingController(text: '${x['defaultSets'] ?? 0}');
    _reps = TextEditingController(text: '${x['defaultReps'] ?? 0}');
    _duration = TextEditingController(text: '${x['defaultDurationSec'] ?? 0}');
    _frequency = TextEditingController(
      text: x['defaultFrequency']?.toString() ?? '',
    );
    _equipment = TextEditingController(
      text: (x['equipment'] as List? ?? const []).join(', '),
    );
    _instructions = TextEditingController(
      text: (x['instructions'] as List? ?? const []).join('\n'),
    );
    _precautions = TextEditingController(
      text: (x['precautions'] as List? ?? const []).join('\n'),
    );
    _difficulty = x['difficulty']?.toString() ?? 'moderate';
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _description,
      _category,
      _bodyPart,
      _sets,
      _reps,
      _duration,
      _frequency,
      _equipment,
      _instructions,
      _precautions,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _saving) return;
    setState(() => _saving = true);
    final payload = {
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'category': _category.text.trim(),
      'bodyPart': _bodyPart.text.trim(),
      'difficulty': _difficulty,
      'defaultSets': int.tryParse(_sets.text) ?? 0,
      'defaultReps': int.tryParse(_reps.text) ?? 0,
      'defaultDurationSec': int.tryParse(_duration.text) ?? 0,
      'defaultFrequency': _frequency.text.trim(),
      'equipment': _equipment.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      'instructions': _instructions.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      'precautions': _precautions.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
    };
    try {
      if (widget.exercise == null) {
        await _api.createPhysioExercise(payload);
      } else {
        await _api.updatePhysioExercise(
          widget.exercise!['_id'].toString(),
          payload,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save exercise')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.exercise == null
                          ? 'New Exercise'
                          : 'Edit Exercise',
                      style: GoogleFonts.manrope(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
                  _field(_name, 'Exercise name *'),
                  _field(_description, 'Description', lines: 3),
                  Row(
                    children: [
                      Expanded(child: _field(_category, 'Category')),
                      const SizedBox(width: 12),
                      Expanded(child: _field(_bodyPart, 'Body part')),
                    ],
                  ),
                  DropdownButtonFormField<String>(
                    value: _difficulty,
                    decoration: const InputDecoration(labelText: 'Difficulty'),
                    items: const [
                      DropdownMenuItem(value: 'easy', child: Text('Easy')),
                      DropdownMenuItem(
                        value: 'moderate',
                        child: Text('Moderate'),
                      ),
                      DropdownMenuItem(value: 'hard', child: Text('Hard')),
                    ],
                    onChanged: (v) =>
                        setState(() => _difficulty = v ?? 'moderate'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _field(_sets, 'Default sets', number: true),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _field(_reps, 'Default reps', number: true),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _field(_duration, 'Seconds', number: true),
                      ),
                    ],
                  ),
                  _field(_frequency, 'Default frequency (e.g. 2x daily)'),
                  _field(_equipment, 'Equipment (comma separated)'),
                  _field(
                    _instructions,
                    'Instructions (one step per line)',
                    lines: 5,
                  ),
                  _field(_precautions, 'Precautions (one per line)', lines: 4),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.physioAccent,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save exercise'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    int lines = 1,
    bool number = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: c,
      maxLines: lines,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
