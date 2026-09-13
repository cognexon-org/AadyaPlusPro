class ApiConstants {
  static const String baseUrl = 'http://13.48.49.45/api';

  // ==================== AUTH ====================
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String me = '/auth/me';
  static const String profileStatus = '/auth/profile-status';
  static const String completeProfile = '/auth/complete-profile';
  static const String updateProfile = '/auth/profile';
  static const String changePassword = '/auth/change-password';
  static const String forgotPassword = '/auth/forgot-password';
  static const String logout = '/auth/logout';

  // ==================== DOCTOR ====================
  static const String doctorProfile = '/doctor/me/profile';
  static const String doctorDashboard = '/doctor/me/dashboard';
  static const String doctorAppointments = '/doctor/me/appointments';
  static const String doctorEarnings = '/doctor/me/earnings';
  static const String doctorEarningsReport = '/doctor/me/earnings/report';
  static const String doctorAvailability = '/doctor/me/availability';
  // Public doctor availability (uses doctorProfileId)
  static String doctorWeeklyAvailability(String doctorId) => '/doctor/$doctorId/availability/weekly';
  static String doctorDayAvailability(String doctorId) => '/doctor/$doctorId/availability';

  // ==================== PHYSIO ====================
  static const String physioProfile = '/physio/me/profile';
  static const String physioDashboard = '/physio/me/dashboard';
  static const String physioAppointments = '/physio/me/appointments';
  static const String physioPatients = '/physio/me/patients';
  static String physioPatientById(String id) => '/physio/me/patients/$id';
  static const String physioEarnings = '/physio/me/earnings';
  static const String physioEarningsReport = '/physio/me/earnings/report';
  static const String physioAvailability = '/physio/me/availability';
  static const String physioBreak = '/physio/me/break';
  static const String physioExercises = '/physio/exercises';
  static String physioExerciseById(String id) => '/physio/exercises/$id';

  // ==================== PATHOLOGY ====================
  static const String pathologyProfile = '/pathology/me/profile';
  static const String pathologyDashboard = '/pathology/me/dashboard';
  static const String pathologyTests = '/pathology/me/tests';
  static const String pathologyTestSlots = '/pathology/me/test-slots';
  static const String pathologyAppointments = '/pathology/me/tests'; // uses /me/tests for appointment-level test orders
  static String pathologyTestById(String id) => '/pathology/me/tests/$id';
  static String pathologyTestStatus(String id) => '/pathology/me/tests/$id/status';
  static String pathologyTestReport(String id) => '/pathology/me/tests/$id/report';
  static const String pathologyMyAppointments = '/pathology/appointments';

  // ==================== PHARMACY ====================
  static const String pharmacyProfile = '/pharmacy/profile';
  static const String pharmacySales = '/pharmacysale';
  static const String pharmacySalesReport = '/pharmacysale/report';
  static const String lowStockMedicines = '/medicine/low-stock';
  static const String expiringMedicines = '/medicine/expiring';

  // ==================== APPOINTMENTS (COMMON) ====================
  static const String appointments = '/appointment';
  static String appointmentsByPatient(String patientId) => '/appointment/patient/$patientId';

  // ==================== PRESCRIPTION ====================
  static const String prescriptions = '/prescription';
  static String prescriptionsByPatient(String patientId) => '/prescription/patient/$patientId';

  // ==================== CALENDAR ====================
  static const String calendarSlots = '/calendar/available-slots';

  // ==================== COMMISSION ====================
  static const String commission = '/commission';
  static const String commissionReport = '/commission/report';

  // ==================== CHAT ====================
  static const String chatSession = '/chat/session';
  static const String myChatSessions = '/chat/professional/sessions';
  static String chatHistory(String sessionId) => '/chat/session/$sessionId/messages';

  // ==================== MISC ====================
  static const String labTests = '/labtest';
  static const String medicines = '/medicine';
  static const String invoices = '/invoice';
  static const String upload = '/upload/profile';
  static const String patients = '/patient';
  static const String notifications = '/notification';
}
