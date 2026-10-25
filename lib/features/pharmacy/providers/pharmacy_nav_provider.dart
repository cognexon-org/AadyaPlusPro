import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tab indexes of the pharmacy dashboard, in the order the shell lays them
/// out. Kept here so a screen can say "go to Orders" without knowing the
/// shell's list.
class PharmacyTab {
  PharmacyTab._();

  static const home = 0;
  static const orders = 1;
  static const medicines = 2;
  static const earnings = 3;
  static const profile = 4;
}

/// A request from inside a tab to switch tabs. The dashboard shell listens,
/// switches, and clears it. Home's "Orders" shortcut used to push a second
/// copy of the Orders screen on top of the tab that already shows it.
final pharmacyTabRequestProvider = StateProvider<int?>((ref) => null);
