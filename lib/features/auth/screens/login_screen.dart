import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/network/api_service.dart';
import '../../pharmacy/theme/pharmacy_colors.dart';
import '../../pharmacy/theme/pharmacy_type.dart';
import '../../pharmacy/widgets/pharmacy_ui.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../widgets/onboarding_hero.dart';
import 'phone_otp_screen.dart';

/// Sign-in for every professional role. Uses the same minimal kit as the
/// pharmacy module — white page, grey fields, one green — so the app reads
/// as one product from the first screen.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  /// Field errors appear only after a sign-in attempt, not while typing.
  bool _attempted = false;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

  /// The stage's light follows the showcase's current module.
  final _tint = ValueNotifier<Color>(LoginShowcase.firstTint);

  /// Hides the "signed out" notice after a while; it's information, not
  /// something to act on.
  Timer? _noticeTimer;

  void _scheduleNoticeHide() {
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 7), () {
      if (mounted) ref.read(authProvider.notifier).clearNotice();
    });
  }

  @override
  void initState() {
    super.initState();
    // Re-validate as the user fixes a field after a failed attempt.
    _emailController.addListener(_onChanged);
    _passwordController.addListener(_onChanged);
    if (ref.read(authProvider).notice != null) _scheduleNoticeHide();
  }

  void _onChanged() {
    if (_attempted) setState(() {});
  }

  @override
  void dispose() {
    _tint.dispose();
    _noticeTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? get _emailError {
    if (!_attempted) return null;
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      return 'Enter your email';
    }
    if (!_emailPattern.hasMatch(email)) {
      return 'That doesn’t look like an email';
    }
    return null;
  }

  String? get _passwordError => _attempted && _passwordController.text.isEmpty
      ? 'Enter your password'
      : null;

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    setState(() => _attempted = true);
    if (_emailError != null || _passwordError != null) return;

    final authNotifier = ref.read(authProvider.notifier);
    final success = await authNotifier.login(
      _emailController.text.trim(),
      _passwordController.text.trim(),
    );
    if (!mounted || !success) return; // the error shows in the banner

    final user = ref.read(authProvider).user;
    // Admin verification gates public discoverability (patients booking a
    // doctor, ordering from a pharmacy) on the backend — it never gates a
    // professional's own ability to manage their practice/store/inventory.
    // The real precondition for the dashboard is a completed profile.
    Navigator.of(context).pushNamedAndRemoveUntil(
      user != null && user.profileCompleted ? '/dashboard' : '/pending',
      (r) => false,
    );
  }

  Future<void> _handleForgotPassword() async {
    final email = await showPharmacySheet<String>(
      context,
      builder: (_) => _EmailSheet(
        title: 'Reset your password',
        subtitle: 'We’ll email you a link to set a new one.',
        action: 'Send reset link',
        initial: _emailController.text.trim(),
      ),
    );
    if (email == null || !mounted) return;
    try {
      await ApiService().forgotPassword(email);
      _toast(
        'If an account exists for $email, a reset link is on its way.',
        PharmacyColors.textStrong,
      );
    } catch (_) {
      _toast(
        'Couldn’t send the link. Check your connection and try again.',
        PharmacyColors.error,
      );
    }
  }

  Future<void> _handleResendVerification() async {
    final email = await showPharmacySheet<String>(
      context,
      builder: (_) => _EmailSheet(
        title: 'Resend verification email',
        subtitle: 'We’ll send a fresh link to confirm your email.',
        action: 'Resend',
        initial: _emailController.text.trim(),
      ),
    );
    if (email == null || !mounted) return;
    try {
      await ApiService().resendVerification(email);
      _toast(
        'If $email is waiting for verification, a new link has been sent.',
        PharmacyColors.textStrong,
      );
    } catch (_) {
      _toast(
        'Couldn’t resend the email. Check your connection and try again.',
        PharmacyColors.error,
      );
    }
  }

  void _toast(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: PharmacyType.sans(
            fontSize: PharmacyType.caption,
            color: Colors.white,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    ref.listen<String?>(authProvider.select((s) => s.notice), (_, next) {
      if (next != null) _scheduleNoticeHide();
    });
    var i = 0;
    Widget enter(Widget child) => PharmacyEntrance(index: i++, child: child);

    final heroHeight = 308 + MediaQuery.paddingOf(context).top;
    return OnboardingLayout(
      heroHeight: heroHeight,
      hero: OnboardingHero(
        // Logo row, bars, headline and card — no dead space under it.
        height: heroHeight,
        tint: _tint,
        scene: LoginShowcase(onTint: (c) => _tint.value = c),
        topLeft: const Padding(
          padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Align(alignment: Alignment.centerLeft, child: HeroLogo()),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  enter(
                    Text(
                      'Welcome back',
                      style: PharmacyType.sans(
                        fontSize: PharmacyType.display,
                        fontWeight: FontWeight.w800,
                        color: PharmacyColors.textStrong,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  enter(
                    Text(
                      'Sign in to manage your practice, lab, pharmacy or field work.',
                      style: PharmacyType.sans(
                        fontSize: PharmacyType.body,
                        color: PharmacyColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  AnimatedSize(
                    duration: PharmacyMotion.fast,
                    alignment: Alignment.topCenter,
                    child: AnimatedSwitcher(
                      duration: PharmacyMotion.medium,
                      switchInCurve: PharmacyMotion.enter,
                      transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, -0.15),
                            end: Offset.zero,
                          ).animate(a),
                          child: child,
                        ),
                      ),
                      child: authState.error != null
                          ? Padding(
                              key: const ValueKey('error'),
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _AuthNote.error(
                                message: authState.error!,
                                onClose: () => ref
                                    .read(authProvider.notifier)
                                    .clearError(),
                              ),
                            )
                          : authState.notice == 'session_expired'
                          ? Padding(
                              key: const ValueKey('notice'),
                              padding: const EdgeInsets.only(bottom: 16),
                              child: _AuthNote.info(
                                title: 'You’ve been signed out',
                                message:
                                    'Your session ended for security. Sign in again to pick up where you left off.',
                                onClose: () => ref
                                    .read(authProvider.notifier)
                                    .clearNotice(),
                              ),
                            )
                          : const SizedBox(
                              key: ValueKey('none'),
                              width: double.infinity,
                            ),
                    ),
                  ),
                  enter(
                    PharmacyTextField(
                      label: 'Email',
                      controller: _emailController,
                      icon: LucideIcons.mail,
                      hint: 'you@example.com',
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      errorText: _emailError,
                      margin: const EdgeInsets.only(bottom: 14),
                    ),
                  ),
                  enter(
                    PharmacyTextField(
                      label: 'Password',
                      controller: _passwordController,
                      icon: LucideIcons.lock,
                      hint: 'Your password',
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _handleLogin(),
                      autofillHints: const [AutofillHints.password],
                      errorText: _passwordError,
                      margin: EdgeInsets.zero,
                      trailing: IconButton(
                        tooltip: _obscurePassword
                            ? 'Show password'
                            : 'Hide password',
                        icon: Icon(
                          _obscurePassword
                              ? LucideIcons.eye
                              : LucideIcons.eyeOff,
                          size: 18,
                          color: PharmacyColors.textTertiary,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                  ),
                  // Both account-recovery links on one line.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _LinkButton(
                        label: 'Resend verification',
                        muted: true,
                        onTap: _handleResendVerification,
                      ),
                      _LinkButton(
                        label: 'Forgot password?',
                        onTap: _handleForgotPassword,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  enter(
                    PharmacyButton(
                      label: 'Sign in',
                      loading: authState.isLoading,
                      onPressed: authState.isLoading ? null : _handleLogin,
                    ),
                  ),
                  const SizedBox(height: 14),
                  // OTP sits alongside the password form rather than
                  // replacing it: accounts that share a mobile number are
                  // refused OTP server-side, and those users still need
                  // this path.
                  Row(
                    children: [
                      const Expanded(
                        child: Divider(color: PharmacyColors.border),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or',
                          style: PharmacyType.sans(
                            fontSize: PharmacyType.caption,
                            color: PharmacyColors.textTertiary,
                          ),
                        ),
                      ),
                      const Expanded(
                        child: Divider(color: PharmacyColors.border),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  enter(
                    PharmacySecondaryButton(
                      label: 'Continue with mobile number',
                      icon: LucideIcons.smartphone,
                      onPressed: authState.isLoading
                          ? null
                          : () => Navigator.of(context).push(
                              PharmacyPageRoute(
                                builder: (_) => const PhoneOtpScreen(),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  enter(
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'New to Aadya Plus Pro? ',
                          style: PharmacyType.sans(
                            fontSize: PharmacyType.body,
                            color: PharmacyColors.textSecondary,
                          ),
                        ),
                        _LinkButton(
                          label: 'Create an account',
                          strong: true,
                          onTap: () =>
                              Navigator.of(context).pushNamed('/register'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The five modules, with how they're described. Shared by the role step
/// of registration. MR accounts are created by a manager or admin, so that
/// card points to sign-in instead of the sign-up form.
typedef ProfessionalRoleInfo = ({
  UserRole role,
  String title,
  String subtitle,
  IconData icon,
});

const List<ProfessionalRoleInfo> kProfessionalRoles = [
  (
    role: UserRole.doctor,
    title: 'Doctor',
    subtitle: 'Consultations, appointments and prescriptions',
    icon: LucideIcons.stethoscope,
  ),
  (
    role: UserRole.physiotherapist,
    title: 'Physiotherapist',
    subtitle: 'Sessions, home visits and exercise plans',
    icon: LucideIcons.activity,
  ),
  (
    role: UserRole.pathology,
    title: 'Pathology lab',
    subtitle: 'Test bookings, sample collection and reports',
    icon: LucideIcons.flaskConical,
  ),
  (
    role: UserRole.pharmacy,
    title: 'Pharmacy',
    subtitle: 'Online orders, stock and billing',
    icon: LucideIcons.pill,
  ),
  (
    role: UserRole.mr,
    title: 'Medical rep (MR)',
    subtitle: 'Doctor calls, tour plans, samples and approvals',
    icon: LucideIcons.briefcaseMedical,
  ),
];

/// A note above the sign-in form: a calm blue notice ("You've been signed
/// out") or a red error ("Wrong password"). Icon in a soft circle, a short
/// bold line, then the detail — readable at a glance, never shouting.
class _AuthNote extends StatelessWidget {
  final String? title;
  final String message;
  final VoidCallback onClose;
  final bool isError;

  const _AuthNote.error({required this.message, required this.onClose})
    : title = null,
      isError = true;

  const _AuthNote.info({
    required String this.title,
    required this.message,
    required this.onClose,
  }) : isError = false;

  @override
  Widget build(BuildContext context) {
    final tone = isError ? PharmacyColors.error : ModuleAccent.onboarding.color;
    final bg = isError
        ? PharmacyColors.errorBg
        : ModuleAccent.onboarding.veryLight;
    // An error is one short line ("Wrong password"): keep it a slim strip
    // whose height is the text's, not the icon's or the close button's.
    final compact = title == null;
    final iconBox = compact ? 22.0 : 32.0;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: compact
            ? const EdgeInsets.fromLTRB(10, 8, 6, 8)
            : const EdgeInsets.fromLTRB(12, 12, 4, 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(compact ? 12 : 14),
          border: Border.all(color: tone.withValues(alpha: 0.18)),
        ),
        child: Row(
          crossAxisAlignment: compact
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Container(
              width: iconBox,
              height: iconBox,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isError ? LucideIcons.circleAlert : LucideIcons.clock3,
                size: compact ? 13 : 16,
                color: tone,
              ),
            ),
            SizedBox(width: compact ? 10 : 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: compact ? 0 : 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null) ...[
                      Text(
                        title!,
                        style: PharmacyType.sans(
                          fontSize: PharmacyType.body,
                          fontWeight: FontWeight.w700,
                          color: PharmacyColors.textStrong,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      message,
                      style: PharmacyType.sans(
                        fontSize: PharmacyType.small,
                        fontWeight: compact ? FontWeight.w600 : FontWeight.w400,
                        color: compact ? tone : PharmacyColors.textSecondary,
                        height: compact ? 1.25 : 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // No IconButton: its 40px minimum would set the strip's height.
            Semantics(
              button: true,
              label: 'Dismiss',
              child: InkResponse(
                onTap: onClose,
                radius: 16,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    LucideIcons.x,
                    size: 14,
                    color: PharmacyColors.textTertiary,
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

class _LinkButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool strong;
  final bool muted;
  const _LinkButton({
    required this.label,
    required this.onTap,
    this.strong = false,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      minimumSize: const Size(0, 36),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: muted
          ? PharmacyColors.textSecondary
          : ModuleAccent.of(context).color,
    ),
    child: Text(
      label,
      style: PharmacyType.sans(
        fontSize: muted ? PharmacyType.small : PharmacyType.body,
        fontWeight: strong || !muted ? FontWeight.w700 : FontWeight.w500,
      ),
    ),
  );
}

/// One email field and an action. Owns its controller, so it is disposed
/// only after the sheet has finished closing.
class _EmailSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final String action;
  final String initial;
  const _EmailSheet({
    required this.title,
    required this.subtitle,
    required this.action,
    required this.initial,
  });

  @override
  State<_EmailSheet> createState() => _EmailSheetState();
}

class _EmailSheetState extends State<_EmailSheet> {
  late final _email = TextEditingController(text: widget.initial);

  @override
  void initState() {
    super.initState();
    _email.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  bool get _valid =>
      _LoginScreenState._emailPattern.hasMatch(_email.text.trim());

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: PharmacyType.sans(
            fontSize: PharmacyType.title,
            fontWeight: FontWeight.w700,
            color: PharmacyColors.textStrong,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.subtitle,
          style: PharmacyType.sans(
            fontSize: PharmacyType.caption,
            color: PharmacyColors.textTertiary,
          ),
        ),
        const SizedBox(height: 16),
        PharmacyTextField(
          label: 'Email',
          controller: _email,
          icon: LucideIcons.mail,
          hint: 'you@example.com',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (_valid) Navigator.pop(context, _email.text.trim());
          },
          margin: EdgeInsets.zero,
        ),
        const SizedBox(height: 16),
        PharmacyButton(
          label: widget.action,
          onPressed: _valid
              ? () => Navigator.pop(context, _email.text.trim())
              : null,
        ),
      ],
    ),
  );
}
