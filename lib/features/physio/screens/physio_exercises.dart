import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/theme/app_theme.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../../core/network/api_service.dart';

class PhysioExercises extends ConsumerStatefulWidget {
  const PhysioExercises({super.key});

  @override
  ConsumerState<PhysioExercises> createState() => _PhysioExercisesState();
}

class _PhysioExercisesState extends ConsumerState<PhysioExercises> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All';

  final List<String> _categories = [
    'All', 'Strength Training', 'Flexibility', 'Balance', 'Cardio',
    'Rehabilitation', 'Posture Correction', 'Pain Relief', 'Mobility'
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(physioDashboardProvider.notifier).loadExercises());
  }

  @override
  Widget build(BuildContext context) {
    final dashData = ref.watch(physioDashboardProvider);
    final exercises = dashData.medicines; // Reusing medicines field for exercises

    final filtered = exercises.where((ex) {
      final matchesSearch = ex['name']?.toString().toLowerCase().contains(_searchController.text.toLowerCase()) ?? true;
      final matchesCat = _selectedCategory == 'All' || ex['category'] == _selectedCategory;
      return matchesSearch && matchesCat;
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text('Exercise Library', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
        centerTitle: true,
        leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Iconsax.arrow_left, color: AppTheme.textPrimary)),
        actions: [
          IconButton(
            onPressed: () => _showAddExercise(context),
            icon: const Icon(Iconsax.add_circle, color: AppTheme.physioAccent),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filters
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search exercises...',
                    prefixIcon: const Icon(Iconsax.search_normal),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    fillColor: AppTheme.surface,
                    filled: true,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length,
                    separatorBuilder: (c, i) => const SizedBox(width: 8),
                    itemBuilder: (c, i) {
                      final cat = _categories[i];
                      final isSelected = _selectedCategory == cat;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedCategory = cat),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.physioAccent : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: isSelected ? AppTheme.physioAccent : AppTheme.border),
                          ),
                          alignment: Alignment.center,
                          child: Text(cat, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : AppTheme.textSecondary)),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: dashData.isLoading && exercises.isEmpty
                ? const Center(child: CircularProgressIndicator(color: AppTheme.physioAccent))
                : filtered.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: filtered.length,
                        itemBuilder: (c, i) => _exerciseCard(filtered[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Iconsax.activity, size: 64, color: AppTheme.textTertiary.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text('No exercises found', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          Text('Try a different search or search category', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textTertiary)),
        ],
      ),
    );
  }

  Widget _exerciseCard(Map<String, dynamic> ex) {
    final bodyParts = (ex['bodyParts'] as List?)?.join(', ') ?? 'N/A';
    final difficulty = ex['difficulty'] ?? 'Beginner';
    final sets = ex['sets'] ?? '--';
    final reps = ex['reps'] ?? '--';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: AppTheme.physioAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Iconsax.activity, color: AppTheme.physioAccent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ex['name'] ?? 'Exercise Name', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                      const SizedBox(height: 4),
                      Text(ex['category'] ?? 'Category', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.physioAccent, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                _diffBadge(difficulty),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(ex['description'] ?? 'No description available.', maxLines: 2, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textSecondary, height: 1.4)),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppTheme.surface, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _stat('Target', bodyParts),
                _stat('Sets/Reps', '$sets × $reps'),
                const Icon(Iconsax.arrow_right_3, size: 18, color: AppTheme.textTertiary),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _diffBadge(String level) {
    Color color = AppTheme.success;
    if (level.toLowerCase() == 'intermediate') color = AppTheme.warning;
    if (level.toLowerCase() == 'advanced') color = AppTheme.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(level, style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _stat(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 10, color: AppTheme.textTertiary)),
      const SizedBox(height: 2),
      Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
    ]);
  }

  void _showAddExercise(BuildContext context) {
    // Show a bottom sheet or dialog to add exercise
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddExerciseSheet(),
    );
  }
}

class _AddExerciseSheet extends StatefulWidget {
  @override
  State<_AddExerciseSheet> createState() => _AddExerciseSheetState();
}

class _AddExerciseSheetState extends State<_AddExerciseSheet> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  String _category = 'Strength Training';
  String _difficulty = 'beginner';
  String _sets = '';
  String _reps = '';
  String _duration = '';
  String _description = '';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Add Exercise', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              const SizedBox(height: 20),
              _field('Exercise Name', (v) => _name = v, required: true),
              const SizedBox(height: 16),
              _dropdown('Category', ['Strength Training', 'Flexibility', 'Balance', 'Cardio', 'Rehabilitation'], (v) => _category = v!),
              const SizedBox(height: 16),
              _dropdown('Difficulty', ['beginner', 'intermediate', 'advanced'], (v) => _difficulty = v!),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _field('Sets', (v) => _sets = v, type: TextInputType.number)),
                  const SizedBox(width: 16),
                  Expanded(child: _field('Reps', (v) => _reps = v, type: TextInputType.number)),
                ],
              ),
              const SizedBox(height: 16),
              _field('Duration (e.g. 15 mins)', (v) => _duration = v),
              const SizedBox(height: 16),
              _field('Description', (v) => _description = v, maxLines: 3),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.physioAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
                  child: Text('Save Exercise', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, Function(String) onSaved, {bool required = false, TextInputType? type, int maxLines = 1}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
      const SizedBox(height: 8),
      TextFormField(
        onSaved: (v) => onSaved(v ?? ''),
        keyboardType: type,
        maxLines: maxLines,
        validator: (v) => required && (v == null || v.isEmpty) ? 'Required' : null,
        decoration: InputDecoration(
          hintText: 'Enter $label',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    ]);
  }

  Widget _dropdown(String label, List<String> items, Function(String?) onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        value: items.first,
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: onChanged,
        decoration: InputDecoration(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
      ),
    ]);
  }

  Future<void> _submit() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      try {
        final api = ApiService();
        await api.createPhysioExercise({
          'name': _name,
          'category': _category,
          'difficulty': _difficulty,
          'sets': int.tryParse(_sets) ?? 0,
          'reps': int.tryParse(_reps) ?? 0,
          'duration': _duration,
          'description': _description,
        });
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Exercise added successfully')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }
}
