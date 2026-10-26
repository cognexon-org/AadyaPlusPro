class ApiConstants {
  static const String _configuredApiBaseUrl = String.fromEnvironment(
    'AADYA_API_BASE_URL',
    defaultValue: '',
  );

  static const String _configuredSocketBaseUrl = String.fromEnvironment(
    'AADYA_SOCKET_BASE_URL',
    defaultValue: '',
  );

  /// The production backend, used when no AADYA_API_BASE_URL is passed.
  ///
  /// Release builds used to throw here unless the URL was supplied with
  /// --dart-define, and a store build made without it crashed on launch
  /// (blank white/black screen). A dart-define still overrides this.
  static const String defaultApiBaseUrl = 'http://16.176.130.55/api';

  static String get baseUrl {
    final configured = _stripTrailingSlash(_configuredApiBaseUrl);
    return configured.isNotEmpty ? configured : defaultApiBaseUrl;
  }

  static String get socketBaseUrl {
    final configured = _stripTrailingSlash(_configuredSocketBaseUrl);
    if (configured.isNotEmpty) return configured;
    final apiUri = Uri.parse(baseUrl);
    var path = apiUri.path;
    if (path.endsWith('/api')) path = path.substring(0, path.length - 4);
    return apiUri
        .replace(path: path.isEmpty ? '/' : path)
        .toString()
        .replaceFirst(RegExp(r'/$'), '');
  }

  static String _stripTrailingSlash(String value) =>
      value.trim().replaceFirst(RegExp(r'/+$'), '');

  // AUTH
  static const login = '/auth/login';
  static const register = '/auth/register';
  static const me = '/auth/me';
  static const profileStatus = '/auth/profile-status';
  static const completeProfile = '/auth/complete-profile';
  static const updateProfile = '/auth/profile';
  static const changePassword = '/auth/change-password';
  static const forgotPassword = '/auth/forgot-password';
  static const resendVerification = '/auth/resend-verification';
  static const logout = '/auth/logout';

  // DOCTOR
  static const doctorProfile = '/doctor/me/profile';
  static const doctorDashboard = '/doctor/me/dashboard';
  static const doctorAppointments = '/doctor/me/appointments';
  static const doctorEarnings = '/doctor/me/earnings';
  static const doctorEarningsReport = '/doctor/me/earnings/report';
  static const doctorAvailability = '/doctor/me/availability';
  static String doctorWeeklyAvailability(String doctorId) =>
      '/doctor/$doctorId/availability/weekly';
  static String doctorDayAvailability(String doctorId) =>
      '/doctor/$doctorId/availability';

  // PHYSIO
  static const physioProfile = '/physio/me/profile';
  static const physioDashboard = '/physio/me/dashboard';
  static const physioAppointments = '/physio/me/appointments';
  static const physioPatients = '/physio/me/patients';
  static String physioPatientById(String id) => '/physio/me/patients/$id';
  static const physioEarnings = '/physio/me/earnings';
  static const physioEarningsReport = '/physio/me/earnings/report';
  static const physioAvailability = '/physio/me/availability';
  static const physioBreak = '/physio/me/break';

  // PHYSIOTHERAPY EXERCISES
  static const physioExerciseCatalog = '/physio-exercises/catalog';
  static String physioExerciseById(String id) =>
      '/physio-exercises/catalog/$id';
  static String physioPatientExercisePlans(String patientId) =>
      '/physio-exercises/patients/$patientId/plans';
  static String physioExercisePlan(String id) => '/physio-exercises/plans/$id';
  static String physioExercisePlanProgress(String id) =>
      '/physio-exercises/plans/$id/progress';
  static String physioExercisePlanAdherence(String id) =>
      '/physio-exercises/plans/$id/adherence';

  // Physio care: treatment packages & courses, assessments, progress.
  static const physioPackages = '/physio-care/me/packages';
  static String physioPackage(String id) => '/physio-care/me/packages/$id';
  static const physioCourses = '/physio-care/me/courses';
  static String physioCourse(String id) => '/physio-care/me/courses/$id';
  static String physioPatientCourses(String patientId) =>
      '/physio-care/me/patients/$patientId/courses';
  static String physioCourseLinkAppointment(
    String courseId,
    String appointmentId,
  ) => '/physio-care/me/courses/$courseId/appointments/$appointmentId';
  static String physioPatientAssessments(String patientId) =>
      '/physio-care/me/patients/$patientId/assessments';
  static String physioAssessment(String id) =>
      '/physio-care/me/assessments/$id';
  static String physioPatientProgress(String patientId) =>
      '/physio-care/me/patients/$patientId/progress';

  // PATHOLOGY COMPATIBILITY
  static const pathologyProfile = '/pathology/me/profile';
  static const pathologyDashboard = '/pathology/me/dashboard';
  static const pathologyTests = '/pathology/me/tests';
  static const pathologyTestSlots = '/pathology/me/test-slots';
  static const pathologyAppointments = '/pathology/me/tests';
  static String pathologyTestById(String id) => '/pathology/me/tests/$id';
  static String pathologyTestStatus(String id) =>
      '/pathology/me/tests/$id/status';
  static String pathologyTestReport(String id) =>
      '/pathology/me/tests/$id/report';
  static const pathologyMyAppointments = '/pathology/appointments';

  // P2 DIAGNOSTICS MERCHANT
  static const diagnosticsMerchantDashboard = '/diagnostics/merchant/dashboard';
  static const diagnosticsMerchantOrders = '/diagnostics/merchant/orders';
  static String diagnosticsMerchantOrder(String id) =>
      '/diagnostics/merchant/orders/$id';
  static String diagnosticsAssignCollector(String id) =>
      '/diagnostics/merchant/orders/$id/assign';
  static String diagnosticsCollectionStatus(String id) =>
      '/diagnostics/merchant/orders/$id/collection-status';
  static String diagnosticsOrderStatus(String id) =>
      '/diagnostics/merchant/orders/$id/status';
  static String diagnosticsOfflinePayment(String id) =>
      '/diagnostics/merchant/orders/$id/payment';
  static String diagnosticsReportUpload(String id) =>
      '/diagnostics/merchant/orders/$id/report';
  static String diagnosticsResults(String id) =>
      '/diagnostics/merchant/orders/$id/results';
  static String diagnosticsRelease(String id) =>
      '/diagnostics/merchant/orders/$id/release';
  static String diagnosticsReportFile(String id) =>
      '/diagnostics/orders/$id/report';
  static const diagnosticsEarnings = '/diagnostics/merchant/earnings';
  static const diagnosticsSchedule = '/diagnostics/merchant/schedule';
  static const diagnosticsHolidays = '/diagnostics/merchant/schedule/holidays';
  static const diagnosticsLibrary = '/diagnostics/merchant/catalog/library';
  static const diagnosticsImport = '/diagnostics/merchant/catalog/import';
  static const diagnosticsStaff = '/diagnostics/merchant/staff';
  static String diagnosticsStaffById(String id) =>
      '/diagnostics/merchant/staff/$id';
  static const diagnosticsCatalog = '/diagnostics/merchant/catalog';
  static const diagnosticsCatalogTests = '/diagnostics/merchant/catalog/tests';
  static String diagnosticsCatalogTest(String id) =>
      '/diagnostics/merchant/catalog/tests/$id';
  static const diagnosticsCatalogPackages =
      '/diagnostics/merchant/catalog/packages';
  static String diagnosticsCatalogPackage(String id) =>
      '/diagnostics/merchant/catalog/packages/$id';

  // PHARMACY PROFILE + TENANT
  static const pharmacyProfile = '/pharmacy/profile';
  static const tenantContext = '/tenant/context';
  static const tenantStores = '/tenant/stores';
  static String tenantSelectStore(String id) => '/tenant/stores/$id/select';
  static String tenantStore(String id) => '/tenant/stores/$id';

  // P2 PHARMACY ERP
  static const medicines = '/medicine';
  static const lowStockMedicines = '/medicine/low-stock';
  static const expiringMedicines = '/medicine/expiring';
  static const expiredMedicines = '/medicine/expired';
  static String medicineByBarcode(String code) =>
      '/medicine/barcode/${Uri.encodeComponent(code)}';
  static const batches = '/batch';
  static const suppliers = '/supplier';
  static const purchaseOrders = '/purchase-order';
  static String purchaseOrder(String id) => '/purchase-order/$id';
  static String purchaseOrderApprove(String id) =>
      '/purchase-order/$id/approve';
  static String purchaseOrderOrdered(String id) => '/purchase-order/$id/order';
  static String purchaseOrderReceive(String id) =>
      '/purchase-order/$id/receive';
  static String purchaseOrderCancel(String id) => '/purchase-order/$id/cancel';
  static String purchaseOrderPayment(String id) =>
      '/purchase-order/$id/payment';
  static String purchaseOrderGrns(String id) => '/purchase-order/$id/grns';
  static const goodsReceipts = '/grns';
  static const stockTransfers = '/stock-transfers';
  static String stockTransferAction(String id, String action) =>
      '/stock-transfers/$id/$action';
  static const pharmacyReturns = '/pharmacy-returns';
  static const pharmacyInventoryDashboard = '/pharmacy-erp/dashboard';
  static const pharmacyInventoryValuation = '/pharmacy-erp/valuation';
  static const pharmacyInventoryLedger = '/pharmacy-erp/ledger';
  static const pharmacyProfitLoss = '/pharmacy-erp/profit-loss';
  static const pharmacySales = '/sales';
  static const counterPayments = '/counter-payments';
  static String counterPayment(String id) => '/counter-payments/$id';
  static String counterPaymentClose(String id) => '/counter-payments/$id/close';
  static const pharmacySalesReport = '/sales/report';
  static const medicineBulkUploadTemplate = '/medicine/bulk-upload/template';
  static const medicineBulkUpload = '/medicine/bulk-upload';
  static const medicineCatalogSearch = '/medicine/catalog/search';

  // P2 E-PHARMACY MERCHANT
  static const merchantOrders = '/epharmacy/merchant/orders';

  /// The patient's uploaded prescription image, served inline. A pharmacy
  /// user is authorised for it whenever one of their store's orders
  /// references the upload, so no extra permission plumbing is needed.
  static String prescriptionUploadFile(String id) =>
      '$baseUrl/epharmacy/prescription-uploads/$id/file';
  static String merchantOrder(String id) => '/epharmacy/merchant/orders/$id';
  static String merchantOrderReject(String id) =>
      '/epharmacy/merchant/orders/$id/reject';
  static const merchantRejectionReasons =
      '/epharmacy/merchant/rejection-reasons';
  static const merchantPause = '/epharmacy/merchant/pause';
  static const merchantSettlement = '/epharmacy/merchant/settlement';
  static String merchantPrescriptionReview(String id) =>
      '/epharmacy/merchant/orders/$id/prescription';
  static String merchantConfirmOrder(String id) =>
      '/epharmacy/merchant/orders/$id/confirm';
  static String merchantOrderStatus(String id) =>
      '/epharmacy/merchant/orders/$id/status';
  static String merchantCancelOrder(String id) =>
      '/epharmacy/merchant/orders/$id/cancel';
  static String merchantRefundOrder(String id) =>
      '/epharmacy/merchant/orders/$id/refund';
  static String merchantOrderInvoicePdf(String id) =>
      '/epharmacy/merchant/orders/$id/invoice.pdf';
  static String merchantOrderPackingSlipPdf(String id) =>
      '/epharmacy/merchant/orders/$id/packing-slip.pdf';
  static String merchantOrderSubstitutes(String id) =>
      '/epharmacy/merchant/orders/$id/substitutes';
  static const merchantDrivers = '/epharmacy/merchant/drivers';
  static const merchantScheduleRegister =
      '/epharmacy/merchant/schedule-register';
  static const merchantCoupons = '/epharmacy/merchant/coupons';
  static String merchantCoupon(String id) => '/epharmacy/merchant/coupons/$id';
  static const merchantSettings = '/epharmacy/merchant/settings';

  // APPOINTMENTS / CONSULTATIONS / PRESCRIPTIONS
  static const appointments = '/appointment';
  static String appointmentsByPatient(String patientId) =>
      '/appointment/patient/$patientId';
  static const consultations = '/consultations';
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
  static const consultationHistory = '$consultations/history';
  static const prescriptions = '/prescription';
  static String prescriptionsByPatient(String patientId) =>
      '/prescription/patient/$patientId';
  static String prescriptionByAppointment(String appointmentId) =>
      '/prescription/appointment/$appointmentId';
  static String prescriptionIssue(String id) => '/prescription/$id/issue';
  static String prescriptionCancel(String id) => '/prescription/$id/cancel';
  static String prescriptionPdf(String id) => '/prescription/$id/pdf';

  // P3 MR / FIELD FORCE
  static const mrMe = '/mr/me';
  static const mrDashboard = '/mr/dashboard';
  static const mrAnalytics = '/mr/analytics';
  static const mrHierarchy = '/mr/hierarchy';
  static const mrTeam = '/mr/team';
  static const mrTerritories = '/mr/territories';
  static const mrAccounts = '/mr/accounts';
  static const mrVisits = '/mr/visits';
  static String mrVisitCheckIn(String id) => '/mr/visits/$id/check-in';
  static String mrVisitCheckOut(String id) => '/mr/visits/$id/check-out';
  static String mrVisitSubmit(String id) => '/mr/visits/$id/submit';
  static String mrVisitReview(String id) => '/mr/visits/$id/review';
  static const mrAttendance = '/mr/attendance';
  static const mrPunchIn = '/mr/attendance/punch-in';
  static const mrPunchOut = '/mr/attendance/punch-out';
  static const mrTourPlans = '/mr/tour-plans';
  static String mrTourPlanSubmit(String id) => '/mr/tour-plans/$id/submit';
  static String mrTourPlanReview(String id) => '/mr/tour-plans/$id/review';
  static const mrExpenses = '/mr/expenses';
  static String mrExpenseSubmit(String id) => '/mr/expenses/$id/submit';
  static String mrExpenseReview(String id) => '/mr/expenses/$id/review';
  static const mrTargets = '/mr/targets';
  static const mrPob = '/mr/pob';
  static String mrPobStatus(String id) => '/mr/pob/$id/status';
  static const mrSamples = '/mr/samples';
  static const mrDetailing = '/mr/detailing';

  // SHARED
  static const calendarSlots = '/calendar/available-slots';
  static const commission = '/commission';
  static const commissionReport = '/commission/report';
  static const chatSession = '/chat/session';
  static const myChatSessions = '/chat/professional/sessions';
  static String chatHistory(String sessionId) =>
      '/chat/session/$sessionId/messages';
  static const labTests = '/labtest';
  static const invoices = '/invoice';
  static const upload = '/upload/profile';
  static const patients = '/patient';
  static const notifications = '/notifications';
  static String notificationRead(String id) => '/notifications/$id/read';
  static const notificationsReadAll = '/notifications/read-all';
  static String notificationById(String id) => '/notifications/$id';
  static const notificationsDeviceToken = '/notifications/device-token';
}
