import 'package:flutter/foundation.dart';

class ApiConstants {
  static const String _configuredApiBaseUrl = String.fromEnvironment(
    'AADYA_API_BASE_URL',
    defaultValue: '',
  );

  static const String _configuredSocketBaseUrl = String.fromEnvironment(
    'AADYA_SOCKET_BASE_URL',
    defaultValue: '',
  );

  /// Compile-time configured AadyaMed API root.
  ///
  /// Production builds must provide a HTTPS URL ending in `/api`:
  /// --dart-define=AADYA_API_BASE_URL=https://api.example.com/api
  static String get baseUrl {
    final configured = _stripTrailingSlash(_configuredApiBaseUrl);
    if (configured.isNotEmpty) return configured;
    if (kReleaseMode) {
      throw StateError(
        'AADYA_API_BASE_URL is required for release builds. '
        'Pass --dart-define=AADYA_API_BASE_URL=https://<host>/api',
      );
    }
    return 'http://13.48.49.45/api';
  }

  /// Socket.IO origin. If not supplied it is derived from the API origin.
  static String get socketBaseUrl {
    final configured = _stripTrailingSlash(_configuredSocketBaseUrl);
    if (configured.isNotEmpty) return configured;

    final apiUri = Uri.parse(baseUrl);
    var path = apiUri.path;
    if (path.endsWith('/api')) {
      path = path.substring(0, path.length - 4);
    }
    final root = apiUri.replace(path: path.isEmpty ? '/' : path);
    return root.toString().replaceFirst(RegExp(r'/$'), '');
  }

  static String _stripTrailingSlash(String value) =>
      value.trim().replaceFirst(RegExp(r'/+$'), '');

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
  // Legacy endpoint retained until Pro P2 cleans the old exercise library.
  static const String physioExercises = '/physio/exercises';
  static String physioExerciseById(String id) => '/physio/exercises/$id';

  // ==================== PATHOLOGY ====================
  static const String pathologyProfile = '/pathology/me/profile';
  static const String pathologyDashboard = '/pathology/me/dashboard';
  static const String pathologyTests = '/pathology/me/tests';
  static const String pathologyTestSlots = '/pathology/me/test-slots';
  static const String pathologyAppointments = '/pathology/me/tests';
  static String pathologyTestById(String id) => '/pathology/me/tests/$id';
  static String pathologyTestStatus(String id) => '/pathology/me/tests/$id/status';
  static String pathologyTestReport(String id) => '/pathology/me/tests/$id/report';
  static const String pathologyMyAppointments = '/pathology/appointments';

  // ==================== PHARMACY ====================
  static const String pharmacyProfile = '/pharmacy/profile';
  // Legacy endpoints are replaced in Pro P2; kept here so P1 stays focused.
  static const String pharmacySales = '/pharmacysale';
  static const String pharmacySalesReport = '/pharmacysale/report';
  static const String lowStockMedicines = '/medicine/low-stock';
  static const String expiringMedicines = '/medicine/expiring';

  // ==================== APPOINTMENTS ====================
  static const String appointments = '/appointment';
  static String appointmentsByPatient(String patientId) => '/appointment/patient/$patientId';

  // ==================== CONSULTATIONS ====================
  static const String consultations = '/consultations';
  static String consultationByAppointment(String appointmentId) =>
      '$consultations/appointment/$appointmentId';
  static String consultationCheckIn(String appointmentId) =>
      '${consultationByAppointment(appointmentId)}/check-in';
  static String consultationStart(String appointmentId) =>
      '${consultationByAppointment(appointmentId)}/start';
  static String consultationJoin(String appointmentId) =>
      '${consultationByAppointment(appointmentId)}/join';
  static String consultationLeave(String appointmentId) =>
      '${consultationByAppointment(appointmentId)}/leave';
  static String consultationSummary(String appointmentId) =>
      '${consultationByAppointment(appointmentId)}/summary';
  static String consultationEnd(String appointmentId) =>
      '${consultationByAppointment(appointmentId)}/end';
  static const String consultationHistory = '$consultations/history';

  // ==================== PRESCRIPTION ====================
  static const String prescriptions = '/prescription';
  static String prescriptionsByPatient(String patientId) => '/prescription/patient/$patientId';
  static String prescriptionByAppointment(String appointmentId) => '/prescription/appointment/$appointmentId';
  static String prescriptionIssue(String id) => '/prescription/$id/issue';
  static String prescriptionCancel(String id) => '/prescription/$id/cancel';
  static String prescriptionPdf(String id) => '/prescription/$id/pdf';

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
  static const String notifications = '/notifications';
}
