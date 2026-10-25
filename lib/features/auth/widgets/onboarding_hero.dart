import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../pharmacy/theme/pharmacy_type.dart';
import '../../pharmacy/widgets/module_accent.dart';

/// Brand colours from the logo.
const kAadyaBlue = Color(0xFF1F5EDC);
const kAadyaGreen = Color(0xFF00A651);

/// The stage the splash and sign-in screens share: midnight navy.
const kStageTop = Color(0xFF060C26);
const kStageBottom = Color(0xFF0B1B52);

/// Module colours lifted for use as light on the dark stage.
Color stageLight(Color c) => Color.lerp(c, Colors.white, 0.38)!;

// ─────────────────────────── Aurora stage ───────────────────────────

/// Midnight navy with slow fields of coloured light drifting across it and a
/// fine film grain on top — depth without decoration. [tint] is the main
/// light; changing it cross-fades smoothly. [bloom] (0–1) opens the light
/// up from nothing, for the splash.
class AuroraBackdrop extends StatefulWidget {
  final Color tint;
  final double bloom;
  const AuroraBackdrop({super.key, required this.tint, this.bloom = 1});

  @override
  State<AuroraBackdrop> createState() => _AuroraBackdropState();
}

class _AuroraBackdropState extends State<AuroraBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: widget.tint),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOutCubic,
      builder: (_, tint, _) => Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _drift,
              builder: (_, _) => CustomPaint(
                painter: _AuroraPainter(
                  tint: tint ?? widget.tint,
                  t: _drift.value,
                  bloom: widget.bloom,
                ),
              ),
            ),
          ),
          // Painted once and cached: the grain never changes.
          const RepaintBoundary(child: CustomPaint(painter: _GrainPainter())),
        ],
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final Color tint;
  final double t;
  final double bloom;
  const _AuroraPainter({
    required this.tint,
    required this.t,
    required this.bloom,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kStageTop, kStageBottom],
        ).createShader(rect),
    );
    final a = t * 2 * math.pi;
    final w = size.width;
    final h = size.height;
    void field(Offset c, double r, Color color, double alpha) {
      final radius = r * (0.35 + 0.65 * bloom);
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha * bloom),
              color.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: radius)),
      );
    }

    // The main light, in the current tint, upper right.
    field(
      Offset(w * (0.78 + 0.06 * math.sin(a)), h * (0.18 + 0.05 * math.cos(a))),
      w * 0.85,
      tint,
      0.55,
    );
    // Brand blue, lower left, drifting against it.
    field(
      Offset(w * (0.12 + 0.06 * math.cos(a)), h * (0.72 + 0.05 * math.sin(a))),
      w * 0.8,
      kAadyaBlue,
      0.5,
    );
    // A faint second note of the tint, centre, for continuity.
    field(
      Offset(
        w * (0.5 + 0.08 * math.sin(a + 1.4)),
        h * (0.48 + 0.04 * math.cos(a + 0.6)),
      ),
      w * 0.55,
      Color.lerp(tint, kAadyaBlue, 0.5)!,
      0.22,
    );
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.t != t || old.tint != tint || old.bloom != bloom;
}

class _GrainPainter extends CustomPainter {
  const _GrainPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    final light = Paint()..color = Colors.white.withValues(alpha: 0.035);
    final dark = Paint()..color = Colors.black.withValues(alpha: 0.05);
    final n = (size.width * size.height / 90).round();
    final pts = <Offset>[];
    final pts2 = <Offset>[];
    for (var i = 0; i < n; i++) {
      final p = Offset(
        rnd.nextDouble() * size.width,
        rnd.nextDouble() * size.height,
      );
      (i.isEven ? pts : pts2).add(p);
    }
    canvas.drawPoints(ui.PointMode.points, pts, light..strokeWidth = 1);
    canvas.drawPoints(ui.PointMode.points, pts2, dark..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_GrainPainter old) => false;
}

// ─────────────────────────── Hero shell ───────────────────────────

