import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../pharmacy/theme/pharmacy_colors.dart';
import '../../pharmacy/theme/pharmacy_type.dart';
import '../../pharmacy/widgets/pharmacy_ui.dart';
import '../providers/auth_provider.dart';
import '../widgets/onboarding_hero.dart';
import 'register_screen.dart';

/// Sign in with a mobile number and an SMS code.
///
/// Offered *alongside* email and password, not instead of it: several existing
/// accounts share a phone number, and the server refuses OTP for an ambiguous
/// number — those users still need the password path.
///
/// A number with no account is not rejected. It comes back from verification
/// with a single-use token and goes straight into registration with the phone
/// already proven.
class PhoneOtpScreen extends ConsumerStatefulWidget {
  const PhoneOtpScreen({super.key});

  @override
  ConsumerState<PhoneOtpScreen> createState() => _PhoneOtpScreenState();
}

enum _Step { phone, code }

class _PhoneOtpScreenState extends ConsumerState<PhoneOtpScreen> {
  static const _codeLength = 6;

  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _codeFocus = FocusNode();

  _Step _step = _Step.phone;
  String _purpose = 'login';
  bool _busy = false;
  String? _error;

  /// Seconds until the code can be resent. The server enforces the same
  /// cooldown; this only stops the user hammering a button that will fail.
  int _resendIn = 0;

  /// Bumped on a wrong code; the boxes shake once per bump.
  int _shake = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _phone.addListener(() => setState(() {}));
    _code.addListener(_onCodeChanged);
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phone.dispose();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  /// Six digits in — from typing or SMS autofill — verifies without a tap.
  void _onCodeChanged() {
    setState(() {
      if (_error != null) _error = null;
    });
    if (_code.text.length == _codeLength && !_busy) _verifyCode();
  }

