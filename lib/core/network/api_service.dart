import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../constants/api_constants.dart';
import 'token_storage.dart';

typedef UnauthorizedHandler = Future<void> Function();

/// Centralized Dio HTTP client with secure authentication and conservative
/// debug logging. Request/response bodies are intentionally not logged because
/// they may contain patient, consultation, prescription or credential data.
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio _dio;
  UnauthorizedHandler? _onUnauthorized;
  bool _handlingUnauthorized = false;

  ApiService._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await TokenStorage.getToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        } else {
          options.headers.remove('Authorization');
        }
        if (kDebugMode) {
          debugPrint('[API] ${options.method} ${options.uri}');
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        if (kDebugMode) {
          debugPrint('[API] ${response.statusCode} ${response.requestOptions.method} ${response.requestOptions.uri}');
        }
        handler.next(response);
      },
      onError: (error, handler) async {
        if (kDebugMode) {
          debugPrint('[API] ${error.response?.statusCode ?? '-'} ${error.requestOptions.method} ${error.requestOptions.uri}');
        }
        if (error.response?.statusCode == 401 && !_handlingUnauthorized) {
          _handlingUnauthorized = true;
          try {
            await TokenStorage.clearAll();
            final callback = _onUnauthorized;
            if (callback != null) await callback();
          } finally {
            _handlingUnauthorized = false;
          }
        }
        handler.next(error);
      },
    ));
  }

  Dio get dio => _dio;

  void setUnauthorizedHandler(UnauthorizedHandler? handler) {
    _onUnauthorized = handler;
  }

  // ==================== AUTH ====================

  Future<Response> login(String email, String password) {
    return _dio.post(ApiConstants.login, data: {
      'email': email,
      'password': password,
    });
  }

  Future<Response> register(Map<String, dynamic> data) {
    return _dio.post(ApiConstants.register, data: data);
  }

  Future<Response> getCurrentUser() {
    return _dio.get(ApiConstants.me);
  }

  Future<Response> getProfileStatus() {
    return _dio.get(ApiConstants.profileStatus);
  }

  Future<Response> completeProfile(Map<String, dynamic> data) {
    return _dio.post(ApiConstants.completeProfile, data: data);
  }

  Future<Response> updateProfile(Map<String, dynamic> data) {
    return _dio.put(ApiConstants.updateProfile, data: data);
  }

  // ==================== DOCTOR ====================

  Future<Response> getDoctorProfile() {
    return _dio.get(ApiConstants.doctorProfile);
  }

  Future<Response> updateDoctorProfile(Map<String, dynamic> data) {
    return _dio.put(ApiConstants.doctorProfile, data: data);
  }

  Future<Response> getDoctorDashboard() {
    return _dio.get(ApiConstants.doctorDashboard);
  }

  Future<Response> getDoctorAppointments({Map<String, dynamic>? queryParams}) {
    return _dio.get(ApiConstants.doctorAppointments, queryParameters: queryParams);
  }

  Future<Response> getDoctorEarnings({Map<String, dynamic>? queryParams}) {
    return _dio.get(ApiConstants.doctorEarnings, queryParameters: queryParams);
  }

  Future<Response> getDoctorEarningsReport({Map<String, dynamic>? queryParams}) {
    return _dio.get(ApiConstants.doctorEarningsReport, queryParameters: queryParams);
  }

  // Doctor availability
  Future<Response> getWeeklyAvailability(String doctorId) {
    return _dio.get(ApiConstants.doctorWeeklyAvailability(doctorId));
  }

  Future<Response> getDayAvailability(String doctorId, {Map<String, dynamic>? queryParams}) {
    return _dio.get(ApiConstants.doctorDayAvailability(doctorId), queryParameters: queryParams);
  }

  Future<Response> updateDoctorAvailability(dynamic data) {
    return _dio.put(ApiConstants.doctorAvailability, data: data);
  }

  /// Alias for updateDoctorAvailability
  Future<Response> updateAvailability(dynamic data) => updateDoctorAvailability(data);

  // ==================== PHYSIO ====================

  Future<Response> getPhysioProfile() {
    return _dio.get(ApiConstants.physioProfile);
  }

  Future<Response> updatePhysioProfile(Map<String, dynamic> data) {
    return _dio.put(ApiConstants.physioProfile, data: data);
  }

  Future<Response> getPhysioDashboard() {
    return _dio.get(ApiConstants.physioDashboard);
  }

  Future<Response> getPhysioAppointments({Map<String, dynamic>? queryParams}) {
    return _dio.get(ApiConstants.physioAppointments, queryParameters: queryParams);
  }

  Future<Response> getPhysioPatients() {
    return _dio.get(ApiConstants.physioPatients);
  }

  Future<Response> getPhysioEarnings({Map<String, dynamic>? queryParams}) {
    return _dio.get(ApiConstants.physioEarnings, queryParameters: queryParams);
  }

  Future<Response> getPhysioEarningsReport({Map<String, dynamic>? queryParams}) {
    return _dio.get(ApiConstants.physioEarningsReport, queryParameters: queryParams);
  }

  Future<Response> updatePhysioAvailability(dynamic data) {
    return _dio.put(ApiConstants.physioAvailability, data: data);
  }

  Future<Response> addPhysioBreak(Map<String, dynamic> data) {
    return _dio.post(ApiConstants.physioBreak, data: data);
  }

  Future<Response> getPhysioExercises({Map<String, dynamic>? queryParams}) {
    return _dio.get(ApiConstants.physioExercises, queryParameters: queryParams);
  }

  Future<Response> getPhysioPatientById(String id) {
    return _dio.get(ApiConstants.physioPatientById(id));
  }

  Future<Response> createPhysioExercise(Map<String, dynamic> data) {
    return _dio.post(ApiConstants.physioExercises, data: data);
  }

  Future<Response> updatePhysioExercise(String id, Map<String, dynamic> data) {
    return _dio.put(ApiConstants.physioExerciseById(id), data: data);
  }

  Future<Response> deletePhysioExercise(String id) {
    return _dio.delete(ApiConstants.physioExerciseById(id));
  }

  // ==================== PATHOLOGY ====================

  Future<Response> getPathologyProfile() {
    return _dio.get(ApiConstants.pathologyProfile);
  }

  // Future<Response> updatePathologyProfile(Map<String, dynamic> data) {
  //   return _dio.put(ApiConstants.pathologyProfile, data: data);
  // }

  Future<Response> getPathologyDashboard() {
    return _dio.get(ApiConstants.pathologyDashboard);
  }

  Future<Response> getPathologyTests({Map<String, dynamic>? queryParams}) {
    return _dio.get(ApiConstants.pathologyTests, queryParameters: queryParams);
  }

  Future<Response> getPathologyAppointments({Map<String, dynamic>? queryParams}) {
    return _dio.get(ApiConstants.pathologyAppointments, queryParameters: queryParams);
  }

  Future<Response> getPathologyMyAppointments({Map<String, dynamic>? queryParams}) {
    return _dio.get(ApiConstants.pathologyMyAppointments, queryParameters: queryParams);
  }

  Future<Response> getPathologyTestById(String id) {
    return _dio.get(ApiConstants.pathologyTestById(id));
  }

  Future<Response> updatePathologyTestStatus(String id, String status) {
    return _dio.patch(ApiConstants.pathologyTestStatus(id), data: {'status': status});
  }

  Future<Response> uploadPathologyReport(String id, Map<String, dynamic> data) {
    return _dio.post(ApiConstants.pathologyTestReport(id), data: data);
  }

  Future<Response> updatePathologyProfile(Map<String, dynamic> data) {
    return _dio.put(ApiConstants.pathologyProfile, data: data);
  }

  // ==================== PHARMACY ====================

  Future<Response> getPharmacyProfile() {
    return _dio.get(ApiConstants.pharmacyProfile);
  }

  Future<Response> createPharmacyProfile(Map<String, dynamic> data) {
    return _dio.post(ApiConstants.pharmacyProfile, data: data);
  }

  Future<Response> updatePharmacyProfile(Map<String, dynamic> data) {
    return _dio.put(ApiConstants.pharmacyProfile, data: data);
  }

  Future<Response> getPharmacySales({Map<String, dynamic>? queryParams}) {
    return _dio.get(ApiConstants.pharmacySales, queryParameters: queryParams);
  }

  Future<Response> getPharmacySalesReport({Map<String, dynamic>? queryParams}) {
    return _dio.get(ApiConstants.pharmacySalesReport, queryParameters: queryParams);
  }

  Future<Response> createPharmacySale(Map<String, dynamic> data) {
    return _dio.post(ApiConstants.pharmacySales, data: data);
  }

  Future<Response> getMedicines({Map<String, dynamic>? queryParams}) {
    return _dio.get(ApiConstants.medicines, queryParameters: queryParams);
  }

  Future<Response> createMedicine(Map<String, dynamic> data) {
    return _dio.post(ApiConstants.medicines, data: data);
  }

  Future<Response> getMedicineById(String id) {
    return _dio.get('${ApiConstants.medicines}/$id');
  }

  Future<Response> getLowStockMedicines() {
    return _dio.get(ApiConstants.lowStockMedicines);
  }

  Future<Response> getExpiringMedicines() {
    return _dio.get(ApiConstants.expiringMedicines);
  }

  Future<Response> getInvoices({Map<String, dynamic>? queryParams}) {
    return _dio.get(ApiConstants.invoices, queryParameters: queryParams);
  }

  // ==================== APPOINTMENTS (COMMON) ====================

  Future<Response> getAppointments({Map<String, dynamic>? queryParams}) {
    return _dio.get(ApiConstants.appointments, queryParameters: queryParams);
  }

  Future<Response> getAppointmentById(String id) {
    return _dio.get('${ApiConstants.appointments}/$id');
  }

  Future<Response> getAppointmentsByPatient(String patientId) {
    return _dio.get(ApiConstants.appointmentsByPatient(patientId));
  }

  Future<Response> updateAppointmentStatus(String id, String status) {
    return _dio.put('${ApiConstants.appointments}/$id/status', data: {'status': status});
  }

  Future<Response> cancelAppointment(String id, {String? reason}) {
    return _dio.post('${ApiConstants.appointments}/$id/cancel', data: {'reason': reason});
  }

  Future<Response> completeAppointment(String id) {
    return _dio.post('${ApiConstants.appointments}/$id/complete');
  }

  // ==================== PRESCRIPTION ====================

  Future<Response> createPrescription(Map<String, dynamic> data) {
    return _dio.post(ApiConstants.prescriptions, data: data);
  }

  Future<Response> getPrescriptions({Map<String, dynamic>? queryParams}) {
    return _dio.get(ApiConstants.prescriptions, queryParameters: queryParams);
  }

  Future<Response> getPrescriptionById(String id) {
    return _dio.get('${ApiConstants.prescriptions}/$id');
  }

  Future<Response> getPrescriptionsByPatient(String patientId) {
    return _dio.get(ApiConstants.prescriptionsByPatient(patientId));
  }

  Future<Response> updatePrescription(String id, Map<String, dynamic> data) {
    return _dio.patch('${ApiConstants.prescriptions}/$id', data: data);
  }

  Future<Response> getPrescriptionByAppointment(String appointmentId) {
    return _dio.get(ApiConstants.prescriptionByAppointment(appointmentId));
  }

  Future<Response> issuePrescription(String id) {
    return _dio.post(ApiConstants.prescriptionIssue(id));
  }

  Future<Response> cancelPrescription(String id, {String? reason}) {
    return _dio.post(ApiConstants.prescriptionCancel(id), data: {
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
  }

  Future<Response<List<int>>> downloadPrescriptionPdf(String id) {
    return _dio.get<List<int>>(
      ApiConstants.prescriptionPdf(id),
      options: Options(responseType: ResponseType.bytes),
    );
  }

  // ==================== CONSULTATION ====================

  Future<Response> getConsultationByAppointment(String appointmentId) {
    return _dio.get(ApiConstants.consultationByAppointment(appointmentId));
  }

  Future<Response> professionalCheckIn(String appointmentId) {
    return _dio.post(ApiConstants.consultationCheckIn(appointmentId), data: const {});
  }

  Future<Response> startConsultation(String appointmentId) {
    return _dio.post(ApiConstants.consultationStart(appointmentId), data: const {});
  }

  Future<Response> joinConsultation(String appointmentId) {
    return _dio.post(ApiConstants.consultationJoin(appointmentId), data: const {});
  }

  Future<Response> leaveConsultation(String appointmentId) {
    return _dio.post(ApiConstants.consultationLeave(appointmentId), data: const {});
  }

  Future<Response> updateConsultationSummary(String appointmentId, Map<String, dynamic> data) {
    return _dio.patch(ApiConstants.consultationSummary(appointmentId), data: data);
  }

  Future<Response> endConsultation(String appointmentId, Map<String, dynamic> data) {
    return _dio.post(ApiConstants.consultationEnd(appointmentId), data: data);
  }

  Future<Response> getConsultationHistory({Map<String, dynamic>? queryParams}) {
    return _dio.get(ApiConstants.consultationHistory, queryParameters: queryParams);
  }

  // ==================== CALENDAR ====================

  Future<Response> getAvailableSlots({Map<String, dynamic>? queryParams}) {
    return _dio.get(ApiConstants.calendarSlots, queryParameters: queryParams);
  }

  // ==================== COMMISSION ====================

  Future<Response> getCommissions({Map<String, dynamic>? queryParams}) {
    return _dio.get(ApiConstants.commission, queryParameters: queryParams);
  }

  Future<Response> getCommissionReport({Map<String, dynamic>? queryParams}) {
    return _dio.get(ApiConstants.commissionReport, queryParameters: queryParams);
  }

  // ==================== CHAT ====================

  Future<Response> getOrCreateChatSession(Map<String, dynamic> data) {
    return _dio.post(ApiConstants.chatSession, data: data);
  }

  Future<Response> getMyChatSessions() {
    return _dio.get(ApiConstants.myChatSessions);
  }

  Future<Response> getChatHistory(String sessionId, {int limit = 50, int skip = 0}) {
    return _dio.get(ApiConstants.chatHistory(sessionId), queryParameters: {
      'limit': limit,
      'skip': skip,
    });
  }
}
