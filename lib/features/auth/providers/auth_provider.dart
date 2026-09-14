import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../models/user_model.dart';
import '../../../core/network/api_service.dart';
import '../../../core/network/token_storage.dart';

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
    return const {'doctor', 'physio', 'physiotherapist', 'pathology', 'pharmacy'}.contains(role);
  }

  String _unsupportedRoleMessage(dynamic rawRole) {
    final role = rawRole?.toString().toLowerCase() ?? '';
    if (role == 'patient') return 'Patient accounts must use the AadyaPlus patient app.';
    if (role == 'mr') return 'The MR field-force mobile experience is enabled in Pro Patch P3.';
    return 'This account role is not supported by AadyaPlus Professional.';
  }

  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  void setUser(UserModel user) {
    state = AuthState(
      user: user,
      isAuthenticated: true,
      isLoading: false,
    );
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

      if (data != null && (data['success'] == true || data['user'] != null || data['data'] != null)) {
        final userData = data['user'] ?? data['data'] ?? data;
        if (userData is! Map || !_isSupportedProfessionalRole(userData['role'])) {
          await TokenStorage.clearAll();
          setError(_unsupportedRoleMessage(userData is Map ? userData['role'] : null));
          return false;
        }
        final token = await TokenStorage.getToken();
        final user = UserModel.fromJson(Map<String, dynamic>.from(userData), token: token);
        
        // Persist user data
        await TokenStorage.saveUserData(jsonEncode(user.toJson()));
        setUser(user);
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
      final rawUser = data['user'] ?? data['data'] ?? data;
      if (rawUser is! Map || !_isSupportedProfessionalRole(rawUser['role'])) {
        await TokenStorage.clearAll();
        setError(_unsupportedRoleMessage(rawUser is Map ? rawUser['role'] : null));
        return false;
      }

      await TokenStorage.saveToken(token);
      final user = UserModel.fromJson(Map<String, dynamic>.from(rawUser), token: token);
      
      // Persist user data
      await TokenStorage.saveUserData(jsonEncode(user.toJson()));
      
      setUser(user.copyWith(token: token));
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

  /// Real registration
  Future<bool> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required UserRole role,
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
      final userData = meResponse.data['user'] ?? meResponse.data['data'] ?? meResponse.data;
      final token = await TokenStorage.getToken();
      final updatedUser = UserModel.fromJson(userData, token: token);
      await TokenStorage.saveUserData(jsonEncode(updatedUser.toJson()));
      setUser(updatedUser);

      return true;
    } on DioException catch (e) {
      setError(_extractErrorMessage(e));
      return false;
    } catch (e) {
      setError('Unexpected error: $e');
      return false;
    }
  }

  /// Logout and clear all stored data
  Future<void> logout() async {
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
