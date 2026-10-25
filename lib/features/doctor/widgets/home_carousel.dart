import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';

/// The small animated scene drawn on the right of a slide.
enum HomeSlideArt {
  // Doctor
  video,
  prescription,
  schedule,
  // Physio
  exercise,
  packages,
  recovery,
  // Pathology
  tubes,
  labReport,
  // Pharmacy
  orders,
  stock,
  coupon,
}

/// One slide on a Home/Today screen: a feature worth using, and where to set
/// it up — [page] to push, or a dashboard [tab] to switch to.
typedef HomeSlide = ({
  String title,
  String body,
  String cta,
  HomeSlideArt art,
  Widget? page,
  int? tab,
});

/// Feature slides, drawn and animated in code (no image or Lottie assets):
/// sharp at any density, in the module's accent, free to download. The
/// carousel advances every few seconds and pauses while touched; only the
/// slide on screen animates, and everything holds still when the system asks
/// for reduced motion.
class HomeCarousel extends StatefulWidget {
  final List<HomeSlide> slides;
  final ValueChanged<HomeSlide> onOpen;
  const HomeCarousel({super.key, required this.slides, required this.onOpen});

  @override
  State<HomeCarousel> createState() => _HomeCarouselState();
}

class _HomeCarouselState extends State<HomeCarousel> {
  static const _interval = Duration(seconds: 6);