/// The top of the sign-in screens: the aurora stage with a [scene] that rises
/// into place, and a slot for the logo or a back button. [tint] colours the
/// light; give it a listenable to let the scene steer it.
class OnboardingHero extends StatefulWidget {
  final double height;
  final Widget scene;
  final Widget? topLeft;
  final ValueListenable<Color>? tint;

  const OnboardingHero({
    super.key,
    required this.height,
    required this.scene,
    this.topLeft,
    this.tint,
  });

  @override
  State<OnboardingHero> createState() => _OnboardingHeroState();
}

class _OnboardingHeroState extends State<OnboardingHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _intro.value = 1;
    } else if (!_intro.isCompleted && !_intro.isAnimating) {
      _intro.forward();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.tint;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (tint == null)
              const AuroraBackdrop(tint: kAadyaBlue)
            else
              ValueListenableBuilder<Color>(
                valueListenable: tint,
                builder: (_, c, _) => AuroraBackdrop(tint: c),
              ),
            Positioned.fill(
              top: 0,
              bottom: 28, // the sheet's overlap
              child: SafeArea(
                bottom: false,
                child: AnimatedBuilder(
                  animation: _intro,
                  builder: (_, child) {
                    final v = Curves.easeOutCubic.transform(_intro.value);
                    return Opacity(
                      opacity: v,
                      child: Transform.translate(
                        offset: Offset(0, 22 * (1 - v)),
                        child: child,
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(top: 56),
                    child: widget.scene,
                  ),
                ),
              ),
            ),
            if (widget.topLeft != null)
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                child: SafeArea(bottom: false, child: widget.topLeft!),
              ),
          ],
        ),
      ),
    );
  }
}

/// The Aadya mark on a white tile, with the wordmark set in white — for the
/// dark stage.
class HeroLogo extends StatelessWidget {
  const HeroLogo({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        clipBehavior: Clip.antiAlias,
        child: Transform.scale(
          scale: 2,
          child: Image.asset('assets/brand/icon.png', fit: BoxFit.contain),
        ),
      ),
      const SizedBox(width: 9),
      Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'Aadya',
              style: PharmacyType.sans(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.4,
              ),
            ),
            TextSpan(
              text: ' Plus',
              style: PharmacyType.sans(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF8CF0B8),
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 7),
      const ProBadge(),
    ],
  );
}

/// The "PRO" tag after the wordmark.
class ProBadge extends StatelessWidget {
  final double size;
  const ProBadge({super.key, this.size = 10});

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: size * 0.6,
      vertical: size * 0.25,
    ),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * 0.6),
      gradient: const LinearGradient(
        colors: [Color(0xFF8CF0B8), Color(0xFF4ADE80)],
      ),
    ),
    child: Text(
      'PRO',
      style: PharmacyType.sans(
        fontSize: size,
        fontWeight: FontWeight.w800,
        color: const Color(0xFF06301B),
        letterSpacing: size * 0.12,
        height: 1.1,
      ),
    ),
  );
}

/// A round, translucent back button for the dark stage.
class HeroBackButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String tooltip;
  const HeroBackButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'Back',
  });

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      backgroundColor: Colors.white.withValues(alpha: 0.1),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
    ),
    icon: const Icon(LucideIcons.arrowLeft, size: 20, color: Colors.white),
  );
}

/// Frosted glass: blurs what's behind, with a hairline edge.
class Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double opacity;
  const Glass({
    super.key,
    required this.child,
    this.radius = 20,
    this.padding = const EdgeInsets.all(14),
    this.opacity = 0.1,
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: opacity + 0.06),
              Colors.white.withValues(alpha: opacity * 0.5),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: child,
      ),
    ),
  );
}

// ─────────────────────────── Sign-in showcase ───────────────────────────

typedef _Beat = ({
  String word,
  Color color,
  IconData role,
  IconData icon,
  String title,
  String body,
  String metric,
  List<double> spark,
});

