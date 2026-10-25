import '../../doctor/providers/doctor_appointments_provider.dart';
import '../../doctor/providers/doctor_earnings_provider.dart';
import '../../doctor/providers/doctor_patients_provider.dart';

export '../../doctor/providers/doctor_appointments_provider.dart'
    show DoctorAppointmentsState, DoctorAppointmentsNotifier;
export '../../doctor/providers/doctor_earnings_provider.dart';
export '../../doctor/providers/doctor_patients_provider.dart';

/// The physio module reuses the doctor module's data layer where the server
/// already does the work: `/appointment`, `/commission` and the patient
/// grouping are scoped to the signed-in professional by role, so the same
/// notifiers serve a physio unchanged. These names exist so physio screens
/// read as physio code; each provider resets per signed-in account.
final physioAppointmentsProvider = doctorAppointmentsProvider;
final physioEarningsProvider = doctorEarningsProvider;
final physioPatientsProvider = doctorPatientsProvider;
