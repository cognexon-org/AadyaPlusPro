import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_service.dart';
import 'doctor_appointments.dart';

class DoctorCalendar extends ConsumerStatefulWidget {
  const DoctorCalendar({super.key});

  @override
  ConsumerState<DoctorCalendar> createState() => _DoctorCalendarState();
}

class _DoctorCalendarState extends ConsumerState<DoctorCalendar> {
  final ApiService _api = ApiService();
  bool _loading = true;
  List<Map<String, dynamic>> _allAppointments = [];
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadAppointments();
  }

  Future<void> _loadAppointments() async {
    setState(() => _loading = true);
    try {
      final res = await _api.getDoctorAppointments(queryParams: {'limit': 1000}); // fetch large chunk to map calendar
      final data = res.data;
      final list = data is Map ? (data['data'] ?? data['appointments'] ?? []) : data;
      if (list is List) {
        _allAppointments = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refresh() async {
    await _loadAppointments();
  }

  @override
  Widget build(BuildContext context) {
    final dayAppointments = _allAppointments.where((a) {
      try {
        final d = DateTime.parse(a['appointmentDate']?.toString() ?? '');
        return d.year == _selectedDate.year && d.month == _selectedDate.month && d.day == _selectedDate.day;
      } catch (_) {
        return false;
      }
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text('Calendar', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white, foregroundColor: AppTheme.textPrimary, elevation: 0, surfaceTintColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading && _allAppointments.isEmpty
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : ListView(
                children: [
                  // Calendar
                  _buildCalendar(_allAppointments),
                  const SizedBox(height: 8),
                  // Appointments for selected day
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(
                        _selectedDate.day == DateTime.now().day && _selectedDate.month == DateTime.now().month
                            ? "Today's Appointments" : '${_selectedDate.day}/${_selectedDate.month} Appointments',
                        style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                        child: Text('${dayAppointments.length}', style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  if (dayAppointments.isEmpty)
                    Center(child: Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(CupertinoIcons.calendar, size: 48, color: AppTheme.textTertiary.withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        Text('No appointments on this date', style: GoogleFonts.manrope(fontSize: 14, color: AppTheme.textSecondary)),
                      ]),
                    ))
                  else
                    ...dayAppointments.map((apt) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _appointmentTile(apt),
                    )),
                  const SizedBox(height: 40),
                ],
              ),
      ),
    );
  }

  Widget _buildCalendar(List<Map<String, dynamic>> allAppointments) {
    final year = _focusedMonth.year;
    final month = _focusedMonth.month;
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);
    final startWeekday = firstDay.weekday; // 1=Mon .. 7=Sun

    // Count appointments per day for dot indicators
    final dayCounts = <int, int>{};
    for (final a in allAppointments) {
      try {
        final d = DateTime.parse(a['appointmentDate']?.toString() ?? '');
        if (d.year == year && d.month == month) {
          dayCounts[d.day] = (dayCounts[d.day] ?? 0) + 1;
        }
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.border)),
      child: Column(
        children: [
          // Month navigation
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton(
              icon: const Icon(CupertinoIcons.chevron_back, size: 20),
              onPressed: () => setState(() => _focusedMonth = DateTime(year, month - 1)),
            ),
            Text(
              '${_monthName(month)} $year',
              style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
            ),
            IconButton(
              icon: const Icon(CupertinoIcons.chevron_right, size: 20),
              onPressed: () => setState(() => _focusedMonth = DateTime(year, month + 1)),
            ),
          ]),
          const SizedBox(height: 12),
          // Day headers
          Row(children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
              .map((d) => Expanded(child: Center(child: Text(d, style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textTertiary)))))
              .toList()),
          const SizedBox(height: 8),
          // Days grid
          ...List.generate(6, (weekRow) {
            return Row(
              children: List.generate(7, (col) {
                final dayNum = weekRow * 7 + col + 1 - (startWeekday - 1);
                if (dayNum < 1 || dayNum > lastDay.day) return const Expanded(child: SizedBox(height: 44));

                final isToday = dayNum == DateTime.now().day && month == DateTime.now().month && year == DateTime.now().year;
                final isSelected = dayNum == _selectedDate.day && month == _selectedDate.month && year == _selectedDate.year;
                final hasAppointments = (dayCounts[dayNum] ?? 0) > 0;

                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedDate = DateTime(year, month, dayNum)),
                    child: Container(
                      height: 44,
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.primary : isToday ? AppTheme.primary.withValues(alpha: 0.08) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(
                          '$dayNum',
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: isToday || isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected ? Colors.white : isToday ? AppTheme.primary : AppTheme.textPrimary,
                          ),
                        ),
                        if (hasAppointments)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            width: 5, height: 5,
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.white : AppTheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ]),
                    ),
                  ),
                );
              }),
            );
          }),
        ],
      ),
    );
  }

  Widget _appointmentTile(Map<String, dynamic> apt) {
    final name = apt['patientId']?['name'] ?? apt['patientName'] ?? 'Patient';
    final status = apt['status'] ?? 'pending';
    final time = apt['startTime'] ?? '';
    final type = apt['type'] ?? 'clinic';
    final reason = apt['reason'] ?? apt['symptoms']?.toString() ?? '';

    final statusColor = status == 'completed' ? AppTheme.success
        : (status == 'confirmed' || status == 'accepted') ? AppTheme.primary
        : status == 'cancelled' ? AppTheme.error : AppTheme.warning;

    return GestureDetector(
      onTap: () async {
        final result = await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AppointmentDetailsScreen(appointment: apt)));
        if (result == true) _loadAppointments();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(gradient: AppTheme.doctorGradient, borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(name[0], style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            Row(children: [
              if (time.isNotEmpty) ...[
                const Icon(CupertinoIcons.clock, size: 12, color: AppTheme.textTertiary),
                const SizedBox(width: 4),
                Text(time, style: GoogleFonts.manrope(fontSize: 11, color: AppTheme.textSecondary)),
                const SizedBox(width: 8),
              ],
              Icon(type == 'video' ? CupertinoIcons.video_camera : type == 'home' ? CupertinoIcons.house : Icons.local_hospital_outlined, size: 12, color: AppTheme.textTertiary),
              const SizedBox(width: 4),
              Text(type, style: GoogleFonts.manrope(fontSize: 11, color: AppTheme.textSecondary)),
            ]),
            if (reason.isNotEmpty)
              Text(reason, style: GoogleFonts.manrope(fontSize: 11, color: AppTheme.textTertiary), maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(status, style: GoogleFonts.manrope(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor)),
          ),
        ]),
      ),
    );
  }

  String _monthName(int month) {
    const names = ['', 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return names[month];
  }
}
