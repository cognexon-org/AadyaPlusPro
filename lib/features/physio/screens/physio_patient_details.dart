import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/screens/app_chat_screen.dart';
import '../../../core/network/api_service.dart';
import 'physio_exercise_plan_editor.dart';
import 'physio_exercise_plan_detail.dart';

class PhysioPatientDetails extends ConsumerStatefulWidget {
  final Map<String, dynamic> patient;

  const PhysioPatientDetails({super.key, required this.patient});

  @override
  ConsumerState<PhysioPatientDetails> createState() => _PhysioPatientDetailsState();
}

class _PhysioPatientDetailsState extends ConsumerState<PhysioPatientDetails> {
  final ApiService _api = ApiService();
  bool _loadingApts = true;
  List<Map<String, dynamic>> _appointments = [];
  bool _loadingPlans = true;
  List<Map<String, dynamic>> _plans = [];

  @override
  void initState() {
    super.initState();
    _fetchPatientAppointments();
    _fetchExercisePlans();
  }

  Future<void> _fetchPatientAppointments() async {
    final patientId = widget.patient['_id'] ?? widget.patient['patientId']?['_id'] ?? '';
    if (patientId.isEmpty) return;

    try {
      final res = await _api.getAppointmentsByPatient(patientId);
      if (res.data['success']) {
        final list = res.data['appointments'] as List? ?? [];
        _appointments = list.map((e) => Map<String, dynamic>.from(e)).toList();
        // Filter for this professional only
        final profile = ref.read(physioDashboardProvider).profile;
        final profId = profile['_id'];
        _appointments = _appointments.where((a) => a['physioId']?.toString() == profId?.toString()).toList();
      }
    } catch (e) {
      debugPrint('Error fetching patient apts: $e');
    } finally {
      if (mounted) setState(() => _loadingApts = false);
    }
  }

  String get _patientId => (widget.patient['_id'] ?? widget.patient['patientId']?['_id'] ?? '').toString();

  Future<void> _fetchExercisePlans() async {
    if (_patientId.isEmpty) {
      if (mounted) setState(() => _loadingPlans = false);
      return;
    }
    try {
      final res = await _api.getPhysioPatientExercisePlans(_patientId);
      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : <String, dynamic>{};
      final list = data['plans'] as List? ?? const [];
      if (mounted) {
        setState(() => _plans = list.map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    } catch (e) {
      debugPrint('Exercise plans error: $e');
    } finally {
      if (mounted) setState(() => _loadingPlans = false);
    }
  }

  Future<void> _createExercisePlan() async {
    if (_patientId.isEmpty) return;
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => PhysioExercisePlanEditor(
        patientId: _patientId,
        patientName: widget.patient['name']?.toString() ?? 'Patient',
        appointmentId: _appointments.isNotEmpty ? _appointments.first['_id']?.toString() : null,
      ),
    ));
    if (created == true) {
      setState(() => _loadingPlans = true);
      await _fetchExercisePlans();
    }
  }

