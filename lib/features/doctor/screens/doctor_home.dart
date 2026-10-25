import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/ui/app_ui.dart';
import '../../auth/models/user_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../../notifications/widgets/notification_bell.dart';
import '../../pharmacy/providers/pharmacy_nav_provider.dart';
import '../providers/doctor_appointments_provider.dart';
import '../widgets/doctor_ui.dart';
import '../widgets/home_carousel.dart';
import 'doctor_appointments.dart';
import 'doctor_availability.dart';
import 'doctor_practice_settings.dart';
import 'doctor_prescriptions.dart';

/// The doctor's Today screen: who's now, what's waiting, how the day runs.
/// One quick action under "Quick actions": opens [page], or the
/// appointments tab when [page] is null.
typedef TodayQuickAction = ({IconData icon, String label, Widget? page});

/// The Today screen, shared by doctors and physiotherapists (same data —
/// the server scopes appointments by role). The defaults are the doctor's;
/// the physio module passes its own wording, details screen and actions.
class DoctorHome extends ConsumerStatefulWidget {
  /// "appointment" or "session".
  final String noun;

  /// How the signed-in name is shown in the header ("Dr. Ananya").
  final String Function(String rawName)? displayName;

  /// The screen an appointment opens.
  final Widget Function(Map<String, dynamic> appointment)? detailsBuilder;

  final List<TodayQuickAction>? quickActions;

  /// Feature slides under the requests; the doctor's by default.
  final List<HomeSlide>? slides;

  const DoctorHome({
    super.key,
    this.noun = 'appointment',
    this.displayName,
    this.detailsBuilder,
    this.quickActions,
    this.slides,
  });

  static const List<HomeSlide> doctorSlides = [
    (
      title: 'See patients by video',
      body: 'Turn on video visits and consult from anywhere.',
      cta: 'Set up',
      art: HomeSlideArt.video,
      page: DoctorPracticeSettings(),
      tab: null,
    ),
    (
      title: 'Prescriptions in seconds',
      body: 'Write, sign and send — the patient gets it instantly.',
      cta: 'Write one',
      art: HomeSlideArt.prescription,
      page: CreatePrescriptionScreen(),
      tab: null,
    ),
    (
      title: 'Open more slots',
      body: 'Add weekly hours so patients can book you sooner.',
      cta: 'Availability',
      art: HomeSlideArt.schedule,
      page: DoctorAvailability(),
      tab: null,
    ),
  ];

  @override
  ConsumerState<DoctorHome> createState() => _DoctorHomeState();
}

class _DoctorHomeState extends ConsumerState<DoctorHome> {
  final Set<String> _busy = {};
  bool _scrolled = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Keeps "in 12 min" and now/next honest without a reload.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _refresh() =>
      ref.read(doctorAppointmentsProvider.notifier).load(silent: true);

  void _open(Map<String, dynamic> a) => Navigator.of(context).push(
    AppPageRoute(
      builder: (_) =>
          widget.detailsBuilder?.call(a) ??
          AppointmentDetailsScreen(appointment: a),
    ),
  );

  void _push(Widget page) =>
      Navigator.of(context).push(AppPageRoute(builder: (_) => page));

  void _goToAppointments() =>
      ref.read(pharmacyTabRequestProvider.notifier).state = 1;

  void _openSlide(HomeSlide s) {
    if (s.page != null) {
      _push(s.page!);
    } else if (s.tab != null) {
      ref.read(pharmacyTabRequestProvider.notifier).state = s.tab;
    }
  }

