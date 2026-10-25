import 'package:flutter/material.dart';

import '../../doctor/screens/doctor_earnings.dart';

/// The physiotherapist's Earnings tab: the shared earnings screen with
/// physio wording. Its data is `physioEarningsProvider` — the doctor
/// earnings notifier, since /commission is scoped to the signed-in
/// professional by role.
class PhysioEarnings extends StatelessWidget {
  const PhysioEarnings({super.key});

  @override
  Widget build(BuildContext context) => const DoctorEarnings(noun: 'session');
}
