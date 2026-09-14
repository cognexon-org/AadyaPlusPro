import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/gradient_button.dart';
import '../../auth/models/user_model.dart';
import '../../auth/providers/auth_provider.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _pageController = PageController();
  int _currentStep = 0;
  final int _totalSteps = 4;

  // Step 1: Role selection
  UserRole? _selectedRole;

  // Step 2: Basic details
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  String _gender = '';
  DateTime? _dob;

  // Step 3: Professional details (dynamic based on role)
  final _licenseController = TextEditingController();
  final _experienceController = TextEditingController();
  final _specializationController = TextEditingController();
  final _clinicNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _aboutController = TextEditingController();
  final _consultationFeeController = TextEditingController();
  final _homeVisitFeeController = TextEditingController();

  // Step 4: Review and submit
  bool _termsAccepted = false;

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _licenseController.dispose();
    _experienceController.dispose();
    _specializationController.dispose();
    _clinicNameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    _aboutController.dispose();
    _consultationFeeController.dispose();
    _homeVisitFeeController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _submitRegistration() async {
    if (_selectedRole == null || !_termsAccepted) return;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text.trim();

    final validationError = _registrationValidationError();
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(validationError), backgroundColor: Colors.red),
      );
      return;
    }

    final authNotifier = ref.read(authProvider.notifier);
    final registered = await authNotifier.register(
      name: name,
      email: email,
      phone: phone,
      password: password,
      role: _selectedRole!,
    );

    if (!mounted) return;
    if (!registered) {
      final error = ref.read(authProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error ?? 'Registration failed'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // The current backend returns a JWT on successful registration. Complete
    // the actual role profile immediately instead of discarding the fields
    // collected by this wizard.
    final user = ref.read(authProvider).user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registration successful. Please sign in to complete your profile.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
      return;
    }

    final profileCompleted =
        await authNotifier.completeProfile(_buildProfessionalProfilePayload());
    if (!mounted) return;

    if (!profileCompleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ref.read(authProvider).error ??
                'Account created, but professional profile submission failed.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.of(context).pushNamedAndRemoveUntil('/pending', (r) => false);
  }

  String? _registrationValidationError() {
    if (_nameController.text.trim().isEmpty ||
        _emailController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      return 'Please fill in all required account fields.';
    }
    if (_licenseController.text.trim().isEmpty) {
      return 'License / registration number is required.';
    }
    if ((_selectedRole == UserRole.doctor ||
            _selectedRole == UserRole.physiotherapist) &&
        _specializationController.text.trim().isEmpty) {
      return 'Specialization is required.';
    }
    if (_selectedRole == UserRole.doctor ||
        _selectedRole == UserRole.physiotherapist) {
      final consultationFee =
          num.tryParse(_consultationFeeController.text.trim());
      if (consultationFee == null || consultationFee <= 0) {
        return 'Enter a valid consultation fee.';
      }
    }
    if (_selectedRole == UserRole.physiotherapist) {
      final homeVisitFee = num.tryParse(_homeVisitFeeController.text.trim());
      if (homeVisitFee == null || homeVisitFee <= 0) {
        return 'Enter a valid home-visit fee.';
      }
    }
    if ((_selectedRole == UserRole.pathology ||
            _selectedRole == UserRole.pharmacy) &&
        _clinicNameController.text.trim().isEmpty) {
      return _selectedRole == UserRole.pathology
          ? 'Lab name is required.'
          : 'Pharmacy name is required.';
    }
    return null;
  }

  Map<String, dynamic> _buildProfessionalProfilePayload() {
    final role = _selectedRole!;
    final address = <String, dynamic>{
      'street': _addressController.text.trim(),
      'address': _addressController.text.trim(),
      'city': _cityController.text.trim(),
      'state': _stateController.text.trim(),
      'pincode': _pincodeController.text.trim(),
    };
    final specialization = _specializationController.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    final experienceYears =
        int.tryParse(_experienceController.text.trim()) ?? 0;
    final consultationFee =
        num.tryParse(_consultationFeeController.text.trim()) ?? 0;
    final homeVisitFee =
        num.tryParse(_homeVisitFeeController.text.trim()) ?? 0;

    switch (role) {
      case UserRole.doctor:
        return {
          'name': _nameController.text.trim(),
          if (_gender.isNotEmpty) 'gender': _gender.toLowerCase(),
          if (_dob != null) 'dateOfBirth': _dob!.toIso8601String(),
          'specialization': specialization,
          'experienceYears': experienceYears,
          'licenseNumber': _licenseController.text.trim(),
          'clinicName': _clinicNameController.text.trim(),
          'clinicAddress': address,
          'consultationFee': consultationFee,
          'homeVisitFee': homeVisitFee,
          'about': _aboutController.text.trim(),
        };
      case UserRole.physiotherapist:
        return {
          'name': _nameController.text.trim(),
          if (_gender.isNotEmpty) 'gender': _gender.toLowerCase(),
          if (_dob != null) 'dateOfBirth': _dob!.toIso8601String(),
          'specialization': specialization,
          'experienceYears': experienceYears,
          'licenseNumber': _licenseController.text.trim(),
          'clinicAddress': address,
          'consultationFee': consultationFee,
          'homeVisitFee': homeVisitFee,
          'about': _aboutController.text.trim(),
        };
      case UserRole.pathology:
        return {
          'labName': _clinicNameController.text.trim(),
          'registrationNumber': _licenseController.text.trim(),
          'address': address,
          'contactPerson': _nameController.text.trim(),
        };
      case UserRole.pharmacy:
        return {
          'pharmacyName': _clinicNameController.text.trim(),
          'licenseNumber': _licenseController.text.trim(),
          'address': address,
          'contactPerson': _nameController.text.trim(),
        };
      case UserRole.mr:
        // MR users are manager/admin provisioned and are not offered in this
        // public registration wizard.
        return const <String, dynamic>{};
    }
  }

  String _getRoleTitle() {
    switch (_selectedRole) {
      case UserRole.doctor:
        return 'Doctor';
      case UserRole.physiotherapist:
        return 'Physiotherapist';
      case UserRole.pathology:
        return 'Pathology Lab';
      case UserRole.pharmacy:
        return 'Pharmacy';
      default:
        return 'Professional';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _prevStep,
                    icon: const Icon(Iconsax.arrow_left, color: AppTheme.textPrimary),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppTheme.border),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Step ${_currentStep + 1} of $_totalSteps',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _getStepTitle(),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Progress bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: List.generate(_totalSteps, (index) {
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: index <= _currentStep
                            ? AppTheme.primary
                            : AppTheme.divider,
                      ),
                    ),
                  );
                }),
              ),
            ),

            // Content
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildRoleSelection(),
                  _buildBasicDetails(),
                  _buildProfessionalDetails(),
                  _buildDocumentsAndSubmit(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case 0:
        return 'Select Your Role';
      case 1:
        return 'Basic Details';
      case 2:
        return 'Professional Details';
      case 3:
        return 'Review & Submit';
      default:
        return '';
    }
  }

  // Step 1: Role Selection
  Widget _buildRoleSelection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What type of healthcare professional are you?',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          _buildRoleCard(
            UserRole.doctor,
            Iconsax.health,
            'Doctor',
            'General Physician, Specialist, Surgeon, etc.',
            AppTheme.doctorAccent,
          ),
          const SizedBox(height: 12),
          _buildRoleCard(
            UserRole.physiotherapist,
            Iconsax.activity,
            'Physiotherapist',
            'Physical therapist, Rehabilitation specialist',
            AppTheme.physioAccent,
          ),
          const SizedBox(height: 12),
          _buildRoleCard(
            UserRole.pathology,
            Iconsax.microscope,
            'Pathology Lab',
            'Diagnostic center, Testing laboratory',
            AppTheme.pathologyAccent,
          ),
          const SizedBox(height: 12),
          _buildRoleCard(
            UserRole.pharmacy,
            Iconsax.building,
            'Pharmacy',
            'Medical store, Pharmacy chain, Online pharmacy',
            AppTheme.pharmacyAccent,
          ),
          const SizedBox(height: 32),
          GradientButton(
            text: 'Continue',
            icon: Iconsax.arrow_right_3,
            onPressed: _selectedRole != null ? _nextStep : () {},
          ),
        ],
      ),
    );
  }

  Widget _buildRoleCard(UserRole role, IconData icon, String title, String subtitle, Color color) {
    final isSelected = _selectedRole == role;
    return GestureDetector(
      onTap: () => setState(() => _selectedRole = role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : AppTheme.border,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 28, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? color : AppTheme.divider,
                  width: 2,
                ),
                color: isSelected ? color : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // Step 2: Basic Details
  Widget _buildBasicDetails() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tell us about yourself',
            style: GoogleFonts.plusJakartaSans(fontSize: 15, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),

          _buildLabel('Full Name'),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              hintText: 'Enter your full name',
              prefixIcon: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Icon(Iconsax.user, size: 20, color: AppTheme.primary),
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildLabel('Email Address'),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              hintText: 'Enter your email',
              prefixIcon: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Icon(Iconsax.sms, size: 20, color: AppTheme.primary),
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildLabel('Phone Number'),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              hintText: 'Enter your phone number',
              prefixIcon: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Icon(Iconsax.call, size: 20, color: AppTheme.primary),
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildLabel('Gender'),
          Row(
            children: ['Male', 'Female', 'Other'].map((g) {
              final isSelected = _gender == g.toLowerCase();
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _gender = g.toLowerCase()),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primary.withValues(alpha: 0.1) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? AppTheme.primary : AppTheme.divider,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        g,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          _buildLabel('Date of Birth'),
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime(1990),
                firstDate: DateTime(1940),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _dob = picked);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFBAE6FD)),
              ),
              child: Row(
                children: [
                  const Icon(Iconsax.calendar, size: 20, color: AppTheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    _dob != null
                        ? '${_dob!.day}/${_dob!.month}/${_dob!.year}'
                        : 'Select date of birth',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: _dob != null ? AppTheme.textPrimary : AppTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildLabel('Password'),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              hintText: 'Create a strong password',
              prefixIcon: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Icon(Iconsax.lock, size: 20, color: AppTheme.primary),
              ),
            ),
          ),
          const SizedBox(height: 32),

          GradientButton(text: 'Continue', icon: Iconsax.arrow_right_3, onPressed: _nextStep),
        ],
      ),
    );
  }

  // Step 3: Professional Details
  Widget _buildProfessionalDetails() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Professional information for ${_getRoleTitle()}',
            style: GoogleFonts.plusJakartaSans(fontSize: 15, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),

          if (_selectedRole == UserRole.doctor || _selectedRole == UserRole.physiotherapist) ...[
            _buildLabel('Specialization'),
            TextField(
              controller: _specializationController,
              decoration: InputDecoration(
                hintText: _selectedRole == UserRole.doctor
                    ? 'e.g., Cardiologist, General Physician'
                    : 'e.g., Sports Physio, Neuro Physio',
                prefixIcon: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Icon(Iconsax.medal_star, size: 20, color: AppTheme.primary),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          _buildLabel(_selectedRole == UserRole.pathology
              ? 'Lab License Number'
              : _selectedRole == UserRole.pharmacy
                  ? 'Drug License Number'
                  : 'Medical License Number'),
          TextField(
            controller: _licenseController,
            decoration: InputDecoration(
              hintText: 'Enter license number',
              prefixIcon: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Icon(Iconsax.document, size: 20, color: AppTheme.primary),
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (_selectedRole == UserRole.doctor || _selectedRole == UserRole.physiotherapist) ...[
            _buildLabel('Years of Experience'),
            TextField(
              controller: _experienceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'Enter years of experience',
                prefixIcon: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Icon(Iconsax.briefcase, size: 20, color: AppTheme.primary),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (_selectedRole == UserRole.doctor || _selectedRole == UserRole.physiotherapist) ...[
            _buildLabel('Consultation Fee (INR)'),
            TextField(
              controller: _consultationFeeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'e.g., 500',
                prefixIcon: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Icon(Iconsax.wallet_2, size: 20, color: AppTheme.primary),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (_selectedRole == UserRole.physiotherapist) ...[
            _buildLabel('Home Visit Fee (INR)'),
            TextField(
              controller: _homeVisitFeeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'e.g., 800',
                prefixIcon: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Icon(Iconsax.home_2, size: 20, color: AppTheme.primary),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          _buildLabel(_selectedRole == UserRole.pathology
              ? 'Lab Name'
              : _selectedRole == UserRole.pharmacy
                  ? 'Pharmacy Name'
                  : 'Clinic / Hospital Name'),
          TextField(
            controller: _clinicNameController,
            decoration: InputDecoration(
              hintText: _selectedRole == UserRole.pathology
                  ? 'Enter lab name'
                  : _selectedRole == UserRole.pharmacy
                      ? 'Enter pharmacy name'
                      : 'Enter clinic name',
              prefixIcon: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Icon(Iconsax.building, size: 20, color: AppTheme.primary),
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildLabel('Address'),
          TextField(
            controller: _addressController,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Enter full address',
              prefixIcon: Padding(
                padding: EdgeInsets.only(left: 14, right: 14, bottom: 24),
                child: Icon(Iconsax.location, size: 20, color: AppTheme.primary),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('City'),
                    TextField(
                      controller: _cityController,
                      decoration: const InputDecoration(hintText: 'City'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('State'),
                    TextField(
                      controller: _stateController,
                      decoration: const InputDecoration(hintText: 'State'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          _buildLabel('Pincode'),
          TextField(
            controller: _pincodeController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: 'Enter pincode',
              prefixIcon: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Icon(Iconsax.map, size: 20, color: AppTheme.primary),
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildLabel('About'),
          TextField(
            controller: _aboutController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Tell patients about your practice...',
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: 14, right: 14, bottom: 48),
                child: Icon(Iconsax.info_circle, size: 20, color: AppTheme.primary),
              ),
            ),
          ),
          const SizedBox(height: 32),

          GradientButton(text: 'Continue', icon: Iconsax.arrow_right_3, onPressed: _nextStep),
        ],
      ),
    );
  }

  // Step 4: Review & Submit
  Widget _buildDocumentsAndSubmit() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Iconsax.shield_tick, color: AppTheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your license number and professional details will be submitted for verification. '
                    'The verification team may request supporting identity or qualification documents before approval.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      height: 1.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Review Summary Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Iconsax.info_circle, size: 20, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'What happens next?',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildInfoStep('1', 'Your profile will be reviewed by our admin team'),
                const SizedBox(height: 8),
                _buildInfoStep('2', 'Verification typically takes 24-48 hours'),
                const SizedBox(height: 8),
                _buildInfoStep('3', 'You\'ll be notified once approved'),
                const SizedBox(height: 8),
                _buildInfoStep('4', 'Start accepting appointments & grow your practice'),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Terms checkbox
          GestureDetector(
            onTap: () => setState(() => _termsAccepted = !_termsAccepted),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _termsAccepted ? AppTheme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _termsAccepted ? AppTheme.primary : AppTheme.divider,
                      width: 2,
                    ),
                  ),
                  child: _termsAccepted
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: 'I agree to the ',
                      style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textSecondary),
                      children: [
                        TextSpan(
                          text: 'Terms of Service',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                        const TextSpan(text: ' and '),
                        TextSpan(
                          text: 'Privacy Policy',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          GradientButton(
            text: 'Submit for Review',
            icon: Iconsax.send_1,
            onPressed: _termsAccepted ? _submitRegistration : () {},
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildInfoStep(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }
}
