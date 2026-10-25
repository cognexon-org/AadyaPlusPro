import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/doctor_ui.dart';
import '../providers/physio_care_provider.dart';
import '../screens/physio_assessment_editor.dart';
import '../screens/physio_exercise_plan_editor.dart';
import '../screens/physio_patient_details.dart';
import 'physio_course_sheet.dart';

const _unlinkable = {'cancelled', 'rejected', 'no_show'};

/// The physio's part of a session's details: the patient's treatment course
/// (count this session in it, or start one), then exercises, assessment and
/// the patient's record.
class PhysioSessionCare extends ConsumerStatefulWidget {
  final Map<String, dynamic> appointment;
  const PhysioSessionCare({super.key, required this.appointment});

  @override
  ConsumerState<PhysioSessionCare> createState() => _PhysioSessionCareState();
}

class _PhysioSessionCareState extends ConsumerState<PhysioSessionCare> {
  bool _linking = false;

  Map<String, dynamic> get _a => widget.appointment;
  Map<String, dynamic> get _patient => apptPatient(_a);
  String get _patientId => refId(_a['patientId']);
  String get _apptId => '${_a['_id'] ?? ''}';

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(physioCoursesProvider.notifier).ensureLoaded();
    });
  }

  Future<void> _link(Map<String, dynamic> course) async {
    setState(() => _linking = true);
    try {
      await ref
          .read(physioCoursesProvider.notifier)
          .link('${course['_id']}', _apptId);
    } catch (e) {
      if (mounted) {
        showAppError(
          context,
          null,
          fallback: doctorError(e, fallback: 'Couldn’t count this session.'),
        );
      }
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  void _push(Widget screen) =>
      Navigator.of(context).push(AppPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final courses = ref.watch(physioCoursesProvider);
    final hasPatient = _patientId.isNotEmpty;
    final name = patientName(_a);
    final active = hasPatient ? courses.activeFor(_patientId) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionTitle('Care'),
        AppGroup(
          children: [
            if (hasPatient) ...[
              _courseRow(courses, active, name),
              const AppHairline(),
            ],
            _CareRow(
              icon: LucideIcons.dumbbell,
              title: 'Assign exercises',
              subtitle: 'Home programme with sets, reps and hold',
              onTap: !hasPatient
                  ? null
                  : () => _push(
                      PhysioExercisePlanEditor(
                        patientId: _patientId,
                        patientName: name,
                        appointmentId: _apptId,
                      ),
                    ),
            ),
            const AppHairline(),
            _CareRow(
              icon: LucideIcons.clipboardPlus,
              title: 'Record assessment',
              subtitle: 'Pain, range of motion, strength, scores',
              onTap: !hasPatient
                  ? null
                  : () => _push(
                      PhysioAssessmentEditor(
                        patientId: _patientId,
                        patientName: name,
                        appointmentId: _apptId,
                        courseId: active == null ? null : '${active['_id']}',
                      ),
                    ),
            ),
            const AppHairline(),
            _CareRow(
              icon: LucideIcons.userRound,
              title: 'Patient record',
              subtitle: 'Course, plans, progress and past sessions',
              onTap: !hasPatient
                  ? null
                  : () => _push(
                      PhysioPatientDetails(
                        patient: {..._patient, '_id': _patientId},
                      ),
                    ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _courseRow(
    PhysioCoursesState courses,
    Map<String, dynamic>? active,
    String name,
  ) {
    final accent = ModuleAccent.of(context).color;
    if (!courses.hasLoaded) {
      return _CareRow(
        icon: LucideIcons.layers,
        title: 'Treatment course',
        subtitle: courses.error ?? 'Checking…',
        subtitleColor: courses.error == null ? null : AppColors.error,
        onTap: courses.error == null
            ? null
            : () => ref.read(physioCoursesProvider.notifier).load(),
        trailing: courses.error == null
            ? const SizedBox.shrink()
            : Text(
                'Retry',
                style: AppType.sans(
                  fontSize: AppType.caption,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
      );
    }
    if (active == null) {
      return _CareRow(
        icon: LucideIcons.layers,
        title: 'Start a course',
        subtitle: 'Sell a package and count sessions against it',
        onTap: () => showStartCourseSheet(
          context,
          patientId: _patientId,
          patientName: name,
          patient: _patient,
        ),
      );
    }
    final used = courseUsed(active);
    final total = courseTotal(active);
    final paid = coursePayment(active) == 'paid';
    final money =
        '${appRupees(active['price'] ?? 0)} ${paid ? 'paid' : 'unpaid'}';
    final linked = courseHasAppointment(active, _a);
    final status = apptStatus(_a);
    final left = courseLeft(active);

    if (linked) {
      return _CareRow(
        icon: LucideIcons.circleCheck,
        title: 'Counted in ${courseTitle(active)}',
        subtitle: '$used of $total used · $money',
        subtitleColor: paid ? null : AppColors.warning,
        trailing: const SizedBox.shrink(),
      );
    }
    final canLink = !_unlinkable.contains(status) && left > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          Icon(LucideIcons.layers, size: 17, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  courseTitle(active),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.sans(
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  left == 0
                      ? 'No sessions left · $money'
                      : '$used of $total used · $money',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.sans(
                    fontSize: AppType.caption,
                    color: paid && left > 0
                        ? AppColors.textTertiary
                        : AppColors.warning,
                  ),
                ),
              ],
            ),
          ),
          if (canLink) ...[
            const SizedBox(width: 8),
            AppButton(
              label: 'Count session',
              compact: true,
              fullWidth: false,
              loading: _linking,
              onPressed: () => _link(active),
            ),
          ],
        ],
      ),
    );
  }
}

class _CareRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? subtitleColor;
  final VoidCallback? onTap;
  final Widget? trailing;
  const _CareRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.subtitleColor,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context).color;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            Icon(icon, size: 17, color: accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.sans(
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      color: subtitleColor ?? AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            trailing ??
                const Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: AppColors.textDisabled,
                ),
          ],
        ),
      ),
    );
  }
}
