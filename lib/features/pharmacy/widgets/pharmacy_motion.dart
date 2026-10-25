import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/pharmacy_colors.dart';

/// Motion primitives for the pharmacy module.
///
/// One vocabulary, used everywhere, so the module moves like one product:
///
/// * content arrives with a short fade-and-rise, staggered top to bottom
///   ([PharmacyEntrance]);
/// * anything tappable sinks slightly under the finger ([PharmacyPressable]);
/// * money and counts roll to their value instead of snapping
///   ([PharmacyCountUp]);
/// * live state breathes ([PharmacyPulse]);
/// * screens open with a soft fade-through ([PharmacyPageRoute]).
///
/// Every primitive checks [MediaQuery.disableAnimationsOf] and renders its
/// final state immediately when the user has asked the OS to reduce motion.
class PharmacyMotion {
  PharmacyMotion._();

  static const fast = Duration(milliseconds: 160);
  static const medium = Duration(milliseconds: 320);
  static const slow = Duration(milliseconds: 650);

  /// Decelerating curve for things arriving on screen.
  static const enter = Curves.easeOutCubic;

  /// Gentle overshoot for things that "land" (counters, bars, badges).
  static const settle = Curves.easeOutBack;

  /// Gap between consecutive items in a staggered list. Capped by
  /// [PharmacyEntrance] so a long list does not keep the last rows waiting.
  static const stagger = Duration(milliseconds: 45);

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

// ───────────────────────────── Entrance ─────────────────────────────

/// Fades and lifts [child] into place once, when first built.
///
/// [index] staggers siblings: item n waits `n × stagger`, capped at the
/// eighth item so rows far down a list are not left blank for long.
class PharmacyEntrance extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration delay;
  final double offsetY;
  final Duration duration;

  const PharmacyEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.delay = Duration.zero,
    this.offsetY = 14,
    this.duration = const Duration(milliseconds: 420),
  });

  @override
  State<PharmacyEntrance> createState() => _PharmacyEntranceState();
}

class _PharmacyEntranceState extends State<PharmacyEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: PharmacyMotion.enter,
  );
  Timer? _start;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted || _start != null) return;
    if (PharmacyMotion.reduced(context)) {
      _c.value = 1;
      return;
    }
    // The entrance is for a screen's first paint. A card built because the
    // list was scrolled to it must already be there — fading it in (after a
    // stagger delay, on top) is what made long lists feel laggy.
    final position = Scrollable.maybeOf(context)?.position;
    if (position != null && position.hasPixels && position.pixels > 0) {
      _c.value = 1;
      return;
    }
    final wait =
        widget.delay + PharmacyMotion.stagger * widget.index.clamp(0, 8);
    if (wait == Duration.zero) {
      _c.forward();
    } else {
      _start = Timer(wait, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _start?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _t.value) * widget.offsetY),
          child: child,
        ),
      ),
    );
  }
}

// ───────────────────────────── Pressable ────────────────────────────

/// Wraps a tappable surface so it sinks to [scale] while pressed and gives a
/// light haptic tick on tap. Replaces bare InkWells on cards and tiles,
/// where a ripple alone reads as flat on a white page.
class PharmacyPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;

  /// Read by screen readers; set it whenever the child is icon-only.
  final String? semanticLabel;

  const PharmacyPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.haptic = true,
    this.semanticLabel,
  });

  @override
  State<PharmacyPressable> createState() => _PharmacyPressableState();
}

class _PharmacyPressableState extends State<PharmacyPressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final reduced = PharmacyMotion.reduced(context);
    return Semantics(
      button: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.haptic) HapticFeedback.selectionClick();
                widget.onTap!();
              },
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _down && !reduced ? widget.scale : 1,
          duration: PharmacyMotion.fast,
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: _down ? 0.92 : 1,
            duration: PharmacyMotion.fast,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── Count-up ─────────────────────────────

/// Rolls a number from its previous value to [value] and formats each frame
/// with [format]. The first build counts up from zero, so a figure arriving
/// from the network reads as "just landed" rather than "was always there".
class PharmacyCountUp extends StatefulWidget {
  final num value;
  final String Function(num value) format;
  final TextStyle? style;
  final Duration duration;
  final TextAlign? textAlign;

  const PharmacyCountUp({
    super.key,
    required this.value,
    required this.format,
    this.style,
    this.duration = const Duration(milliseconds: 900),
    this.textAlign,
  });

  @override
  State<PharmacyCountUp> createState() => _PharmacyCountUpState();
}

class _PharmacyCountUpState extends State<PharmacyCountUp> {
  double _from = 0;