final List<_Beat> _beats = [
  (
    word: 'doctor.',
    color: ModuleAccent.doctor.color,
    role: LucideIcons.stethoscope,
    icon: LucideIcons.video,
    title: 'Video consult at 10:30',
    body: 'Priya K. booked a follow-up',
    metric: '12 consults today',
    spark: [0.3, 0.45, 0.4, 0.6, 0.55, 0.8, 0.9],
  ),
  (
    word: 'physio.',
    color: ModuleAccent.physio.color,
    role: LucideIcons.personStanding,
    icon: LucideIcons.activity,
    title: 'Session 3 of 10 done',
    body: 'Home visit · Arjun M.',
    metric: '92% plan adherence',
    spark: [0.5, 0.55, 0.62, 0.6, 0.74, 0.8, 0.92],
  ),
  (
    word: 'lab.',
    color: ModuleAccent.pathology.color,
    role: LucideIcons.flaskConical,
    icon: LucideIcons.fileCheck2,
    title: 'Report released',
    body: 'CBC · Lipid profile · 2 flags',
    metric: '38 reports today',
    spark: [0.2, 0.35, 0.5, 0.45, 0.65, 0.7, 0.88],
  ),
  (
    word: 'pharmacy.',
    color: ModuleAccent.pharmacy.color,
    role: LucideIcons.pill,
    icon: LucideIcons.shoppingBag,
    title: 'New order · ₹486',
    body: 'Sharma Medicos · 3 items',
    metric: '₹24.6k sales today',
    spark: [0.35, 0.3, 0.5, 0.62, 0.58, 0.76, 0.86],
  ),
];

/// The sign-in hero: "One app for every doctor." with the last word rolling
/// through the four professions. On each beat the word's colour, the aurora,
/// the glass card and its metric all change together — one idea, one rhythm,
/// with story-style progress bars showing the timing.
class LoginShowcase extends StatefulWidget {
  /// Receives the current module colour, to tint the stage.
  final ValueChanged<Color>? onTint;
  const LoginShowcase({super.key, this.onTint});

  /// The colour the showcase opens on.
  static Color get firstTint => _beats.first.color;

  @override
  State<LoginShowcase> createState() => _LoginShowcaseState();
}

class _LoginShowcaseState extends State<LoginShowcase>
    with TickerProviderStateMixin {
  static const _beat = Duration(milliseconds: 3400);

  int _i = 0;
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: _beat,
  )..addStatusListener(_onBeat);
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );

  void _onBeat(AnimationStatus s) {
    if (s != AnimationStatus.completed || !mounted) return;
    setState(() => _i = (_i + 1) % _beats.length);
    widget.onTint?.call(_beats[_i].color);
    _progress.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _progress.stop();
      _float.stop();
    } else {
      if (!_progress.isAnimating) _progress.forward();
      if (!_float.isAnimating) _float.repeat();
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final beat = _beats[_i];
    final light = stageLight(beat.color);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedBuilder(
            animation: _progress,
            builder: (_, _) => _StoryBars(
              count: _beats.length,
              current: _i,
              progress: _progress.value,
            ),
          ),
          const SizedBox(height: 14),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'One app for',
                    style: PharmacyType.sans(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -1.2,
                      height: 1.05,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        'every ',
                        style: PharmacyType.sans(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -1.2,
                          height: 1.05,
                        ),
                      ),
                      Expanded(
                        child: _RollingWord(word: beat.word, color: light),
                      ),
                    ],
                  ),
                ],
              ),
              // Beside the short first line, above the end of the second.
              Positioned(
                right: 0,
                top: -6,
                child: AnimatedBuilder(
                  animation: _float,
                  builder: (_, _) => _RoleMedallion(
                    key: ValueKey(_i),
                    beat: beat,
                    light: light,
                    spin: _float.value,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 92,
            child: AnimatedBuilder(
              animation: _float,
              builder: (_, _) {
                final f = math.sin(_float.value * 2 * math.pi);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // The card and the chip drift out of phase: depth.
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 18 + 2 * f,
                      child: _swap(_GlassMoment(beat: beat, light: light)),
                    ),
                    Positioned(
                      right: 6,
                      top: -4 - 3 * f,
                      child: _swap(_MetricChip(beat: beat, light: light)),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Old moment out, then the new one in — never both at once, so two
  /// glass cards never show through each other. The incoming half runs on
  /// the last 55% of the switch; the outgoing (played in reverse) clears in
  /// the first 45%.
  Widget _swap(Widget child) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 760),
    transitionBuilder: (c, a) {
      final staged = CurvedAnimation(
        parent: a,
        curve: const Interval(0.45, 1, curve: Curves.easeOutCubic),
      );
      return FadeTransition(
        opacity: staged,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.3),
            end: Offset.zero,
          ).animate(staged),
          child: ScaleTransition(
            scale: Tween(begin: 0.95, end: 1.0).animate(staged),
            child: c,
          ),
        ),
      );
    },
    layoutBuilder: (current, previous) =>
        Stack(clipBehavior: Clip.none, children: [...previous, ?current]),
    child: KeyedSubtree(key: ValueKey(_i), child: child),
  );
}

