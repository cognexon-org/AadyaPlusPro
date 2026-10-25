import 'package:flutter/material.dart';

import '../../doctor/screens/doctor_appointments.dart';
import '../widgets/physio_session_care.dart';

/// One session: the shared appointment details (time, patient, visit,
/// home-visit navigation, accept/start/no-show/cancel), with the physio's
/// care section — treatment course, exercise plan, assessment — in place of
/// the doctor's prescription.
class PhysioAppointmentDetails extends StatelessWidget {
  final Map<String, dynamic> appointment;
  const PhysioAppointmentDetails({super.key, required this.appointment});

  @override
  Widget build(BuildContext context) => AppointmentDetailsScreen(
    appointment: appointment,
    noun: 'session',
    careSection: (context, a) => PhysioSessionCare(appointment: a),
  );
}
