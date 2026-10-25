import 'package:flutter/material.dart';

import '../../doctor/screens/doctor_appointments.dart';
import 'physio_appointment_details.dart';

/// The Sessions tab: requests to answer, upcoming and past sessions — the
/// shared appointments layout with physio wording.
class PhysioAppointments extends StatelessWidget {
  const PhysioAppointments({super.key});

  @override
  Widget build(BuildContext context) => DoctorAppointments(
    title: 'Sessions',
    noun: 'session',
    detailsBuilder: (a) => PhysioAppointmentDetails(appointment: a),
  );
}
