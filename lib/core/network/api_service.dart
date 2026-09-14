import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../constants/api_constants.dart';
import 'token_storage.dart';

typedef UnauthorizedHandler = Future<void> Function();

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  late final Dio _dio;
  UnauthorizedHandler? _onUnauthorized;
  bool _handlingUnauthorized = false;
  String? _pharmacyStoreId;

  ApiService._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: const {
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

        if (_pharmacyStoreId != null &&
            _pharmacyStoreId!.isNotEmpty &&
            _isStoreScopedPath(options.path)) {
          options.headers['X-Pharmacy-Store-Id'] = _pharmacyStoreId;
        }

        if (kDebugMode) {
          debugPrint('[API] ${options.method} ${options.uri}');
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        if (kDebugMode) {
          debugPrint(
            '[API] ${response.statusCode} '
            '${response.requestOptions.method} ${response.requestOptions.uri}',
          );
        }
        handler.next(response);
      },
      onError: (error, handler) async {
        if (kDebugMode) {
          debugPrint(
            '[API] ${error.response?.statusCode ?? '-'} '
            '${error.requestOptions.method} ${error.requestOptions.uri}',
          );
        }
        if (error.response?.statusCode == 401 && !_handlingUnauthorized) {
          _handlingUnauthorized = true;
          try {
            await TokenStorage.clearAll();
            _pharmacyStoreId = null;
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
  String? get selectedPharmacyStoreId => _pharmacyStoreId;

  void setUnauthorizedHandler(UnauthorizedHandler? handler) {
    _onUnauthorized = handler;
  }

  void setPharmacyStoreId(String? storeId) {
    final value = storeId?.trim();
    _pharmacyStoreId = (value == null || value.isEmpty) ? null : value;
  }

  bool _isStoreScopedPath(String path) {
    const prefixes = <String>[
      '/medicine',
      '/medicines',
      '/batch',
      '/batches',
      '/supplier',
      '/suppliers',
      '/purchase-order',
      '/orders/purchase',
      '/sales',
      '/pharmacy-sale',
      '/stock-adjustment',
      '/pharmacy-erp',
      '/epharmacy/merchant',
      '/stock-transfers',
      '/pharmacy-returns',
      '/grns',
    ];
    return prefixes.any(path.startsWith);
  }

  // AUTH
  Future<Response> login(String email, String password) =>
      _dio.post(ApiConstants.login, data: {'email': email, 'password': password});
  Future<Response> register(Map<String, dynamic> data) => _dio.post(ApiConstants.register, data: data);
  Future<Response> getCurrentUser() => _dio.get(ApiConstants.me);
  Future<Response> getProfileStatus() => _dio.get(ApiConstants.profileStatus);
  Future<Response> completeProfile(Map<String, dynamic> data) => _dio.post(ApiConstants.completeProfile, data: data);
  Future<Response> updateProfile(Map<String, dynamic> data) => _dio.put(ApiConstants.updateProfile, data: data);

  // DOCTOR
  Future<Response> getDoctorProfile() => _dio.get(ApiConstants.doctorProfile);
  Future<Response> updateDoctorProfile(Map<String, dynamic> data) => _dio.put(ApiConstants.doctorProfile, data: data);
  Future<Response> getDoctorDashboard() => _dio.get(ApiConstants.doctorDashboard);
  Future<Response> getDoctorAppointments({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.doctorAppointments, queryParameters: queryParams);
  Future<Response> getDoctorEarnings({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.doctorEarnings, queryParameters: queryParams);
  Future<Response> getDoctorEarningsReport({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.doctorEarningsReport, queryParameters: queryParams);
  Future<Response> getWeeklyAvailability(String doctorId) => _dio.get(ApiConstants.doctorWeeklyAvailability(doctorId));
  Future<Response> getDayAvailability(String doctorId, {Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.doctorDayAvailability(doctorId), queryParameters: queryParams);
  Future<Response> updateDoctorAvailability(dynamic data) => _dio.put(ApiConstants.doctorAvailability, data: data);
  Future<Response> updateAvailability(dynamic data) => updateDoctorAvailability(data);

  // PHYSIO
  Future<Response> getPhysioProfile() => _dio.get(ApiConstants.physioProfile);
  Future<Response> updatePhysioProfile(Map<String, dynamic> data) => _dio.put(ApiConstants.physioProfile, data: data);
  Future<Response> getPhysioDashboard() => _dio.get(ApiConstants.physioDashboard);
  Future<Response> getPhysioAppointments({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.physioAppointments, queryParameters: queryParams);
  Future<Response> getPhysioPatients() => _dio.get(ApiConstants.physioPatients);
  Future<Response> getPhysioEarnings({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.physioEarnings, queryParameters: queryParams);
  Future<Response> getPhysioEarningsReport({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.physioEarningsReport, queryParameters: queryParams);
  Future<Response> updatePhysioAvailability(dynamic data) => _dio.put(ApiConstants.physioAvailability, data: data);
  Future<Response> addPhysioBreak(Map<String, dynamic> data) => _dio.post(ApiConstants.physioBreak, data: data);
  Future<Response> getPhysioPatientById(String id) => _dio.get(ApiConstants.physioPatientById(id));

  // PATHOLOGY COMPATIBILITY
  Future<Response> getPathologyProfile() => _dio.get(ApiConstants.pathologyProfile);
  Future<Response> getPathologyDashboard() => _dio.get(ApiConstants.pathologyDashboard);
  Future<Response> getPathologyTests({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.pathologyTests, queryParameters: queryParams);
  Future<Response> getPathologyAppointments({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.pathologyAppointments, queryParameters: queryParams);
  Future<Response> getPathologyMyAppointments({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.pathologyMyAppointments, queryParameters: queryParams);
  Future<Response> getPathologyTestById(String id) => _dio.get(ApiConstants.pathologyTestById(id));
  Future<Response> updatePathologyTestStatus(String id, String status) => _dio.patch(ApiConstants.pathologyTestStatus(id), data: {'status': status});
  Future<Response> uploadPathologyReport(String id, Map<String, dynamic> data) => _dio.post(ApiConstants.pathologyTestReport(id), data: data);
  Future<Response> updatePathologyProfile(Map<String, dynamic> data) => _dio.put(ApiConstants.pathologyProfile, data: data);

  // P2 DIAGNOSTICS MERCHANT
  Future<Response> getDiagnosticsMerchantDashboard() => _dio.get(ApiConstants.diagnosticsMerchantDashboard);
  Future<Response> getDiagnosticsMerchantOrders({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.diagnosticsMerchantOrders, queryParameters: queryParams);
  Future<Response> getDiagnosticsMerchantOrder(String id) => _dio.get(ApiConstants.diagnosticsMerchantOrder(id));
  Future<Response> assignDiagnosticsCollector(String id, String staffId) => _dio.post(ApiConstants.diagnosticsAssignCollector(id), data: {'staffId': staffId});
  Future<Response> updateDiagnosticsCollectionStatus(String id, String status, {String? note}) => _dio.post(
        ApiConstants.diagnosticsCollectionStatus(id),
        data: {'status': status, if (note != null && note.trim().isNotEmpty) 'note': note.trim()},
      );
  Future<Response> updateDiagnosticsOrderStatus(String id, String status, {String? reason}) => _dio.post(
        ApiConstants.diagnosticsOrderStatus(id),
        data: {'status': status, if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()},
      );
  Future<Response> recordDiagnosticsOfflinePayment(String id, {required num amount, required String method, String? reference}) => _dio.post(
        ApiConstants.diagnosticsOfflinePayment(id),
        data: {'amount': amount, 'method': method, if (reference != null && reference.trim().isNotEmpty) 'reference': reference.trim()},
      );
  Future<Response> uploadDiagnosticsReport(String id, String filePath, {String? notes}) async {
    final form = FormData.fromMap({
      'report': await MultipartFile.fromFile(filePath),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
    return _dio.post(ApiConstants.diagnosticsReportUpload(id), data: form);
  }
  Future<Response> getDiagnosticsStaff() => _dio.get(ApiConstants.diagnosticsStaff);
  Future<Response> createDiagnosticsStaff(Map<String, dynamic> data) => _dio.post(ApiConstants.diagnosticsStaff, data: data);
  Future<Response> updateDiagnosticsStaff(String id, Map<String, dynamic> data) => _dio.patch(ApiConstants.diagnosticsStaffById(id), data: data);
  Future<Response> deleteDiagnosticsStaff(String id) => _dio.delete(ApiConstants.diagnosticsStaffById(id));
  Future<Response> getDiagnosticsCatalog() => _dio.get(ApiConstants.diagnosticsCatalog);
  Future<Response> createDiagnosticsCatalogTest(Map<String, dynamic> data) => _dio.post(ApiConstants.diagnosticsCatalogTests, data: data);
  Future<Response> updateDiagnosticsCatalogTest(String id, Map<String, dynamic> data) => _dio.patch(ApiConstants.diagnosticsCatalogTest(id), data: data);
  Future<Response> deleteDiagnosticsCatalogTest(String id) => _dio.delete(ApiConstants.diagnosticsCatalogTest(id));
  Future<Response> createDiagnosticsPackage(Map<String, dynamic> data) => _dio.post(ApiConstants.diagnosticsCatalogPackages, data: data);
  Future<Response> updateDiagnosticsPackage(String id, Map<String, dynamic> data) => _dio.patch(ApiConstants.diagnosticsCatalogPackage(id), data: data);
  Future<Response> deleteDiagnosticsPackage(String id) => _dio.delete(ApiConstants.diagnosticsCatalogPackage(id));

  // PHARMACY PROFILE + TENANT
  Future<Response> getPharmacyProfile() => _dio.get(ApiConstants.pharmacyProfile);
  Future<Response> createPharmacyProfile(Map<String, dynamic> data) => _dio.post(ApiConstants.pharmacyProfile, data: data);
  Future<Response> updatePharmacyProfile(Map<String, dynamic> data) => _dio.put(ApiConstants.pharmacyProfile, data: data);
  Future<Response> getPharmacyTenantContext() => _dio.get(ApiConstants.tenantContext);
  Future<Response> getPharmacyStores() => _dio.get(ApiConstants.tenantStores);
  Future<Response> selectPharmacyStore(String id) => _dio.post(ApiConstants.tenantSelectStore(id));

  // P2 PHARMACY ERP
  Future<Response> getPharmacyInventoryDashboard() => _dio.get(ApiConstants.pharmacyInventoryDashboard);
  Future<Response> getInventoryValuation() => _dio.get(ApiConstants.pharmacyInventoryValuation);
  Future<Response> getInventoryLedger({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.pharmacyInventoryLedger, queryParameters: queryParams);
  Future<Response> getPharmacyProfitLoss({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.pharmacyProfitLoss, queryParameters: queryParams);

  Future<Response> getPharmacySales({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.pharmacySales, queryParameters: queryParams);
  Future<Response> getPharmacySalesReport({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.pharmacySalesReport, queryParameters: queryParams);
  Future<Response> createPharmacySale(Map<String, dynamic> data) => _dio.post(ApiConstants.pharmacySales, data: data);

  Future<Response> getMedicines({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.medicines, queryParameters: queryParams);
  Future<Response> createMedicine(Map<String, dynamic> data) => _dio.post(ApiConstants.medicines, data: data);
  Future<Response> getMedicineById(String id) => _dio.get('${ApiConstants.medicines}/$id');
  Future<Response> getLowStockMedicines() => _dio.get(ApiConstants.lowStockMedicines);
  Future<Response> getExpiringMedicines() => _dio.get(ApiConstants.expiringMedicines);

  Future<Response> getSuppliers({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.suppliers, queryParameters: queryParams);
  Future<Response> createSupplier(Map<String, dynamic> data) => _dio.post(ApiConstants.suppliers, data: data);
  Future<Response> getPurchaseOrders({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.purchaseOrders, queryParameters: queryParams);
  Future<Response> createPurchaseOrder(Map<String, dynamic> data) => _dio.post(ApiConstants.purchaseOrders, data: data);
  Future<Response> getPurchaseOrder(String id) => _dio.get(ApiConstants.purchaseOrder(id));
  Future<Response> approvePurchaseOrder(String id) => _dio.post(ApiConstants.purchaseOrderApprove(id));
  Future<Response> markPurchaseOrderOrdered(String id) => _dio.post(ApiConstants.purchaseOrderOrdered(id));
  Future<Response> cancelPurchaseOrder(String id) => _dio.post(ApiConstants.purchaseOrderCancel(id));
  Future<Response> recordPurchasePayment(String id, num amount) => _dio.post(ApiConstants.purchaseOrderPayment(id), data: {'amount': amount});
  Future<Response> receivePurchaseOrder(String id, Map<String, dynamic> data) => _dio.post(ApiConstants.purchaseOrderReceive(id), data: data);
  Future<Response> getPurchaseOrderGrns(String id) => _dio.get(ApiConstants.purchaseOrderGrns(id));
  Future<Response> getGoodsReceipts() => _dio.get(ApiConstants.goodsReceipts);

  Future<Response> getStockTransfers() => _dio.get(ApiConstants.stockTransfers);
  Future<Response> createStockTransfer(Map<String, dynamic> data) => _dio.post(ApiConstants.stockTransfers, data: data);
  Future<Response> stockTransferAction(String id, String action, {Map<String, dynamic>? data}) => _dio.post(ApiConstants.stockTransferAction(id, action), data: data ?? const {});
  Future<Response> getPharmacyReturns() => _dio.get(ApiConstants.pharmacyReturns);
  Future<Response> createPharmacyReturn(Map<String, dynamic> data) => _dio.post(ApiConstants.pharmacyReturns, data: data);

  // P2 E-PHARMACY MERCHANT
  Future<Response> getMerchantOrders({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.merchantOrders, queryParameters: queryParams);
  Future<Response> getMerchantOrder(String id) => _dio.get(ApiConstants.merchantOrder(id));
  Future<Response> reviewMerchantPrescription(String id, {required bool approved, String? reason}) => _dio.post(
        ApiConstants.merchantPrescriptionReview(id),
        data: {'decision': approved ? 'approved' : 'rejected', if (reason != null && reason.trim().isNotEmpty) 'notes': reason.trim()},
      );
  Future<Response> confirmMerchantOrder(String id) => _dio.post(ApiConstants.merchantConfirmOrder(id));
  Future<Response> updateMerchantOrderStatus(String id, String status, {String? reason}) => _dio.post(
        ApiConstants.merchantOrderStatus(id),
        data: {'status': status, if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()},
      );
  Future<Response> cancelMerchantOrder(String id, {String? reason}) => _dio.post(
        ApiConstants.merchantCancelOrder(id),
        data: {if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()},
      );
  Future<Response> retryMerchantRefund(String id) => _dio.post(ApiConstants.merchantRefundOrder(id));
  Future<Response> getMerchantCoupons() => _dio.get(ApiConstants.merchantCoupons);
  Future<Response> createMerchantCoupon(Map<String, dynamic> data) => _dio.post(ApiConstants.merchantCoupons, data: data);
  Future<Response> updateMerchantCoupon(String id, Map<String, dynamic> data) => _dio.patch(ApiConstants.merchantCoupon(id), data: data);
  Future<Response> updateMerchantSettings(Map<String, dynamic> data) => _dio.patch(ApiConstants.merchantSettings, data: data);

  Future<Response> getInvoices({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.invoices, queryParameters: queryParams);

  // APPOINTMENTS
  Future<Response> getAppointments({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.appointments, queryParameters: queryParams);
  Future<Response> getAppointmentById(String id) => _dio.get('${ApiConstants.appointments}/$id');
  Future<Response> getAppointmentsByPatient(String patientId) => _dio.get(ApiConstants.appointmentsByPatient(patientId));
  Future<Response> updateAppointmentStatus(String id, String status) => _dio.put('${ApiConstants.appointments}/$id/status', data: {'status': status});
  Future<Response> cancelAppointment(String id, {String? reason}) => _dio.post('${ApiConstants.appointments}/$id/cancel', data: {'reason': reason});
  Future<Response> completeAppointment(String id) => _dio.post('${ApiConstants.appointments}/$id/complete');

  // PRESCRIPTION
  Future<Response> createPrescription(Map<String, dynamic> data) => _dio.post(ApiConstants.prescriptions, data: data);
  Future<Response> getPrescriptions({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.prescriptions, queryParameters: queryParams);
  Future<Response> getPrescriptionById(String id) => _dio.get('${ApiConstants.prescriptions}/$id');
  Future<Response> getPrescriptionsByPatient(String patientId) => _dio.get(ApiConstants.prescriptionsByPatient(patientId));
  Future<Response> updatePrescription(String id, Map<String, dynamic> data) => _dio.patch('${ApiConstants.prescriptions}/$id', data: data);
  Future<Response> getPrescriptionByAppointment(String appointmentId) => _dio.get(ApiConstants.prescriptionByAppointment(appointmentId));
  Future<Response> issuePrescription(String id) => _dio.post(ApiConstants.prescriptionIssue(id));
  Future<Response> cancelPrescription(String id, {String? reason}) => _dio.post(ApiConstants.prescriptionCancel(id), data: {if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()});
  Future<Response<List<int>>> downloadPrescriptionPdf(String id) => _dio.get<List<int>>(ApiConstants.prescriptionPdf(id), options: Options(responseType: ResponseType.bytes));

  // CONSULTATION
  Future<Response> getConsultationByAppointment(String appointmentId) => _dio.get(ApiConstants.consultationByAppointment(appointmentId));
  Future<Response> professionalCheckIn(String appointmentId) => _dio.post(ApiConstants.consultationCheckIn(appointmentId), data: const {});
  Future<Response> startConsultation(String appointmentId) => _dio.post(ApiConstants.consultationStart(appointmentId), data: const {});
  Future<Response> joinConsultation(String appointmentId) => _dio.post(ApiConstants.consultationJoin(appointmentId), data: const {});
  Future<Response> leaveConsultation(String appointmentId) => _dio.post(ApiConstants.consultationLeave(appointmentId), data: const {});
  Future<Response> updateConsultationSummary(String appointmentId, Map<String, dynamic> data) => _dio.patch(ApiConstants.consultationSummary(appointmentId), data: data);
  Future<Response> endConsultation(String appointmentId, Map<String, dynamic> data) => _dio.post(ApiConstants.consultationEnd(appointmentId), data: data);
  Future<Response> getConsultationHistory({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.consultationHistory, queryParameters: queryParams);


  // P3 MR / FIELD FORCE
  Future<Response> getMrMe() => _dio.get(ApiConstants.mrMe);
  Future<Response> getMrDashboard({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.mrDashboard, queryParameters: queryParams);
  Future<Response> getMrAnalytics({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.mrAnalytics, queryParameters: queryParams);
  Future<Response> getMrHierarchy() => _dio.get(ApiConstants.mrHierarchy);
  Future<Response> getMrTeam() => _dio.get(ApiConstants.mrTeam);
  Future<Response> getMrTerritories({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.mrTerritories, queryParameters: queryParams);
  Future<Response> getMrAccounts({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.mrAccounts, queryParameters: queryParams);
  Future<Response> getMrVisits({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.mrVisits, queryParameters: queryParams);
  Future<Response> createMrVisit(Map<String, dynamic> data) => _dio.post(ApiConstants.mrVisits, data: data);
  Future<Response> mrVisitCheckIn(String id, Map<String, dynamic> data) => _dio.post(ApiConstants.mrVisitCheckIn(id), data: data);
  Future<Response> mrVisitCheckOut(String id, Map<String, dynamic> data) => _dio.post(ApiConstants.mrVisitCheckOut(id), data: data);
  Future<Response> mrVisitSubmit(String id, Map<String, dynamic> data) => _dio.post(ApiConstants.mrVisitSubmit(id), data: data);
  Future<Response> mrVisitReview(String id, String decision, {String? comment}) => _dio.post(
        ApiConstants.mrVisitReview(id),
        data: {'decision': decision, if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim()},
      );
  Future<Response> getMrAttendance({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.mrAttendance, queryParameters: queryParams);
  Future<Response> mrPunchIn(Map<String, dynamic> data) => _dio.post(ApiConstants.mrPunchIn, data: data);
  Future<Response> mrPunchOut(Map<String, dynamic> data) => _dio.post(ApiConstants.mrPunchOut, data: data);
  Future<Response> getMrTourPlans({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.mrTourPlans, queryParameters: queryParams);
  Future<Response> saveMrTourPlan(Map<String, dynamic> data) => _dio.put(ApiConstants.mrTourPlans, data: data);
  Future<Response> submitMrTourPlan(String id) => _dio.post(ApiConstants.mrTourPlanSubmit(id));
  Future<Response> reviewMrTourPlan(String id, String decision, {String? comment}) => _dio.post(
        ApiConstants.mrTourPlanReview(id),
        data: {'decision': decision, if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim()},
      );
  Future<Response> getMrExpenses({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.mrExpenses, queryParameters: queryParams);
  Future<Response> createMrExpense(Map<String, dynamic> data) => _dio.post(ApiConstants.mrExpenses, data: data);
  Future<Response> submitMrExpense(String id) => _dio.post(ApiConstants.mrExpenseSubmit(id));
  Future<Response> reviewMrExpense(String id, String decision, {String? comment}) => _dio.post(
        ApiConstants.mrExpenseReview(id),
        data: {'decision': decision, if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim()},
      );
  Future<Response> getMrTargets({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.mrTargets, queryParameters: queryParams);
  Future<Response> setMrTarget(Map<String, dynamic> data) => _dio.put(ApiConstants.mrTargets, data: data);
  Future<Response> getMrPob({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.mrPob, queryParameters: queryParams);
  Future<Response> createMrPob(Map<String, dynamic> data) => _dio.post(ApiConstants.mrPob, data: data);
  Future<Response> updateMrPobStatus(String id, String status) => _dio.patch(ApiConstants.mrPobStatus(id), data: {'status': status});
  Future<Response> getMrSamples({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.mrSamples, queryParameters: queryParams);
  Future<Response> createMrSampleTransaction(Map<String, dynamic> data) => _dio.post(ApiConstants.mrSamples, data: data);
  Future<Response> getMrDetailing({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.mrDetailing, queryParameters: queryParams);

  // P3 NOTIFICATIONS
  Future<Response> getNotifications({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.notifications, queryParameters: queryParams);
  Future<Response> markNotificationRead(String id) => _dio.put(ApiConstants.notificationRead(id));
  Future<Response> markAllNotificationsRead() => _dio.put(ApiConstants.notificationsReadAll);
  Future<Response> deleteNotification(String id) => _dio.delete(ApiConstants.notificationById(id));
  Future<Response> registerDeviceToken(Map<String, dynamic> data) => _dio.post(ApiConstants.notificationsDeviceToken, data: data);
  Future<Response> unregisterDeviceToken(Map<String, dynamic> data) => _dio.delete(ApiConstants.notificationsDeviceToken, data: data);

  // SHARED
  Future<Response> getAvailableSlots({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.calendarSlots, queryParameters: queryParams);
  Future<Response> getCommissions({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.commission, queryParameters: queryParams);
  Future<Response> getCommissionReport({Map<String, dynamic>? queryParams}) => _dio.get(ApiConstants.commissionReport, queryParameters: queryParams);
  Future<Response> getOrCreateChatSession(Map<String, dynamic> data) => _dio.post(ApiConstants.chatSession, data: data);
  Future<Response> getMyChatSessions() => _dio.get(ApiConstants.myChatSessions);
  Future<Response> getChatHistory(String sessionId, {int limit = 50, int skip = 0}) => _dio.get(ApiConstants.chatHistory(sessionId), queryParameters: {'limit': limit, 'skip': skip});
}
