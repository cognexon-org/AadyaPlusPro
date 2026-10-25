import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/notifications/professional_notification_navigation_service.dart';
import 'core/notifications/professional_push_notification_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/auth/screens/splash_screen.dart';
import 'features/dashboard/screens/dashboard_shell.dart';
import 'features/onboarding/screens/pending_approval_screen.dart';
import 'features/pharmacy/widgets/module_accent.dart';
import 'features/pharmacy/services/pharmacy_order_ringer.dart';
import 'features/pharmacy/widgets/pharmacy_new_order_banner.dart';
import 'features/auth/models/user_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // Push initialization is best-effort. A missing Firebase project must never
  // block doctors, pharmacies, diagnostics teams or field-force users from
  // opening the app.
  await ProfessionalPushNotificationService.instance.initialize();

  runApp(const ProviderScope(child: AadyaProfessionalApp()));
}

class AadyaProfessionalApp extends ConsumerWidget {
  const AadyaProfessionalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AuthState>(authProvider, (previous, next) {
      final lostSession =
          previous?.isAuthenticated == true && !next.isAuthenticated;
      if (!lostSession) return;
      ProfessionalNotificationNavigationService.instance.setAuthenticatedReady(
        false,
      );
      ref.read(pharmacyOrderBannerProvider.notifier).dismiss();
      PharmacyOrderRinger.instance.stop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ProfessionalNotificationNavigationService.navigatorKey.currentState
            ?.pushNamedAndRemoveUntil('/login', (route) => false);
      });
    });

    return MaterialApp(
      navigatorKey: ProfessionalNotificationNavigationService.navigatorKey,
      navigatorObservers: [PharmacyRouteTracker.instance],
      // The pharmacy new-order banner lives above the navigator, so it stays
      // on screen whichever page is open.
      builder: (context, child) => Consumer(
        builder: (context, ref, _) {
          // One accent per module, above the navigator so sheets, dialogs
          // and pushed pages all pick it up: onboarding blue while signed
          // out, the role's colour once signed in.
          final role = ref.watch(
            authProvider.select((s) => s.isAuthenticated ? s.user?.role : null),
          );
          return ModuleTheme(
            accent: _accentFor(role),
            child: PharmacyNewOrderOverlay(
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
      ),
      title: 'Aadya Plus Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/pending': (context) => const PendingApprovalScreen(),
        '/dashboard': (context) => const DashboardShell(),
      },
    );
  }
}

ModuleAccent _accentFor(UserRole? role) => switch (role) {
  null => ModuleAccent.onboarding,
  UserRole.pharmacy => ModuleAccent.pharmacy,
  UserRole.doctor => ModuleAccent.doctor,
  UserRole.physiotherapist => ModuleAccent.physio,
  UserRole.pathology => ModuleAccent.pathology,
  UserRole.mr => ModuleAccent.mr,
};