/// The profession's icon on a glowing disc in its colour, a thin ring
/// turning around it. Flips (a 3D turn) to the next profession on each beat.
class _RoleMedallion extends StatefulWidget {
  final _Beat beat;
  final Color light;
  final double spin;
  const _RoleMedallion({
    super.key,
    required this.beat,
    required this.light,
    required this.spin,
  });

  @override
  State<_RoleMedallion> createState() => _RoleMedallionState();
}

class _RoleMedallionState extends State<_RoleMedallion>
    with SingleTickerProviderStateMixin {
  // Each new profession turns in from edge-on.
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _flip.value = 1;
    } else if (!_flip.isAnimating && !_flip.isCompleted) {
      _flip.forward();
    }
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 78.0;
    final beat = widget.beat;
    return AnimatedBuilder(
      animation: _flip,
      builder: (_, _) {
        final f = Curves.easeOutBack.transform(_flip.value);
        return Opacity(
          opacity: _flip.value.clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0016)
              ..rotateY((1 - f) * math.pi / 2),
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Halo.
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          beat.color.withValues(alpha: 0.55),
                          beat.color.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                  // Turning ring with a travelling dot.
                  CustomPaint(
                    size: const Size(size - 6, size - 6),
                    painter: _OrbitRingPainter(
                      color: widget.light,
                      turn: widget.spin,
                    ),
                  ),
                  // The disc.
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [widget.light, beat.color],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: beat.color.withValues(alpha: 0.6),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(beat.role, size: 26, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OrbitRingPainter extends CustomPainter {
  final Color color;
  final double turn;
  const _OrbitRingPainter({required this.color, required this.turn});

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final c = size.center(Offset.zero);
    final start = turn * 2 * math.pi;
    canvas.drawArc(
      r,
      start,
      math.pi * 1.25,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: start,
          endAngle: start + math.pi * 1.25,
          colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.9)],
          transform: GradientRotation(start),
        ).createShader(r),
    );
    final end = start + math.pi * 1.25;
    canvas.drawCircle(
      c + Offset(math.cos(end), math.sin(end)) * size.width / 2,
      2.6,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_OrbitRingPainter old) =>
      old.turn != turn || old.color != color;
}

