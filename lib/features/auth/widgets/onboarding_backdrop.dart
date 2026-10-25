import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'onboarding_hero.dart' show kAadyaBlue, kAadyaGreen;

/// The registration background: white, with soft washes of the logo's blue
/// and green drifting slowly around the top corners. Faint enough that text
/// on top keeps full contrast; it just keeps the long form from feeling
/// static. Holds still when "reduce motion" is on.
class OnboardingBackdrop extends StatefulWidget {
  final Widget child;
  const OnboardingBackdrop({super.key, required this.child});

  @override
  State<OnboardingBackdrop> createState() => _OnboardingBackdropState();
}

class _OnboardingBackdropState extends State<OnboardingBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
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
    final width = MediaQuery.sizeOf(context).width;
    Widget wash(Color c, double size, double opacity) => IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              c.withValues(alpha: opacity),
              c.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );

    return ColoredBox(
      color: Colors.white,
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = _c.value * 2 * math.pi;
                return Stack(
                  children: [
                    Positioned(
                      top: -width * 0.45 + math.sin(t) * 20,
                      left: -width * 0.35 + math.cos(t) * 24,
                      child: wash(kAadyaBlue, width * 1.1, 0.16),
                    ),
                    Positioned(
                      top: -width * 0.3 + math.cos(t) * 18,
                      right: -width * 0.45 + math.sin(t) * 22,
                      child: wash(kAadyaGreen, width * 0.95, 0.13),
                    ),
                  ],
                );
              },
            ),
          ),
          Positioned.fill(child: widget.child),
        ],
      ),
    );
  }
}
