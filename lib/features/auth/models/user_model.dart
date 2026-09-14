enum UserRole {
  doctor,
  physiotherapist,
  pathology,
  pharmacy,
  mr,
}

enum VerificationStatus {
  pending,
  approved,
  rejected,
  suspended,
}

class UserModel {
  final String? id;
  final String name;
  final String email;
  final String phone;
  final UserRole role;
  final VerificationStatus verificationStatus;
  final String? profileImage;
  final String? token;
  final bool isVerified;
  final bool profileCompleted;
  final bool isActive;
  final String? profileId;

  UserModel({
    this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    this.verificationStatus = VerificationStatus.pending,
    this.profileImage,
    this.token,
    this.isVerified = false,
    this.profileCompleted = false,
    this.isActive = true,
    this.profileId,
  });

  factory UserModel.fromJson(Map<String, dynamic> json, {String? token}) {
    final isVerified = json['isVerified'] ?? false;
    final status = json['status']?.toString().toLowerCase() ?? '';
    final explicitVerification = json['verificationStatus'];

    // Derive verificationStatus from multiple fields:
    // 1. If explicit verificationStatus is provided, use it
    // 2. If isVerified is true OR status is 'active', treat as approved
    // 3. Otherwise default to pending
    VerificationStatus verificationStatus;
    if (explicitVerification != null && explicitVerification.toString().isNotEmpty) {
      verificationStatus = _parseVerification(explicitVerification.toString());
    } else if (isVerified == true || status == 'active') {
      verificationStatus = VerificationStatus.approved;
    } else {
      verificationStatus = VerificationStatus.pending;
    }

    return UserModel(
      id: json['_id'] ?? json['id'],
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      role: _parseRole(json['role'] ?? ''),
      verificationStatus: verificationStatus,
      profileImage: json['profileImage'],
      token: token ?? json['token'],
      isVerified: isVerified,
      profileCompleted: json['profileCompleted'] ?? false,
      isActive: json['isActive'] ?? (status == 'active'),
      profileId: json['profileId']?.toString(),
    );
  }

  /// Parse from login response which may nest user data inside { user: {...}, token: "..." }
  factory UserModel.fromLoginResponse(Map<String, dynamic> json) {
    final userData = json['user'] ?? json['data'] ?? json;
    final token = json['token'] as String?;
    return UserModel.fromJson(userData as Map<String, dynamic>, token: token);
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'role': _roleToString(role),
      'verificationStatus': verificationStatus.name,
      'profileImage': profileImage,
      'token': token,
      'isVerified': isVerified,
      'profileCompleted': profileCompleted,
      'isActive': isActive,
      'profileId': profileId,
    };
  }

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    UserRole? role,
    VerificationStatus? verificationStatus,
    String? profileImage,
    String? token,
    bool? isVerified,
    bool? profileCompleted,
    bool? isActive,
    String? profileId,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      profileImage: profileImage ?? this.profileImage,
      token: token ?? this.token,
      isVerified: isVerified ?? this.isVerified,
      profileCompleted: profileCompleted ?? this.profileCompleted,
      isActive: isActive ?? this.isActive,
      profileId: profileId ?? this.profileId,
    );
  }

  static UserRole _parseRole(String role) {
    switch (role.toLowerCase()) {
      case 'doctor':
        return UserRole.doctor;
      case 'physiotherapist':
      case 'physio':
        return UserRole.physiotherapist;
      case 'pathology':
        return UserRole.pathology;
      case 'pharmacy':
        return UserRole.pharmacy;
      case 'mr':
        return UserRole.mr;
      default:
        return UserRole.doctor;
    }
  }

  static String _roleToString(UserRole role) {
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

  static VerificationStatus _parseVerification(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return VerificationStatus.approved;
      case 'rejected':
        return VerificationStatus.rejected;
      case 'suspended':
        return VerificationStatus.suspended;
      default:
        return VerificationStatus.pending;
    }
  }
}
