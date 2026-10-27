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

  /// False after a request fails to reach the server at all (no connection,
  /// timeout); true again on the next response of any kind. Reflects whether
  /// the *server* is reachable, which is what matters — a phone can be on
  /// Wi-Fi with no internet. Drives the offline banner.
  static final ValueNotifier<bool> reachable = ValueNotifier<bool>(true);

  static bool _isNetworkFailure(DioException e) =>
      e.response == null &&
      const {
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.unknown,
      }.contains(e.type);
  bool _handlingUnauthorized = false;
  String? _pharmacyStoreId;

  ApiService._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
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
          reachable.value = true;
          if (kDebugMode) {
            debugPrint(
              '[API] ${response.statusCode} '
              '${response.requestOptions.method} ${response.requestOptions.uri}',
            );
          }
          handler.next(response);
        },
        onError: (error, handler) async {
          reachable.value = !_isNetworkFailure(error);
          if (kDebugMode) {
            debugPrint(
              '[API] ${error.response?.statusCode ?? '-'} '
              '${error.requestOptions.method} ${error.requestOptions.uri}',
            );
          }
          // Only a signed-in call that's refused means the session ended.
          // A request sent without a token (a poll finishing after sign-out)
          // or a wrong password on the sign-in screen is not that.
          final hadToken =
              error.requestOptions.headers['Authorization'] != null;
          final path = error.requestOptions.path;
          final isAuthCall =
              path.contains('/auth/login') ||
              path.contains('/auth/register') ||
              path.contains('/auth/otp') ||
              path.contains('/auth/logout');
          if (error.response?.statusCode == 401 &&
              hadToken &&
              !isAuthCall &&
              !_handlingUnauthorized) {
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
      ),
    );
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
  Future<Response> login(String email, String password) => _dio.post(
    ApiConstants.login,
    data: {'email': email, 'password': password},
  );
  Future<Response> register(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.register, data: data);
  Future<Response> getCurrentUser() => _dio.get(ApiConstants.me);
  Future<Response> getProfileStatus() => _dio.get(ApiConstants.profileStatus);
  Future<Response> completeProfile(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.completeProfile, data: data);
  Future<Response> updateProfile(Map<String, dynamic> data) =>
      _dio.put(ApiConstants.updateProfile, data: data);
  Future<Response> forgotPassword(String email) =>
      _dio.post(ApiConstants.forgotPassword, data: {'email': email});
  Future<Response> resendVerification(String email) =>
      _dio.post(ApiConstants.resendVerification, data: {'email': email});
  Future<Response> changePassword(String currentPassword, String newPassword) =>
      _dio.put(
        ApiConstants.changePassword,
        data: {'currentPassword': currentPassword, 'newPassword': newPassword},
      );

  // DOCTOR
  Future<Response> getDoctorProfile() => _dio.get(ApiConstants.doctorProfile);
  Future<Response> updateDoctorProfile(Map<String, dynamic> data) =>
      _dio.put(ApiConstants.doctorProfile, data: data);
  Future<Response> getDoctorDashboard() =>
      _dio.get(ApiConstants.doctorDashboard);
  Future<Response> getDoctorAppointments({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.doctorAppointments, queryParameters: queryParams);
  Future<Response> getDoctorEarnings({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.doctorEarnings, queryParameters: queryParams);
  Future<Response> getDoctorEarningsReport({
    Map<String, dynamic>? queryParams,
  }) =>
      _dio.get(ApiConstants.doctorEarningsReport, queryParameters: queryParams);
  Future<Response> getWeeklyAvailability(String doctorId) =>
      _dio.get(ApiConstants.doctorWeeklyAvailability(doctorId));
  Future<Response> getDayAvailability(
    String doctorId, {
    Map<String, dynamic>? queryParams,
  }) => _dio.get(
    ApiConstants.doctorDayAvailability(doctorId),
    queryParameters: queryParams,
  );
  Future<Response> updateDoctorAvailability(dynamic data) =>
      _dio.put(ApiConstants.doctorAvailability, data: data);
  Future<Response> updateAvailability(dynamic data) =>
      updateDoctorAvailability(data);

  /// The signed-in doctor's own weekly hours plus practice settings —
  /// works before verification, unlike the public availability endpoints.
  Future<Response> getMyDoctorAvailability() =>
      _dio.get(ApiConstants.doctorAvailability);

  // PHYSIO
  Future<Response> getPhysioProfile() => _dio.get(ApiConstants.physioProfile);
  Future<Response> updatePhysioProfile(Map<String, dynamic> data) =>
      _dio.put(ApiConstants.physioProfile, data: data);
  Future<Response> getPhysioDashboard() =>
      _dio.get(ApiConstants.physioDashboard);
  Future<Response> getPhysioAppointments({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.physioAppointments, queryParameters: queryParams);
  Future<Response> getPhysioPatients() => _dio.get(ApiConstants.physioPatients);
  Future<Response> getPhysioEarnings({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.physioEarnings, queryParameters: queryParams);
  Future<Response> getPhysioEarningsReport({
    Map<String, dynamic>? queryParams,
  }) =>
      _dio.get(ApiConstants.physioEarningsReport, queryParameters: queryParams);
  Future<Response> updatePhysioAvailability(dynamic data) =>
      _dio.put(ApiConstants.physioAvailability, data: data);
  Future<Response> addPhysioBreak(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.physioBreak, data: data);
  Future<Response> getPhysioPatientById(String id) =>
      _dio.get(ApiConstants.physioPatientById(id));

  // PHYSIOTHERAPY EXERCISES
  Future<Response> getPhysioExercises({Map<String, dynamic>? queryParams}) =>
      _dio.get(
        ApiConstants.physioExerciseCatalog,
        queryParameters: queryParams,
      );
  Future<Response> createPhysioExercise(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.physioExerciseCatalog, data: data);
  Future<Response> updatePhysioExercise(String id, Map<String, dynamic> data) =>
      _dio.patch(ApiConstants.physioExerciseById(id), data: data);
  Future<Response> deletePhysioExercise(String id) =>
      _dio.delete(ApiConstants.physioExerciseById(id));
  Future<Response> getPhysioPatientExercisePlans(String patientId) =>
      _dio.get(ApiConstants.physioPatientExercisePlans(patientId));
  Future<Response> createPhysioPatientExercisePlan(
    String patientId,
    Map<String, dynamic> data,
  ) =>
      _dio.post(ApiConstants.physioPatientExercisePlans(patientId), data: data);
  Future<Response> getPhysioExercisePlan(String id) =>
      _dio.get(ApiConstants.physioExercisePlan(id));
  Future<Response> updatePhysioExercisePlan(
    String id,
    Map<String, dynamic> data,
  ) => _dio.patch(ApiConstants.physioExercisePlan(id), data: data);
  Future<Response> cancelPhysioExercisePlan(String id) =>
      _dio.delete(ApiConstants.physioExercisePlan(id));
  Future<Response> getPhysioExercisePlanProgress(String id) =>
      _dio.get(ApiConstants.physioExercisePlanProgress(id));

  /// The physio logs a session done in clinic against a plan.
  Future<Response> logPhysioExercisePlanProgress(
    String id,
    Map<String, dynamic> data,
  ) => _dio.post(ApiConstants.physioExercisePlanProgress(id), data: data);

  /// Prescribed vs done per exercise, overall compliance and pain averages.
  Future<Response> getPhysioExercisePlanAdherence(
    String id, {
    Map<String, dynamic>? queryParams,
  }) => _dio.get(
    ApiConstants.physioExercisePlanAdherence(id),
    queryParameters: queryParams,
  );

  // Physio care — packages, treatment courses, assessments.
  Future<Response> getPhysioPackages({bool includeInactive = false}) =>
      _dio.get(
        ApiConstants.physioPackages,
        queryParameters: {if (includeInactive) 'includeInactive': true},
      );
  Future<Response> createPhysioPackage(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.physioPackages, data: data);
  Future<Response> updatePhysioPackage(String id, Map<String, dynamic> data) =>
      _dio.patch(ApiConstants.physioPackage(id), data: data);
  Future<Response> archivePhysioPackage(String id) =>
      _dio.delete(ApiConstants.physioPackage(id));

  Future<Response> getPhysioCourses({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.physioCourses, queryParameters: queryParams);
  Future<Response> createPhysioCourse(
    String patientId,
    Map<String, dynamic> data,
  ) => _dio.post(ApiConstants.physioPatientCourses(patientId), data: data);
  Future<Response> getPhysioCourse(String id) =>
      _dio.get(ApiConstants.physioCourse(id));
  Future<Response> updatePhysioCourse(String id, Map<String, dynamic> data) =>
      _dio.patch(ApiConstants.physioCourse(id), data: data);
  Future<Response> linkPhysioCourseAppointment(
    String courseId,
    String appointmentId,
  ) => _dio.post(
    ApiConstants.physioCourseLinkAppointment(courseId, appointmentId),
  );

  Future<Response> getPhysioAssessments(String patientId) =>
      _dio.get(ApiConstants.physioPatientAssessments(patientId));
  Future<Response> createPhysioAssessment(
    String patientId,
    Map<String, dynamic> data,
  ) => _dio.post(ApiConstants.physioPatientAssessments(patientId), data: data);
  Future<Response> getPhysioAssessment(String id) =>
      _dio.get(ApiConstants.physioAssessment(id));
  Future<Response> updatePhysioAssessment(
    String id,
    Map<String, dynamic> data,
  ) => _dio.patch(ApiConstants.physioAssessment(id), data: data);
  Future<Response> getPhysioPatientProgress(String patientId) =>
      _dio.get(ApiConstants.physioPatientProgress(patientId));

  // PATHOLOGY COMPATIBILITY
  Future<Response> getPathologyProfile() =>
      _dio.get(ApiConstants.pathologyProfile);
  Future<Response> getPathologyDashboard() =>
      _dio.get(ApiConstants.pathologyDashboard);
  Future<Response> getPathologyTests({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.pathologyTests, queryParameters: queryParams);
  Future<Response> getPathologyAppointments({
    Map<String, dynamic>? queryParams,
  }) => _dio.get(
    ApiConstants.pathologyAppointments,
    queryParameters: queryParams,
  );
  Future<Response> getPathologyMyAppointments({
    Map<String, dynamic>? queryParams,
  }) => _dio.get(
    ApiConstants.pathologyMyAppointments,
    queryParameters: queryParams,
  );
  Future<Response> getPathologyTestById(String id) =>
      _dio.get(ApiConstants.pathologyTestById(id));
  Future<Response> updatePathologyTestStatus(String id, String status) => _dio
      .patch(ApiConstants.pathologyTestStatus(id), data: {'status': status});
  Future<Response> uploadPathologyReport(
    String id,
    Map<String, dynamic> data,
  ) => _dio.post(ApiConstants.pathologyTestReport(id), data: data);
  Future<Response> updatePathologyProfile(Map<String, dynamic> data) =>
      _dio.put(ApiConstants.pathologyProfile, data: data);

  // P2 DIAGNOSTICS MERCHANT
  Future<Response> getDiagnosticsMerchantDashboard() =>
      _dio.get(ApiConstants.diagnosticsMerchantDashboard);
  Future<Response> getDiagnosticsMerchantOrders({
    Map<String, dynamic>? queryParams,
  }) => _dio.get(
    ApiConstants.diagnosticsMerchantOrders,
    queryParameters: queryParams,
  );
  Future<Response> getDiagnosticsMerchantOrder(String id) =>
      _dio.get(ApiConstants.diagnosticsMerchantOrder(id));
  Future<Response> assignDiagnosticsCollector(String id, String staffId) =>
      _dio.post(
        ApiConstants.diagnosticsAssignCollector(id),
        data: {'staffId': staffId},
      );
  Future<Response> updateDiagnosticsCollectionStatus(
    String id,
    String status, {
    String? note,
    Map<String, dynamic>? extra,
  }) => _dio.post(
    ApiConstants.diagnosticsCollectionStatus(id),
    data: {
      'status': status,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      ...?extra,
    },
  );
  Future<Response> updateDiagnosticsOrderStatus(
    String id,
    String status, {
    String? reason,
    Map<String, dynamic>? extra,
  }) => _dio.post(
    ApiConstants.diagnosticsOrderStatus(id),
    data: {
      'status': status,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      ...?extra,
    },
  );
  Future<Response> saveDiagnosticsResults(
    String id,
    Map<String, dynamic> data,
  ) => _dio.post(ApiConstants.diagnosticsResults(id), data: data);
  Future<Response> releaseDiagnosticsReport(String id, {String? signedBy}) =>
      _dio.post(
        ApiConstants.diagnosticsRelease(id),
        data: {
          if (signedBy != null && signedBy.trim().isNotEmpty)
            'signedBy': signedBy.trim(),
        },
      );
  Future<Response<List<int>>> downloadDiagnosticsReport(String id) =>
      _dio.get<List<int>>(
        ApiConstants.diagnosticsReportFile(id),
        options: Options(responseType: ResponseType.bytes),
      );
  Future<Response> getDiagnosticsEarnings(String range) => _dio.get(
    ApiConstants.diagnosticsEarnings,
    queryParameters: {'range': range},
  );
  Future<Response> getDiagnosticsSchedule() =>
      _dio.get(ApiConstants.diagnosticsSchedule);
  Future<Response> saveDiagnosticsSchedule(List<Map<String, dynamic>> days) =>
      _dio.put(ApiConstants.diagnosticsSchedule, data: {'days': days});
  Future<Response> setDiagnosticsHoliday(String date, {required bool closed}) =>
      _dio.post(
        ApiConstants.diagnosticsHolidays,
        data: {'date': date, 'closed': closed},
      );
  Future<Response> getDiagnosticsLibrary() =>
      _dio.get(ApiConstants.diagnosticsLibrary);
  Future<Response> importDiagnosticsLibrary(List<Map<String, dynamic>> items) =>
      _dio.post(ApiConstants.diagnosticsImport, data: {'items': items});
  Future<Response> recordDiagnosticsOfflinePayment(
    String id, {
    required num amount,
    required String method,
    String? reference,
  }) => _dio.post(
    ApiConstants.diagnosticsOfflinePayment(id),
    data: {
      'amount': amount,
      'method': method,
      if (reference != null && reference.trim().isNotEmpty)
        'reference': reference.trim(),
    },
  );
  Future<Response> uploadDiagnosticsReport(
    String id,
    String filePath, {
    String? notes,
  }) async {
    final form = FormData.fromMap({
      'report': await MultipartFile.fromFile(filePath),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
    return _dio.post(ApiConstants.diagnosticsReportUpload(id), data: form);
  }

  Future<Response> getDiagnosticsStaff() =>
      _dio.get(ApiConstants.diagnosticsStaff);
  Future<Response> createDiagnosticsStaff(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.diagnosticsStaff, data: data);
  Future<Response> updateDiagnosticsStaff(
    String id,
    Map<String, dynamic> data,
  ) => _dio.patch(ApiConstants.diagnosticsStaffById(id), data: data);
  Future<Response> deleteDiagnosticsStaff(String id) =>
      _dio.delete(ApiConstants.diagnosticsStaffById(id));
  Future<Response> getDiagnosticsCatalog() =>
      _dio.get(ApiConstants.diagnosticsCatalog);
  Future<Response> createDiagnosticsCatalogTest(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.diagnosticsCatalogTests, data: data);
  Future<Response> updateDiagnosticsCatalogTest(
    String id,
    Map<String, dynamic> data,
  ) => _dio.patch(ApiConstants.diagnosticsCatalogTest(id), data: data);
  Future<Response> deleteDiagnosticsCatalogTest(String id) =>
      _dio.delete(ApiConstants.diagnosticsCatalogTest(id));
  Future<Response> createDiagnosticsPackage(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.diagnosticsCatalogPackages, data: data);
  Future<Response> updateDiagnosticsPackage(
    String id,
    Map<String, dynamic> data,
  ) => _dio.patch(ApiConstants.diagnosticsCatalogPackage(id), data: data);
  Future<Response> deleteDiagnosticsPackage(String id) =>
      _dio.delete(ApiConstants.diagnosticsCatalogPackage(id));

  // PHARMACY PROFILE + TENANT
  Future<Response> getPharmacyProfile() =>
      _dio.get(ApiConstants.pharmacyProfile);
  Future<Response> createPharmacyProfile(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.pharmacyProfile, data: data);
  Future<Response> updatePharmacyProfile(Map<String, dynamic> data) =>
      _dio.put(ApiConstants.pharmacyProfile, data: data);
  Future<Response> getPharmacyTenantContext() =>
      _dio.get(ApiConstants.tenantContext);
  Future<Response> getPharmacyStores() => _dio.get(ApiConstants.tenantStores);

  /// Updates one branch record. Accepts name, licenseNumber,
  /// drugLicenseNumber, gstin, email, phone, address, operatingHours —
  /// notably gstin and drugLicenseNumber, which the pharmacy *profile*
  /// endpoint has no field for.
  Future<Response> updatePharmacyStore(String id, Map<String, dynamic> data) =>
      _dio.put(ApiConstants.tenantStore(id), data: data);
  Future<Response> selectPharmacyStore(String id) =>
      _dio.post(ApiConstants.tenantSelectStore(id));

  // P2 PHARMACY ERP
  Future<Response> getPharmacyInventoryDashboard() =>
      _dio.get(ApiConstants.pharmacyInventoryDashboard);
  Future<Response> getInventoryValuation() =>
      _dio.get(ApiConstants.pharmacyInventoryValuation);
  Future<Response> getInventoryLedger({Map<String, dynamic>? queryParams}) =>
      _dio.get(
        ApiConstants.pharmacyInventoryLedger,
        queryParameters: queryParams,
      );
  Future<Response> getPharmacyProfitLoss({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.pharmacyProfitLoss, queryParameters: queryParams);

  Future<Response> getPharmacySales({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.pharmacySales, queryParameters: queryParams);
  Future<Response> getPharmacySalesReport({
    Map<String, dynamic>? queryParams,
  }) =>
      _dio.get(ApiConstants.pharmacySalesReport, queryParameters: queryParams);
  Future<Response> createPharmacySale(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.pharmacySales, data: data);

  /// One counter sale in full — populated customer, line items with their
  /// batch allocations, and any completed returns against it.
  Future<Response> getPharmacySaleById(String id) =>
      _dio.get('${ApiConstants.pharmacySales}/$id');

  // ── Counter payment collection (Razorpay UPI QR) ──────────────────

  /// Raises a UPI QR for whatever is outstanding on a counter sale or an
  /// unpaid online order. Pass exactly one of [saleId] / [orderId].
  Future<Response> createCounterPaymentQr({String? saleId, String? orderId}) =>
      _dio.post(
        '${ApiConstants.counterPayments}/qr',
        data: {
          if (saleId != null) 'saleId': saleId,
          if (orderId != null) 'orderId': orderId,
        },
      );

  /// Current state of a QR. The server reconciles with Razorpay on each call,
  /// so this works whether or not webhooks are configured.
  Future<Response> getCounterPayment(String id) =>
      _dio.get(ApiConstants.counterPayment(id));

  Future<Response> closeCounterPayment(String id) =>
      _dio.post(ApiConstants.counterPaymentClose(id));

  /// The branch's customers, aggregated from its own past bills — there is no
  /// customer collection behind this.
  Future<Response> getPharmacySaleCustomers({String? search}) => _dio.get(
    '${ApiConstants.pharmacySales}/customers',
    queryParameters: {
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    },
  );

  /// Headers for loading an authenticated image straight into `Image.network`
  /// — the prescription file endpoint sits behind `protect`, so the widget
  /// needs the bearer token the Dio interceptor would normally attach.
  static Future<Map<String, String>> authImageHeaders() async {
    final token = await TokenStorage.getToken();
    return {
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  // createPharmacySale only reserves a 'draft' sale — this is what actually
  // deducts stock (FEFO) and marks it 'dispensed' so it counts as revenue.
  Future<Response> dispensePharmacySale(String id) =>
      _dio.post('${ApiConstants.pharmacySales}/$id/dispense');

  Future<Response> getMedicines({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.medicines, queryParameters: queryParams);
  Future<Response> createMedicine(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.medicines, data: data);
  Future<Response> getMedicineById(String id) =>
      _dio.get('${ApiConstants.medicines}/$id');
  Future<Response> updateMedicine(String id, Map<String, dynamic> data) =>
      _dio.put('${ApiConstants.medicines}/$id', data: data);
  Future<Response> deactivateMedicine(String id) =>
      _dio.delete('${ApiConstants.medicines}/$id');
  // Medicine CRUD can't set stock directly (it's ledger-controlled) — this is
  // the actual stock-intake call, creating a batch and crediting quantity.
  Future<Response> addMedicineStock(String id, Map<String, dynamic> data) =>
      _dio.post('${ApiConstants.medicines}/$id/stock', data: data);
  Future<Response> getLowStockMedicines() =>
      _dio.get(ApiConstants.lowStockMedicines);
  Future<Response> getExpiringMedicines() =>
      _dio.get(ApiConstants.expiringMedicines);
  Future<Response> getExpiredMedicines() =>
      _dio.get(ApiConstants.expiredMedicines);

  /// The branch's medicine with exactly this barcode; 404 when none.
  Future<Response> getMedicineByBarcode(String code) =>
      _dio.get(ApiConstants.medicineByBarcode(code));

  Future<Response<List<int>>> downloadMedicineBulkUploadTemplate() =>
      _dio.get<List<int>>(
        ApiConstants.medicineBulkUploadTemplate,
        options: Options(responseType: ResponseType.bytes),
      );

  /// [dryRun] validates the file and reports what *would* be imported without
  /// writing anything. The bulk-upload screen posts once with dryRun to build
  /// the preview, then again without it once the user confirms.
  Future<Response> bulkUploadMedicines(
    String filePath, {
    bool dryRun = false,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
    });
    return _dio.post(
      ApiConstants.medicineBulkUpload,
      data: form,
      queryParameters: dryRun ? const {'dryRun': 'true'} : null,
    );
  }

  Future<Response> searchMedicineCatalog(String query) => _dio.get(
    ApiConstants.medicineCatalogSearch,
    queryParameters: {'q': query},
  );

  Future<Response> getSuppliers({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.suppliers, queryParameters: queryParams);
  Future<Response> createSupplier(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.suppliers, data: data);
  Future<Response> getPurchaseOrders({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.purchaseOrders, queryParameters: queryParams);
  Future<Response> createPurchaseOrder(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.purchaseOrders, data: data);
  Future<Response> getPurchaseOrder(String id) =>
      _dio.get(ApiConstants.purchaseOrder(id));
  Future<Response> approvePurchaseOrder(String id) =>
      _dio.post(ApiConstants.purchaseOrderApprove(id));
  Future<Response> markPurchaseOrderOrdered(String id) =>
      _dio.post(ApiConstants.purchaseOrderOrdered(id));
  Future<Response> cancelPurchaseOrder(String id) =>
      _dio.post(ApiConstants.purchaseOrderCancel(id));
  Future<Response> recordPurchasePayment(String id, num amount) => _dio.post(
    ApiConstants.purchaseOrderPayment(id),
    data: {'amount': amount},
  );
  Future<Response> receivePurchaseOrder(String id, Map<String, dynamic> data) =>
      _dio.post(ApiConstants.purchaseOrderReceive(id), data: data);
  Future<Response> getPurchaseOrderGrns(String id) =>
      _dio.get(ApiConstants.purchaseOrderGrns(id));
  Future<Response> getGoodsReceipts() => _dio.get(ApiConstants.goodsReceipts);

  Future<Response> getStockTransfers() => _dio.get(ApiConstants.stockTransfers);
  Future<Response> createStockTransfer(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.stockTransfers, data: data);
  Future<Response> stockTransferAction(
    String id,
    String action, {
    Map<String, dynamic>? data,
  }) => _dio.post(
    ApiConstants.stockTransferAction(id, action),
    data: data ?? const {},
  );
  Future<Response> getPharmacyReturns() =>
      _dio.get(ApiConstants.pharmacyReturns);
  Future<Response> createPharmacyReturn(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.pharmacyReturns, data: data);

  // P2 E-PHARMACY MERCHANT
  Future<Response> getMerchantOrders({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.merchantOrders, queryParameters: queryParams);

  // ── Phone OTP ─────────────────────────────────────────────────────

  /// Requests a code. The response's `purpose` says whether this number
  /// belongs to an existing account ('login') or a new one ('signup').
  Future<Response> sendPhoneOtp(String phone) =>
      _dio.post('/auth/otp/send', data: {'phone': phone});

  /// Verifies the code. An existing account comes back with a token; a new
  /// number comes back with a single-use `verificationToken` for /register.
  Future<Response> verifyPhoneOtp(String phone, String code) =>
      _dio.post('/auth/otp/verify', data: {'phone': phone, 'code': code});

  /// Asks the server for the day's welcome notification. Idempotent per day
  /// server-side, so it is safe to call on every launch.
  Future<Response> sendDailyWelcome() =>
      _dio.post('/notifications/daily-welcome');

  /// What Aadya Plus owes this store and what it has already paid out.
  /// Distinct from the store's own P&L: this is platform settlement.
  Future<Response> getMerchantSettlement() =>
      _dio.get(ApiConstants.merchantSettlement);

  /// Pauses the store for [minutes], or resumes it when [minutes] is 0.
  Future<Response> setStorePause({required int minutes, String? reason}) =>
      _dio.post(
        ApiConstants.merchantPause,
        data: {
          'minutes': minutes,
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
      );

  /// Declines a new order the store cannot fulfil. Distinct from cancelling
  /// an order already accepted: this records *why*, and is the only action
  /// available before stock has been allocated.
  Future<Response> rejectMerchantOrder(
    String id, {
    required String reason,
    String? note,
  }) => _dio.post(
    ApiConstants.merchantOrderReject(id),
    data: {'reason': reason, if (note != null && note.isNotEmpty) 'note': note},
  );

  Future<Response> getMerchantOrder(String id) =>
      _dio.get(ApiConstants.merchantOrder(id));

  /// [checklist] is what the pharmacist verified (see
  /// showPrescriptionChecklist); required by the server for approvals.
  Future<Response> reviewMerchantPrescription(
    String id, {
    required bool approved,
    String? reason,
    Map<String, dynamic>? checklist,
  }) => _dio.post(
    ApiConstants.merchantPrescriptionReview(id),
    data: {
      'decision': approved ? 'approved' : 'rejected',
      if (reason != null && reason.trim().isNotEmpty) 'notes': reason.trim(),
      if (checklist != null) 'checklist': checklist,
    },
  );

  /// The customer's bill (after acceptance) or the packing slip, as PDF bytes.
  Future<Response<List<int>>> downloadMerchantOrderPdf(
    String id, {
    bool packingSlip = false,
  }) => _dio.get<List<int>>(
    packingSlip
        ? ApiConstants.merchantOrderPackingSlipPdf(id)
        : ApiConstants.merchantOrderInvoicePdf(id),
    options: Options(responseType: ResponseType.bytes),
  );

  /// Same-salt medicines in stock at this store, per order line.
  Future<Response> getOrderSubstitutes(String id, {String? medicineId}) =>
      _dio.get(
        ApiConstants.merchantOrderSubstitutes(id),
        queryParameters: {if (medicineId != null) 'medicineId': medicineId},
      );

  Future<Response> getScheduleRegister({Map<String, dynamic>? queryParams}) =>
      _dio.get(
        ApiConstants.merchantScheduleRegister,
        queryParameters: queryParams,
      );

  /// Accepts an order. [availability] maps order-item id -> the quantity the
  /// store can actually supply; omit it to accept everything as ordered.
  /// Supplying less reduces the order and refunds the difference.
  Future<Response> confirmMerchantOrder(
    String id, {
    Map<String, int>? availability,
  }) => _dio.post(
    ApiConstants.merchantConfirmOrder(id),
    data: {if (availability != null) 'availability': availability},
  );

  /// [extra] carries what a step needs — `driver` for a handover.
  Future<Response> updateMerchantOrderStatus(
    String id,
    String status, {
    String? reason,
    Map<String, dynamic>? extra,
  }) => _dio.post(
    ApiConstants.merchantOrderStatus(id),
    data: {
      ...?extra,
      'status': status,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    },
  );

  /// Drivers this store handed orders to recently, newest first.
  Future<Response> getRecentDrivers() => _dio.get(ApiConstants.merchantDrivers);
  Future<Response> cancelMerchantOrder(String id, {String? reason}) =>
      _dio.post(
        ApiConstants.merchantCancelOrder(id),
        data: {
          if (reason != null && reason.trim().isNotEmpty)
            'reason': reason.trim(),
        },
      );
  Future<Response> retryMerchantRefund(String id) =>
      _dio.post(ApiConstants.merchantRefundOrder(id));
  Future<Response> getMerchantCoupons() =>
      _dio.get(ApiConstants.merchantCoupons);
  Future<Response> createMerchantCoupon(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.merchantCoupons, data: data);
  Future<Response> updateMerchantCoupon(String id, Map<String, dynamic> data) =>
      _dio.patch(ApiConstants.merchantCoupon(id), data: data);
  Future<Response> getMerchantSettings() =>
      _dio.get(ApiConstants.merchantSettings);
  Future<Response> updateMerchantSettings(Map<String, dynamic> data) =>
      _dio.patch(ApiConstants.merchantSettings, data: data);

  Future<Response> getInvoices({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.invoices, queryParameters: queryParams);

  // APPOINTMENTS
  Future<Response> getAppointments({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.appointments, queryParameters: queryParams);
  Future<Response> getAppointmentById(String id) =>
      _dio.get('${ApiConstants.appointments}/$id');
  Future<Response> getAppointmentsByPatient(String patientId) =>
      _dio.get(ApiConstants.appointmentsByPatient(patientId));
  Future<Response> updateAppointmentStatus(String id, String status) => _dio
      .put('${ApiConstants.appointments}/$id/status', data: {'status': status});
  Future<Response> cancelAppointment(String id, {String? reason}) => _dio.post(
    '${ApiConstants.appointments}/$id/cancel',
    data: {'reason': reason},
  );
  Future<Response> completeAppointment(String id) =>
      _dio.post('${ApiConstants.appointments}/$id/complete');

  // PRESCRIPTION
  Future<Response> createPrescription(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.prescriptions, data: data);
  Future<Response> getPrescriptions({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.prescriptions, queryParameters: queryParams);
  Future<Response> getPrescriptionById(String id) =>
      _dio.get('${ApiConstants.prescriptions}/$id');
  Future<Response> getPrescriptionsByPatient(String patientId) =>
      _dio.get(ApiConstants.prescriptionsByPatient(patientId));
  Future<Response> updatePrescription(String id, Map<String, dynamic> data) =>
      _dio.patch('${ApiConstants.prescriptions}/$id', data: data);
  Future<Response> getPrescriptionByAppointment(String appointmentId) =>
      _dio.get(ApiConstants.prescriptionByAppointment(appointmentId));
  Future<Response> issuePrescription(String id) =>
      _dio.post(ApiConstants.prescriptionIssue(id));
  Future<Response> cancelPrescription(String id, {String? reason}) => _dio.post(
    ApiConstants.prescriptionCancel(id),
    data: {
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    },
  );
  Future<Response<List<int>>> downloadPrescriptionPdf(String id) =>
      _dio.get<List<int>>(
        ApiConstants.prescriptionPdf(id),
        options: Options(responseType: ResponseType.bytes),
      );

  // CONSULTATION
  Future<Response> getConsultationByAppointment(String appointmentId) =>
      _dio.get(ApiConstants.consultationByAppointment(appointmentId));
  Future<Response> professionalCheckIn(String appointmentId) => _dio.post(
    ApiConstants.consultationCheckIn(appointmentId),
    data: const {},
  );
  Future<Response> startConsultation(String appointmentId) =>
      _dio.post(ApiConstants.consultationStart(appointmentId), data: const {});
  Future<Response> joinConsultation(String appointmentId) =>
      _dio.post(ApiConstants.consultationJoin(appointmentId), data: const {});
  Future<Response> leaveConsultation(String appointmentId) =>
      _dio.post(ApiConstants.consultationLeave(appointmentId), data: const {});
  Future<Response> updateConsultationSummary(
    String appointmentId,
    Map<String, dynamic> data,
  ) => _dio.patch(ApiConstants.consultationSummary(appointmentId), data: data);
  Future<Response> endConsultation(
    String appointmentId,
    Map<String, dynamic> data,
  ) => _dio.post(ApiConstants.consultationEnd(appointmentId), data: data);
  Future<Response> getConsultationHistory({
    Map<String, dynamic>? queryParams,
  }) =>
      _dio.get(ApiConstants.consultationHistory, queryParameters: queryParams);

  // P3 MR / FIELD FORCE
  Future<Response> getMrMe() => _dio.get(ApiConstants.mrMe);
  Future<Response> updateMrMe(Map<String, dynamic> data) =>
      _dio.patch(ApiConstants.mrMe, data: data);
  Future<Response> getMrDashboard({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.mrDashboard, queryParameters: queryParams);
  Future<Response> getMrAnalytics({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.mrAnalytics, queryParameters: queryParams);
  Future<Response> getMrHierarchy() => _dio.get(ApiConstants.mrHierarchy);
  Future<Response> getMrTeam({bool includeInactive = false}) => _dio.get(
    ApiConstants.mrTeam,
    queryParameters: {if (includeInactive) 'includeInactive': 'true'},
  );
  Future<Response> createMrTeamUser(Map<String, dynamic> data) =>
      _dio.post('${ApiConstants.mrTeam}/users', data: data);
  Future<Response> updateMrTeamMember(String id, Map<String, dynamic> data) =>
      _dio.patch('${ApiConstants.mrTeam}/$id', data: data);
  Future<Response> createMrTerritory(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.mrTerritories, data: data);
  Future<Response> updateMrTerritory(String id, Map<String, dynamic> data) =>
      _dio.patch('${ApiConstants.mrTerritories}/$id', data: data);
  Future<Response> createMrDetailing(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.mrDetailing, data: data);
  Future<Response> updateMrDetailing(String id, Map<String, dynamic> data) =>
      _dio.patch('${ApiConstants.mrDetailing}/$id', data: data);
  Future<Response> getMrTerritories({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.mrTerritories, queryParameters: queryParams);
  Future<Response> getMrAccounts({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.mrAccounts, queryParameters: queryParams);
  Future<Response> createMrAccount(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.mrAccounts, data: data);
  Future<Response> updateMrAccount(String id, Map<String, dynamic> data) =>
      _dio.patch('${ApiConstants.mrAccounts}/$id', data: data);
  Future<Response> getMrVisits({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.mrVisits, queryParameters: queryParams);
  Future<Response> createMrVisit(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.mrVisits, data: data);
  Future<Response> mrVisitCheckIn(String id, Map<String, dynamic> data) =>
      _dio.post(ApiConstants.mrVisitCheckIn(id), data: data);
  Future<Response> mrVisitCheckOut(String id, Map<String, dynamic> data) =>
      _dio.post(ApiConstants.mrVisitCheckOut(id), data: data);
  Future<Response> mrVisitSubmit(String id, Map<String, dynamic> data) =>
      _dio.post(ApiConstants.mrVisitSubmit(id), data: data);
  Future<Response> mrVisitReview(
    String id,
    String decision, {
    String? comment,
  }) => _dio.post(
    ApiConstants.mrVisitReview(id),
    data: {
      'decision': decision,
      if (comment != null && comment.trim().isNotEmpty)
        'comment': comment.trim(),
    },
  );
  Future<Response> getMrAttendance({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.mrAttendance, queryParameters: queryParams);
  Future<Response> mrPunchIn(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.mrPunchIn, data: data);
  Future<Response> mrPunchOut(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.mrPunchOut, data: data);
  Future<Response> getMrTourPlans({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.mrTourPlans, queryParameters: queryParams);
  Future<Response> saveMrTourPlan(Map<String, dynamic> data) =>
      _dio.put(ApiConstants.mrTourPlans, data: data);
  Future<Response> submitMrTourPlan(String id) =>
      _dio.post(ApiConstants.mrTourPlanSubmit(id));
  Future<Response> reviewMrTourPlan(
    String id,
    String decision, {
    String? comment,
  }) => _dio.post(
    ApiConstants.mrTourPlanReview(id),
    data: {
      'decision': decision,
      if (comment != null && comment.trim().isNotEmpty)
        'comment': comment.trim(),
    },
  );
  Future<Response> getMrExpenses({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.mrExpenses, queryParameters: queryParams);
  Future<Response> createMrExpense(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.mrExpenses, data: data);
  Future<Response> submitMrExpense(String id) =>
      _dio.post(ApiConstants.mrExpenseSubmit(id));
  Future<Response> reviewMrExpense(
    String id,
    String decision, {
    String? comment,
  }) => _dio.post(
    ApiConstants.mrExpenseReview(id),
    data: {
      'decision': decision,
      if (comment != null && comment.trim().isNotEmpty)
        'comment': comment.trim(),
    },
  );
  Future<Response> payMrExpense(String id, {String? reference}) => _dio.post(
    ApiConstants.mrExpensePay(id),
    data: {
      if (reference != null && reference.trim().isNotEmpty)
        'reference': reference.trim(),
    },
  );
  Future<Response> uploadMrExpenseReceipt(String id, String filePath) async {
    final ext = filePath.split('.').last.toLowerCase();
    final type = switch (ext) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    final form = FormData.fromMap({
      'receipt': await MultipartFile.fromFile(
        filePath,
        contentType: DioMediaType.parse(type),
      ),
    });
    return _dio.post(ApiConstants.mrExpenseReceipt(id), data: form);
  }

  Future<Response> getMrExpenseReceipt(String id) => _dio.get(
    ApiConstants.mrExpenseReceipt(id),
    options: Options(responseType: ResponseType.bytes),
  );
  Future<Response> getMrLeaves({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.mrLeaves, queryParameters: queryParams);
  Future<Response> applyMrLeave(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.mrLeaves, data: data);
  Future<Response> reviewMrLeave(
    String id,
    String decision, {
    String? comment,
  }) => _dio.post(
    ApiConstants.mrLeaveReview(id),
    data: {
      'decision': decision,
      if (comment != null && comment.trim().isNotEmpty)
        'comment': comment.trim(),
    },
  );
  Future<Response> cancelMrLeave(String id) =>
      _dio.post(ApiConstants.mrLeaveCancel(id));
  Future<Response> searchMrDirectory(String kind, String q) => _dio.get(
    ApiConstants.mrDirectory,
    queryParameters: {'kind': kind, 'q': q},
  );
  Future<Response> getMrTargets({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.mrTargets, queryParameters: queryParams);
  Future<Response> setMrTarget(Map<String, dynamic> data) =>
      _dio.put(ApiConstants.mrTargets, data: data);
  Future<Response> getMrPob({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.mrPob, queryParameters: queryParams);
  Future<Response> createMrPob(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.mrPob, data: data);
  Future<Response> updateMrPobStatus(String id, String status) =>
      _dio.patch(ApiConstants.mrPobStatus(id), data: {'status': status});
  Future<Response> getMrSamples({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.mrSamples, queryParameters: queryParams);
  Future<Response> createMrSampleTransaction(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.mrSamples, data: data);
  Future<Response> getMrDetailing({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.mrDetailing, queryParameters: queryParams);

  // P3 NOTIFICATIONS
  Future<Response> getNotifications({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.notifications, queryParameters: queryParams);
  Future<Response> markNotificationRead(String id) =>
      _dio.put(ApiConstants.notificationRead(id));
  Future<Response> markAllNotificationsRead() =>
      _dio.put(ApiConstants.notificationsReadAll);
  Future<Response> deleteNotification(String id) =>
      _dio.delete(ApiConstants.notificationById(id));
  Future<Response> registerDeviceToken(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.notificationsDeviceToken, data: data);
  Future<Response> unregisterDeviceToken(Map<String, dynamic> data) =>
      _dio.delete(ApiConstants.notificationsDeviceToken, data: data);

  // SHARED
  Future<Response> getAvailableSlots({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.calendarSlots, queryParameters: queryParams);
  Future<Response> getCommissions({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.commission, queryParameters: queryParams);
  Future<Response> getCommissionReport({Map<String, dynamic>? queryParams}) =>
      _dio.get(ApiConstants.commissionReport, queryParameters: queryParams);
  Future<Response> getOrCreateChatSession(Map<String, dynamic> data) =>
      _dio.post(ApiConstants.chatSession, data: data);
  Future<Response> getMyChatSessions() => _dio.get(ApiConstants.myChatSessions);
  Future<Response> getChatHistory(
    String sessionId, {
    int limit = 50,
    int skip = 0,
  }) => _dio.get(
    ApiConstants.chatHistory(sessionId),
    queryParameters: {'limit': limit, 'skip': skip},
  );
}