/// Thin segments like a story viewer: done, filling, waiting.
class _StoryBars extends StatelessWidget {
  final int count;
  final int current;
  final double progress;
  const _StoryBars({
    required this.count,
    required this.current,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var i = 0; i < count; i++) ...[
        if (i > 0) const SizedBox(width: 5),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: Colors.white.withValues(alpha: 0.18)),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: i < current
                        ? 1
                        : i == current
                        ? progress
                        : 0,
                    child: Container(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

/// The headline's last word: rolls like a slot machine to the next one, in
/// its module colour, with a hand-drawn underline swash that redraws.
class _RollingWord extends StatefulWidget {
  final String word;
  final Color color;
  const _RollingWord({required this.word, required this.color});

  @override
  State<_RollingWord> createState() => _RollingWordState();
}

class _RollingWordState extends State<_RollingWord>
    with SingleTickerProviderStateMixin {
  late String _from = widget.word;
  late Color _fromColor = widget.color;
  late final AnimationController _roll = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    value: 1,
  );

  TextStyle _style(Color c) => PharmacyType.sans(
    fontSize: 34,
    fontWeight: FontWeight.w800,
    color: c,
    letterSpacing: -1.2,
    height: 1.05,
  );

  @override
  void didUpdateWidget(_RollingWord old) {
    super.didUpdateWidget(old);
    if (old.word != widget.word) {
      _from = old.word;
      _fromColor = old.color;
      if (MediaQuery.of(context).disableAnimations) {
        _roll.value = 1;
      } else {
        _roll.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _roll.dispose();
    super.dispose();
  }

  double _textWidth(String s) {
    final tp = TextPainter(
      text: TextSpan(text: s.replaceAll('.', ''), style: _style(Colors.white)),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  @override
  Widget build(BuildContext context) {
    const lineH = 42.0;
    return AnimatedBuilder(
      animation: _roll,
      builder: (_, _) {
        // Roll (0–0.45), then the swash draws (0.4–1).
        final r = Curves.easeInOutCubic.transform(
          (_roll.value / 0.45).clamp(0.0, 1.0),
        );
        final swash = Curves.easeOutCubic.transform(
          ((_roll.value - 0.4) / 0.6).clamp(0.0, 1.0),
        );
        return SizedBox(
          height: lineH + 12,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRect(
                child: SizedBox(
                  height: lineH,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      if (r < 1)
                        Transform.translate(
                          offset: Offset(0, -lineH * r),
                          child: Opacity(
                            opacity: 1 - r,
                            child: Text(
                              _from,
                              maxLines: 1,
                              style: _style(_fromColor),
                            ),
                          ),
                        ),
                      Transform.translate(
                        offset: Offset(0, lineH * (1 - r)),
                        child: Opacity(
                          opacity: r,
                          child: Text(
                            widget.word,
                            maxLines: 1,
                            style: _style(widget.color),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: lineH - 4,
                child: CustomPaint(
                  size: Size(_textWidth(widget.word), 12),
                  painter: _SwashPainter(progress: swash, color: widget.color),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A brush-like underline: a shallow curve that tapers at both ends.
class _SwashPainter extends CustomPainter {
  final double progress;
  final Color color;
  const _SwashPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final path = Path()
      ..moveTo(2, size.height * 0.7)
      ..quadraticBezierTo(
        size.width * 0.45,
        size.height * 0.05,
        size.width - 2,
        size.height * 0.45,
      );
    final metric = path.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * progress);
    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          colors: [
            color.withValues(alpha: 0.35),
            color,
            color.withValues(alpha: 0.6),
          ],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_SwashPainter old) =>
      old.progress != progress || old.color != color;
}

/// The module's real moment, on frosted glass.
class _GlassMoment extends StatelessWidget {
  final _Beat beat;
  final Color light;
  const _GlassMoment({required this.beat, required this.light});

  @override
  Widget build(BuildContext context) => Glass(
    padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [light, beat.color],
            ),
            boxShadow: [
              BoxShadow(
                color: beat.color.withValues(alpha: 0.5),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(beat.icon, size: 19, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                beat.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PharmacyType.sans(
                  fontSize: PharmacyType.body,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                beat.body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PharmacyType.sans(
                  fontSize: PharmacyType.caption,
                  color: Colors.white.withValues(alpha: 0.68),
                ),
              ),
            ],
          ),
        ),
        Text(
          'now',
          style: PharmacyType.sans(
            fontSize: PharmacyType.micro,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
      ],
    ),
  );
}

/// A small glass chip with a figure and a sparkline.
class _MetricChip extends StatelessWidget {
  final _Beat beat;
  final Color light;
  const _MetricChip({required this.beat, required this.light});

  @override
  Widget build(BuildContext context) => Glass(
    radius: 12,
    opacity: 0.14,
    padding: const EdgeInsets.fromLTRB(9, 6, 10, 6),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(30, 14),
          painter: _SparkPainter(values: beat.spark, color: light),
        ),
        const SizedBox(width: 7),
        Text(
          beat.metric,
          style: PharmacyType.sans(
            fontSize: PharmacyType.micro,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    ),
  );
}

class _SparkPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  const _SparkPainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final pts = [
      for (var i = 0; i < values.length; i++)
        Offset(
          size.width * i / (values.length - 1),
          size.height * (1 - values[i]),
        ),
    ];
    final path = Path()..addPolygon(pts, false);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    canvas.drawCircle(pts.last, 2.2, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.values != values || old.color != color;
}

// ─────────────────────────── Mobile sign-in: SMS ───────────────────────────

/// The top of a phone rising from the bottom of the stage, its lock screen
/// waiting for the code. Once a code is sent ([codeSent]) the Messages
/// notification drops in and the code's dots type out one by one.
class SmsScene extends StatefulWidget {
  final bool codeSent;
  const SmsScene({super.key, required this.codeSent});

  @override
  State<SmsScene> createState() => _SmsSceneState();
}

class _SmsSceneState extends State<SmsScene> with TickerProviderStateMixin {
  late final AnimationController _arrive = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
    value: widget.codeSent ? 1 : 0,
  );
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  bool get _still => MediaQuery.of(context).disableAnimations;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_still) {
      _shimmer.stop();
      _arrive.value = widget.codeSent ? 1 : 0;
    } else if (!_shimmer.isAnimating) {
      _shimmer.repeat();
    }
  }

  @override
  void didUpdateWidget(SmsScene old) {
    super.didUpdateWidget(old);
    if (widget.codeSent && !old.codeSent) {
      if (_still) {
        _arrive.value = 1;
      } else {
        HapticFeedback.lightImpact();
        _arrive.forward(from: 0);
      }
    } else if (!widget.codeSent && old.codeSent) {
      _arrive.value = 0;
    }
  }

  @override
  void dispose() {
    _arrive.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final phoneW = math.min(box.maxWidth * 0.7, 250.0);
        return AnimatedBuilder(
          animation: Listenable.merge([_arrive, _shimmer]),
          builder: (context, _) => Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.hardEdge,
            children: [
              // A soft pool of light under the phone.
              Positioned(
                bottom: -60,
                child: Container(
                  width: phoneW * 1.5,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        (widget.codeSent ? kAadyaGreen : kAadyaBlue).withValues(
                          alpha: 0.45,
                        ),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(bottom: -28, child: _phone(phoneW, box.maxHeight + 4)),
            ],
          ),
        );
      },
    );
  }

  Widget _phone(double w, double h) {
    final a = _arrive.value;
    final drop = Curves.easeOutBack.transform((a / 0.4).clamp(0.0, 1.0));
    final typed = ((a - 0.35) / 0.55 * 6).clamp(0.0, 6.0).floor();
    return Container(
      width: w,
      height: h,
      padding: const EdgeInsets.fromLTRB(7, 7, 7, 0),
      decoration: BoxDecoration(
        // Brushed-metal frame with a light catching the top edge.
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5B6B92), Color(0xFF1A2547), Color(0xFF2E3B63)],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 40,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Container(
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          color: Color(0xFF070E2B),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Wallpaper: the stage's own light, inside the phone.
            Positioned.fill(
              child: AuroraBackdrop(
                tint: widget.codeSent ? kAadyaGreen : const Color(0xFF6D5BF0),
              ),
            ),
            // Glass reflection across the screen.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: const Alignment(0.2, 0.2),
                    colors: [
                      Colors.white.withValues(alpha: 0.12),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 0),
              child: Column(
                children: [
                  Container(
                    width: 70,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    DateFormat('EEEE d MMMM').format(DateTime.now()),
                    style: PharmacyType.sans(
                      fontSize: PharmacyType.micro,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  Text(
                    DateFormat('h:mm').format(DateTime.now()),
                    style: PharmacyType.sans(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.05,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (!widget.codeSent)
                    _waiting()
                  else
                    Opacity(
                      opacity: (a / 0.25).clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, -26 * (1 - drop)),
                        child: _notification(typed),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _waiting() {
    final x = _shimmer.value;
    return Glass(
      radius: 16,
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(
              LucideIcons.messageSquare,
              size: 13,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your code will arrive here',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PharmacyType.sans(
                    fontSize: PharmacyType.micro,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  width: 96,
                  height: 7,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: LinearGradient(
                      begin: Alignment(-2 + 3 * x, 0),
                      end: Alignment(-1 + 3 * x, 0),
                      colors: [
                        Colors.white.withValues(alpha: 0.14),
                        Colors.white.withValues(alpha: 0.4),
                        Colors.white.withValues(alpha: 0.14),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _notification(int typed) => Glass(
    radius: 16,
    opacity: 0.22,
    padding: const EdgeInsets.all(10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF4ADE80), kAadyaGreen],
            ),
            borderRadius: BorderRadius.circular(7),
          ),
          child: const Icon(
            LucideIcons.messageSquare,
            size: 13,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'MESSAGES',
                    style: PharmacyType.sans(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.7),
                      letterSpacing: 0.6,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'now',
                    style: PharmacyType.sans(
                      fontSize: 9,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  for (var i = 0; i < 6; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(
                          alpha: i < typed ? 1 : 0.25,
                        ),
                      ),
                    ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      'is your code',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PharmacyType.sans(
                        fontSize: PharmacyType.micro,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────── Sheet ───────────────────────────

/// The whole sign-in page as one fixed screen: the hero pinned at the top
/// and the white sheet filling everything below it, down to the bottom edge.
/// Nothing scrolls or stretches while the form fits. When the keyboard opens
/// the sheet glides up over the hero (leaving its top bar visible) so the
/// field being typed in stays in view, and only then can the form scroll if
/// it still doesn't fit.
class OnboardingLayout extends StatelessWidget {
  final double heroHeight;
  final Widget hero;
  final Widget child;
  const OnboardingLayout({
    super.key,
    required this.heroHeight,
    required this.hero,
    required this.child,
  });

  /// How far the sheet tucks up over the hero's bottom edge.
  static const overlap = 28.0;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final typing = media.viewInsets.bottom > 0;
    // While typing, stop just under the hero's top bar (logo / back button).
    final sheetTop = typing ? media.padding.top + 60 : heroHeight - overlap;
    return Scaffold(
      // White behind everything: the sheet's colour, so nothing else can
      // show at the bottom edge, even mid keyboard animation.
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: heroHeight,
            child: hero,
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            top: sheetTop,
            left: 0,
            right: 0,
            bottom: 0,
            child: OnboardingSheet(
              child: ScrollConfiguration(
                behavior: const _NoStretch(),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.only(
                    bottom: typing ? 16 : media.padding.bottom,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// No Android stretch or glow at the edges — a form that fits shouldn't
/// look draggable.
class _NoStretch extends ScrollBehavior {
  const _NoStretch();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

/// The white sheet the form sits on, overlapping the hero with a rounded top
/// and sliding up into place on first build.
class OnboardingSheet extends StatefulWidget {
  final Widget child;
  const OnboardingSheet({super.key, required this.child});

  @override
  State<OnboardingSheet> createState() => _OnboardingSheetState();
}

class _OnboardingSheetState extends State<OnboardingSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.value = 1;
    } else if (!_c.isAnimating && !_c.isCompleted) {
      Future.delayed(const Duration(milliseconds: 180), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = Curves.easeOutCubic.transform(_c.value);
        return Transform.translate(
          offset: Offset(0, (1 - v) * 48),
          child: child,
        );
      },
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          boxShadow: [
            BoxShadow(
              color: Color(0x40060C26),
              blurRadius: 30,
              offset: Offset(0, -6),
            ),
          ],
        ),
        child: widget.child,
      ),
    );
  }
}
