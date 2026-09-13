import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_service.dart';
import '../../auth/providers/auth_provider.dart';

class DoctorSchedule extends ConsumerStatefulWidget {
  const DoctorSchedule({super.key});

  @override
  ConsumerState<DoctorSchedule> createState() => _DoctorScheduleState();
}

class _DoctorScheduleState extends ConsumerState<DoctorSchedule> {
  final ApiService _api = ApiService();
  bool _loading = true;
  List<Map<String, dynamic>> _weeklySchedule = [];
  DateTime _previewDate = DateTime.now();
  Map<String, dynamic>? _dayPreview;
  bool _previewLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    setState(() => _loading = true);
    try {
      final user = ref.read(authProvider).user;
      final doctorId = user?.profileId;
      if (doctorId == null) { setState(() => _loading = false); return; }
      
      final res = await _api.getWeeklyAvailability(doctorId);
      final data = res.data;
      final avail = data['availability'] ?? data;
      if (avail is List) {
        _weeklySchedule = avail.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadDayPreview() async {
    setState(() { _previewLoading = true; _dayPreview = null; });
    try {
      final user = ref.read(authProvider).user;
      final doctorId = user?.profileId;
      if (doctorId == null) return;

      final dateStr = '${_previewDate.year}-${_previewDate.month.toString().padLeft(2, '0')}-${_previewDate.day.toString().padLeft(2, '0')}';
      final res = await _api.getDayAvailability(doctorId, queryParams: {'date': dateStr});
      _dayPreview = Map<String, dynamic>.from(res.data);
    } catch (_) {}
    if (mounted) setState(() => _previewLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text('My Schedule', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white, foregroundColor: AppTheme.textPrimary, elevation: 0, surfaceTintColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Iconsax.refresh), onPressed: _loadSchedule),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              onRefresh: _loadSchedule,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Summary
                  _summarySection(),
                  const SizedBox(height: 20),

                  // Weekly overview
                  Text('Weekly Schedule', style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                  const SizedBox(height: 12),
                  ..._weeklySchedule.map((day) => _dayCard(day)),

                  if (_weeklySchedule.isEmpty)
                    _emptyState('No schedule set', 'Go to Availability to set your working hours.'),

                  const SizedBox(height: 24),

                  // Day preview
                  Text('Day Preview', style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                  const SizedBox(height: 12),
                  _dayPreviewSection(),
                ],
              ),
            ),
    );
  }

  Widget _summarySection() {
    final totalDays = _weeklySchedule.length;
    final totalSlots = _weeklySchedule.fold<int>(0, (s, d) => s + ((d['slots'] as List?)?.length ?? 0));
    final totalMins = _weeklySchedule.fold<int>(0, (s, d) {
      final slots = d['slots'] as List? ?? [];
      return s + slots.fold<int>(0, (acc, sl) {
        final start = _timeToMinutes(sl['startTime'] ?? '00:00');
        final end = _timeToMinutes(sl['endTime'] ?? '00:00');
        return acc + (end - start).clamp(0, 1440);
      });
    });

    return Row(children: [
      _miniCard('Days', '$totalDays', AppTheme.primary),
      const SizedBox(width: 10),
      _miniCard('Slots', '$totalSlots', AppTheme.accent),
      const SizedBox(width: 10),
      _miniCard('Hours/wk', '${totalMins ~/ 60}', AppTheme.success),
    ]);
  }

  Widget _miniCard(String label, String value, Color color) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.15))),
      child: Column(children: [
        Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textSecondary)),
      ]),
    ));
  }

  Widget _dayCard(Map<String, dynamic> day) {
    final dayName = (day['day'] ?? '').toString();
    final displayName = dayName.isNotEmpty ? '${dayName[0].toUpperCase()}${dayName.substring(1)}' : dayName;
    final slots = day['slots'] as List? ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
            child: Text(displayName, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary)),
          ),
          const Spacer(),
          Text('${slots.length} slot${slots.length != 1 ? 's' : ''}', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
        ]),
        if (slots.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: slots.map((s) {
            final typeColor = s['type'] == 'home' ? AppTheme.success : s['type'] == 'video' ? const Color(0xFF7C3AED) : AppTheme.primary;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(8), border: Border.all(color: typeColor.withValues(alpha: 0.15))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(s['type'] == 'video' ? Iconsax.video : s['type'] == 'home' ? Iconsax.home : Iconsax.hospital, size: 12, color: typeColor),
                const SizedBox(width: 6),
                Text('${s['startTime']} - ${s['endTime']}', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w500, color: typeColor)),
              ]),
            );
          }).toList()),
        ],
      ]),
    );
  }

  Widget _dayPreviewSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context, initialDate: _previewDate,
                firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _previewDate = picked);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.border)),
              child: Row(children: [
                const Icon(Iconsax.calendar, size: 16, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text('${_previewDate.day}/${_previewDate.month}/${_previewDate.year}', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500)),
              ]),
            ),
          )),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: _previewLoading ? null : _loadDayPreview,
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text(_previewLoading ? 'Loading...' : 'Preview', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          ),
        ]),

        if (_dayPreview != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(_dayPreview!['dayName'] ?? '', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (_dayPreview!['isAvailable'] == true ? AppTheme.success : AppTheme.error).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _dayPreview!['isAvailable'] == true ? 'Available' : 'Not Available',
                    style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: _dayPreview!['isAvailable'] == true ? AppTheme.success : AppTheme.error),
                  ),
                ),
              ]),
              if (_dayPreview!['slots'] is List) ...[
                const SizedBox(height: 10),
                ...(_dayPreview!['slots'] as List).map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Container(width: 4, height: 4, decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 8),
                    Text('${s['startTime']} - ${s['endTime']}', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textPrimary)),
                    const SizedBox(width: 8),
                    Text('(${s['type'] ?? 'clinic'})', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textTertiary)),
                  ]),
                )),
              ],
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _emptyState(String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
      child: Column(children: [
        Icon(Iconsax.calendar, size: 48, color: AppTheme.textTertiary.withValues(alpha: 0.4)),
        const SizedBox(height: 12),
        Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
        const SizedBox(height: 4),
        Text(subtitle, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textTertiary)),
      ]),
    );
  }

  int _timeToMinutes(String t) {
    final parts = t.split(':').map(int.parse).toList();
    return parts[0] * 60 + (parts.length > 1 ? parts[1] : 0);
  }
}