  @override
  Widget build(BuildContext context) {
    final patient = widget.patient;
    final name = patient['name'] ?? 'Unknown Patient';
    final email = patient['email'] ?? 'No email';
    final phone = patient['phone'] ?? 'No phone';
    final age = patient['age']?.toString() ?? '--';
    final gender = patient['gender'] ?? '--';
    
    final chronicList = patient['chronicConditions'] as List? ?? [];
    final chronicConditions = chronicList.isEmpty ? 'No significant history' : chronicList.join(', ');
    
    final totalVisits = patient['totalVisits']?.toString() ?? _appointments.length.toString();
    final activeTreatments = _plans.where((p) => p['status'] == 'active').length.toString();

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: AppTheme.physioGradient),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      Container(
                        width: 80, height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20)]
                        ),
                        child: Center(child: Text(name[0].toUpperCase(), style: GoogleFonts.manrope(fontSize: 32, fontWeight: FontWeight.w800, color: AppTheme.physioAccent))),
                      ),
                      const SizedBox(height: 12),
                      Text(name, style: GoogleFonts.manrope(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                      Text(phone, style: GoogleFonts.manrope(fontSize: 14, color: Colors.white70)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stat Cards
                  Row(
                    children: [
                      _statCard('Total Visits', totalVisits, CupertinoIcons.calendar_badge_plus),
                      const SizedBox(width: 12),
                      _statCard('Active Plans', activeTreatments, CupertinoIcons.waveform_path),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // Medical Profile
                  _sectionHeader('Medical Profile', Icons.badge_outlined),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.border)),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _medicalItem('Age', age),
                            _medicalItem('Gender', gender),
                            _medicalItem('Blood Group', patient['bloodGroup'] ?? '--'),
                          ],
                        ),
                        const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1)),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _medicalItem('Height', '${patient['height'] ?? '--'} cm'),
                            _medicalItem('Weight', '${patient['weight'] ?? '--'} kg'),
                            _medicalItem('BMI', _calcBMI(patient['weight'], patient['height'])),
                          ],
                        ),
                        const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1)),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Conditions', style: GoogleFonts.manrope(fontSize: 12, color: AppTheme.textTertiary)),
                            const SizedBox(height: 4),
                            Text(chronicConditions, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _sectionHeader('Exercise Plans', CupertinoIcons.waveform_path),
                      TextButton.icon(
                        onPressed: _createExercisePlan,
                        icon: const Icon(CupertinoIcons.add, size: 17),
                        label: const Text('New Plan'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_loadingPlans)
                    const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: AppTheme.physioAccent)))
                  else if (_plans.isEmpty)
                    _emptyState('No exercise plan assigned yet')
                  else
                    ..._plans.map(_buildExercisePlanCard),
                  const SizedBox(height: 28),

                  // History Timeline
                  _sectionHeader('Session Timeline', CupertinoIcons.timer),
                  const SizedBox(height: 12),
                  if (_loadingApts)
                    const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: AppTheme.physioAccent)))
                  else if (_appointments.isEmpty)
                    _emptyState('No previous sessions found')
                  else
                    ..._appointments.map((a) => _buildTimelineItem(a)),
                  
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppTheme.physioAccent),
        const SizedBox(width: 8),
        Text(title, style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppTheme.border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppTheme.physioAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 20, color: AppTheme.physioAccent)),
            const SizedBox(height: 12),
            Text(label, style: GoogleFonts.manrope(fontSize: 12, color: AppTheme.textSecondary)),
            Text(value, style: GoogleFonts.manrope(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.physioAccent)),
          ],
        ),
      ),
    );
  }

  Widget _medicalItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.manrope(fontSize: 11, color: AppTheme.textTertiary)),
        const SizedBox(height: 2),
        Text(value, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
      ],
    );
  }

  Widget _buildExercisePlanCard(Map<String, dynamic> plan) {
    final exercises = plan['exercises'] as List? ?? const [];
    final status = (plan['status'] ?? 'active').toString();
    final statusColor = status == 'completed' ? AppTheme.success : status == 'cancelled' ? AppTheme.textTertiary : AppTheme.physioAccent;
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PhysioExercisePlanDetail(planId: plan['_id'].toString()),
      )).then((_) => _fetchExercisePlans()),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: statusColor.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
            child: Icon(CupertinoIcons.waveform_path, color: statusColor),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(plan['title'] ?? 'Exercise plan', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            const SizedBox(height: 3),
            Text('${exercises.length} exercises • ${status.toUpperCase()}', style: GoogleFonts.manrope(fontSize: 12, color: statusColor)),
          ])),
          const Icon(CupertinoIcons.chevron_right, size: 18, color: AppTheme.textTertiary),
        ]),
      ),
    );
  }

  Widget _buildTimelineItem(Map<String, dynamic> apt) {
    final date = DateTime.tryParse(apt['appointmentDate']?.toString() ?? '') ?? DateTime.now();
    final status = apt['status']?.toString().toUpperCase() ?? 'PENDING';
    final type = apt['type']?.toString().toUpperCase() ?? 'CLINIC';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
      child: Row(
        children: [
          Column(
            children: [
              Text(DateFormat('dd').format(date), style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
              Text(DateFormat('MMM').format(date).toUpperCase(), style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.physioAccent)),
            ],
          ),
          const SizedBox(width: 16),
          const VerticalDivider(width: 1, thickness: 1),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(type, style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textTertiary)),
                    const SizedBox(width: 8),
                    Container(width: 4, height: 4, decoration: const BoxDecoration(color: AppTheme.border, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(status, style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, color: status == 'COMPLETED' ? AppTheme.success : AppTheme.warning)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(apt['therapyType'] ?? 'Physiotherapy Session', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                Text('${apt['startTime']} - ${apt['endTime']}', style: GoogleFonts.manrope(fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _openAptChat(apt),
            icon: const Icon(CupertinoIcons.chat_bubble_2, color: AppTheme.physioAccent, size: 22),
          ),
        ],
      ),
    );
  }

  Future<void> _openAptChat(Map<String, dynamic> apt) async {
    final patientId = widget.patient['_id'] ?? widget.patient['patientId']?['_id'] ?? '';
    final name = widget.patient['name'] ?? 'Patient';
    final profile = ref.read(physioDashboardProvider).profile;
    final profId = profile['_id'];

    if (patientId.isEmpty || profId == null) return;

    try {
      final res = await _api.getOrCreateChatSession({
        'patientId': patientId,
        'appointmentId': apt['_id'], // Pass the specific appointment ID
      });

      if (res.data['success']) {
        final session = res.data['session'];
        if (mounted) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AppChatScreen(
              sessionId: session['_id'],
              patientName: name,
              patientId: patientId,
              professionalId: profId,
              professionalType: 'physio',
            ),
          ));
        }
      }
    } catch (e) {
      debugPrint('Chat error: $e');
    }
  }

  Widget _emptyState(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
      child: Column(children: [
        Icon(CupertinoIcons.folder_open, size: 40, color: AppTheme.textTertiary.withValues(alpha: 0.3)),
        const SizedBox(height: 12),
        Text(text, style: GoogleFonts.manrope(color: AppTheme.textTertiary, fontSize: 13)),
      ]),
    );
  }

  String _calcBMI(dynamic w, dynamic h) {
    if (w is num && h is num && h > 0) {
      final bmi = w / ((h / 100) * (h / 100));
      return bmi.toStringAsFixed(1);
    }
    return '--';
  }
}
