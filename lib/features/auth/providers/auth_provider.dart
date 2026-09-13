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

  AuthNotifier() : super(const AuthState());

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
        final token = await TokenStorage.getToken();
        final user = UserModel.fromJson(userData, token: token);
        
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
        final user = UserModel.fromJson(jsonDecode(cachedData));
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

      // Extract token
      final token = data['token'] as String?;
      if (token == null || token.isEmpty) {
        setError(data['message'] ?? 'Login failed: no token received');
        return false;
      }

      // Save token first so subsequent API calls are authenticated
      await TokenStorage.saveToken(token);

      // Parse user from response
      final user = UserModel.fromLoginResponse(data);
      
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
