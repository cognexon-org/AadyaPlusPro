import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/availability_day_sheet.dart';
import '../../doctor/widgets/availability_model.dart';
import '../../doctor/widgets/availability_save_bar.dart';
import '../../doctor/widgets/doctor_ui.dart';
import '../providers/physio_profile_provider.dart';

/// The physio's weekly hours — the one place to set when patients can book.
/// Same editor as the doctor's.
///
/// There is no GET availability endpoint for a physio: the week comes from
/// the profile (GET /physio/me/profile) and is saved whole with
/// PUT /physio/me/availability.
class PhysioAvailability extends ConsumerStatefulWidget {
  const PhysioAvailability({super.key});

  @override
  ConsumerState<PhysioAvailability> createState() => _PhysioAvailabilityState();
}

class _PhysioAvailabilityState extends ConsumerState<PhysioAvailability> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  Map<String, AvailabilityDay> _initial = parseWeek(null);
  Map<String, AvailabilityDay> _week = parseWeek(null);

  /// Types switched on in practice settings; null if unknown.
  Set<String>? _enabledTypes;
  int? _slotMinutes;

  bool get _dirty => !_loading && _error == null && !sameWeek(_initial, _week);

  @override
  void initState() {
    super.initState();
    // After the first frame's build: loading updates the provider.
    Future.microtask(_load);
  }

  Future<void> _load({bool force = false}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final notifier = ref.read(physioProfileProvider.notifier);
    await (force ? notifier.load(silent: true) : notifier.ensureLoaded());
    if (!mounted) return;
    final st = ref.read(physioProfileProvider);
    // A failed refresh keeps the last good profile; only a profile that was
    // never read blocks the grid.
    if (!st.hasLoaded || st.profile.isEmpty) {
      setState(() {
        _loading = false;
        _error = st.error ?? "Couldn't load your hours.";
      });
      return;
    }
    final p = st.profile;
    final week = parseWeek(p['availability']);
    setState(() {
      _initial = week;
      _week = week;
      _enabledTypes = {
        if (p['clinicConsultationEnabled'] != false) 'clinic',
        if (_typeOn(p, 'homeVisitEnabled', 'homeVisitFee')) 'home',
        if (_typeOn(p, 'teleconsultationEnabled', 'videoCallFee')) 'video',
      };
      _slotMinutes = int.tryParse('${p['slotDurationMinutes'] ?? ''}');
      _loading = false;
    });
  }

  /// The server's rule: on when switched on, or never set but priced.
  static bool _typeOn(Map<String, dynamic> p, String flag, String fee) {
    final v = p[flag];
    return v == true ||
        (v == null && (num.tryParse('${p[fee] ?? ''}') ?? 0) > 0);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(physioProfileProvider.notifier)
          .saveAvailability(weekToJson(_week));
      if (!mounted) return;
      setState(() {
        _saving = false;
        _initial = _week;
      });
      doctorToast(context, 'Hours saved');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      doctorToast(
        context,
        doctorError(e, fallback: "Couldn't save your hours."),
        error: true,
      );
    }
  }

  Future<void> _editDay(String day) async {
    final current = _week[day] ?? const AvailabilityDay();
    final result = await showAvailabilityDaySheet(
      context,
      day: day,
      blocks: current.blocks,
    );
    if (result == null || !mounted) return;
    setState(() {
      _week = {
        ..._week,
        day: AvailabilityDay(enabled: result.isNotEmpty, blocks: result),
      };
    });
  }

  void _toggleDay(String day, bool on) {
    final current = _week[day] ?? const AvailabilityDay();
    // Turning on a day with nothing in it: ask for the hours rather than
    // switching on an empty day that patients still can't book.
    if (on && current.blocks.isEmpty) {
      _editDay(day);
      return;
    }
    setState(() => _week = {..._week, day: current.copyWith(enabled: on)});
  }

  void _copyMonday() {
    final monday = _week['monday'] ?? const AvailabilityDay();
    if (!monday.isOpen) {
      doctorToast(context, 'Set Monday’s hours first.');
      return;
    }
    setState(() {
      _week = {
        ..._week,
        for (final d in const ['tuesday', 'wednesday', 'thursday', 'friday'])
          d: AvailabilityDay(enabled: true, blocks: [...monday.blocks]),
      };
    });
    doctorToast(context, 'Monday’s hours copied to Tuesday – Friday');
  }

  @override
  Widget build(BuildContext context) {
    return DoctorDiscardGuard(
      dirty: _dirty,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: doctorSettingsAppBar('Availability'),
        body: SafeArea(top: false, child: _body()),
        bottomNavigationBar: doctorSaveBar(
          dirty: _dirty,
          saving: _saving,
          onSave: _save,
          label: 'Save hours',
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: AppListSkeleton(count: 7),
      );
    }
    if (_error != null) {
      // No grid on a failed load: saving over hours we never read would
      // wipe the physio's real week.
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          AppErrorBanner(message: _error!, onRetry: () => _load(force: true)),
        ],
      );
    }
    return RefreshIndicator(
      color: ModuleAccent.of(context).color,
      onRefresh: () async {
        if (_dirty) return;
        await _load(force: true);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          AppEntrance(child: _summary()),
          ..._typeWarnings(),
          const SizedBox(height: 22),
          AppSectionTitle(
            'Weekly hours',
            action: 'Copy Monday to weekdays',
            onAction: _copyMonday,
          ),
          AppEntrance(
            index: 1,
            child: AppGroup(
              children: [
                for (final d in kWeekDays) ...[
                  if (d != kWeekDays.first) const AppHairline(),
                  _dayRow(d),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Tap a day to change its hours. Changes apply to new bookings; '
            'existing appointments stay as they are.',
            style: AppType.sans(
              fontSize: AppType.caption,
              height: 1.45,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary() {
    final minutes = weeklyMinutes(_week);
    final types = weeklyTypes(_week);
    final openDays = kWeekDays.where((d) => _week[d]?.isOpen ?? false).length;
    final detail = minutes == 0
        ? 'Patients can’t book you until you add some hours.'
        : [
            '$openDays ${openDays == 1 ? 'day' : 'days'}',
            '${types.length} visit ${types.length == 1 ? 'type' : 'types'}',
            if (_slotMinutes != null) '$_slotMinutes-min slots',
          ].join(' · ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            minutes == 0 ? 'No hours set' : '${hoursLabel(minutes)} a week',
            style: AppType.sans(
              fontSize: AppType.figure,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: minutes == 0 ? AppColors.warning : AppColors.textStrong,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            detail,
            style: AppType.sans(
              fontSize: AppType.caption,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// A block for a type that is switched off in practice settings can never
  /// be booked — say so instead of letting the physio wonder.
  List<Widget> _typeWarnings() {
    final enabled = _enabledTypes;
    if (enabled == null) return const [];
    final offered = <String>{
      for (final b
          in _week.values.where((d) => d.isOpen).expand((d) => d.blocks))
        if (b.type != 'all') b.type,
    };
    final off = offered.where((t) => !enabled.contains(t)).toList();
    if (off.isEmpty) return const [];
    final names = off.map((t) => apptTypeInfo(t).label.toLowerCase()).toList();
    final list = names.length == 1
        ? names.first
        : '${names.take(names.length - 1).join(', ')} and ${names.last}';
    return [
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              LucideIcons.triangleAlert,
              size: 15,
              color: AppColors.warning,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'Some hours are for $list, which is turned off in practice '
                'settings, so patients can’t book them.',
                style: AppType.sans(
                  fontSize: AppType.caption,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _dayRow(String day) {
    final d = _week[day] ?? const AvailabilityDay();
    final open = d.isOpen;
    return AppPressable(
      scale: 0.985,
      onTap: () => _editDay(day),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    weekDayLabel(day),
                    style: AppType.sans(
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w600,
                      color: open
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (!open)
                    Text(
                      d.blocks.isEmpty
                          ? 'Closed'
                          : 'Closed · ${d.blocks.length} '
                                '${d.blocks.length == 1 ? 'block' : 'blocks'} kept',
                      style: AppType.sans(
                        fontSize: AppType.caption,
                        color: AppColors.textTertiary,
                      ),
                    )
                  else
                    for (final b in d.blocks)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          blockLabel(b),
                          style: AppType.sans(
                            fontSize: AppType.caption,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                ],
              ),
            ),
            AppSwitch(value: open, onChanged: (v) => _toggleDay(day, v)),
          ],
        ),
      ),
    );
  }
}
