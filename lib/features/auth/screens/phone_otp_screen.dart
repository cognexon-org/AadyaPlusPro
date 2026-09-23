import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
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
  Timer? _resendTimer;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phone.dispose();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
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

  Future<void> _sendCode() async {
    final phone = _phone.text.trim();
    if (phone.length != 10) {
      setState(() => _error = 'Enter your 10-digit mobile number');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await ref.read(authProvider.notifier).sendPhoneOtp(phone);
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

    if (!result.ok) return;

    if (result.registered) {
      // The provider already stored the session; the root listener routes to
      // the dashboard, so just close this screen.
      if (mounted) Navigator.of(context).pop();
      return;
    }

    // New number: carry the proven phone and its token into registration.
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => RegisterScreen(
          prefilledPhone: _phone.text.trim(),
          phoneVerificationToken: result.verificationToken,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onCode = _step == _Step.code;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Back from the code step returns to the number, not out of the
            // flow — a mistyped number is the most likely reason to go back.
            if (onCode) {
              setState(() {
                _step = _Step.phone;
                _error = null;
              });
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Text(
              onCode ? 'Enter the code' : 'Sign in with mobile',
              style: GoogleFonts.manrope(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              onCode
                  ? 'We sent a 6-digit code to +91 ${_phone.text.trim()}'
                  : 'We will text you a code to confirm the number.',
              style: GoogleFonts.manrope(
                fontSize: 13.5,
                height: 1.45,
                color: AppTheme.textSecondary,
              ),
            ),
            if (onCode && _purpose == 'signup') ...[
              const SizedBox(height: 14),
              _notice(
                'This number has no account yet. Once the code is confirmed '
                'we will take you through creating one.',
              ),
            ],
            const SizedBox(height: 26),
            if (onCode) _codeField() else _phoneField(),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 16,
                    color: AppTheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: GoogleFonts.manrope(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppTheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 22),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : (onCode ? _verifyCode : _sendCode),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        onCode ? 'Verify & continue' : 'Send code',
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            if (onCode) ...[
              const SizedBox(height: 14),
              Center(
                child: TextButton(
                  onPressed: _resendIn > 0 || _busy ? null : _sendCode,
                  child: Text(
                    _resendIn > 0
                        ? 'Resend code in ${_resendIn}s'
                        : 'Resend code',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _resendIn > 0
                          ? AppTheme.textTertiary
                          : AppTheme.primary,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Use email and password instead',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _phoneField() => TextField(
    controller: _phone,
    keyboardType: TextInputType.phone,
    autofocus: true,
    maxLength: 10,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    style: GoogleFonts.manrope(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
      color: AppTheme.textPrimary,
    ),
    decoration: InputDecoration(
      counterText: '',
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 14, right: 8),
        child: Text(
          '+91',
          style: GoogleFonts.manrope(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary,
          ),
        ),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 0),
      hintText: '98765 43210',
      filled: true,
      fillColor: const Color(0xFFF6F8FA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 18),
    ),
    onSubmitted: (_) => _sendCode(),
  );

  Widget _codeField() => TextField(
    controller: _code,
    focusNode: _codeFocus,
    keyboardType: TextInputType.number,
    autofocus: true,
    maxLength: 6,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    textAlign: TextAlign.center,
    style: GoogleFonts.manrope(
      fontSize: 26,
      fontWeight: FontWeight.w800,
      letterSpacing: 10,
      color: AppTheme.textPrimary,
    ),
    decoration: InputDecoration(
      counterText: '',
      hintText: '••••••',
      hintStyle: GoogleFonts.manrope(
        fontSize: 26,
        letterSpacing: 10,
        color: AppTheme.textTertiary,
      ),
      filled: true,
      fillColor: const Color(0xFFF6F8FA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 18),
    ),
    onSubmitted: (_) => _verifyCode(),
  );

  Widget _notice(String text) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: AppTheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
    ),
    child: Text(
      text,
      style: GoogleFonts.manrope(
        fontSize: 12.5,
        height: 1.45,
        color: AppTheme.textSecondary,
      ),
    ),
  );
}
