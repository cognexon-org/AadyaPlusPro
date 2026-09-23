import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_form_fields.dart';
import '../providers/auth_provider.dart';
import 'phone_otp_screen.dart';
import '../models/user_model.dart';
import '../../../core/network/api_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleForgotPassword() async {
    final controller = TextEditingController(
      text: _emailController.text.trim(),
    );
    final email = await AppDialog.show<String>(
      context,
      title: 'Reset Password',
      subtitle: "We'll email you a link to set a new password",
      icon: CupertinoIcons.lock_rotation,
      content: AppTextField(
        label: 'Email',
        controller: controller,
        icon: CupertinoIcons.mail,
        hint: 'Enter your account email',
        margin: EdgeInsets.zero,
      ),
      actions: [
        AppDialog.cancelButton(context),
        AppDialog.primaryButton(
          'Send Reset Link',
          () => Navigator.pop(context, controller.text.trim()),
        ),
      ],
    );

    if (email == null || email.isEmpty || !mounted) return;

    try {
      await ApiService().forgotPassword(email);
      if (!mounted) return;
      _showSnackBar(
        'If an account exists for $email, a reset link has been sent — check your email.',
      );
    } catch (_) {
      if (!mounted) return;
      _showSnackBar(
        'Could not send reset link. Please check your connection and try again.',
      );
    }
  }

  Future<void> _handleResendVerification() async {
    final controller = TextEditingController(
      text: _emailController.text.trim(),
    );
    final email = await AppDialog.show<String>(
      context,
      title: 'Resend Verification Email',
      subtitle: "We'll send a fresh verification link",
      icon: CupertinoIcons.mail_solid,
      content: AppTextField(
        label: 'Email',
        controller: controller,
        icon: CupertinoIcons.mail,
        hint: 'Enter your account email',
        margin: EdgeInsets.zero,
      ),
      actions: [
        AppDialog.cancelButton(context),
        AppDialog.primaryButton(
          'Resend',
          () => Navigator.pop(context, controller.text.trim()),
        ),
      ],
    );

    if (email == null || email.isEmpty || !mounted) return;

    try {
      await ApiService().resendVerification(email);
      if (!mounted) return;
      _showSnackBar(
        'If an unverified account exists for $email, a new verification link has been sent.',
      );
    } catch (_) {
      if (!mounted) return;
      _showSnackBar(
        'Could not resend verification email. Please check your connection and try again.',
      );
    }
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnackBar('Please enter email and password');
      return;
    }

    final authNotifier = ref.read(authProvider.notifier);
    final success = await authNotifier.login(email, password);

    if (!mounted) return;

    if (success) {
      final user = ref.read(authProvider).user;
      // Admin verification gates public discoverability (patients booking a
      // doctor, ordering from a pharmacy) on the backend — it never gates a
      // professional's own ability to manage their practice/store/inventory.
      // The real precondition for the dashboard is a completed profile.
      if (user != null && user.profileCompleted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/dashboard', (r) => false);
      } else {
        Navigator.of(context).pushNamedAndRemoveUntil('/pending', (r) => false);
      }
    } else {
      final error = ref.read(authProvider).error;
      _showSnackBar(error ?? 'Login failed');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.manrope(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.error,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showDemoRoleSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Demo Mode',
              style: GoogleFonts.manrope(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select a role to preview (no backend needed)',
              style: GoogleFonts.manrope(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            _RoleTile(
              icon: Icons.medical_services_outlined,
              title: 'Doctor',
              subtitle: 'Manage appointments & patients',
              color: AppTheme.doctorAccent,
              onTap: () {
                Navigator.pop(context);
                ref.read(authProvider.notifier).demoLogin(UserRole.doctor);
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/dashboard', (r) => false);
              },
            ),
            const SizedBox(height: 12),
            _RoleTile(
              icon: CupertinoIcons.waveform_path,
              title: 'Physiotherapist',
              subtitle: 'Manage sessions & exercises',
              color: AppTheme.physioAccent,
              onTap: () {
                Navigator.pop(context);
                ref
                    .read(authProvider.notifier)
                    .demoLogin(UserRole.physiotherapist);
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/dashboard', (r) => false);
              },
            ),
            const SizedBox(height: 12),
            _RoleTile(
              icon: Icons.biotech_outlined,
              title: 'Pathology Lab',
              subtitle: 'Manage tests & reports',
              color: AppTheme.pathologyAccent,
              onTap: () {
                Navigator.pop(context);
                ref.read(authProvider.notifier).demoLogin(UserRole.pathology);
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/dashboard', (r) => false);
              },
            ),
            const SizedBox(height: 12),
            _RoleTile(
              icon: Icons.apartment_outlined,
              title: 'Pharmacy',
              subtitle: 'Manage medicines & orders',
              color: AppTheme.pharmacyAccent,
              onTap: () {
                Navigator.pop(context);
                ref.read(authProvider.notifier).demoLogin(UserRole.pharmacy);
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/dashboard', (r) => false);
              },
            ),
            const SizedBox(height: 16),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              // Logo section
              Center(
                child: Column(
                  children: [
                    Image.asset(
                      'assets/brand/logo.png',
                      height: 64,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Professional',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Sign in to your professional account',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),

              // Error message
              if (authState.error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.error.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        CupertinoIcons.exclamationmark_triangle,
                        size: 18,
                        color: AppTheme.error,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          authState.error!,
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            color: AppTheme.error,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () =>
                            ref.read(authProvider.notifier).clearError(),
                        child: const Icon(
                          CupertinoIcons.xmark_circle,
                          size: 18,
                          color: AppTheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Email input
              Text(
                'Email Address',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  hintText: 'Enter your email address',
                  prefixIcon: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: const Icon(
                      CupertinoIcons.mail,
                      size: 20,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Password input
              Text(
                'Password',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _handleLogin(),
                decoration: InputDecoration(
                  hintText: 'Enter your password',
                  prefixIcon: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Icon(
                      CupertinoIcons.lock,
                      size: 20,
                      color: AppTheme.primary,
                    ),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? CupertinoIcons.eye_slash
                          : CupertinoIcons.eye,
                      size: 20,
                      color: AppTheme.textTertiary,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _handleResendVerification,
                    child: Text(
                      'Resend verification email',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _handleForgotPassword,
                    child: Text(
                      'Forgot Password?',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Login button
              GradientButton(
                text: 'Sign In',
                icon: Icons.login_outlined,
                isLoading: authState.isLoading,
                onPressed: _handleLogin,
              ),
              const SizedBox(height: 18),

              // OTP sits alongside the password form rather than replacing
              // it: accounts that share a mobile number are refused OTP
              // server-side, and those users still need this path.
              Row(
                children: [
                  Expanded(child: Divider(color: AppTheme.divider)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text(
                      'OR',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: AppTheme.divider)),
                ],
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: authState.isLoading
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PhoneOtpScreen(),
                        ),
                      ),
                icon: const Icon(Icons.smartphone_outlined, size: 18),
                label: Text(
                  'Continue with mobile number',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              if (kDebugMode) ...[
                Row(
                  children: [
                    Expanded(child: Divider(color: AppTheme.divider)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'DEVELOPMENT',
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: AppTheme.divider)),
                  ],
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _showDemoRoleSelector,
                  icon: const Icon(Icons.monitor_outlined, size: 18),
                  label: Text(
                    'Try Demo Mode',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                    side: const BorderSide(color: AppTheme.divider),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Register link
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Don't have an account? ",
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pushNamed('/register'),
                      child: Text(
                        'Register Now',
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _RoleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.2)),
            color: color.withValues(alpha: 0.04),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 24, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(CupertinoIcons.chevron_right, size: 20, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
