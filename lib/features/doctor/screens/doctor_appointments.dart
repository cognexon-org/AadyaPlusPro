import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_service.dart';
import '../../../shared/widgets/empty_state.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import 'doctor_prescriptions.dart';
import '../../../shared/screens/professional_consultation_screen.dart';
import '../../../shared/screens/app_chat_screen.dart';
import 'prescription_details.dart';

class DoctorAppointments extends ConsumerStatefulWidget {
  const DoctorAppointments({super.key});

  @override
  ConsumerState<DoctorAppointments> createState() => _DoctorAppointmentsState();
}

class _DoctorAppointmentsState extends ConsumerState<DoctorAppointments> {
  final ApiService _api = ApiService();
  bool _loading = true;
  List<Map<String, dynamic>> _allAppointments = [];
  String _statusFilter = 'all';
  String _typeFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadAppointments();
  }

  Future<void> _loadAppointments() async {
    setState(() => _loading = true);
    try {
      final res = await _api.getDoctorAppointments(queryParams: {'limit': 1000});
      final data = res.data;
      final list = data is Map ? (data['data'] ?? data['appointments'] ?? []) : data;
      if (list is List) {
        // Sort descending by date
        final parsedList = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        parsedList.sort((a, b) {
          final da = DateTime.tryParse(a['createdAt']?.toString() ?? '') ?? DateTime.now();
          final db = DateTime.tryParse(b['createdAt']?.toString() ?? '') ?? DateTime.now();
          return db.compareTo(da);
        });
        _allAppointments = parsedList;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refresh() async {
    await _loadAppointments();
    ref.read(doctorDashboardProvider.notifier).loadDashboard(); // Refresh home stats too
  }

  List<Map<String, dynamic>> get _filtered {
    return _allAppointments.where((a) {
      if (_statusFilter != 'all') {
        final status = (a['status'] ?? 'pending').toString().toLowerCase();
        if (status != _statusFilter.toLowerCase()) return false;
      }
      if (_typeFilter != 'all' && a['type'] != _typeFilter) return false;
      return true;
    }).toList();
  }

  void _openDetails(Map<String, dynamic> apt) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AppointmentDetailsScreen(appointment: apt)),
    );
    if (result == true) {
      _refresh(); // Refresh if status changed in details
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Appointments',
                    style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Manage your consultations and schedules',
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Status Filters
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildFilterChips(['all', 'pending', 'confirmed', 'in_progress', 'completed', 'cancelled'], _statusFilter, (v) => setState(() => _statusFilter = v)),
            ),
            const SizedBox(height: 8),
            // Type Filters
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildFilterChips(['all', 'clinic', 'video', 'home'], _typeFilter, (v) => setState(() => _typeFilter = v)),
            ),
            const SizedBox(height: 12),

            // Appointments list
            Expanded(
              child: _loading && _allAppointments.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: filtered.isEmpty
                          ? ListView(children: const [
                              SizedBox(height: 80),
                              EmptyState(icon: Iconsax.calendar, title: 'No appointments found', subtitle: 'Try changing your filters or pull to refresh'),
                            ])
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              itemCount: filtered.length,
                              itemBuilder: (context, i) => _buildAppointmentCard(filtered[i]),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips(List<String> options, String selected, ValueChanged<String> onChanged) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: options.map((opt) {
          final isSelected = selected == opt;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onChanged(opt),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primary : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.divider),
                ),
                child: Text(
                  opt == 'all' ? 'All' : opt[0].toUpperCase() + opt.substring(1),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? Colors.white : AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAppointmentCard(Map<String, dynamic> apt) {
    final patient = apt['patientId'];
    final patientName = patient is Map ? (patient['name'] ?? 'Patient') : 'Patient';
    final status = (apt['status'] ?? 'pending').toString();
    final type = (apt['type'] ?? 'clinic').toString();
    final reason = apt['reason']?.toString().isEmpty ?? true ? 'Consultation' : apt['reason'];
    final fee = apt['consultationFee'] ?? apt['totalAmount'] ?? 0;
    final date = apt['appointmentDate'] ?? '';
    final time = apt['startTime'] ?? '';
    final id = apt['_id'] ?? '';

    final statusColor = status == 'confirmed' || status == 'accepted' ? AppTheme.primary : status == 'pending' ? AppTheme.warning : status == 'cancelled' ? AppTheme.error : AppTheme.success;
    final typeIcon = type == 'video' ? Iconsax.video : type == 'home' ? Iconsax.home : Iconsax.hospital;

    return GestureDetector(
      onTap: () => _openDetails(apt),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(gradient: AppTheme.doctorGradient, borderRadius: BorderRadius.circular(12)),
                  child: Center(child: Text(patientName[0], style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(patientName, style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                      const SizedBox(height: 2),
                      Text(reason, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(status.toUpperCase(), style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Iconsax.calendar, size: 14, color: AppTheme.textTertiary),
                const SizedBox(width: 6),
                Text(_formatDate(date), style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
                const SizedBox(width: 14),
                const Icon(Iconsax.clock, size: 14, color: AppTheme.textTertiary),
                const SizedBox(width: 6),
                Text(time, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
                const SizedBox(width: 14),
                Icon(typeIcon, size: 14, color: AppTheme.textTertiary),
                const SizedBox(width: 6),
                Text(type, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
                const Spacer(),
                Text('₹$fee', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primary)),
              ],
            ),
            if (status == 'pending') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _updateStatus(id, 'rejected'),
                      icon: const Icon(Iconsax.close_circle, size: 16),
                      label: Text('Reject', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.error, side: const BorderSide(color: AppTheme.error),
                        padding: const EdgeInsets.symmetric(vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _updateStatus(id, 'accepted'),
                      icon: const Icon(Iconsax.tick_circle, size: 16),
                      label: Text('Accept', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary, foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _updateStatus(String appointmentId, String status) async {
    if (appointmentId.isEmpty) return;
    final success = await ref.read(appointmentActionsProvider.notifier).updateStatus(appointmentId, status);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Appointment $status'),
        backgroundColor: (status == 'confirmed' || status == 'accepted') ? AppTheme.success : AppTheme.error,
      ));
      _refresh();
    }
  }

  String _formatDate(dynamic date) {
    if (date is String && date.isNotEmpty) {
      try {
        final dt = DateTime.parse(date);
        final now = DateTime.now();
        if (dt.year == now.year && dt.month == now.month && dt.day == now.day) return 'Today';
        if (dt.year == now.year && dt.month == now.month && dt.day == now.day + 1) return 'Tomorrow';
        return '${dt.day}/${dt.month}';
      } catch (_) {}
    }
    return date?.toString() ?? '';
  }
}

// ==================== APPOINTMENT DETAILS SCREEN ====================

class AppointmentDetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> appointment;
  const AppointmentDetailsScreen({super.key, required this.appointment});

  @override
  ConsumerState<AppointmentDetailsScreen> createState() => _AppointmentDetailsScreenState();
}

class _AppointmentDetailsScreenState extends ConsumerState<AppointmentDetailsScreen> {
  final ApiService _api = ApiService();
  Map<String, dynamic>? _prescription;
  bool _loadingPrescription = true;

  @override
  void initState() {
    super.initState();
    _loadPrescription();
  }

  Future<void> _loadPrescription() async {
    try {
      final aptId = widget.appointment['_id']?.toString() ?? '';
      if (aptId.isEmpty) return;
      final res = await _api.getPrescriptionByAppointment(aptId);
      final raw = res.data is Map ? res.data['prescription'] : null;
      if (raw is Map && mounted) {
        setState(() => _prescription = Map<String, dynamic>.from(raw));
      }
    } catch (_) {
      // A 404 simply means no appointment-linked prescription exists yet.
    }
    if (mounted) setState(() => _loadingPrescription = false);
  }

  Future<void> _changeStatus(String status) async {
    final id = widget.appointment['_id'] ?? '';
    if (id.isEmpty) return;
    
    // Show loading dialog
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
    
    final success = await ref.read(appointmentActionsProvider.notifier).updateStatus(id, status);
    
    if (mounted) Navigator.pop(context); // hide loading
    
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Appointment marked as $status', style: const TextStyle(color: Colors.white)), backgroundColor: AppTheme.success));
      Navigator.of(context).pop(true); // Return true to refresh previous screen
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update status'), backgroundColor: AppTheme.error));
    }
  }

  Future<void> _makePhoneCall(String phone) async {
    if (phone.isEmpty || phone == 'N/A') return;
    final Uri uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  bool _loadingChat = false;

  Future<void> _openInAppChat(String patientId, String patientName, String appointmentId) async {
    if (patientId.isEmpty) return;
    final profile = ref.read(doctorDashboardProvider).profile;
    if (profile.isEmpty) return;
    
    final profId = profile['_id'];

    setState(() => _loadingChat = true);
    try {
      final res = await _api.getOrCreateChatSession({
        'patientId': patientId,
        if (appointmentId.isNotEmpty) 'appointmentId': appointmentId,
      });

      if (res.data['success']) {
        final session = res.data['session'];
        if (mounted) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AppChatScreen(
              sessionId: session['_id'],
              patientName: patientName,
              patientId: patientId,
              professionalId: profId,
              professionalType: 'doctor',
            ),
          ));
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to start chat')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loadingChat = false);
    }
  }

  Future<void> _openMaps(Map<String, dynamic> apt) async {
    final loc = apt['location'];
    if (loc != null && loc['coordinates'] is List && (loc['coordinates'] as List).length == 2) {
      final lng = loc['coordinates'][0];
      final lat = loc['coordinates'][1];
      final Uri uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
      if (await canLaunchUrl(uri)) await launchUrl(uri);
    } else if (apt['address'] != null) {
      final Uri uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(apt['address'].toString())}');
      if (await canLaunchUrl(uri)) await launchUrl(uri);
    }
  }

  Future<void> _openConsultation() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfessionalConsultationScreen(
          appointment: widget.appointment,
        ),
      ),
    );
    await _loadPrescription();
    if (result == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _cancelAppointment() async {
    final id = widget.appointment['_id']?.toString() ?? '';
    if (id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel appointment?'),
        content: const Text('The patient will see this appointment as cancelled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel appointment')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.cancelAppointment(id, reason: 'Cancelled by professional');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Appointment cancelled'), backgroundColor: AppTheme.success),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to cancel: $e'), backgroundColor: AppTheme.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final apt = widget.appointment;
    final appointmentId = apt['_id']?.toString() ?? '';
    final patient = apt['patientId'];
    final patientIdStr = patient is Map ? (patient['_id']?.toString() ?? '') : patient?.toString() ?? '';
    final patientName = patient is Map ? (patient['name'] ?? 'Patient') : 'Patient';
    final patientPhone = patient is Map ? (patient['phone'] ?? 'N/A') : 'N/A';
    final patientAge = patient is Map ? (patient['age'] ?? 'N/A') : 'N/A';
    final patientGender = patient is Map ? (patient['gender'] ?? 'N/A') : 'N/A';
    
    final status = (apt['status'] ?? 'pending').toString();
    final type = (apt['type'] ?? 'clinic').toString();
    final symptoms = apt['symptoms'] is List ? (apt['symptoms'] as List).join(', ') : 'N/A';
    final reason = apt['reason']?.toString().isEmpty ?? true ? 'N/A' : apt['reason'];
    final fee = apt['consultationFee'] ?? apt['totalAmount'] ?? 0;
    final platformFee = apt['platformCommission'] ?? 0;
    final earning = apt['professionalEarning'] ?? 0;
    
    // Date & Time
    String dateStr = '';
    if (apt['appointmentDate'] != null) {
      try {
        final d = DateTime.parse(apt['appointmentDate']);
        dateStr = '${d.day}/${d.month}/${d.year}';
      } catch (_) {}
    }
    
    final statusColor = status == 'confirmed' || status == 'accepted' ? AppTheme.primary : status == 'pending' ? AppTheme.warning : status == 'cancelled' ? AppTheme.error : AppTheme.success;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text('Appointment Details', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white, foregroundColor: AppTheme.textPrimary, elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status and Date Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Status', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                        child: Text(status.toUpperCase(), style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildInfoCol('Date', dateStr, Iconsax.calendar),
                      _buildInfoCol('Time', apt['startTime'] ?? '', Iconsax.clock),
                      _buildInfoCol('Type', type, type == 'video' ? Iconsax.video : type == 'home' ? Iconsax.home : Iconsax.hospital),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // Patient Info
            Text('Patient Information', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 50, height: 50,
                        decoration: BoxDecoration(gradient: AppTheme.doctorGradient, shape: BoxShape.circle),
                        child: Center(child: Text(patientName[0], style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white))),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(patientName, style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                            Text('$patientGender, $patientAge years', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textSecondary)),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          _loadingChat 
                            ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                            : IconButton(onPressed: () => _openInAppChat(patientIdStr, patientName, appointmentId), icon: const Icon(Iconsax.messages_2, color: AppTheme.primary)),
                          IconButton(onPressed: () => _makePhoneCall(patientPhone), icon: const Icon(Iconsax.call, color: AppTheme.primary)),
                        ],
                      ),
                    ],
                  ),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
                  _buildDetailRow('Phone', patientPhone),
                  const SizedBox(height: 8),
                  _buildDetailRow('Symptoms', symptoms),
                  const SizedBox(height: 8),
                  _buildDetailRow('Reason', reason),
                  if (type == 'home' && apt['address'] != null) ...[
                    const SizedBox(height: 12),
                    Text('Patient Location', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => _openMaps(apt),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2))),
                        child: Row(
                          children: [
                            const Icon(Iconsax.location5, color: AppTheme.primary, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(apt['address'], style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                                  const SizedBox(height: 2),
                                  Text('Tap to view on Google Maps', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.primary.withValues(alpha: 0.7))),
                                ],
                              ),
                            ),
                            const Icon(Iconsax.routing, color: AppTheme.primary, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (['confirmed', 'accepted', 'in_progress', 'completed'].contains(status)) ...[
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _openConsultation,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            Icon(type == 'video' ? Iconsax.video5 : Iconsax.health, color: AppTheme.primary, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    status == 'completed' ? 'View Consultation Summary' : 'Open Consultation Workspace',
                                    style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primary),
                                  ),
                                  Text(
                                    type == 'video'
                                        ? 'Start/join the secure video room from here'
                                        : 'Clinical notes, prescription and completion',
                                    style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Iconsax.arrow_right_3, color: AppTheme.primary, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Prescription Details
            if (status == 'completed' || status == 'confirmed' || status == 'accepted' || status == 'in_progress') ...[
              Text('Prescription', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
              const SizedBox(height: 12),
              if (_loadingPrescription)
                const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
              else if (_prescription != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Iconsax.document_text, color: AppTheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text((_prescription!['status'] == 'draft' ? 'Draft Prescription' : 'Issued Prescription'), style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primary))),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_prescription!['diagnosis'] != null && _prescription!['diagnosis'].toString().isNotEmpty) ...[
                        _buildDetailRow('Diagnosis', _prescription!['diagnosis'] is List ? (_prescription!['diagnosis'] as List).join(', ') : _prescription!['diagnosis'].toString()),
                        const SizedBox(height: 8),
                      ],
                      if (_prescription!['medicines'] != null && (_prescription!['medicines'] as List).isNotEmpty) ...[
                        Text('Medicines:', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textSecondary)),
                        const SizedBox(height: 4),
                        ...(_prescription!['medicines'] as List).map((m) {
                          final name = m is Map ? (m['medicineName'] ?? m['name'] ?? '') : m.toString();
                          final dosage = m is Map ? (m['dosage'] ?? '') : '';
                          return Row(
                            children: [
                              Container(width: 4, height: 4, margin: const EdgeInsets.only(right: 8), decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle)),
                              Expanded(child: Text('$name${dosage.isNotEmpty ? ' - $dosage' : ''}', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w500))),
                            ],
                          );
                        }),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            if (_prescription != null) {
                              Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => PrescriptionDetailsScreen(prescription: _prescription!),
                              ));
                            }
                          },
                          icon: const Icon(Iconsax.eye, size: 16),
                          label: Text('View Details', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        ),
                      )
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Iconsax.document, size: 32, color: AppTheme.textTertiary.withValues(alpha: 0.5)),
                        const SizedBox(height: 8),
                        Text('No prescription written', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppTheme.textSecondary)),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final result = await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => CreatePrescriptionScreen(
                                initialPatientId: patient is Map ? patient['_id'] : patient,
                                initialPatientName: patientName,
                                initialAppointmentId: apt['_id'],
                              ),
                            ));
                            if (result == true) _loadPrescription();
                          },
                          icon: const Icon(Iconsax.edit, size: 16),
                          label: Text('Write Prescription', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        )
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 20),
            ],
            
            // Payment Info
            Text('Payment Details', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
              child: Column(
                children: [
                  _buildDetailRow('Total Fee Paid', '₹$fee', valueWeight: FontWeight.w700),
                  const SizedBox(height: 8),
                  _buildDetailRow('Platform Commission', '- ₹$platformFee', valueColor: AppTheme.error),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
                  _buildDetailRow('Your Net Earning', '₹$earning', valueColor: AppTheme.success, valueWeight: FontWeight.w700, valueSize: 16),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomActions(status),
    );
  }

  Widget? _buildBottomActions(String status) {
    if (status == 'cancelled' || status == 'completed') return null;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))]),
      child: SafeArea(
        child: Row(
          children: [
            if (status == 'pending') ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _changeStatus('rejected'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.error, side: const BorderSide(color: AppTheme.error), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: Text('Reject', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _changeStatus('accepted'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: Text('Accept', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
                ),
              ),
            ] else if (status == 'confirmed' || status == 'accepted') ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: _cancelAppointment,
                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.error, side: const BorderSide(color: AppTheme.error), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: Text('Cancel', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _openConsultation,
                  icon: const Icon(Iconsax.health, size: 18),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  label: Text('Consult', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
                ),
              ),
            ] else if (status == 'in_progress') ...[
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _openConsultation,
                  icon: const Icon(Iconsax.health, size: 18),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  label: Text('Continue Consultation', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCol(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: AppTheme.textTertiary),
        const SizedBox(height: 8),
        Text(value, style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppTheme.textTertiary)),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor, FontWeight? valueWeight, double? valueSize}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textSecondary))),
        Expanded(flex: 3, child: Text(value, textAlign: TextAlign.right, style: GoogleFonts.plusJakartaSans(fontSize: valueSize ?? 13, fontWeight: valueWeight ?? FontWeight.w500, color: valueColor ?? AppTheme.textPrimary))),
      ],
    );
  }
}
