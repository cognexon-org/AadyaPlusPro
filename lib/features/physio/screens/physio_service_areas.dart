import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../dashboard/providers/dashboard_provider.dart';

class PhysioServiceAreas extends ConsumerStatefulWidget {
  const PhysioServiceAreas({super.key});

  @override
  ConsumerState<PhysioServiceAreas> createState() => _PhysioServiceAreasState();
}

class _PhysioServiceAreasState extends ConsumerState<PhysioServiceAreas> {
  final TextEditingController _areaController = TextEditingController();
  List<String> _areas = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(physioDashboardProvider).profile;
    _areas = List<String>.from(profile['servesAreas'] ?? []);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final success = await ref.read(physioDashboardProvider.notifier).updateProfile({
      'servesAreas': _areas,
    });
    setState(() => _isSaving = false);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Service areas updated successfully')),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update service areas')),
        );
      }
    }
  }

  void _addArea() {
    final area = _areaController.text.trim();
    if (area.isNotEmpty) {
      if (!_areas.contains(area)) {
        setState(() {
          _areas.add(area);
          _areaController.clear();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Area already added')),
        );
      }
    }
  }

  void _removeArea(String area) {
    setState(() {
      _areas.remove(area);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text('Service Areas', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        actions: [
          if (_isSaving)
            const Center(child: Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.physioAccent))))
          else
            TextButton(
              onPressed: _save,
              child: Text('Save', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: AppTheme.physioAccent)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppTheme.physioAccent.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.physioAccent.withValues(alpha: 0.1))),
              child: Row(children: [
                const Icon(CupertinoIcons.info_circle, color: AppTheme.physioAccent),
                const SizedBox(width: 12),
                Expanded(child: Text('Add the areas or localities where you provide home visit physiotherapy services.', style: GoogleFonts.manrope(fontSize: 13, color: AppTheme.textSecondary))),
              ]),
            ),
            const SizedBox(height: 24),
            Text('Add New Area', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _areaController,
                    decoration: InputDecoration(
                      hintText: 'e.g. Indiranagar, Bangalore',
                      hintStyle: GoogleFonts.manrope(color: AppTheme.textTertiary, fontSize: 14),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.physioAccent)),
                    ),
                    onSubmitted: (_) => _addArea(),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _addArea,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppTheme.physioAccent, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(CupertinoIcons.add, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Text('Current Areas (${_areas.length})', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            if (_areas.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
                child: Column(children: [
                  Icon(CupertinoIcons.map_pin, size: 48, color: AppTheme.textTertiary.withValues(alpha: 0.3)),
                  const SizedBox(height: 12),
                  Text('No areas added yet', style: GoogleFonts.manrope(color: AppTheme.textTertiary)),
                ]),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _areas.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final area = _areas[index];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
                    child: Row(children: [
                      const Icon(CupertinoIcons.location, size: 18, color: AppTheme.physioAccent),
                      const SizedBox(width: 12),
                      Expanded(child: Text(area, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textPrimary))),
                      GestureDetector(
                        onTap: () => _removeArea(area),
                        child: const Icon(CupertinoIcons.trash, size: 18, color: AppTheme.error),
                      ),
                    ]),
                  );
                },
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