  final _controller = PageController();
  Timer? _timer;
  int _page = 0;
  bool _touching = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timer?.cancel();
    if (widget.slides.length > 1 && !MediaQuery.of(context).disableAnimations) {
      _timer = Timer.periodic(_interval, (_) => _advance());
    }
  }

  void _advance() {
    if (_touching || !_controller.hasClients || !mounted) return;
    final next = (_page + 1) % widget.slides.length;
    _controller.animateToPage(
      next,
      duration: AppMotion.slow,
      curve: AppMotion.enter,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context).color;
    return Column(
      children: [
        SizedBox(
          height: 152,
          child: Listener(
            onPointerDown: (_) => _touching = true,
            onPointerUp: (_) => _touching = false,
            onPointerCancel: (_) => _touching = false,
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.slides.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _Slide(
                  slide: widget.slides[i],
                  accent: accent,
                  active: i == _page,
                  onTap: () => widget.onOpen(widget.slides[i]),
                ),
              ),
            ),
          ),
        ),
        if (widget.slides.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.slides.length; i++)
                AnimatedContainer(
                  duration: AppMotion.medium,
                  curve: AppMotion.enter,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page ? accent : AppColors.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Slide extends StatelessWidget {
  final HomeSlide slide;
  final Color accent;
  final bool active;
  final VoidCallback onTap;
  const _Slide({
    required this.slide,
    required this.accent,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final deep = Color.lerp(accent, Colors.black, 0.28)!;
    return Semantics(
      button: true,
      label: '${slide.title}. ${slide.body}',
      child: Material(
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accent, deep],
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                // Soft rings behind the art, for depth.
                Positioned(right: -40, top: -50, child: _ring(180, 0.07)),
                Positioned(right: 40, bottom: -70, child: _ring(130, 0.06)),
                Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 6, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              slide.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.sans(
                                fontSize: AppType.heading,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              slide.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.sans(
                                fontSize: AppType.caption,
                                color: Colors.white.withValues(alpha: 0.86),
                                height: 1.35,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.fromLTRB(12, 6, 9, 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    slide.cta,
                                    style: AppType.sans(
                                      fontSize: AppType.small,
                                      fontWeight: FontWeight.w700,
                                      color: deep,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    LucideIcons.arrowRight,
                                    size: 14,
                                    color: deep,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 128,
                      height: double.infinity,
                      child: Center(
                        child: _AnimatedArt(
                          art: slide.art,
                          accent: accent,
                          active: active,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ring(double size, double alpha) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: Colors.white.withValues(alpha: alpha * 2),
        width: 18,
      ),
    ),
  );
}

/// Runs the scene's loop while its slide is on screen.
class _AnimatedArt extends StatefulWidget {
  final HomeSlideArt art;
  final Color accent;
  final bool active;
  const _AnimatedArt({
    required this.art,
    required this.accent,
    required this.active,
  });

  @override
  State<_AnimatedArt> createState() => _AnimatedArtState();
}

class _AnimatedArtState extends State<_AnimatedArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );

  bool get _shouldRun =>
      widget.active && !MediaQuery.of(context).disableAnimations;

  void _sync() {
    if (_shouldRun) {
      if (!_loop.isAnimating) _loop.repeat();
    } else {
      _loop.stop();
      // The finished picture, so a still scene still tells its story.
      _loop.value = HomeArtFrame.rest;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_AnimatedArt old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: _loop,
      builder: (_, _) =>
          HomeArtFrame(art: widget.art, accent: widget.accent, t: _loop.value),
    ),
  );
}

// ── Scenes ────────────────────────────────────────────────────────────────
// White shapes on the accent gradient with accent details, each in a
// 116 × 116 box, drawn for a loop position t ∈ [0, 1). Every scene builds up
// over the loop, holds its finished state around [rest], and resets in the
// last few percent so the loop restarts cleanly.

/// One frame of a slide's scene. Public so previews can render a strip of
/// frames; the carousel drives it through [_AnimatedArt].
class HomeArtFrame extends StatelessWidget {
  final HomeSlideArt art;
  final Color accent;
  final double t;
  const HomeArtFrame({
    super.key,
    required this.art,
    required this.accent,
    required this.t,
  });

  /// Loop position where every scene shows its complete picture.
  static const rest = 0.92;

  @override
  Widget build(BuildContext context) {
    final s = _Kit(accent, t);
    return SizedBox(
      width: 116,
      height: 116,
      child: switch (art) {
        HomeSlideArt.video => _video(s),
        HomeSlideArt.prescription => _prescription(s),
        HomeSlideArt.schedule => _schedule(s),
        HomeSlideArt.exercise => _exercise(s),
        HomeSlideArt.packages => _packages(s),
        HomeSlideArt.recovery => _recovery(s),
        HomeSlideArt.tubes => _tubes(s),
        HomeSlideArt.labReport => _labReport(s),
        HomeSlideArt.orders => _orders(s),
        HomeSlideArt.stock => _stock(s),
        HomeSlideArt.coupon => _coupon(s),
      },
    );
  }

  // ── Doctor ──────────────────────────────────────────────────────────────

  /// A phone on a video call: the phone floats, the patient "speaks" (a
  /// ring pulses out from the avatar) and the Live dot blinks.
  Widget _video(_Kit s) {
    final speak = s.wave(2);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 22,
          top: 4 + s.bob(3),
          child: Transform.rotate(
            angle: -0.06,
            child: s.card(
              w: 72,
              h: 108,
              radius: 16,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Color.lerp(accent, Colors.white, 0.82),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Center(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 34 + 16 * speak,
                                height: 34 + 16 * speak,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: accent.withValues(
                                    alpha: 0.28 * (1 - speak),
                                  ),
                                ),
                              ),
                              CircleAvatar(
                                radius: 17,
                                backgroundColor: accent,
                                child: const Icon(
                                  LucideIcons.userRound,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _callDot(
                          LucideIcons.mic,
                          Color.lerp(
                            AppColors.textSecondary,
                            AppColors.success,
                            s.wave(2),
                          )!,
                        ),
                        _callDot(LucideIcons.phoneOff, AppColors.error),
                        _callDot(LucideIcons.video, AppColors.textSecondary),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 12,
          child: s.chip(
            'Live',
            lead: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(
                  alpha: 0.35 + 0.65 * s.wave(1.5),
                ),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _callDot(IconData icon, Color color) => Container(
    width: 16,
    height: 16,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, size: 9, color: color),
  );

  /// The prescription writes itself: lines draw in as the pen moves along
  /// them, then a tick pops in.
  Widget _prescription(_Kit s) {
    final lines = [
      (w: 48.0, p: s.seg(0.05, 0.24)),
      (w: 36.0, p: s.seg(0.26, 0.42)),
      (w: 44.0, p: s.seg(0.44, 0.62)),
    ];
    // Pen sits at the tip of whichever line is being written.
    var penX = 0.0, penY = 0.0;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].p > 0 && (lines[i].p < 1 || i == lines.length - 1)) {
        penX = lines[i].w * lines[i].p;
        penY = i * 10.0;
      }
    }
    final tick = s.pop(0.66, 0.8);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 26,
          top: 8,
          child: Transform.rotate(
            angle: 0.1,
            child: s.card(
              w: 70,
              h: 92,
              color: Colors.white.withValues(alpha: 0.45),
              child: const SizedBox(),
            ),
          ),
        ),
        Positioned(
          left: 14,
          top: 6,
          child: Transform.rotate(
            angle: -0.07,
            child: s.card(
              w: 76,
              h: 98,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rx',
                          style: AppType.sans(
                            fontSize: AppType.figure,
                            fontWeight: FontWeight.w800,
                            color: accent,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final l in lines) ...[
                          s.bar(l.w * l.p),
                          const SizedBox(height: 5),
                        ],
                        const Spacer(),
                        s.bar(
                          26 * s.seg(0.6, 0.7),
                          h: 3,
                          color: accent.withValues(alpha: 0.5),
                        ),
                      ],
                    ),
                    if (s.t < 0.64 && s.t > 0.03)
                      Positioned(
                        left: penX - 2,
                        top: 18 + penY,
                        child: Icon(
                          LucideIcons.penLine,
                          size: 16,
                          color: accent,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 4,
          bottom: 4,
          child: Transform.scale(
            scale: tick,
            child: s.badge(LucideIcons.check, iconColor: AppColors.success),
          ),
        ),
      ],
    );
  }

  /// Slots open one by one on the week grid while the clock hand turns.
  Widget _schedule(_Kit s) {
    const open = [1, 2, 5, 7, 8, 10];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 6,
          top: 14,
          child: s.card(
            w: 96,
            h: 88,
            child: Column(
              children: [
                Container(
                  height: 20,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(14),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (var i = 0; i < 4; i++)
                        s.bar(10, h: 4, color: accent.withValues(alpha: 0.6)),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: GridView.count(
                      crossAxisCount: 4,
                      mainAxisSpacing: 5,
                      crossAxisSpacing: 5,
                      childAspectRatio: 1.5,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      children: [
                        for (var i = 0; i < 12; i++)
                          Stack(
                            fit: StackFit.expand,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: AppColors.border.withValues(
                                    alpha: 0.7,
                                  ),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              if (open.contains(i))
                                Transform.scale(
                                  scale: s.pop(
                                    0.08 + open.indexOf(i) * 0.09,
                                    0.2 + open.indexOf(i) * 0.09,
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: accent,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
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
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: _Kit.shadow,
            ),
            child: CustomPaint(
              painter: _ClockPainter(color: accent, turn: s.t),
            ),
          ),
        ),
        Positioned(
          left: 0,
          bottom: 2,
          child: Opacity(
            opacity: s.seg(0.62, 0.72),
            child: Transform.translate(
              offset: Offset(0, 8 * (1 - s.seg(0.62, 0.74))),
              child: s.chip('+6 slots'),
            ),
          ),
        ),
      ],
    );
  }

  // ── Physio ──────────────────────────────────────────────────────────────

  /// The completion ring fills while the dumbbell is lifted; the % counts up.
  Widget _exercise(_Kit s) {
    final fill = s.seg(0.0, 0.62);
    final lift = s.wave(2);
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Container(
          width: 92,
          height: 92,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: _Kit.shadow,
          ),
          child: CustomPaint(
            painter: _RingPainter(progress: 0.72 * fill, color: accent),
            child: Center(
              child: Transform.translate(
                offset: Offset(0, 5 - 10 * lift),
                child: Transform.rotate(
                  angle: -0.25 + 0.25 * lift,
                  child: Icon(LucideIcons.dumbbell, size: 30, color: accent),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 6,
          child: Transform.scale(
            scale: s.pop(0.1, 0.25),
            child: s.chip('3 × 12'),
          ),
        ),
        Positioned(
          left: 0,
          bottom: 6,
          child: s.chip(
            '${(72 * fill).round()}%',
            lead: Transform.scale(
              scale: 0.85 + 0.25 * s.wave(3),
              child: const Icon(
                LucideIcons.flame,
                size: 11,
                color: AppColors.warning,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Session passes fan out, then each session dot ticks off.
  Widget _packages(_Kit s) {
    final fan = s.seg(0.0, 0.3);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = 2; i >= 1; i--)
          Positioned(
            left: 12 + (i * 8) * fan + 2,
            top: 22 - (i * 7) * fan,
            child: Transform.rotate(
              angle: 0.06 * i * fan,
              child: s.card(
                w: 80,
                h: 84,
                color: Colors.white.withValues(alpha: 0.3 + 0.15 * (2 - i)),
                child: const SizedBox(),
              ),
            ),
          ),
        Positioned(
          left: 12,
          top: 22,
          child: s.card(
            w: 80,
            h: 84,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '10',
                    style: AppType.sans(
                      fontSize: AppType.display,
                      fontWeight: FontWeight.w800,
                      color: accent,
                      height: 1,
                    ),
                  ),
                  Text(
                    'sessions',
                    style: AppType.sans(
                      fontSize: AppType.micro,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      for (var i = 0; i < 5; i++)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 3),
                          decoration: BoxDecoration(
                            color: Color.lerp(
                              AppColors.border,
                              accent,
                              i < 3
                                  ? s.seg(0.35 + i * 0.12, 0.45 + i * 0.12)
                                  : 0,
                            ),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Transform.rotate(
            angle: 0.18 * math.sin(s.t * math.pi * 8) * (1 - s.seg(0.0, 0.5)),
            child: s.badge(LucideIcons.ticket),
          ),
        ),
      ],
    );
  }

  /// The recovery line draws itself; its last point pulses.
  Widget _recovery(_Kit s) {
    final draw = s.seg(0.0, 0.66);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 4,
          top: 16,
          child: s.card(
            w: 104,
            h: 78,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: CustomPaint(
                painter: _ChartPainter(
                  color: accent,
                  progress: draw,
                  pulse: draw >= 1 ? s.wave(2) : 0,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: s.chip(
            'Pain ${(7 - 5 * draw).round()} → 2',
            lead: const Icon(
              LucideIcons.trendingDown,
              size: 11,
              color: AppColors.success,
            ),
          ),
        ),
        Positioned(
          left: 0,
          bottom: 2 + s.bob(2),
          child: s.badge(LucideIcons.activity),
        ),
      ],
    );
  }

  // ── Pathology ───────────────────────────────────────────────────────────

  /// Four tubes in a rack fill one after another, bubbles rising inside;
  /// the flask beside them sways.
  Widget _tubes(_Kit s) {
    const caps = [
      Color(0xFF8B5CF6),
      Color(0xFFF59E0B),
      Color(0xFF94A3B8),
      Color(0xFFEAB308),
    ];
    const liquid = [
      Color(0xFFDC2626),
      Color(0xFFDC2626),
      Color(0xFFB91C1C),
      Color(0xFFEAB308),
    ];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = 0; i < caps.length; i++)
          Positioned(
            left: 16.0 + i * 22,
            bottom: 22 + s.bob(1.5, phase: i * 0.2),
            child: _Tube(
              cap: caps[i],
              liquid: liquid[i],
              height: 46 + (i.isEven ? 8.0 : 0),
              fill: 0.75 * s.seg(0.05 + i * 0.13, 0.35 + i * 0.13),
              t: (s.t + i * 0.27) % 1,
            ),
          ),
        Positioned(
          left: 6,
          bottom: 10,
          child: s.card(w: 100, h: 18, radius: 6, child: const SizedBox()),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: Transform.rotate(
            angle: 0.2 * math.sin(s.t * math.pi * 4),
            child: s.badge(LucideIcons.flaskConical),
          ),
        ),
        Positioned(
          left: 0,
          top: 8,
          child: Transform.scale(
            scale: s.pop(0.62, 0.76),
            child: s.chip('+20 tests'),
          ),
        ),
      ],
    );
  }

  /// The report fills in row by row, H and L flags pop, then it's sent.
  Widget _labReport(_Kit s) {
    const flags = [null, 'H', null, 'L'];
    // Flies off toward the patient, then fades back in at its spot.
    final fly = s.t < 0.84 ? s.seg(0.7, 0.82) : 0.0;
    final back = s.t < 0.84 ? 1.0 : s.seg(0.84, 0.9);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 14,
          top: 6,
          child: Transform.rotate(
            angle: -0.05,
            child: s.card(
              w: 80,
              h: 100,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(9, 10, 9, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    s.bar(34, h: 6, color: accent),
                    const SizedBox(height: 9),
                    for (var i = 0; i < flags.length; i++)
                      Opacity(
                        opacity: s.seg(0.06 + i * 0.12, 0.16 + i * 0.12),
                        child: Transform.translate(
                          offset: Offset(
                            -6 * (1 - s.seg(0.06 + i * 0.12, 0.18 + i * 0.12)),
                            0,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                s.bar(30),
                                const Spacer(),
                                if (flags[i] == null)
                                  s.bar(
                                    14,
                                    color: AppColors.textTertiary.withValues(
                                      alpha: 0.5,
                                    ),
                                  )
                                else
                                  Transform.scale(
                                    scale: s.pop(
                                      0.14 + i * 0.12,
                                      0.28 + i * 0.12,
                                    ),
                                    child: Text(
                                      flags[i]!,
                                      style: AppType.sans(
                                        fontSize: AppType.micro,
                                        fontWeight: FontWeight.w800,
                                        color: flags[i] == 'H'
                                            ? const Color(0xFFC2410C)
                                            : const Color(0xFF1D4ED8),
                                        height: 1,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // The send badge lifts off toward the patient, then lands back.
        Positioned(
          right: 2 - 14 * fly,
          bottom: 6 + 60 * fly,
          child: Opacity(
            opacity: (1 - fly) * back,
            child: Transform.rotate(
              angle: -0.4 * fly,
              child: s.badge(LucideIcons.send),
            ),
          ),
        ),
        Positioned(
          right: 4,
          top: 4,
          child: Transform.scale(
            scale: s.pop(0.55, 0.68),
            child: s.chip('PDF'),
          ),
        ),
      ],
    );
  }

  // ── Pharmacy ────────────────────────────────────────────────────────────

  /// A new order drops onto the phone while the bell rings.
  Widget _orders(_Kit s) {
    final drop = s.seg(0.08, 0.3);
    final ring = s.t < 0.42
        ? math.sin(s.t * math.pi * 24) * 0.35 * (1 - s.t / 0.42)
        : 0.0;
    Widget orderRow({required bool fresh}) => Container(
      height: 22,
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: fresh ? accent.withValues(alpha: 0.12) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.pill,
            size: 10,
            color: fresh ? accent : AppColors.textTertiary,
          ),
          const SizedBox(width: 5),
          s.bar(fresh ? 22 : 18, h: 4),
          const Spacer(),
          s.bar(10, h: 4, color: fresh ? accent : AppColors.border),
        ],
      ),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 22,
          top: 4 + s.bob(2),
          child: s.card(
            w: 72,
            h: 108,
            radius: 16,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
              child: ClipRect(
                child: Stack(
                  children: [
                    Transform.translate(
                      offset: Offset(0, 27 * drop),
                      child: Column(
                        children: [
                          orderRow(fresh: false),
                          orderRow(fresh: false),
                          orderRow(fresh: false),
                        ],
                      ),
                    ),
                    Transform.translate(
                      offset: Offset(0, -27 * (1 - drop)),
                      child: Opacity(
                        opacity: drop,
                        child: orderRow(fresh: true),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 2,
          top: 0,
          child: Transform.rotate(
            angle: ring,
            child: s.badge(LucideIcons.bellRing),
          ),
        ),
        Positioned(
          left: 0,
          bottom: 8,
          child: Transform.scale(
            scale: s.pop(0.2, 0.34),
            child: s.chip(
              'New order',
              lead: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(
                    alpha: 0.4 + 0.6 * s.wave(2),
                  ),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Stock runs down on the shelf, one item goes low and the alert pulses,
  /// then it's restocked.
  Widget _stock(_Kit s) {
    final drain = s.seg(0.05, 0.4);
    final restock = s.seg(0.6, 0.78);
    final levels = [
      0.85 - 0.2 * drain + 0.2 * restock,
      0.7 - 0.55 * drain + 0.55 * restock, // the one that runs low
      0.9 - 0.25 * drain + 0.25 * restock,
    ];
    final low = drain > 0.9 && restock < 0.2;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 6,
          top: 16,
          child: s.card(
            w: 98,
            h: 86,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < levels.length; i++)
                    Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          width: 18,
                          height: 54 * levels[i],
                          decoration: BoxDecoration(
                            color: i == 1 && levels[i] < 0.3
                                ? AppColors.error
                                : accent.withValues(alpha: 0.85 - i * 0.18),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        s.bar(18, h: 3),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 2,
          child: Transform.scale(
            scale: low ? 1 + 0.15 * s.wave(4) : 1,
            child: s.badge(
              low ? LucideIcons.triangleAlert : LucideIcons.packageCheck,
              iconColor: low ? AppColors.error : AppColors.success,
            ),
          ),
        ),
        Positioned(
          left: 0,
          bottom: 4,
          child: s.chip(
            low ? 'Low stock' : (restock > 0.5 ? 'Restocked' : 'In stock'),
          ),
        ),
      ],
    );
  }

  /// A coupon wiggles in with a few sparkles around it.
  Widget _coupon(_Kit s) {
    final inP = s.pop(0.02, 0.22);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 8,
          top: 30,
          child: Transform.rotate(
            angle: -0.12 + 0.08 * math.sin(s.t * math.pi * 4),
            child: Transform.scale(
              scale: inP,
              child: s.card(
                w: 96,
                h: 56,
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(14),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        LucideIcons.percent,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '20% off',
                              style: AppType.sans(
                                fontSize: AppType.small,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textStrong,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 5),
                            s.bar(32, h: 4),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        for (final (dx, dy, phase, size) in const [
          (4.0, 12.0, 0.0, 12.0),
          (92.0, 18.0, 0.33, 10.0),
          (70.0, 96.0, 0.66, 13.0),
        ])
          Positioned(
            left: dx,
            top: dy,
            child: Opacity(
              opacity: (0.25 + 0.75 * _Kit.waveAt(s.t, 2, phase)).clamp(0, 1),
              child: Transform.scale(
                scale: 0.6 + 0.5 * _Kit.waveAt(s.t, 2, phase),
                child: Icon(
                  LucideIcons.sparkle,
                  size: size,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        Positioned(
          right: 2,
          bottom: 4 + s.bob(3),
          child: s.badge(LucideIcons.gift),
        ),
      ],
    );
  }
}

/// A vacutainer: cap, glass, and liquid that rises to [fill] with bubbles.
class _Tube extends StatelessWidget {
  final Color cap;
  final Color liquid;
  final double height;
  final double fill;
  final double t;
  const _Tube({
    required this.cap,
    required this.liquid,
    required this.height,
    required this.fill,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final level = height * fill;
    return Column(
      children: [
        Container(
          width: 16,
          height: 9,
          decoration: BoxDecoration(
            color: cap,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        Container(
          width: 13,
          height: height,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(7)),
            boxShadow: _Kit.shadow,
          ),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.bottomCenter,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Container(
                width: 13,
                height: level,
                color: liquid.withValues(alpha: 0.8),
              ),
              // Two bubbles rising through the liquid.
              if (level > 10)
                for (final (x, off) in const [(3.0, 0.0), (7.0, 0.5)])
                  Positioned(
                    left: x,
                    bottom: ((t + off) % 1) * (level - 4),
                    child: Container(
                      width: 3,
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(
                          alpha: 0.7 * (1 - ((t + off) % 1)),
                        ),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shared drawing pieces and timing helpers for one frame.
class _Kit {
  final Color accent;
  final double t;
  const _Kit(this.accent, this.t);

  static const shadow = [
    BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 6)),
  ];

  /// 0→1 between [a] and [b] (eased), held at 1 until the loop's last 6%,
  /// where it fades back to 0 so the next loop starts from scratch.
  double seg(double a, double b) {
    if (t >= 0.94) return 1 - ((t - 0.94) / 0.06).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(((t - a) / (b - a)).clamp(0.0, 1.0));
  }

  /// Like [seg] but overshoots a little — for things that pop in.
  double pop(double a, double b) {
    if (t >= 0.94) return 1 - ((t - 0.94) / 0.06).clamp(0.0, 1.0);
    return Curves.easeOutBack.transform(((t - a) / (b - a)).clamp(0.0, 1.0));
  }

  /// 0→1→0, [times] per loop.
  double wave(double times) => waveAt(t, times, 0);

  static double waveAt(double t, double times, double phase) =>
      0.5 - 0.5 * math.cos(2 * math.pi * (t * times + phase));

  /// A gentle float of ±[amp] px, once per loop.
  double bob(double amp, {double phase = 0}) =>
      amp * math.sin(2 * math.pi * (t + phase));

  Widget card({
    required double w,
    required double h,
    required Widget child,
    double radius = 14,
    Color color = Colors.white,
  }) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: shadow,
    ),
    child: child,
  );

  Widget badge(IconData icon, {Color? iconColor, double size = 34}) =>
      Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: shadow,
        ),
        child: Icon(icon, size: size * 0.5, color: iconColor ?? accent),
      );

  Widget bar(double w, {double h = 5, Color? color}) => Container(
    width: math.max(0, w),
    height: h,
    decoration: BoxDecoration(
      color: color ?? AppColors.border,
      borderRadius: BorderRadius.circular(h),
    ),
  );

  Widget chip(String text, {Widget? lead}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      boxShadow: shadow,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (lead != null) ...[lead, const SizedBox(width: 4)],
        Text(
          text,
          style: AppType.sans(
            fontSize: AppType.micro,
            fontWeight: FontWeight.w800,
            color: AppColors.textStrong,
          ),
        ),
      ],
    ),
  );
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  const _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final r = (Offset.zero & size).deflate(9);
    canvas.drawOval(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = color.withValues(alpha: 0.14),
    );
    if (progress <= 0) return;
    canvas.drawArc(
      r,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

/// A clock face whose minute hand makes one turn per loop.
class _ClockPainter extends CustomPainter {
  final Color color;
  final double turn;
  const _ClockPainter({required this.color, required this.turn});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color;
    canvas.drawCircle(c, size.width * 0.3, ring);
    final hand = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = color;
    final a = 2 * math.pi * turn - math.pi / 2;
    canvas.drawLine(
      c,
      c + Offset(math.cos(a), math.sin(a)) * size.width * 0.22,
      hand,
    );
    final h = 2 * math.pi * turn / 12 - math.pi / 2 + 1.2;
    canvas.drawLine(
      c,
      c + Offset(math.cos(h), math.sin(h)) * size.width * 0.14,
      hand,
    );
  }

  @override
  bool shouldRepaint(_ClockPainter old) =>
      old.turn != turn || old.color != color;
}

class _ChartPainter extends CustomPainter {
  final Color color;
  final double progress;
  final double pulse;
  const _ChartPainter({
    required this.color,
    required this.progress,
    required this.pulse,
  });

  static const _points = [0.2, 0.3, 0.28, 0.5, 0.62, 0.78, 0.9];

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (progress <= 0) return;

    final pts = [
      for (var i = 0; i < _points.length; i++)
        Offset(
          size.width * i / (_points.length - 1),
          size.height * (1 - _points[i]),
        ),
    ];
    final full = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final mid = (a.dx + b.dx) / 2;
      full.cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
    }
    // Only the drawn part of the line, so it appears to be traced.
    final metric = full.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * progress);
    final tip = metric.getTangentForOffset(metric.length * progress)!.position;

    final fill = Path.from(drawn)
      ..lineTo(tip.dx, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    if (pulse > 0) {
      canvas.drawCircle(
        tip,
        5 + 7 * pulse,
        Paint()..color = color.withValues(alpha: 0.3 * (1 - pulse)),
      );
    }
    canvas.drawCircle(tip, 5, Paint()..color = Colors.white);
    canvas.drawCircle(tip, 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.color != color || old.progress != progress || old.pulse != pulse;
}
