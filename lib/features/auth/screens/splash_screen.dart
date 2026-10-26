import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../pharmacy/theme/pharmacy_type.dart';
import '../providers/auth_provider.dart';
import '../widgets/onboarding_hero.dart';

/// Launch screen, staged like a title sequence on the same midnight stage
/// the sign-in screen uses:
///
/// 1. The aurora opens up out of the dark.
/// 2. The mark settles in, and a band of light sweeps across it.
/// 3. "Aadya Plus" rises letter by letter, then the PRO tag pops in.
/// 4. A gradient loading line runs at the foot while the session is checked.
///
/// The saved-session check runs during the animation, so opening the app
/// takes as long as the slower of the two, not the sum.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  late final AnimationController _loading = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  static const _word = 'Aadya Plus';

  @override
  void initState() {
    super.initState();
    _route();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _intro.value = 1;
    } else if (!_intro.isAnimating && !_intro.isCompleted) {
      _intro.forward();
      _loading.repeat();
    }
  }

  Future<void> _route() async {
    final minimum = Future<void>.delayed(const Duration(milliseconds: 2100));
    final signedIn = await ref.read(authProvider.notifier).tryAutoLogin();
    await minimum;
    if (!mounted) return;
    final user = ref.read(authProvider).user;
    // See login_screen.dart — profileCompleted is the real gate, not
    // verificationStatus (that only affects public discoverability).
    final route = !signedIn
        ? '/login'
        : (user != null && user.profileCompleted)
        ? '/dashboard'
        : '/pending';
    Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  void dispose() {
    _intro.dispose();
    _loading.dispose();
    super.dispose();
  }

  double _phase(double from, double to, [Curve curve = Curves.easeOutCubic]) {
    final v = ((_intro.value - from) / (to - from)).clamp(0.0, 1.0);
    return curve.transform(v);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final badge = math.min(size.width * 0.28, 116.0);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: kStageTop,
        body: AnimatedBuilder(
          animation: Listenable.merge([_intro, _loading]),
          builder: (context, _) {
            final bloom = _phase(0.0, 0.5);
            final markIn = _phase(0.12, 0.42, Curves.easeOutBack);
            final markFade = _phase(0.12, 0.3);
            final shine = _phase(0.38, 0.68, Curves.easeInOutCubic);
            final tag = _phase(0.7, 0.9);
            final foot = _phase(0.78, 1.0);

            return Stack(
              fit: StackFit.expand,
              children: [
                AuroraBackdrop(tint: const Color(0xFF6D5BF0), bloom: bloom),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // The mark: a white tile with a halo, then a sweep of
                    // light across it.
                    Opacity(
                      opacity: markFade,
                      child: Transform.scale(
                        scale: 0.8 + 0.2 * markIn,
                        child: SizedBox(
                          width: badge * 1.7,
                          height: badge * 1.7,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: badge * 1.55,
                                height: badge * 1.55,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      Colors.white.withValues(alpha: 0.16),
                                      Colors.white.withValues(alpha: 0),
                                    ],
                                  ),
                                ),
                              ),
                              Container(
                                width: badge,
                                height: badge,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(
                                    badge * 0.28,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x66000000),
                                      blurRadius: 40,
                                      offset: Offset(0, 16),
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    // The logo fills its square; shown
                                    // as is, on its own white tile.
                                    Transform.scale(
                                      scale: 1,
                                      child: Image.asset(
                                        'assets/brand/icon.png',
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    if (shine > 0 && shine < 1)
                                      Transform.translate(
                                        offset: Offset(
                                          badge * (2.4 * shine - 1.2),
                                          0,
                                        ),
                                        child: Transform.rotate(
                                          angle: 0.35,
                                          child: Container(
                                            width: badge * 0.35,
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  Colors.white.withValues(
                                                    alpha: 0,
                                                  ),
                                                  Colors.white.withValues(
                                                    alpha: 0.85,
                                                  ),
                                                  Colors.white.withValues(
                                                    alpha: 0,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // The wordmark, letter by letter, then the PRO tag.
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _word.length; i++) _letter(i),
                        const SizedBox(width: 10),
                        Opacity(
                          opacity: tag,
                          child: Transform.scale(
                            scale:
                                0.6 +
                                0.4 * _phase(0.7, 0.9, Curves.easeOutBack),
                            child: const ProBadge(size: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 40),
                      child: Opacity(
                        opacity: foot,
                        child: Column(
                          children: [
                            _LoadingLine(t: _loading.value),
                            const SizedBox(height: 14),
                            Text(
                              'Connecting healthcare',
                              style: PharmacyType.sans(
                                fontSize: PharmacyType.small,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// One letter of the wordmark, rising in on its own beat.
  Widget _letter(int i) {
    final start = 0.42 + i * 0.03;
    final v = _phase(start, start + 0.22, Curves.easeOutCubic);
    final plus = i >= 6; // "Plus", after the space
    return Opacity(
      opacity: v,
      child: Transform.translate(
        offset: Offset(0, 16 * (1 - v)),
        child: Text(
          _word[i],
          style: PharmacyType.sans(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: plus ? const Color(0xFF8CF0B8) : Colors.white,
            letterSpacing: -0.8,
          ),
        ),
      ),
    );
  }
}

/// A short gradient segment travelling along a faint track.
class _LoadingLine extends StatelessWidget {
  final double t;
  const _LoadingLine({required this.t});

  @override
  Widget build(BuildContext context) {
    const w = 110.0;
    const seg = 40.0;
    final x = Curves.easeInOutCubic.transform(t) * (w + seg) - seg;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        width: w,
        height: 3,
        child: Stack(
          children: [
            Container(color: Colors.white.withValues(alpha: 0.14)),
            Positioned(
              left: x,
              child: Container(
                width: seg,
                height: 3,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0x008CF0B8),
                      Color(0xFF8CF0B8),
                      Colors.white,
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
}
