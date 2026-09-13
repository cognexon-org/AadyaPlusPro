import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/theme/app_theme.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../../core/network/api_service.dart';

class PhysioAvailability extends ConsumerStatefulWidget {
  const PhysioAvailability({super.key});

  @override
  ConsumerState<PhysioAvailability> createState() => _PhysioAvailabilityState();
}

class _PhysioAvailabilityState extends ConsumerState<PhysioAvailability> {
  final List<String> _days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
  Map<String, List<Map<String, dynamic>>> _availability = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadAvailability();
  }

  void _loadAvailability() {
    final profile = ref.read(physioDashboardProvider).profile;
    final availList = profile['availability'] as List?;
    _availability = {};
    for (final day in _days) {
      _availability[day] = [];
    }
    
    if (availList != null) {
      for (final item in availList) {
        final day = item['day']?.toString().toLowerCase();
        if (day != null && _availability.containsKey(day)) {
          _availability[day] = List<Map<String, dynamic>>.from(item['slots'] ?? []);
        }
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
        title: Text('Set Availability', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
        centerTitle: true,
        leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Iconsax.arrow_left, color: AppTheme.textPrimary)),
        actions: [
          if (_isSaving)
            const Center(child: Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.physioAccent))))
          else
            TextButton(
              onPressed: _saveAvailability,
              child: Text('Save', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.physioAccent)),
            ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _days.length,
        itemBuilder: (c, i) => _dayCard(_days[i]),
      ),
    );
  }

  Widget _dayCard(String day) {
    final slots = _availability[day] ?? [];
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(day[0].toUpperCase() + day.substring(1), style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                GestureDetector(
                  onTap: () => _addSlot(day),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: AppTheme.physioAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      const Icon(Iconsax.add, size: 14, color: AppTheme.physioAccent),
                      const SizedBox(width: 4),
                      Text('Add Slot', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.physioAccent)),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          if (slots.isEmpty)
            Padding(padding: const EdgeInsets.only(bottom: 20), child: Text('No slots added - Unavailable', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textTertiary)))
          else
            Column(
              children: slots.asMap().entries.map((entry) => _slotRow(day, entry.key, entry.value)).toList(),
            ),
        ],
      ),
    );
  }

  Widget _slotRow(String day, int index, Map<String, dynamic> slot) {
    final type = slot['type'] ?? 'clinic';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(type == 'home' ? Iconsax.home : Iconsax.building, size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Expanded(child: Text('${slot['startTime']} - ${slot['endTime']}', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary))),
          GestureDetector(
            onTap: () => _removeSlot(day, index),
            child: const Icon(Iconsax.trash, size: 16, color: AppTheme.error),
          ),
        ],
      ),
    );
  }

  void _addSlot(String day) async {
    final TimeOfDay? start = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
    if (start == null) return;
    
    final TimeOfDay? end = await showTimePicker(context: context, initialTime: TimeOfDay(hour: (start.hour + 1) % 24, minute: start.minute));
    if (end == null) return;

    final type = await showDialog<String>(context: context, builder: (c) => AlertDialog(
      title: Text('Select Visit Type', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.bold)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: const Text('Clinic'), onTap: () => Navigator.pop(c, 'clinic')),
        ListTile(title: const Text('Home Visit'), onTap: () => Navigator.pop(c, 'home')),
        ListTile(title: const Text('Both (Clinic & Home)'), onTap: () => Navigator.pop(c, 'both')),
      ]),
    ));

    if (type != null) {
      setState(() {
        final st = '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
        final et = '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
        
        if (type == 'both') {
          _availability[day]!.add({ 'startTime': st, 'endTime': et, 'type': 'clinic' });
          _availability[day]!.add({ 'startTime': st, 'endTime': et, 'type': 'home' });
        } else {
          _availability[day]!.add({ 'startTime': st, 'endTime': et, 'type': type });
        }
      });
    }
  }

  void _removeSlot(String day, int index) {
    setState(() {
      _availability[day]!.removeAt(index);
    });
  }

  Future<void> _saveAvailability() async {
    setState(() => _isSaving = true);
    try {
      final formatted = _availability.entries.map((e) => {
        'day': e.key,
        'slots': e.value,
      }).toList();

      await ApiService().updatePhysioAvailability({'availability': formatted});
      await ref.read(physioDashboardProvider.notifier).loadProfile();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Availability updated successfully')));
      }
    } catch (e) {
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }
}
