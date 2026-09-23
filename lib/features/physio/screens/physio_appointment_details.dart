import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../shared/screens/app_chat_screen.dart';
import '../../doctor/screens/doctor_prescriptions.dart';
import '../../doctor/screens/prescription_details.dart';
import '../../../core/network/api_service.dart';
import '../../../shared/screens/professional_consultation_screen.dart';

class PhysioAppointmentDetails extends ConsumerStatefulWidget {
  final Map<String, dynamic> appointment;

  const PhysioAppointmentDetails({super.key, required this.appointment});

  @override
  ConsumerState<PhysioAppointmentDetails> createState() =>
      _PhysioAppointmentDetailsState();
}

class _PhysioAppointmentDetailsState
    extends ConsumerState<PhysioAppointmentDetails> {
  final ApiService _api = ApiService();
  Map<String, dynamic>? _prescription;
  bool _loadingPrescription = true;
  bool _loadingChat = false;

  @override
  void initState() {
    super.initState();
    _loadPrescription();
  }

  Future<void> _loadPrescription() async {
    final appointmentId = widget.appointment['_id']?.toString() ?? '';
    if (appointmentId.isEmpty) {
      if (mounted) setState(() => _loadingPrescription = false);
      return;
    }
    if (mounted) setState(() => _loadingPrescription = true);
    try {
      final res = await _api.getPrescriptionByAppointment(appointmentId);
      final data = res.data;
      final value = data is Map ? (data['prescription'] ?? data['data']) : null;
      if (mounted) {
        setState(
          () => _prescription = value is Map
              ? Map<String, dynamic>.from(value)
              : null,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _prescription = null);
    } finally {
      if (mounted) setState(() => _loadingPrescription = false);
    }
  }

  Future<void> _openConsultation() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ProfessionalConsultationScreen(appointment: widget.appointment),
      ),
    );
    await _loadPrescription();
  }

  Future<void> _cancelSession() async {
    final id = widget.appointment['_id']?.toString() ?? '';
    if (id.isEmpty) return;
    final confirmed = await AppDialog.confirm(
      context,
      title: 'Cancel session?',
      message: 'The patient will see this appointment as cancelled.',
      icon: CupertinoIcons.calendar_badge_minus,
      cancelLabel: 'Keep',
      confirmLabel: 'Cancel session',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await _api.cancelAppointment(id, reason: 'Cancelled by professional');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session cancelled'),
          backgroundColor: AppTheme.success,
        ),
      );
      ref.read(physioDashboardProvider.notifier).loadAppointments();
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to cancel: $error'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  Future<void> _changeStatus(String status) async {
    final id = widget.appointment['_id'] ?? '';
    if (id.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final success = await ref
        .read(appointmentActionsProvider.notifier)
        .updateStatus(id, status);

    if (mounted) Navigator.pop(context);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Session marked as $status'),
          backgroundColor: AppTheme.success,
        ),
      );
      ref.read(physioDashboardProvider.notifier).loadAppointments();
      Navigator.of(context).pop(true);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update status'),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  Future<void> _makePhoneCall(String phone) async {
    if (phone.isEmpty || phone == 'N/A') return;
    final Uri uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openMaps(Map<String, dynamic> apt) async {
    final loc = apt['location'];
    if (loc != null &&
        loc['coordinates'] is List &&
        (loc['coordinates'] as List).length == 2) {
      final lng = loc['coordinates'][0];
      final lat = loc['coordinates'][1];
      final Uri uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
      );
      if (await canLaunchUrl(uri)) await launchUrl(uri);
    } else if (apt['address'] != null) {
      final Uri uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(apt['address'].toString())}',
      );
      if (await canLaunchUrl(uri)) await launchUrl(uri);
    }
  }

  Future<void> _openInAppChat(
    String patientId,
    String patientName,
    String appointmentId,
  ) async {
    if (patientId.isEmpty) return;
    final profile = ref.read(physioDashboardProvider).profile;
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
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AppChatScreen(
                sessionId: session['_id'],
                patientName: patientName,
                patientId: patientId,
                professionalId: profId,
                professionalType: 'physio',
              ),
            ),
          );
        }
      } else {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Failed to start chat')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loadingChat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final apt = widget.appointment;
    final appointmentId = apt['_id']?.toString() ?? '';
    final patient = apt['patientId'];
    final patientIdStr = patient is Map
        ? (patient['_id']?.toString() ?? '')
        : patient?.toString() ?? '';
    final patientName = patient is Map
        ? (patient['name'] ?? 'Patient')
        : 'Patient';
    final patientPhone = patient is Map ? (patient['phone'] ?? 'N/A') : 'N/A';
    final patientAge = patient is Map ? (patient['age'] ?? 'N/A') : 'N/A';
    final patientGender = patient is Map ? (patient['gender'] ?? 'N/A') : 'N/A';

    final status = (apt['status'] ?? 'pending').toString();
    final type = (apt['type'] ?? 'clinic').toString();
    final reason = apt['reason']?.toString().isEmpty ?? true
        ? 'Standard Session'
        : apt['reason'];
    final symptoms = apt['symptoms'] is List
        ? (apt['symptoms'] as List).join(', ')
        : 'None';

    // Payment info
    final fee = apt['consultationFee'] ?? apt['totalAmount'] ?? 0;
    final platformFee = apt['platformCommission'] ?? 0;
    final earning = apt['professionalEarning'] ?? 0;

    String formattedDate = '';
    try {
      if (apt['appointmentDate'] != null) {
        final d = DateTime.parse(apt['appointmentDate']);
        formattedDate = DateFormat('dd MMM yyyy').format(d);
      }
    } catch (_) {}

    final statusColor = status == 'confirmed' || status == 'accepted'
        ? AppTheme.physioAccent
        : status == 'pending'
        ? AppTheme.warning
        : status == 'cancelled'
        ? AppTheme.error
        : AppTheme.success;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(
          'Session Details',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status and Schedule Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Status',
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: GoogleFonts.manrope(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildInfoCol(
                        'Date',
                        formattedDate,
                        CupertinoIcons.calendar,
                      ),
                      _buildInfoCol(
                        'Time',
                        apt['startTime'] ?? '--',
                        CupertinoIcons.clock,
                      ),
                      _buildInfoCol(
                        'Type',
                        type.toUpperCase(),
                        type == 'home'
                            ? CupertinoIcons.house
                            : Icons.local_hospital_outlined,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Patient Info
            Text(
              'Patient Information',
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: AppTheme.physioGradient,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            patientName[0],
                            style: GoogleFonts.manrope(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              patientName,
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              '$patientGender, $patientAge years',
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          _loadingChat
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.physioAccent,
                                    ),
                                  ),
                                )
                              : IconButton(
                                  onPressed: () => _openInAppChat(
                                    patientIdStr,
                                    patientName,
                                    appointmentId,
                                  ),
                                  icon: const Icon(
                                    CupertinoIcons.chat_bubble_2,
                                    color: AppTheme.physioAccent,
                                  ),
                                ),
                          IconButton(
                            onPressed: () => _makePhoneCall(patientPhone),
                            icon: const Icon(
                              CupertinoIcons.phone,
                              color: AppTheme.physioAccent,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1),
                  ),
                  _buildDetailRow('Reason', reason),
                  const SizedBox(height: 8),
                  _buildDetailRow('Symptoms', symptoms),

                  if (type == 'home' &&
                      (apt['address'] != null || patient is Map)) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 24),
                    Text(
                      'Service Location',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => _openMaps(apt),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.physioAccent.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.physioAccent.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              CupertinoIcons.location_solid,
                              color: AppTheme.physioAccent,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    apt['address'] ?? 'Tap to view address',
                                    style: GoogleFonts.manrope(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.physioAccent,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Tap to view on Google Maps',
                                    style: GoogleFonts.manrope(
                                      fontSize: 11,
                                      color: AppTheme.physioAccent.withValues(
                                        alpha: 0.7,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              CupertinoIcons.arrow_branch,
                              color: AppTheme.physioAccent,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Therapy Plan / Prescription
            if (status == 'completed' ||
                status == 'confirmed' ||
                status == 'accepted' ||
                status == 'in_progress') ...[
              Text(
                'Therapy Plan',
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              if (_loadingPrescription)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(
                      color: AppTheme.physioAccent,
                    ),
                  ),
                )
              else if (_prescription != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            CupertinoIcons.waveform_path,
                            color: AppTheme.physioAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Active Exercise Plan',
                              style: GoogleFonts.manrope(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.physioAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_prescription!['exercises'] != null &&
                          (_prescription!['exercises'] as List).isNotEmpty) ...[
                        ...(_prescription!['exercises'] as List).map((ex) {
                          final name = ex['name'] ?? 'Exercise';
                          final reps = ex['reps']?.toString() ?? '--';
                          final sets = ex['sets']?.toString() ?? '--';
                          final duration = ex['duration'] ?? '--';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: GoogleFonts.manrope(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    _buildMetric('Sets', sets),
                                    const SizedBox(width: 12),
                                    _buildMetric('Reps', reps),
                                    const SizedBox(width: 12),
                                    _buildMetric('Time', duration),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PrescriptionDetailsScreen(
                                  prescription: _prescription!,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(CupertinoIcons.eye, size: 16),
                          label: Text(
                            'Full Details',
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.physioAccent,
                            side: const BorderSide(
                              color: AppTheme.physioAccent,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          CupertinoIcons.doc,
                          size: 40,
                          color: AppTheme.textTertiary.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No Therapy Plan Written',
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final result = await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CreatePrescriptionScreen(
                                  initialPatientId: patientIdStr,
                                  initialPatientName: patientName,
                                  initialAppointmentId: appointmentId,
                                ),
                              ),
                            );
                            if (result == true) _loadPrescription();
                          },
                          icon: const Icon(CupertinoIcons.pencil, size: 16),
                          label: Text(
                            'Create Plan',
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.physioAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 20),
            ],

            // Payment Details
            Text(
              'Payment Summary',
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                children: [
                  _buildDetailRow('Session Fee', '₹$fee'),
                  const SizedBox(height: 8),
                  _buildDetailRow(
                    'Platform Fee',
                    '- ₹$platformFee',
                    valueColor: AppTheme.error,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1),
                  ),
                  _buildDetailRow(
                    'Estimated Earning',
                    '₹$earning',
                    valueColor: AppTheme.success,
                    valueWeight: FontWeight.w700,
                    valueSize: 16,
                  ),
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
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (status == 'pending') ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _changeStatus('rejected'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: const BorderSide(color: AppTheme.error),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Reject Session',
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _changeStatus('accepted'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.physioAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Accept session',
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ] else if (status == 'confirmed' || status == 'accepted') ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: _cancelSession,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: const BorderSide(color: AppTheme.error),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Cancel Session',
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _openConsultation,
                  icon: const Icon(Icons.medical_services_outlined, size: 18),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.physioAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  label: Text(
                    'Consult',
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ] else if (status == 'in_progress') ...[
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _openConsultation,
                  icon: const Icon(Icons.medical_services_outlined, size: 18),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.physioAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  label: Text(
                    'Continue Consultation',
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
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
        Text(
          value,
          style: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 11,
            color: AppTheme.textTertiary,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    Color? valueColor,
    FontWeight? valueWeight,
    double? valueSize,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 13,
            color: AppTheme.textSecondary,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.manrope(
            fontSize: valueSize ?? 13,
            fontWeight: valueWeight ?? FontWeight.w500,
            color: valueColor ?? AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildMetric(String label, String value) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: GoogleFonts.manrope(
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.manrope(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}
