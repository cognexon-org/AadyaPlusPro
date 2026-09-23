import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../models/user_model.dart';
import '../../../core/network/api_service.dart';
import '../../../core/network/token_storage.dart';
import '../../../core/notifications/onesignal_service.dart';
import '../../../core/notifications/professional_push_notification_service.dart';

// Auth state
class AuthState {
  final UserModel? user;
  final bool isLoading;
  final bool isAuthenticated;
  final String? error;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.isAuthenticated = false,
    this.error,
  });

  AuthState copyWith({
    UserModel? user,
    bool? isLoading,
    bool? isAuthenticated,
    String? error,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      error: error,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final ApiService _api = ApiService();

  AuthNotifier() : super(const AuthState()) {
    _api.setUnauthorizedHandler(_handleUnauthorized);
  }

  Future<void> _handleUnauthorized() async {
    state = const AuthState(
      isAuthenticated: false,
      isLoading: false,
      error: 'Your session expired. Please sign in again.',
    );
  }

  bool _isSupportedProfessionalRole(dynamic rawRole) {
    final role = rawRole?.toString().toLowerCase() ?? '';
    return const {
      'doctor',
      'physio',
      'physiotherapist',
      'pathology',
      'pharmacy',
      'mr',
    }.contains(role);
  }

  String _unsupportedRoleMessage(dynamic rawRole) {
    final role = rawRole?.toString().toLowerCase() ?? '';
    if (role == 'patient')
      return 'Patient accounts must use the AadyaPlus patient app.';
    return 'This account role is not supported by AadyaPlus Professional.';
  }

  Map<String, dynamic> _userPayload(dynamic responseData) {
    if (responseData is! Map) return <String, dynamic>{};
    final raw = responseData['user'] ?? responseData['data'] ?? responseData;
    if (raw is! Map) return <String, dynamic>{};
    final user = Map<String, dynamic>.from(raw);
    final profile = responseData['profile'];
    if (profile is Map && profile['verificationStatus'] != null) {
      user['verificationStatus'] = profile['verificationStatus'];
    }
    return user;
  }

  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  void setUser(UserModel user) {
    state = AuthState(user: user, isAuthenticated: true, isLoading: false);
  }

  void setError(String error) {
    state = state.copyWith(error: error, isLoading: false);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Try to restore session from stored token
  Future<bool> tryAutoLogin() async {
    final hasToken = await TokenStorage.hasToken();
    if (!hasToken) return false;

    try {
      state = state.copyWith(isLoading: true);
      final response = await _api.getCurrentUser();
      final data = response.data;

      if (data != null &&
          (data['success'] == true ||
              data['user'] != null ||
              data['data'] != null)) {
        final userData = _userPayload(data);
        if (userData.isEmpty ||
            !_isSupportedProfessionalRole(userData['role'])) {
          await TokenStorage.clearAll();
          setError(_unsupportedRoleMessage(userData['role']));
          return false;
        }
        final token = await TokenStorage.getToken();
        final user = UserModel.fromJson(userData, token: token);

        // Persist user data
        await TokenStorage.saveUserData(jsonEncode(user.toJson()));
        setUser(user);
        await ProfessionalPushNotificationService.instance
            .syncAuthenticatedDevice();
        return true;
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await TokenStorage.clearAll();
      }
    } catch (_) {
      // Fall through to offline check
    }

    // Try offline: load cached user data
    try {
      final cachedData = await TokenStorage.getUserData();
      if (cachedData != null) {
        final decoded = jsonDecode(cachedData);
        if (decoded is! Map || !_isSupportedProfessionalRole(decoded['role'])) {
          await TokenStorage.clearAll();
          state = const AuthState(isAuthenticated: false, isLoading: false);
          return false;
        }
        final user = UserModel.fromJson(Map<String, dynamic>.from(decoded));
        setUser(user);
        await ProfessionalPushNotificationService.instance
            .syncAuthenticatedDevice();
        return true;
      }
    } catch (_) {}

    state = state.copyWith(isLoading: false);
    return false;
  }

  /// Real login with email and password
  Future<bool> login(String email, String password) async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      final response = await _api.login(email, password);
      final data = response.data;

      if (data == null) {
        setError('Empty response from server');
        return false;
      }

      // Extract token and validate the account role before persisting it.
      final token = data['token'] as String?;
      if (token == null || token.isEmpty) {
        setError(data['message'] ?? 'Login failed: no token received');
        return false;
      }
      final rawUser = _userPayload(data);
      if (rawUser.isEmpty || !_isSupportedProfessionalRole(rawUser['role'])) {
        await TokenStorage.clearAll();
        setError(_unsupportedRoleMessage(rawUser['role']));
        return false;
      }

      await TokenStorage.saveToken(token);
      final user = UserModel.fromJson(rawUser, token: token);

      // Persist user data
      await TokenStorage.saveUserData(jsonEncode(user.toJson()));

      setUser(user.copyWith(token: token));
      await ProfessionalPushNotificationService.instance
          .syncAuthenticatedDevice();
      return true;
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      setError(message);
      return false;
    } catch (e) {
      setError('Unexpected error: $e');
      return false;
    }
  }

  /// Requests an OTP for [phone].
  ///
  /// Returns the server's `purpose` — 'login' for a number that already has an
  /// account, 'signup' for one that does not — so the caller can route to
  /// registration without waiting for the verify step to fail.
  Future<({bool ok, String purpose, String? error})> sendPhoneOtp(
    String phone,
  ) async {
    try {
      state = state.copyWith(isLoading: true, error: null);
      final response = await _api.sendPhoneOtp(phone);
      state = state.copyWith(isLoading: false);
      final data = response.data;
      return (
        ok: true,
        purpose: '${data is Map ? data['purpose'] ?? 'login' : 'login'}',
        error: null,
      );
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      setError(message);
      return (ok: false, purpose: 'login', error: message);
    }
  }

  /// Verifies an OTP.
  ///
  /// An existing account is signed in here and [registered] comes back true.
  /// A new number returns [verificationToken] for the caller to carry into
  /// registration — no account is created by this call.
  Future<({bool ok, bool registered, String? verificationToken, String? error})>
  verifyPhoneOtp(String phone, String code) async {
    try {
      state = state.copyWith(isLoading: true, error: null);
      final response = await _api.verifyPhoneOtp(phone, code);
      final data = response.data;

      if (data is! Map) {
        setError('Empty response from server');
        return (
          ok: false,
          registered: false,
          verificationToken: null,
          error: 'Empty response from server',
        );
      }

      if (data['registered'] != true) {
        state = state.copyWith(isLoading: false);
        return (
          ok: true,
          registered: false,
          verificationToken: data['verificationToken']?.toString(),
          error: null,
        );
      }

      final token = data['token'] as String?;
      if (token == null || token.isEmpty) {
        setError('Sign-in failed: no token received');
        return (
          ok: false,
          registered: true,
          verificationToken: null,
          error: 'no token',
        );
      }

      // Same role gate as password login: this app is for professionals, and
      // a patient account signing in here would land in an empty dashboard.
      final rawUser = _userPayload(data);
      if (rawUser.isEmpty || !_isSupportedProfessionalRole(rawUser['role'])) {
        await TokenStorage.clearAll();
        final message = _unsupportedRoleMessage(rawUser['role']);
        setError(message);
        return (
          ok: false,
          registered: true,
          verificationToken: null,
          error: message,
        );
      }

      await TokenStorage.saveToken(token);
      final user = UserModel.fromJson(rawUser, token: token);
      await TokenStorage.saveUserData(jsonEncode(user.toJson()));
      setUser(user.copyWith(token: token));
      await ProfessionalPushNotificationService.instance
          .syncAuthenticatedDevice();
      return (ok: true, registered: true, verificationToken: null, error: null);
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      setError(message);
      return (
        ok: false,
        registered: false,
        verificationToken: null,
        error: message,
      );
    }
  }

  /// Real registration
  Future<bool> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required UserRole role,

    /// Issued by /auth/otp/verify for a number that has no account yet.
    /// Passing it tells the server the phone is already proven, and it is
    /// redeemed exactly once.
    String? verificationToken,
  }) async {
    try {
      state = state.copyWith(isLoading: true, error: null);

      final response = await _api.register({
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
        'role': _roleToApiString(role),
        'registrationSource': 'mobile',
        if (verificationToken != null && verificationToken.isNotEmpty)
          'verificationToken': verificationToken,
      });

      final data = response.data;

      if (data == null) {
        setError('Empty response from server');
        return false;
      }

      // Some backends return token on register, some don't
      final token = data['token'] as String?;
      if (token != null && token.isNotEmpty) {
        await TokenStorage.saveToken(token);
        final user = UserModel.fromLoginResponse(data);
        await TokenStorage.saveUserData(jsonEncode(user.toJson()));
        setUser(user.copyWith(token: token));
        await ProfessionalPushNotificationService.instance
            .syncAuthenticatedDevice();
      } else {
        // Registration succeeded but need to login separately
        state = state.copyWith(isLoading: false);
      }

      return true;
    } on DioException catch (e) {
      final message = _extractErrorMessage(e);
      setError(message);
      return false;
    } catch (e) {
      setError('Unexpected error: $e');
      return false;
    }
  }

  /// Complete professional profile after registration
  Future<bool> completeProfile(Map<String, dynamic> profileData) async {
    try {
      state = state.copyWith(isLoading: true, error: null);
      await _api.completeProfile(profileData);

      // Re-fetch the user to get updated profileCompleted status
      final meResponse = await _api.getCurrentUser();
      final userData = _userPayload(meResponse.data);
      final token = await TokenStorage.getToken();
      final updatedUser = UserModel.fromJson(userData, token: token);
      await TokenStorage.saveUserData(jsonEncode(updatedUser.toJson()));
      setUser(updatedUser);
      await ProfessionalPushNotificationService.instance
          .syncAuthenticatedDevice();

      return true;
    } on DioException catch (e) {
      setError(_extractErrorMessage(e));
      return false;
    } catch (e) {
      setError('Unexpected error: $e');
      return false;
    }
  }

  /// Re-fetch the current user (e.g. to pick up a verificationStatus change
  /// after admin approval) without disturbing isLoading/error UI state.
  /// Returns true if the fetch succeeded, regardless of whether anything
  /// actually changed.
  Future<bool> refreshUser() async {
    try {
      final response = await _api.getCurrentUser();
      final userData = _userPayload(response.data);
      if (userData.isEmpty) return false;
      final token = state.user?.token ?? await TokenStorage.getToken();
      final updatedUser = UserModel.fromJson(userData, token: token);
      await TokenStorage.saveUserData(jsonEncode(updatedUser.toJson()));
      state = state.copyWith(user: updatedUser, isAuthenticated: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Logout and clear all stored data
  Future<void> logout() async {
    // Unbind first: leaving the OneSignal external id attached would send the
    // next person to sign in on this device the previous user's order alerts.
    await OneSignalService.instance.unbindUser();
    await ProfessionalPushNotificationService.instance
        .unregisterAuthenticatedDevice();
    try {
      await _api.dio.post('/auth/logout');
    } catch (_) {
      // Logout endpoint failure shouldn't block local cleanup
    }
    await TokenStorage.clearAll();
    state = const AuthState();
  }

  // ==================== DEMO MODE (FALLBACK) ====================

  /// Demo login for different roles (when backend is unavailable)
  void demoLogin(UserRole role) {
    final user = UserModel(
      id: 'demo_${role.name}',
      name: _getDemoName(role),
      email: '${role.name}@aadyamed.com',
      phone: '9876543210',
      role: role,
      verificationStatus: VerificationStatus.approved,
      isVerified: true,
      profileCompleted: true,
      profileImage: null,
    );
    setUser(user);
  }

  /// Demo login for pending verification
  void demoLoginPending(UserRole role) {
    final user = UserModel(
      id: 'demo_${role.name}',
      name: _getDemoName(role),
      email: '${role.name}@aadyamed.com',
      phone: '9876543210',
      role: role,
      verificationStatus: VerificationStatus.pending,
      isVerified: false,
      profileCompleted: false,
      profileImage: null,
    );
    setUser(user);
  }

  // ==================== HELPERS ====================

  String _getDemoName(UserRole role) {
    switch (role) {
      case UserRole.doctor:
        return 'Dr. Rajesh Kumar';
      case UserRole.physiotherapist:
        return 'Anita Sharma';
      case UserRole.pathology:
        return 'HealthCare Diagnostics';
      case UserRole.pharmacy:
        return 'MedPlus Pharmacy';
      case UserRole.mr:
        return 'Field Representative';
    }
  }

  String _roleToApiString(UserRole role) {
    switch (role) {
      case UserRole.doctor:
        return 'doctor';
      case UserRole.physiotherapist:
        return 'physio';
      case UserRole.pathology:
        return 'pathology';
      case UserRole.pharmacy:
        return 'pharmacy';
      case UserRole.mr:
        return 'mr';
    }
  }

  String _extractErrorMessage(DioException e) {
    if (e.response?.data != null) {
      final data = e.response!.data;
      if (data is Map) {
        return data['message'] ?? data['error'] ?? 'Request failed';
      }
      if (data is String) return data;
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out. Please check your network.';
      case DioExceptionType.connectionError:
        return 'Unable to connect to server. Please check your internet connection.';
      default:
        return e.message ?? 'Something went wrong';
    }
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);
