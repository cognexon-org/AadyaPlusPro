import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../doctor/screens/doctor_home.dart';
import '../../doctor/widgets/home_carousel.dart';
import 'physio_appointment_details.dart';
import 'physio_availability.dart';
import 'physio_exercises.dart';
import 'physio_packages.dart';

/// The physiotherapist's Today screen: the shared Today layout (now/next
/// with home-visit navigation, requests, the day's sessions, the week) with
/// physio wording and tools.
class PhysioHome extends StatelessWidget {
  const PhysioHome({super.key});

  @override
  Widget build(BuildContext context) => DoctorHome(
    noun: 'session',
    displayName: (raw) => raw.isEmpty ? 'Today' : raw.split(' ').first,
    detailsBuilder: (a) => PhysioAppointmentDetails(appointment: a),
    slides: const [
      (
        title: 'Home programmes that stick',
        body: 'Assign sets, reps and holds, then see who keeps up.',
        cta: 'Exercises',
        art: HomeSlideArt.exercise,
        page: PhysioExercises(),
        tab: null,
      ),
      (
        title: 'Sell session packages',
        body: 'Bundle 5 or 10 sessions; each visit is counted for you.',
        cta: 'Packages',
        art: HomeSlideArt.packages,
        page: PhysioPackages(),
        tab: null,
      ),
      (
        title: 'Show patients their progress',
        body: 'Record pain and range of motion at every assessment.',
        cta: 'Patients',
        art: HomeSlideArt.recovery,
        page: null,
        tab: 2,
      ),
    ],
    quickActions: const [
      (icon: LucideIcons.dumbbell, label: 'Exercises', page: PhysioExercises()),
      (
        icon: LucideIcons.packageOpen,
        label: 'Packages',
        page: PhysioPackages(),
      ),
      (
        icon: LucideIcons.clock,
        label: 'Availability',
        page: PhysioAvailability(),
      ),
      (icon: LucideIcons.calendarDays, label: 'Sessions', page: null),
    ],
  );
}