  Future<void> _accept(Map<String, dynamic> a) async {
    final id = '${a['_id']}';
    setState(() => _busy.add(id));
    try {
      await ref.read(doctorAppointmentsProvider.notifier).accept(id);
      _toast('Accepted — ${patientName(a)} is on your schedule');
    } catch (e) {
      _toast(doctorError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppType.sans(fontSize: AppType.caption, color: Colors.white),
        ),
        backgroundColor: error ? AppColors.error : AppColors.textStrong,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(doctorAppointmentsProvider);
    final user = ref.watch(authProvider.select((s) => s.user));
    final accent = ModuleAccent.of(context);
    final today = state.today;
    final remaining = today
        .where(
          (a) => const {'confirmed', 'in_progress'}.contains(apptStatus(a)),
        )
        .length;
    final next = state.nowOrNext;
    final requests = state.requests;

    var i = 0;
    Widget enter(Widget c) => AppEntrance(index: i++, child: c);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _header(user, today.length, remaining, accent),
            AnimatedContainer(
              duration: AppMotion.fast,
              height: 1,
              color: _scrolled ? AppColors.border : Colors.transparent,
            ),
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  final s = n.metrics.pixels > 4;
                  if (s != _scrolled) setState(() => _scrolled = s);
                  return false;
                },
                child: RefreshIndicator(
                  color: accent.color,
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    children: [
                      if (user != null &&
                          user.verificationStatus !=
                              VerificationStatus.approved)
                        enter(
                          _VerificationNote(status: user.verificationStatus),
                        ),
                      if (state.error != null && !state.hasLoaded)
                        AppErrorBanner(message: state.error!, onRetry: _refresh)
                      else if (state.isLoading && !state.hasLoaded)
                        const AppListSkeleton(count: 3)
                      else ...[
                        enter(
                          _NowNextCard(
                            appointment: next,
                            onOpen: _open,
                            noun: widget.noun,
                          ),
                        ),
                        if (requests.isNotEmpty) ...[
                          const SizedBox(height: 22),
                          enter(
                            AppSectionTitle(
                              requests.length == 1
                                  ? '1 request waiting'
                                  : '${requests.length} requests waiting',
                              action: requests.length > 2 ? 'See all' : null,
                              onAction: _goToAppointments,
                            ),
                          ),
                          for (final a in requests.take(2))
                            enter(
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: DoctorAppointmentCard(
                                  appointment: a,
                                  showDay: true,
                                  onTap: () => _open(a),
                                  actions: AppButton(
                                    label: 'Accept',
                                    icon: LucideIcons.check,
                                    compact: true,
                                    loading: _busy.contains('${a['_id']}'),
                                    onPressed: _busy.contains('${a['_id']}')
                                        ? null
                                        : () => _accept(a),
                                  ),
                                ),
                              ),
                            ),
                        ],
                        const SizedBox(height: 22),
                        enter(
                          HomeCarousel(
                            slides: widget.slides ?? DoctorHome.doctorSlides,
                            onOpen: _openSlide,
                          ),
                        ),
                        const SizedBox(height: 22),
                        enter(
                          AppSectionTitle(
                            today.isEmpty
                                ? 'Today'
                                : 'Today · ${today.length} ${widget.noun}${today.length == 1 ? '' : 's'}',
                            action: 'Schedule',
                            onAction: _goToAppointments,
                          ),
                        ),
                        if (today.isEmpty)
                          enter(
                            AppEmptyState(
                              icon: LucideIcons.calendarCheck,
                              text: 'No ${widget.noun}s today.',
                            ),
                          )
                        else
                          for (final a in today)
                            enter(
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: DoctorAppointmentCard(
                                  appointment: a,
                                  onTap: () => _open(a),
                                ),
                              ),
                            ),
                        const SizedBox(height: 22),
                        enter(const AppSectionTitle('This week')),
                        enter(_WeekCard(state: state)),
                        const SizedBox(height: 22),
                        enter(const AppSectionTitle('Quick actions')),
                        enter(
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              for (final q
                                  in widget.quickActions ??
                                      const <TodayQuickAction>[
                                        (
                                          icon: LucideIcons.filePlus2,
                                          label: 'New Rx',
                                          page: CreatePrescriptionScreen(),
                                        ),
                                        (
                                          icon: LucideIcons.fileText,
                                          label: 'All Rx',
                                          page: DoctorPrescriptions(),
                                        ),
                                        (
                                          icon: LucideIcons.clock,
                                          label: 'Availability',
                                          page: DoctorAvailability(),
                                        ),
                                        (
                                          icon: LucideIcons.calendarDays,
                                          label: 'Schedule',
                                          page: null,
                                        ),
                                      ])
                                _QuickAction(
                                  icon: q.icon,
                                  label: q.label,
                                  onTap: q.page == null
                                      ? _goToAppointments
                                      : () => _push(q.page!),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(
    UserModel? user,
    int todayCount,
    int remaining,
    ModuleAccent accent,
  ) {
    final raw = (user?.name ?? '').trim();
    final name =
        widget.displayName?.call(raw) ??
        (raw.isEmpty
            ? 'Doctor'
            : raw.toLowerCase().startsWith('dr')
            ? raw
            : 'Dr. ${raw.split(' ').first}');
    final line = todayCount == 0
        ? 'No ${widget.noun}s today'
        : remaining == 0
        ? 'All $todayCount done for today'
        : '$remaining of $todayCount still to see';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.sans(
                    fontSize: AppType.heading,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textStrong,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$line · ${DateFormat('EEE d MMM').format(DateTime.now())}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.sans(
                    fontSize: AppType.caption,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          NotificationBell(color: accent.color),
        ],
      ),
    );
  }
}

/// The patient being seen now, or next today — the one decision the doctor
/// makes most often from this screen.
class _NowNextCard extends StatelessWidget {
  final Map<String, dynamic>? appointment;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final String noun;
  const _NowNextCard({
    required this.appointment,
    required this.onOpen,
    required this.noun,
  });

  Future<void> _navigate(Map<String, dynamic> a) async {
    final loc = a['location'];
    Uri? uri;
    if (loc is Map && loc['coordinates'] is List) {
      final c = loc['coordinates'] as List;
      if (c.length == 2) {
        uri = Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=${c[1]},${c[0]}',
        );
      }
    }
    final address = '${a['address'] ?? ''}'.trim();
    uri ??= address.isEmpty
        ? null
        : Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(address)}',
          );
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    final a = appointment;
    if (a == null) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: accent.veryLight,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.light,
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.coffee, color: accent.color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You’re clear for now',
                    style: AppType.sans(
                      fontSize: AppType.title,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textStrong,
                    ),
                  ),
                  Text(
                    'No more ${noun}s scheduled today.',
                    style: AppType.sans(
                      fontSize: AppType.small,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final start = apptStart(a);
    final live = apptStatus(a) == 'in_progress';
    final mins = start?.difference(DateTime.now()).inMinutes;
    final when = live
        ? (noun == 'session' ? 'In session' : 'In consultation')
        : mins == null
        ? 'Next'
        : mins <= 0
        ? 'Due now'
        : mins < 60
        ? 'Next · in $mins min'
        : 'Next · ${timeLabel(start)}';

    return AppPressable(
      scale: 0.985,
      onTap: () => onOpen(a),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accent.color,
              Color.lerp(accent.color, Colors.black, 0.18)!,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (live) ...[
                  const AppPulse(color: Colors.white),
                  const SizedBox(width: 8),
                ],
                Text(
                  when,
                  style: AppType.sans(
                    fontSize: AppType.small,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const Spacer(),
                Text(
                  timeLabel(start),
                  style: AppType.sans(
                    fontSize: AppType.small,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              patientName(a),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.sans(
                fontSize: AppType.figure,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              [
                apptTypeInfo(apptType(a)).label,
                if ((a['symptoms'] is List) &&
                    (a['symptoms'] as List).isNotEmpty)
                  (a['symptoms'] as List).map((e) => '$e').join(', '),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.sans(
                fontSize: AppType.small,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
            if (apptType(a) == 'home' &&
                '${a['address'] ?? ''}'.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.mapPin,
                    size: 13,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      '${a['address']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.sans(
                        fontSize: AppType.caption,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        apptType(a) == 'video'
                            ? LucideIcons.video
                            : LucideIcons.stethoscope,
                        size: 15,
                        color: accent.color,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        live ? 'Continue' : 'Open',
                        style: AppType.sans(
                          fontSize: AppType.small,
                          fontWeight: FontWeight.w700,
                          color: accent.color,
                        ),
                      ),
                    ],
                  ),
                ),
                if (apptType(a) == 'home') ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _navigate(a),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            LucideIcons.navigation,
                            size: 15,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Navigate',
                            style: AppType.sans(
                              fontSize: AppType.small,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Last seven days as bars (labelled with their real weekdays) plus the
/// numbers a doctor actually tracks.
class _WeekCard extends StatelessWidget {
  final DoctorAppointmentsState state;
  const _WeekCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    final days = state.lastSevenDays;
    final total = days.fold<int>(0, (s, v) => s + v);
    final maxY = (days.fold<int>(0, (m, v) => v > m ? v : m)).toDouble();
    final now = DateTime.now();
    final seen = state.all.where((a) {
      final d = apptStart(a);
      return apptStatus(a) == 'completed' &&
          d != null &&
          now.difference(d).inDays < 7;
    }).length;
    final noShows = state.all.where((a) {
      final d = apptStart(a);
      return apptStatus(a) == 'no_show' &&
          d != null &&
          now.difference(d).inDays < 7;
    }).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _Figure(label: 'Booked', value: total),
              _Figure(label: 'Seen', value: seen),
              _Figure(label: 'Upcoming', value: state.upcoming.length),
              _Figure(label: 'No-shows', value: noShows, warn: noShows > 0),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 84,
            child: BarChart(
              BarChartData(
                maxY: maxY < 4 ? 4 : maxY + 1,
                alignment: BarChartAlignment.spaceAround,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  topTitles: const AxisTitles(),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 18,
                      getTitlesWidget: (v, _) {
                        final d = now.subtract(Duration(days: 6 - v.toInt()));
                        return Text(
                          v.toInt() == 6
                              ? 'Today'
                              : DateFormat('E').format(d)[0],
                          style: AppType.sans(
                            fontSize: AppType.micro,
                            fontWeight: v.toInt() == 6
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: v.toInt() == 6
                                ? accent.color
                                : AppColors.textTertiary,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var x = 0; x < 7; x++)
                    BarChartGroupData(
                      x: x,
                      barRods: [
                        BarChartRodData(
                          toY: days[x].toDouble(),
                          width: 16,
                          color: x == 6 ? accent.color : accent.light,
                          borderRadius: BorderRadius.circular(5),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: maxY < 4 ? 4 : maxY + 1,
                            color: AppColors.bg,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final int value;
  final bool warn;
  const _Figure({required this.label, required this.value, this.warn = false});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCountUp(
          value: value.toDouble(),
          format: (v) => v.round().toString(),
          style: AppType.sans(
            fontSize: AppType.figure,
            fontWeight: FontWeight.w800,
            color: warn ? AppColors.warning : AppColors.textStrong,
          ),
        ),
        Text(
          label,
          style: AppType.sans(
            fontSize: AppType.caption,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    ),
  );
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    return AppPressable(
      onTap: onTap,
      semanticLabel: label,
      child: SizedBox(
        width: 72,
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.veryLight,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: accent.color),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.sans(
                fontSize: AppType.caption,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerificationNote extends StatelessWidget {
  final VerificationStatus status;
  const _VerificationNote({required this.status});

  @override
  Widget build(BuildContext context) {
    final rejected =
        status == VerificationStatus.rejected ||
        status == VerificationStatus.suspended;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: rejected ? AppColors.errorBg : AppColors.warningBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            rejected ? LucideIcons.shieldAlert : LucideIcons.shieldEllipsis,
            size: 17,
            color: rejected ? AppColors.error : AppColors.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              rejected
                  ? 'Your verification needs attention. Patients can’t book you until it’s resolved — check Profile.'
                  : 'Your registration is being verified (usually 24–48 hours). Patients can book you once it’s approved.',
              style: AppType.sans(
                fontSize: AppType.small,
                height: 1.4,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