  void _startResendCountdown(int seconds) {
    _resendTimer?.cancel();
    setState(() => _resendIn = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _resendIn -= 1);
      if (_resendIn <= 0) timer.cancel();
    });
  }

  bool get _phoneValid => RegExp(r'^[6-9]\d{9}$').hasMatch(_phone.text.trim());

  Future<void> _sendCode() async {
    if (!_phoneValid) {
      setState(() => _error = 'Enter your 10-digit mobile number');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await ref
        .read(authProvider.notifier)
        .sendPhoneOtp(_phone.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.error;
      if (result.ok) {
        _purpose = result.purpose;
        _step = _Step.code;
        _code.clear();
      }
    });
    if (result.ok) {
      _startResendCountdown(60);
      _codeFocus.requestFocus();
    }
  }

  Future<void> _verifyCode() async {
    final code = _code.text.trim();
    if (code.length < 4) {
      setState(() => _error = 'Enter the code from the SMS');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await ref
        .read(authProvider.notifier)
        .verifyPhoneOtp(_phone.text.trim(), code);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.error;
    });

    if (!result.ok) {
      // A wrong code is retyped from scratch, not edited digit by digit.
      setState(() => _shake++);
      _code.clear();
      _codeFocus.requestFocus();
      HapticFeedback.lightImpact();
      return;
    }

    if (result.registered) {
      // The provider already stored the session; the root listener routes to
      // the dashboard, so just close this screen.
      if (mounted) Navigator.of(context).pop();
      return;
    }

    // New number: carry the proven phone and its token into registration.
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      PharmacyPageRoute(
        builder: (_) => RegisterScreen(
          prefilledPhone: _phone.text.trim(),
          phoneVerificationToken: result.verificationToken,
        ),
      ),
    );
  }

  /// Back from the code step returns to the number, not out of the flow — a
  /// mistyped number is the most likely reason to go back.
  void _back() {
    if (_step == _Step.code) {
      _resendTimer?.cancel();
      setState(() {
        _step = _Step.phone;
        _error = null;
        _resendIn = 0;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final onCode = _step == _Step.code;
    final height = MediaQuery.sizeOf(context).height;

    final heroHeight = (height * 0.46).clamp(300.0, 420.0);
    return PopScope(
      canPop: !onCode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: OnboardingLayout(
        heroHeight: heroHeight,
        hero: OnboardingHero(
          height: heroHeight,
          scene: SmsScene(codeSent: onCode),
          topLeft: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: HeroBackButton(
                tooltip: onCode ? 'Change number' : 'Back',
                onPressed: _back,
              ),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 12),
          child: AnimatedSwitcher(
            duration: PharmacyMotion.medium,
            switchInCurve: PharmacyMotion.enter,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0.06, 0),
                  end: Offset.zero,
                ).animate(a),
                child: child,
              ),
            ),
            child: KeyedSubtree(
              key: ValueKey(_step),
              child: onCode ? _codeStep() : _phoneStep(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _title(String title, Widget subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: PharmacyType.sans(
          fontSize: PharmacyType.display,
          fontWeight: FontWeight.w800,
          color: PharmacyColors.textStrong,
          letterSpacing: -0.5,
        ),
      ),
      const SizedBox(height: 6),
      subtitle,
    ],
  );

  Widget _phoneStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _title(
        'Sign in with mobile',
        Text(
          'We’ll text you a 6-digit code. No password needed.',
          style: PharmacyType.sans(
            fontSize: PharmacyType.body,
            height: 1.45,
            color: PharmacyColors.textSecondary,
          ),
        ),
      ),
      const SizedBox(height: 24),
      _phoneField(),
      _errorLine(),
      const SizedBox(height: 20),
      PharmacyButton(
        label: 'Send code',
        icon: LucideIcons.send,
        loading: _busy,
        onPressed: _busy || !_phoneValid ? null : _sendCode,
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          const Icon(
            LucideIcons.shieldCheck,
            size: 14,
            color: PharmacyColors.textTertiary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Your number is only used to sign you in.',
              style: PharmacyType.sans(
                fontSize: PharmacyType.caption,
                color: PharmacyColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Center(
        child: _link(
          'Use email and password instead',
          () => Navigator.of(context).pop(),
          muted: true,
        ),
      ),
    ],
  );

  Widget _codeStep() {
    final accent = ModuleAccent.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(
          'Enter the code',
          Text.rich(
            TextSpan(
              text: 'Sent to ',
              style: PharmacyType.sans(
                fontSize: PharmacyType.body,
                color: PharmacyColors.textSecondary,
              ),
              children: [
                TextSpan(
                  text: '+91 ${_formatted()}',
                  style: PharmacyType.sans(
                    fontSize: PharmacyType.body,
                    fontWeight: FontWeight.w700,
                    color: PharmacyColors.textStrong,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_purpose == 'signup') ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accent.veryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.userPlus, size: 16, color: accent.color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No account uses this number yet. After the code, we’ll help you create one.',
                    style: PharmacyType.sans(
                      fontSize: PharmacyType.small,
                      height: 1.45,
                      color: PharmacyColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        _ShakeOnChange(trigger: _shake, child: _codeBoxes(accent)),
        _errorLine(),
        const SizedBox(height: 20),
        PharmacyButton(
          label: 'Verify and continue',
          loading: _busy,
          onPressed: _busy || _code.text.length != _codeLength
              ? null
              : _verifyCode,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _link('Change number', _back),
            _link(
              _resendIn > 0
                  ? 'Resend in 0:${_resendIn.toString().padLeft(2, '0')}'
                  : 'Resend code',
              _resendIn > 0 || _busy ? null : _sendCode,
            ),
          ],
        ),
      ],
    );
  }

  Widget _errorLine() => AnimatedSize(
    duration: PharmacyMotion.fast,
    child: _error == null
        ? const SizedBox(width: double.infinity)
        : Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  LucideIcons.circleAlert,
                  size: 15,
                  color: PharmacyColors.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error!,
                    style: PharmacyType.sans(
                      fontSize: PharmacyType.small,
                      color: PharmacyColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
  );

  String _formatted() {
    final p = _phone.text.trim();
    return p.length == 10 ? '${p.substring(0, 5)} ${p.substring(5)}' : p;
  }

  Widget _phoneField() => TextField(
    controller: _phone,
    keyboardType: TextInputType.phone,
    autofocus: true,
    autofillHints: const [AutofillHints.telephoneNumberNational],
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(10),
    ],
    cursorColor: ModuleAccent.of(context).color,
    style: PharmacyType.sans(
      fontSize: PharmacyType.title,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
      color: PharmacyColors.textStrong,
    ),
    decoration: InputDecoration(
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 16, right: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '+91',
              style: PharmacyType.sans(
                fontSize: PharmacyType.title,
                fontWeight: FontWeight.w700,
                color: PharmacyColors.textSecondary,
              ),
            ),
            const SizedBox(width: 10),
            Container(width: 1, height: 18, color: PharmacyColors.borderStrong),
          ],
        ),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      suffixIcon: AnimatedSwitcher(
        duration: PharmacyMotion.fast,
        child: _phoneValid
            ? Icon(
                LucideIcons.circleCheck,
                key: const ValueKey('ok'),
                size: 20,
                color: ModuleAccent.of(context).color,
              )
            : const SizedBox.shrink(key: ValueKey('no')),
      ),
      hintText: '98765 43210',
      hintStyle: PharmacyType.sans(
        fontSize: PharmacyType.title,
        letterSpacing: 1.2,
        color: PharmacyColors.textDisabled,
      ),
      filled: true,
      fillColor: PharmacyColors.panel,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: ModuleAccent.of(context).color,
          width: 1.5,
        ),
      ),
    ),
    onSubmitted: (_) => _sendCode(),
  );

  /// Six boxes over one invisible field, so the keyboard, paste and SMS
  /// autofill all work as for a normal text field. Each digit pops in.
  Widget _codeBoxes(ModuleAccent accent) {
    final digits = _code.text;
    return GestureDetector(
      onTap: () => _codeFocus.requestFocus(),
      child: Stack(
        children: [
          Row(
            children: [
              for (var i = 0; i < _codeLength; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: AnimatedContainer(
                    duration: PharmacyMotion.fast,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i < digits.length
                          ? accent.veryLight
                          : PharmacyColors.panel,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        width: 1.5,
                        color: _error != null
                            ? PharmacyColors.error
                            : (i == digits.length && _codeFocus.hasFocus)
                            ? accent.color
                            : Colors.transparent,
                      ),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (c, a) => ScaleTransition(
                        scale: Tween(begin: 0.5, end: 1.0).animate(
                          CurvedAnimation(parent: a, curve: Curves.easeOutBack),
                        ),
                        child: FadeTransition(opacity: a, child: c),
                      ),
                      child: Text(
                        i < digits.length ? digits[i] : '',
                        key: ValueKey(
                          '$i-${i < digits.length ? digits[i] : ''}',
                        ),
                        style: PharmacyType.sans(
                          fontSize: PharmacyType.figure,
                          fontWeight: FontWeight.w800,
                          color: PharmacyColors.textStrong,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: _code,
                focusNode: _codeFocus,
                autofocus: true,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(_codeLength),
                ],
                showCursor: false,
                enableInteractiveSelection: false,
                decoration: const InputDecoration(border: InputBorder.none),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _link(String label, VoidCallback? onTap, {bool muted = false}) =>
      TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          foregroundColor: muted
              ? PharmacyColors.textSecondary
              : ModuleAccent.of(context).color,
          disabledForegroundColor: PharmacyColors.textTertiary,
        ),
        child: Text(
          label,
          style: PharmacyType.sans(
            fontSize: PharmacyType.small,
            fontWeight: muted ? FontWeight.w500 : FontWeight.w700,
          ),
        ),
      );
}

/// Shakes its child sideways once each time [trigger] changes.
class _ShakeOnChange extends StatelessWidget {
  final int trigger;
  final Widget child;
  const _ShakeOnChange({required this.trigger, required this.child});

  @override
  Widget build(BuildContext context) {
    if (trigger == 0) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey(trigger),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      builder: (context, t, c) => Transform.translate(
        offset: Offset(math.sin(t * math.pi * 6) * 10 * (1 - t), 0),
        child: c,
      ),
      child: child,
    );
  }
}
