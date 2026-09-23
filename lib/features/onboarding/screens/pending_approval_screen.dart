import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';

// Reached only when profileCompleted is false — normally unreachable, since
// both the registration wizard and login now route straight to '/dashboard'
// once the profile is complete (admin verification only affects public
// discoverability, never the professional's own dashboard access). Getting
// here means something interrupted profile setup (e.g. an old app version,
// or a manual account edit) — this screen lets the user recheck status or
// pick registration back up rather than being stuck.
class PendingApprovalScreen extends ConsumerStatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  ConsumerState<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends ConsumerState<PendingApprovalScreen> {
  Timer? _pollTimer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) => _checkStatus());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkStatus({bool showFeedback = false}) async {
    if (_checking) return;
    setState(() => _checking = true);
    final ok = await ref.read(authProvider.notifier).refreshUser();
    if (!mounted) return;
    setState(() => _checking = false);

    final user = ref.read(authProvider).user;
    if (user?.profileCompleted == true) {
      Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (r) => false);
      return;
    }
    if (showFeedback) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Still incomplete — please finish registration.' : 'Could not check status. Check your connection.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Animated illustration
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 800),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: child,
                  );
                },
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primary.withValues(alpha: 0.1),
                        AppTheme.accent.withValues(alpha: 0.1),
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: AppTheme.accentGradient,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        CupertinoIcons.clock,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              Text(
                'Profile Setup Incomplete',
                style: GoogleFonts.manrope(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Hi ${user?.name ?? "there"}, it looks like your professional profile setup didn\'t finish. Finish registration to reach your dashboard — this doesn\'t require admin approval.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  color: AppTheme.textSecondary,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 32),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.info.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.info.withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.info_circle, size: 20, color: AppTheme.info),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Admin verification only affects whether patients can discover and book you publicly — you can still set up your profile, store and inventory right away.',
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          color: AppTheme.info,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 2),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _checking ? null : () => _checkStatus(showFeedback: true),
                  icon: _checking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: Text(
                    _checking ? 'Checking...' : 'Check Again',
                    style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pushNamedAndRemoveUntil('/register', (r) => false);
                  },
                  child: Text(
                    'Resume Registration',
                    style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Logout button
              TextButton.icon(
                onPressed: () {
                  ref.read(authProvider.notifier).logout();
                  Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
                },
                icon: const Icon(Icons.logout_outlined, size: 18),
                label: Text(
                  'Sign Out',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
