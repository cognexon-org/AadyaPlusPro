import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_service.dart';

class DoctorAvailability extends ConsumerStatefulWidget {
  const DoctorAvailability({super.key});

  @override
  ConsumerState<DoctorAvailability> createState() => _DoctorAvailabilityState();
}

class _DoctorAvailabilityState extends ConsumerState<DoctorAvailability> {
  final ApiService _api = ApiService();
  bool _loading = true;
  bool _saving = false;
  
  final List<String> _days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
  Map<String, Map<String, dynamic>> _availability = {};

  @override
  void initState() {
    super.initState();
    _loadAvailability();
  }

  Future<void> _loadAvailability() async {
    setState(() => _loading = true);
    try {
      final res = await _api.getDoctorProfile();
      final data = res.data;
      final profile = data['doctor'] ?? data['profile'] ?? {};
      final List existing = profile['availability'] ?? [];
      
      final Map<String, Map<String, dynamic>> map = {};
      for (var day in _days) {
        final found = existing.firstWhere((e) => e['day'] == day, orElse: () => null);
        map[day] = {
          'enabled': found != null,
          'slots': found != null ? (found['slots'] as List).toList() : [],
        };
      }
      _availability = map;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _addSlot(String day) {
    setState(() {
      _availability[day]!['enabled'] = true;
      _availability[day]!['slots'].add({
        'startTime': '09:00',
        'endTime': '17:00',
        'type': 'clinic',
        'maxPatients': 1,
      });
    });
  }

  void _removeSlot(String day, int index) {
    setState(() {
      _availability[day]!['slots'].removeAt(index);
      if (_availability[day]!['slots'].isEmpty) {
        _availability[day]!['enabled'] = false;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final List payload = [];
      _availability.forEach((day, data) {
        if (data['enabled'] && data['slots'].isNotEmpty) {
          payload.add({'day': day, 'slots': data['slots']});
        }
      });
      await _api.updateAvailability({'availability': payload});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Availability updated successfully'), backgroundColor: AppTheme.success));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text('My Availability', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white, foregroundColor: AppTheme.textPrimary, elevation: 0, surfaceTintColor: Colors.white,
      ),
      body: _loading 
        ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              ..._days.map((day) => _buildDayCard(day)),
              const SizedBox(height: 80),
            ]),
          ),
      bottomSheet: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))]),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text('Save Availability', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }

  Widget _buildDayCard(String day) {
    final data = _availability[day]!;
    final bool isEnabled = data['enabled'];
    final List slots = data['slots'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
      child: Column(children: [
        ListTile(
          title: Text(day[0].toUpperCase() + day.substring(1), style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          trailing: Switch(
            value: isEnabled,
            onChanged: (v) {
              setState(() {
                _availability[day]!['enabled'] = v;
                if (v && slots.isEmpty) _addSlot(day);
              });
            },
            activeColor: AppTheme.primary,
          ),
        ),
        if (isEnabled) ...[
          const Divider(height: 1),
          ...slots.asMap().entries.map((entry) => _buildSlotRow(day, entry.key, entry.value)),
          TextButton.icon(
            onPressed: () => _addSlot(day),
            icon: const Icon(Iconsax.add_circle, size: 18),
            label: Text('Add Slot', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 8),
        ],
      ]),
    );
  }

  Widget _buildSlotRow(String day, int index, Map slot) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(children: [
        Row(children: [
          Expanded(child: _buildTimePicker(day, index, 'startTime')),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('to')),
          Expanded(child: _buildTimePicker(day, index, 'endTime')),
          IconButton(onPressed: () => _removeSlot(day, index), icon: const Icon(Iconsax.trash, size: 18, color: AppTheme.error)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _buildTypeDropdown(day, index)),
          const SizedBox(width: 8),
          Expanded(child: _buildMaxPatients(day, index)),
        ]),
      ]),
    );
  }

  Widget _buildTimePicker(String day, int index, String key) {
    return InkWell(
      onTap: () async {
        final current = _availability[day]!['slots'][index][key].split(':');
        final time = await showTimePicker(context: context, initialTime: TimeOfDay(hour: int.parse(current[0]), minute: int.parse(current[1])));
        if (time != null) {
          setState(() {
            _availability[day]!['slots'][index][key] = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(8)),
        child: Text(_availability[day]!['slots'][index][key], style: GoogleFonts.plusJakartaSans(fontSize: 13)),
      ),
    );
  }

  Widget _buildTypeDropdown(String day, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(8)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _availability[day]!['slots'][index]['type'],
          isExpanded: true,
          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textPrimary),
          items: const [
            DropdownMenuItem(value: 'clinic', child: Text('Clinic')),
            DropdownMenuItem(value: 'video', child: Text('Video')),
            DropdownMenuItem(value: 'home', child: Text('Home')),
          ],
          onChanged: (v) => setState(() => _availability[day]!['slots'][index]['type'] = v),
        ),
      ),
    );
  }

  Widget _buildMaxPatients(String day, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(8)),
      child: TextField(
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(border: InputBorder.none, hintText: 'Max pts'),
        style: GoogleFonts.plusJakartaSans(fontSize: 13),
        controller: TextEditingController(text: _availability[day]!['slots'][index]['maxPatients'].toString())..selection = TextSelection.collapsed(offset: _availability[day]!['slots'][index]['maxPatients'].toString().length),
        onChanged: (v) => _availability[day]!['slots'][index]['maxPatients'] = int.tryParse(v) ?? 1,
      ),
    );
  }
}
