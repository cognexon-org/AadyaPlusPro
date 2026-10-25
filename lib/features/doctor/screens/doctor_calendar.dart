import 'package:flutter/widgets.dart';

import 'doctor_availability.dart';

// DEPRECATED: the weekly hours now live in one screen, [DoctorAvailability].
// This class only forwards there so existing imports keep compiling; link to
// DoctorAvailability directly and delete this file once nothing uses it.
class DoctorCalendar extends StatelessWidget {
  const DoctorCalendar({super.key});

  @override
  Widget build(BuildContext context) => const DoctorAvailability();
}