  @override
  void didUpdateWidget(PharmacyCountUp old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _from = old.value.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.value.toDouble();
    if (PharmacyMotion.reduced(context)) {
      return Text(
        widget.format(widget.value),
        style: widget.style,
        textAlign: widget.textAlign,
        maxLines: 1,
      );
    }
    return TweenAnimationBuilder<double>(
      key: ValueKey(target),
      tween: Tween(begin: _from, end: target),
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Text(
        // Whole numbers stay whole mid-roll; a count that flickers through
        // 3.47 on its way to 4 looks broken.
        widget.format(widget.value is int ? v.round() : v),
        style: widget.style,
        textAlign: widget.textAlign,
        maxLines: 1,
      ),
    );
  }
}

// ────────────────────────────── Pulse ───────────────────────────────

/// A breathing dot with an expanding halo — the module's "live" signal.
/// Used for orders waiting on the store, never for decoration.
class PharmacyPulse extends StatefulWidget {
  final Color color;
  final double size;

  const PharmacyPulse({
    super.key,
    this.color = PharmacyColors.green,
    this.size = 8,
  });

  @override
  State<PharmacyPulse> createState() => _PharmacyPulseState();
}

class _PharmacyPulseState extends State<PharmacyPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (PharmacyMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 2.6,
      height: s * 2.6,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = Curves.easeOut.transform(_c.value);
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: s + s * 1.6 * t,
                height: s + s * 1.6 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.35 * (1 - t)),
                ),
              ),
              Container(
                width: s,
                height: s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ──────────────────────────── Grow bar ──────────────────────────────

/// A bar that grows from zero to [fraction] of [maxHeight] when first shown,
/// and animates between values afterwards. For the small trend charts.
class PharmacyGrowBar extends StatelessWidget {
  final double fraction;
  final double maxHeight;
  final double minHeight;
  final double width;
  final Color color;
  final int index;

  const PharmacyGrowBar({
    super.key,
    required this.fraction,
    required this.maxHeight,
    required this.color,
    this.minHeight = 4,
    this.width = 8,
    this.index = 0,
  });

  @override
  Widget build(BuildContext context) {
    final target = minHeight + (maxHeight - minHeight) * fraction.clamp(0, 1);
    if (PharmacyMotion.reduced(context)) {
      return _bar(target);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: minHeight, end: target),
      duration: Duration(milliseconds: 650 + index * 60),
      curve: PharmacyMotion.settle,
      builder: (_, h, _) => _bar(h.clamp(minHeight, maxHeight + 6)),
    );
  }

  Widget _bar(double h) => Container(
    width: width,
    height: h,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(width / 2),
    ),
  );
}

// ─────────────────────────── Scrolling ──────────────────────────────

/// Pharmacy screens stay pinned when pulled: no Android stretch, no glow, no
/// iOS rubber-band. Pull-to-refresh still works — its spinner floats over the
/// content instead of the whole page being dragged down with the finger.
class PharmacyScrollBehavior extends MaterialScrollBehavior {
  const PharmacyScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const ClampingScrollPhysics();
}

/// Applies [PharmacyScrollBehavior] to everything below it.
class PharmacyScrollScope extends StatelessWidget {
  final Widget child;
  const PharmacyScrollScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: const PharmacyScrollBehavior(),
    child: child,
  );
}

// ─────────────────────────── Page route ─────────────────────────────

/// The module's screen transition: incoming page fades in while rising a
/// few pixels, outgoing page dims back. Softer than Android's default zoom
/// and quicker than a full slide.
///
/// On iOS it defers to the platform transition so the edge-swipe back
/// gesture keeps working.
class PharmacyPageRoute<T> extends MaterialPageRoute<T> {
  PharmacyPageRoute({required super.builder, super.settings});

  /// Every pharmacy screen opened this way gets the pinned scrolling.
  @override
  Widget buildContent(BuildContext context) =>
      PharmacyScrollScope(child: super.buildContent(context));

  @override
  Duration get transitionDuration => const Duration(milliseconds: 340);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 260);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      return const CupertinoPageTransitionsBuilder().buildTransitions(
        this,
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    if (PharmacyMotion.reduced(context)) return child;
    final enter = CurvedAnimation(
      parent: animation,
      curve: PharmacyMotion.enter,
      reverseCurve: Curves.easeInCubic,
    );
    final exit = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.6).animate(exit),
      child: FadeTransition(
        opacity: enter,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.035),
            end: Offset.zero,
          ).animate(enter),
          child: child,
        ),
      ),
    );
  }
}

// ──────────────────────────── Floating ──────────────────────────────

/// Drifts [child] up and down by [amplitude] pixels, forever. For the one
/// illustration on an empty state, so the screen does not look frozen.
class PharmacyFloat extends StatefulWidget {
  final Widget child;
  final double amplitude;

  const PharmacyFloat({super.key, required this.child, this.amplitude = 4});

  @override
  State<PharmacyFloat> createState() => _PharmacyFloatState();
}

class _PharmacyFloatState extends State<PharmacyFloat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (PharmacyMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
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
      child: widget.child,
      builder: (_, child) => Transform.translate(
        offset: Offset(
          0,
          (Curves.easeInOut.transform(_c.value) - 0.5) * 2 * widget.amplitude,
        ),
        child: child,
      ),
    );
  }
}
