import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/models/user_model.dart';
import '../../auth/providers/auth_provider.dart';

// Tabs for each role
import '../../doctor/screens/doctor_home.dart';
import '../../doctor/screens/doctor_appointments.dart';
import '../../doctor/screens/doctor_patients.dart';
import '../../doctor/screens/doctor_earnings.dart';
import '../../doctor/screens/doctor_profile.dart';

import '../../physio/screens/physio_home.dart';
import '../../physio/screens/physio_appointments.dart';
import '../../physio/screens/physio_patients.dart';
import '../../physio/screens/physio_earnings.dart';
import '../../physio/screens/physio_profile.dart';

import '../../pathology/screens/pathology_home.dart';
import '../../pathology/screens/pathology_orders.dart';
import '../../pathology/screens/pathology_test_catalog.dart';
import '../../pathology/screens/pathology_earnings.dart';
import '../../pathology/screens/pathology_profile.dart';

import '../../pharmacy/screens/pharmacy_home.dart';
import '../../pharmacy/screens/pharmacy_orders.dart';
import '../../pharmacy/screens/pharmacy_medicines.dart';
import '../../pharmacy/screens/pharmacy_earnings.dart';
import '../../pharmacy/screens/pharmacy_profile.dart';
import '../../pharmacy/providers/pharmacy_store_provider.dart';

class DashboardShell extends ConsumerStatefulWidget {
  const DashboardShell({super.key});

  @override
  ConsumerState<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends ConsumerState<DashboardShell> {
  int _currentIndex = 0;

  List<Widget> _getPages(UserRole role) {
    switch (role) {
      case UserRole.doctor:
        return const [
          DoctorHome(),
          DoctorAppointments(),
          DoctorPatients(),
          DoctorEarnings(),
          DoctorProfile(),
        ];
      case UserRole.physiotherapist:
        return const [
          PhysioHome(),
          PhysioAppointments(),
          PhysioPatients(),
          PhysioEarnings(),
          PhysioProfile(),
        ];
      case UserRole.pathology:
        return const [
          PathologyHome(),
          PathologyOrders(),
          PathologyTestCatalog(),
          PathologyEarnings(),
          PathologyProfile(),
        ];
      case UserRole.pharmacy:
        return const [
          PharmacyHome(),
          PharmacyOrders(),
          PharmacyMedicines(),
          PharmacyEarnings(),
          PharmacyProfile(),
        ];
    }
  }

  List<BottomNavigationBarItem> _getNavItems(UserRole role) {
    switch (role) {
      case UserRole.doctor:
        return const [
          BottomNavigationBarItem(icon: Icon(Iconsax.home_2), activeIcon: Icon(Iconsax.home_25), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Iconsax.calendar), activeIcon: Icon(Iconsax.calendar5), label: 'Appointments'),
          BottomNavigationBarItem(icon: Icon(Iconsax.people), activeIcon: Icon(Iconsax.people5), label: 'Patients'),
          BottomNavigationBarItem(icon: Icon(Iconsax.wallet_2), activeIcon: Icon(Iconsax.wallet_35), label: 'Earnings'),
          BottomNavigationBarItem(icon: Icon(Iconsax.profile_circle), activeIcon: Icon(Iconsax.profile_circle5), label: 'Profile'),
        ];
      case UserRole.physiotherapist:
        return const [
          BottomNavigationBarItem(icon: Icon(Iconsax.home_2), activeIcon: Icon(Iconsax.home_25), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Iconsax.calendar), activeIcon: Icon(Iconsax.calendar5), label: 'Appointments'),
          BottomNavigationBarItem(icon: Icon(Iconsax.people), activeIcon: Icon(Iconsax.people5), label: 'Patients'),
          BottomNavigationBarItem(icon: Icon(Iconsax.wallet_2), activeIcon: Icon(Iconsax.wallet_35), label: 'Earnings'),
          BottomNavigationBarItem(icon: Icon(Iconsax.profile_circle), activeIcon: Icon(Iconsax.profile_circle5), label: 'Profile'),
        ];
      case UserRole.pathology:
        return const [
          BottomNavigationBarItem(icon: Icon(Iconsax.home_2), activeIcon: Icon(Iconsax.home_25), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Iconsax.clipboard_text), activeIcon: Icon(Iconsax.clipboard_text5), label: 'Orders'),
          BottomNavigationBarItem(icon: Icon(Iconsax.microscope), activeIcon: Icon(Iconsax.microscope), label: 'Tests'),
          BottomNavigationBarItem(icon: Icon(Iconsax.wallet_2), activeIcon: Icon(Iconsax.wallet_35), label: 'Earnings'),
          BottomNavigationBarItem(icon: Icon(Iconsax.profile_circle), activeIcon: Icon(Iconsax.profile_circle5), label: 'Profile'),
        ];
      case UserRole.pharmacy:
        return const [
          BottomNavigationBarItem(icon: Icon(Iconsax.home_2), activeIcon: Icon(Iconsax.home_25), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Iconsax.clipboard_text), activeIcon: Icon(Iconsax.clipboard_text5), label: 'Orders'),
          BottomNavigationBarItem(icon: Icon(Iconsax.box), activeIcon: Icon(Iconsax.box5), label: 'Medicines'),
          BottomNavigationBarItem(icon: Icon(Iconsax.wallet_2), activeIcon: Icon(Iconsax.wallet_35), label: 'Earnings'),
          BottomNavigationBarItem(icon: Icon(Iconsax.profile_circle), activeIcon: Icon(Iconsax.profile_circle5), label: 'Profile'),
        ];
    }
  }

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.doctor:
        return AppTheme.doctorAccent;
      case UserRole.physiotherapist:
        return AppTheme.physioAccent;
      case UserRole.pathology:
        return AppTheme.pathologyAccent;
      case UserRole.pharmacy:
        return AppTheme.pharmacyAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final role = authState.user?.role ?? UserRole.doctor;
    final pages = _getPages(role);
    final navItems = _getNavItems(role);
    final roleColor = _getRoleColor(role);

    if (role == UserRole.pharmacy) {
      Future.microtask(() => ref.read(pharmacyStoreProvider.notifier).initialize());
    }

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (i) => setState(() => _currentIndex = i),
              items: navItems,
              selectedItemColor: roleColor,
              unselectedItemColor: AppTheme.textTertiary,
              selectedLabelStyle: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600),
              unselectedLabelStyle: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w500),
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
          ),
        ),
      ),
    );
  }
}
