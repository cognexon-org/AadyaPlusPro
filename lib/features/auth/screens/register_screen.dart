import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../pharmacy/theme/pharmacy_colors.dart';
import '../../pharmacy/theme/pharmacy_type.dart';
import '../../pharmacy/widgets/pharmacy_ui.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../widgets/onboarding_backdrop.dart';
import '../widgets/role_picker.dart';
import 'login_screen.dart' show kProfessionalRoles;

/// Four-step sign-up: role → account → professional details → review.
///
/// Each step is checked before moving on, so a mistake shows next to its
/// field instead of as a toast three screens later. The phone's back button
/// steps back rather than throwing the whole form away.
class RegisterScreen extends ConsumerStatefulWidget {
  /// Set when arriving from the OTP screen, where the number was already
  /// confirmed by SMS.
  final String? prefilledPhone;

  /// Single-use proof from /auth/otp/verify that [prefilledPhone] belongs to
  /// this person. The server redeems it once, which is what stops one verified
  /// number being used to open several accounts.
  final String? phoneVerificationToken;

  const RegisterScreen({
    super.key,
    this.prefilledPhone,
    this.phoneVerificationToken,
  });

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  static const _steps = [
    'Choose your role',
    'Your account',
    'Professional details',
    'Review and submit',
  ];

  final _pageController = PageController();
  int _step = 0;

  /// Steps whose Continue has been pressed — their errors are shown.
  final Set<int> _attempted = {};

  UserRole? _role;

  // Account
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  String _gender = '';
  DateTime? _dob;

  // Professional
  final _license = TextEditingController();
  final _experience = TextEditingController();
  final _specialization = TextEditingController();
  final _clinicName = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _pincode = TextEditingController();
  final _about = TextEditingController();
  final _consultationFee = TextEditingController();
  final _homeVisitFee = TextEditingController();
  final _videoFee = TextEditingController();

  /// Which visit types this practitioner offers. Physios must offer home
  /// visits (the server requires a home-visit fee for them).
  bool _offerClinic = true;
  bool _offerVideo = false;
  bool _offerHome = false;
  bool get _homeRequired => _role == UserRole.physiotherapist;
  bool get _homeOn => _homeRequired || _offerHome;

  bool _termsAccepted = false;

  List<TextEditingController> get _all => [
    _name,
    _email,
    _phone,
    _password,
    _license,
    _experience,
    _specialization,
    _clinicName,
    _address,
    _city,
    _state,
    _pincode,
    _about,
    _consultationFee,
    _homeVisitFee,
    _videoFee,
  ];

  bool get _phoneVerified => (widget.phoneVerificationToken ?? '').isNotEmpty;
  bool get _isPractitioner =>
      _role == UserRole.doctor || _role == UserRole.physiotherapist;

  @override
  void initState() {
    super.initState();
    // A number confirmed by SMS isn't editable — the token is bound to it.
    if (widget.prefilledPhone != null) _phone.text = widget.prefilledPhone!;
    for (final c in _all) {
      c.addListener(_revalidate);
    }
  }

  void _revalidate() {
    if (_attempted.contains(_step)) setState(() {});
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  // ─────────────────────────── Validation ───────────────────────────

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

  String? _err(int step, String field) {
    if (!_attempted.contains(step)) return null;
    return _errors(step)[field];
  }

  /// Field → message for everything wrong on [step]. Rules match the
  /// server's (auth.controller validateRegistrationData) so nothing passes
  /// here only to fail at submit.
  Map<String, String> _errors(int step) {
    final e = <String, String>{};
    String t(TextEditingController c) => c.text.trim();
    switch (step) {
      case 0:
        if (_role == null) e['role'] = 'Choose the role that fits you';
      case 1:
        if (t(_name).length < 2) e['name'] = 'Enter your full name';
        if (!_emailPattern.hasMatch(t(_email))) {
          e['email'] = 'Enter a valid email';
        }
        if (!RegExp(r'^[0-9]{10}$').hasMatch(t(_phone))) {
          e['phone'] = 'Enter a 10-digit mobile number';
        }
        if (_password.text.length < 6) {
          e['password'] = 'Use at least 6 characters';
        }
      case 2:
        if (t(_license).isEmpty) e['license'] = 'Required for verification';
        if (_isPractitioner && t(_specialization).isEmpty) {
          e['specialization'] = 'Enter at least one specialisation';
        }
        if (_isPractitioner) {
          bool bad(TextEditingController c) {
            final fee = num.tryParse(t(c));
            return fee == null || fee <= 0;
          }

          if (!_offerClinic && !_offerVideo && !_homeOn) {
            e['visitTypes'] = 'Offer at least one kind of visit';
          }
          if (_offerClinic && bad(_consultationFee))
            e['fee'] = 'Enter your fee';
          if (_offerVideo && bad(_videoFee)) e['videoFee'] = 'Enter your fee';
          if (_homeOn && bad(_homeVisitFee)) e['homeFee'] = 'Enter your fee';
        }
        if (!_isPractitioner && t(_clinicName).isEmpty) {
          e['clinic'] = _role == UserRole.pathology
              ? 'Enter the lab’s name'
              : 'Enter the pharmacy’s name';
        }
        if (t(_pincode).isNotEmpty &&
            !RegExp(r'^\d{6}$').hasMatch(t(_pincode))) {
          e['pincode'] = 'Pincode has 6 digits';
        }
      case 3:
        if (!_termsAccepted) e['terms'] = 'Accept the terms to continue';
    }
    return e;
  }

  // ─────────────────────────── Navigation ───────────────────────────

  void _goTo(int step) {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
    _pageController.animateToPage(
      step,
      duration: PharmacyMotion.medium,
      curve: PharmacyMotion.enter,
    );
  }

  void _continue() {
    // Field-force (MR) accounts are provisioned by the company's manager or
    // admin; there is nothing to fill in here.
    if (_step == 0 && _role == UserRole.mr) {
      final nav = Navigator.of(context);
      nav.canPop() ? nav.pop() : nav.pushReplacementNamed('/login');
      return;
    }
    setState(() => _attempted.add(_step));
    if (_errors(_step).isNotEmpty) {
      HapticFeedback.lightImpact();
      return;
    }
    if (_step < _steps.length - 1) {
      _goTo(_step + 1);
    } else {
      _submit();
    }
  }

  void _back() {
    if (_step > 0) {
      _goTo(_step - 1);
    } else {
      Navigator.pop(context);
    }
  }

  // ─────────────────────────── Submit ───────────────────────────

  Future<void> _submit() async {
    // Re-check every step: Edit on the review page can leave one invalid.
    for (var s = 0; s < _steps.length; s++) {
      if (_errors(s).isNotEmpty) {
        setState(() => _attempted.add(s));
        _goTo(s);
        return;
      }
    }

    final auth = ref.read(authProvider.notifier);
    final registered = await auth.register(
      name: _name.text.trim(),
      email: _email.text.trim(),
      phone: _phone.text.trim(),
      password: _password.text.trim(),
      role: _role!,
      verificationToken: widget.phoneVerificationToken,
    );
    if (!mounted) return;
    if (!registered) {
      _toast(ref.read(authProvider).error ?? 'Registration failed');
      return;
    }

    // The backend returns a JWT on registration; complete the role profile
    // straight away rather than discarding what this wizard collected.
    if (ref.read(authProvider).user == null) {
      _toast(
        'Account created. Sign in to finish your profile.',
        color: PharmacyColors.textStrong,
      );
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
      return;
    }

    final completed = await auth.completeProfile(_profilePayload());
    if (!mounted) return;
    if (!completed) {
      _toast(
        ref.read(authProvider).error ??
            'Account created, but your professional details didn’t save. Try again.',
      );
      return;
    }
    // Admin verification only affects public discoverability, not the
    // professional's access to their own dashboard.
    Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (r) => false);
  }

  Map<String, dynamic> _profilePayload() {
    final address = <String, dynamic>{
      'street': _address.text.trim(),
      'address': _address.text.trim(),
      'city': _city.text.trim(),
      'state': _state.text.trim(),
      'pincode': _pincode.text.trim(),
    };
    final specialization = _specialization.text
        .split(',')
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();
    final experienceYears = int.tryParse(_experience.text.trim()) ?? 0;
    num fee(TextEditingController c) => num.tryParse(c.text.trim()) ?? 0;
    final videoFee = _offerVideo ? fee(_videoFee) : 0;
    final homeVisitFee = _homeOn ? fee(_homeVisitFee) : 0;
    // The server needs a base consultation fee even when clinic visits are
    // off; use the clinic fee, else the first fee that was entered.
    final consultationFee = _offerClinic
        ? fee(_consultationFee)
        : (videoFee > 0 ? videoFee : homeVisitFee);

    switch (_role!) {
      case UserRole.doctor:
        return {
          'name': _name.text.trim(),
          if (_gender.isNotEmpty) 'gender': _gender,
          if (_dob != null) 'dateOfBirth': _dob!.toIso8601String(),
          'specialization': specialization,
          'experienceYears': experienceYears,
          'licenseNumber': _license.text.trim(),
          'clinicName': _clinicName.text.trim(),
          'clinicAddress': address,
          'consultationFee': consultationFee,
          'homeVisitFee': homeVisitFee,
          'videoCallFee': videoFee,
          'clinicConsultationEnabled': _offerClinic,
          'teleconsultationEnabled': _offerVideo,
          'homeVisitEnabled': _offerHome,
          'about': _about.text.trim(),
        };
      case UserRole.physiotherapist:
        return {
          'name': _name.text.trim(),
          if (_gender.isNotEmpty) 'gender': _gender,
          if (_dob != null) 'dateOfBirth': _dob!.toIso8601String(),
          'specialization': specialization,
          'experienceYears': experienceYears,
          'licenseNumber': _license.text.trim(),
          'clinicAddress': address,
          'consultationFee': consultationFee,
          'homeVisitFee': homeVisitFee,
          'videoCallFee': videoFee,
          'about': _about.text.trim(),
        };
      case UserRole.pathology:
        return {
          'labName': _clinicName.text.trim(),
          'registrationNumber': _license.text.trim(),
          'address': address,
          'contactPerson': _name.text.trim(),
        };
      case UserRole.pharmacy:
        return {
          'pharmacyName': _clinicName.text.trim(),
          'licenseNumber': _license.text.trim(),
          'address': address,
          'contactPerson': _name.text.trim(),
        };
      case UserRole.mr:
        // MR users are provisioned by a manager, not offered here.
        return const <String, dynamic>{};
    }
  }

  void _toast(String message, {Color color = PharmacyColors.error}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: PharmacyType.sans(
            fontSize: PharmacyType.caption,
            color: Colors.white,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: color,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ─────────────────────────── Build ───────────────────────────

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authProvider.select((s) => s.isLoading));
    final last = _step == _steps.length - 1;

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: PharmacyColors.bg,
        body: OnboardingBackdrop(
          child: SafeArea(
            child: Column(
              children: [
                _header(),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _page(_roleStep()),
                      _page(_accountStep()),
                      _page(_professionalStep()),
                      _page(_reviewStep()),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                  decoration: const BoxDecoration(
                    color: PharmacyColors.bg,
                    border: Border(
                      top: BorderSide(color: PharmacyColors.border),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The role can't be switched after sign-up; say so
                      // where the choice is confirmed.
                      if (_step == 0 && _role != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                LucideIcons.lock,
                                size: 12,
                                color: PharmacyColors.textTertiary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _role == UserRole.mr
                                    ? 'Your manager or company admin creates MR accounts'
                                    : 'Your role can’t be changed after sign-up',
                                style: PharmacyType.sans(
                                  fontSize: PharmacyType.caption,
                                  color: PharmacyColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      // On the role step the button previews the chosen
                      // module's colour.
                      ModuleTheme(
                        accent: _step == 0 && _role != null
                            ? accentForRole(_role!)
                            : ModuleAccent.of(context),
                        child: PharmacyButton(
                          label: last
                              ? 'Create account'
                              : _step == 0 && _role == UserRole.mr
                              ? 'I have an MR account · Sign in'
                              : _step == 0 && _role != null
                              ? 'Continue as ${_roleTitle(_role!)}'
                              : 'Continue',
                          icon: last ? LucideIcons.circleCheckBig : null,
                          loading: loading,
                          onPressed: loading ? null : _continue,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 6, 20, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: _step == 0 ? 'Back to sign in' : 'Previous step',
              onPressed: _back,
              icon: const Icon(
                LucideIcons.arrowLeft,
                size: 20,
                color: PharmacyColors.textStrong,
              ),
            ),
            const Spacer(),
            Text(
              'Step ${_step + 1} of ${_steps.length}',
              style: PharmacyType.sans(
                fontSize: PharmacyType.caption,
                fontWeight: FontWeight.w600,
                color: PharmacyColors.textTertiary,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 0, 14),
          child: AnimatedSwitcher(
            duration: PharmacyMotion.fast,
            child: Text(
              _steps[_step],
              key: ValueKey(_step),
              style: PharmacyType.sans(
                fontSize: PharmacyType.display,
                fontWeight: FontWeight.w800,
                color: PharmacyColors.textStrong,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(
            children: [
              for (var i = 0; i < _steps.length; i++)
                Expanded(
                  child: AnimatedContainer(
                    duration: PharmacyMotion.medium,
                    curve: PharmacyMotion.enter,
                    height: 4,
                    margin: EdgeInsets.only(
                      right: i == _steps.length - 1 ? 0 : 6,
                    ),
                    decoration: BoxDecoration(
                      color: i <= _step
                          ? ModuleAccent.of(context).color
                          : PharmacyColors.borderStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _page(Widget child) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
    child: child,
  );

  Widget _intro(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Text(
      text,
      style: PharmacyType.sans(
        fontSize: PharmacyType.body,
        color: PharmacyColors.textSecondary,
      ),
    ),
  );

  String _roleTitle(UserRole r) => switch (r) {
    UserRole.doctor => 'doctor',
    UserRole.physiotherapist => 'physiotherapist',
    UserRole.pathology => 'lab',
    UserRole.pharmacy => 'pharmacy',
    UserRole.mr => 'MR',
  };

  // ── Step 1 ──
  Widget _roleStep() {
    final error = _err(0, 'role');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _intro('Pick what you do — you’ll get the tools built for it.'),
        RolePicker(
          selected: _role,
          onSelect: (r) {
            HapticFeedback.selectionClick();
            setState(() => _role = r);
          },
        ),
        if (error != null) _fieldError(error),
      ],
    );
  }

  // ── Step 2 ──
  Widget _accountStep() {
    const s = 1;
    final personal = _isPractitioner;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _intro(
          personal
              ? 'You’ll sign in with this email and password.'
              : 'The person who manages this account. You’ll sign in with this email and password.',
        ),
        PharmacyTextField(
          label: personal ? 'Full name' : 'Contact person',
          controller: _name,
          icon: LucideIcons.user,
          hint: personal ? 'As on your registration certificate' : 'Your name',
          required: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.name],
          errorText: _err(s, 'name'),
        ),
        PharmacyTextField(
          label: 'Email',
          controller: _email,
          icon: LucideIcons.mail,
          hint: 'you@example.com',
          required: true,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          errorText: _err(s, 'email'),
        ),
        PharmacyTextField(
          label: 'Mobile number',
          controller: _phone,
          icon: LucideIcons.phone,
          hint: '10-digit number',
          required: true,
          readOnly: _phoneVerified,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.telephoneNumberNational],
          errorText: _err(s, 'phone'),
          trailing: _phoneVerified
              ? Tooltip(
                  message: 'Verified by OTP',
                  child: Icon(
                    LucideIcons.badgeCheck,
                    size: 18,
                    color: ModuleAccent.of(context).color,
                  ),
                )
              : null,
        ),
        PharmacyTextField(
          label: 'Password',
          controller: _password,
          icon: LucideIcons.lock,
          hint: 'At least 6 characters',
          required: true,
          obscureText: _obscure,
          autofillHints: const [AutofillHints.newPassword],
          errorText: _err(s, 'password'),
          margin: const EdgeInsets.only(bottom: 6),
          trailing: IconButton(
            tooltip: _obscure ? 'Show password' : 'Hide password',
            onPressed: () => setState(() => _obscure = !_obscure),
            icon: Icon(
              _obscure ? LucideIcons.eye : LucideIcons.eyeOff,
              size: 18,
              color: PharmacyColors.textTertiary,
            ),
          ),
        ),
        _PasswordStrength(password: _password.text),
        if (personal) ...[
          const SizedBox(height: 18),
          _label('Gender'),
          Row(
            children: [
              for (final g in const ['Male', 'Female', 'Other'])
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: g == 'Other' ? 0 : 8),
                    child: PharmacyFilterChip(
                      block: true,
                      label: g,
                      selected: _gender == g.toLowerCase(),
                      onTap: () => setState(() => _gender = g.toLowerCase()),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          PharmacyPickerField(
            label: 'Date of birth',
            valueText: _dob == null
                ? 'Select date'
                : DateFormat('d MMM yyyy').format(_dob!),
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: _dob ?? DateTime(now.year - 30),
                firstDate: DateTime(1940),
                lastDate: DateTime(now.year - 18, now.month, now.day),
              );
              if (picked != null) setState(() => _dob = picked);
            },
            margin: EdgeInsets.zero,
          ),
        ],
      ],
    );
  }

  // ── Step 3 ──
  Widget _professionalStep() {
    const s = 2;
    final role = _role;
    final orgLabel = role == UserRole.pathology
        ? 'Lab name'
        : role == UserRole.pharmacy
        ? 'Pharmacy name'
        : 'Clinic or hospital';
    final licenseLabel = role == UserRole.pathology
        ? 'Lab registration number'
        : role == UserRole.pharmacy
        ? 'Drug licence number'
        : 'Medical registration number';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _intro(
          'Checked by our team before you appear to patients. You can use the app meanwhile.',
        ),
        if (!_isPractitioner)
          PharmacyTextField(
            label: orgLabel,
            controller: _clinicName,
            icon: role == UserRole.pharmacy
                ? LucideIcons.store
                : LucideIcons.building2,
            required: true,
            textCapitalization: TextCapitalization.words,
            errorText: _err(s, 'clinic'),
          ),
        PharmacyTextField(
          label: licenseLabel,
          controller: _license,
          icon: LucideIcons.fileBadge,
          hint: role == UserRole.pharmacy ? 'e.g. 20B/21B-MH-12345' : null,
          required: true,
          textCapitalization: TextCapitalization.characters,
          errorText: _err(s, 'license'),
        ),
        if (_isPractitioner) ...[
          PharmacyTextField(
            label: 'Specialisation',
            controller: _specialization,
            icon: LucideIcons.award,
            hint: role == UserRole.doctor
                ? 'e.g. General physician, Cardiology'
                : 'e.g. Sports, Neuro',
            required: true,
            textCapitalization: TextCapitalization.words,
            errorText: _err(s, 'specialization'),
          ),
          PharmacyTextField(
            label: 'Years of experience',
            controller: _experience,
            icon: LucideIcons.briefcase,
            isNum: true,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
          ),
          const SizedBox(height: 4),
          PharmacySectionTitle('Visit types you offer'),
          _visitTypes(s),
          const SizedBox(height: 16),
          if (role == UserRole.doctor)
            PharmacyTextField(
              label: orgLabel,
              controller: _clinicName,
              icon: LucideIcons.building2,
              hint: 'Optional',
              textCapitalization: TextCapitalization.words,
            ),
        ],
        const SizedBox(height: 4),
        PharmacySectionTitle(
          role == UserRole.pharmacy || role == UserRole.pathology
              ? 'Address'
              : 'Where you practise',
        ),
        PharmacyTextField(
          label: 'Street address',
          controller: _address,
          icon: LucideIcons.mapPin,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
        ),
        Row(
          children: [
            Expanded(
              child: PharmacyTextField(
                label: 'City',
                controller: _city,
                textCapitalization: TextCapitalization.words,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PharmacyTextField(
                label: 'State',
                controller: _state,
                textCapitalization: TextCapitalization.words,
              ),
            ),
          ],
        ),
        PharmacyTextField(
          label: 'Pincode',
          controller: _pincode,
          isNum: true,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          errorText: _err(s, 'pincode'),
        ),
        if (_isPractitioner)
          PharmacyTextField(
            label: 'About you',
            controller: _about,
            hint: 'What patients should know — shown on your profile',
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            margin: EdgeInsets.zero,
          ),
      ],
    );
  }

  // ── Step 4 ──
  Widget _reviewStep() {
    final roleInfo = kProfessionalRoles.where((r) => r.role == _role);
    String v(TextEditingController c) =>
        c.text.trim().isEmpty ? '—' : c.text.trim();
    final place = [
      _city.text.trim(),
      _state.text.trim(),
      _pincode.text.trim(),
    ].where((e) => e.isNotEmpty).join(', ');
    final next = switch (_role) {
      UserRole.pharmacy => 'set up your stock and start taking online orders.',
      UserRole.pathology => 'add your test menu and start taking bookings.',
      _ => 'set your availability and start taking appointments.',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _intro('Check your details. You can edit anything before submitting.'),
        _reviewGroup('Account', 1, [
          ('Role', roleInfo.isEmpty ? '—' : roleInfo.first.title),
          (_isPractitioner ? 'Name' : 'Contact person', v(_name)),
          ('Email', v(_email)),
          ('Mobile', v(_phone)),
        ]),
        const SizedBox(height: 18),
        _reviewGroup('Professional', 2, [
          if (!_isPractitioner || _clinicName.text.trim().isNotEmpty)
            (
              _role == UserRole.pathology
                  ? 'Lab'
                  : _role == UserRole.pharmacy
                  ? 'Pharmacy'
                  : 'Clinic',
              v(_clinicName),
            ),
          ('Licence', v(_license)),
          if (_isPractitioner) ('Specialisation', v(_specialization)),
          if (_isPractitioner && _offerClinic)
            (
              _role == UserRole.doctor ? 'Clinic visit' : 'Clinic session',
              '₹${_consultationFee.text.trim()}',
            ),
          if (_isPractitioner && _offerVideo)
            ('Video consultation', '₹${_videoFee.text.trim()}'),
          if (_isPractitioner && _homeOn)
            ('Home visit', '₹${_homeVisitFee.text.trim()}'),
          if (place.isNotEmpty) ('Location', place),
        ]),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ModuleAccent.of(context).veryLight,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                LucideIcons.shieldCheck,
                size: 18,
                color: ModuleAccent.of(context).color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your licence is verified within 24–48 hours; we may ask for a document. '
                  'You can use the app meanwhile — $next',
                  style: PharmacyType.sans(
                    fontSize: PharmacyType.small,
                    height: 1.45,
                    color: PharmacyColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _termsAccepted = !_termsAccepted),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: PharmacyMotion.fast,
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: _termsAccepted
                        ? ModuleAccent.of(context).color
                        : PharmacyColors.bg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      width: 1.5,
                      color: _termsAccepted
                          ? ModuleAccent.of(context).color
                          : _err(3, 'terms') != null
                          ? PharmacyColors.error
                          : PharmacyColors.borderStrong,
                    ),
                  ),
                  child: _termsAccepted
                      ? const Icon(
                          LucideIcons.check,
                          size: 14,
                          color: Colors.white,
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: 'I agree to the ',
                      style: PharmacyType.sans(
                        fontSize: PharmacyType.small,
                        color: PharmacyColors.textSecondary,
                      ),
                      children: [
                        TextSpan(
                          text: 'Terms of Service',
                          style: PharmacyType.sans(
                            fontSize: PharmacyType.small,
                            fontWeight: FontWeight.w700,
                            color: PharmacyColors.textStrong,
                          ),
                        ),
                        const TextSpan(text: ' and '),
                        TextSpan(
                          text: 'Privacy Policy',
                          style: PharmacyType.sans(
                            fontSize: PharmacyType.small,
                            fontWeight: FontWeight.w700,
                            color: PharmacyColors.textStrong,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_err(3, 'terms') != null) _fieldError(_err(3, 'terms')!),
      ],
    );
  }

  /// Clinic / video / home, each with a switch and its fee. Fee fields only
  /// show for the types switched on, so a doctor who only sees patients at
  /// the clinic isn't asked for fees they don't charge.
  Widget _visitTypes(int step) {
    Widget row({
      required IconData icon,
      required String title,
      required String subtitle,
      required bool on,
      required ValueChanged<bool>? onChanged,
      required TextEditingController fee,
      required String errorKey,
    }) {
      final accent = ModuleAccent.of(context);
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: on ? accent.veryLight : PharmacyColors.bg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 16,
                    color: on ? accent.color : PharmacyColors.textTertiary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: PharmacyType.sans(
                          fontSize: PharmacyType.body,
                          fontWeight: FontWeight.w600,
                          color: PharmacyColors.textPrimary,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: PharmacyType.sans(
                          fontSize: PharmacyType.caption,
                          color: PharmacyColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onChanged != null)
                  PharmacySwitch(value: on, onChanged: onChanged)
                else
                  Text(
                    'Required',
                    style: PharmacyType.sans(
                      fontSize: PharmacyType.caption,
                      fontWeight: FontWeight.w600,
                      color: PharmacyColors.textTertiary,
                    ),
                  ),
              ],
            ),
            AnimatedSize(
              duration: PharmacyMotion.fast,
              child: on
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10, left: 46),
                      child: PharmacyTextField(
                        label: 'Fee',
                        controller: fee,
                        icon: LucideIcons.indianRupee,
                        hint: 'Per visit',
                        isNum: true,
                        required: true,
                        dense: true,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        errorText: _err(step, errorKey),
                        margin: EdgeInsets.zero,
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      );
    }

    final doctor = _role == UserRole.doctor;
    final error = _err(step, 'visitTypes');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PharmacyGroup(
          children: [
            row(
              icon: LucideIcons.building2,
              title: doctor ? 'Clinic visit' : 'Clinic session',
              subtitle: 'Patients come to you',
              on: _offerClinic,
              onChanged: (v) => setState(() => _offerClinic = v),
              fee: _consultationFee,
              errorKey: 'fee',
            ),
            const PharmacyHairline(),
            row(
              icon: LucideIcons.video,
              title: 'Video consultation',
              subtitle: 'Consult online from anywhere',
              on: _offerVideo,
              onChanged: (v) => setState(() => _offerVideo = v),
              fee: _videoFee,
              errorKey: 'videoFee',
            ),
            const PharmacyHairline(),
            row(
              icon: LucideIcons.house,
              title: 'Home visit',
              subtitle: _homeRequired
                  ? 'Physiotherapists offer home sessions'
                  : 'You visit the patient',
              on: _homeOn,
              onChanged: _homeRequired
                  ? null
                  : (v) => setState(() => _offerHome = v),
              fee: _homeVisitFee,
              errorKey: 'homeFee',
            ),
          ],
        ),
        if (error != null) _fieldError(error),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 2),
          child: Text(
            'You can change these any time in Practice settings.',
            style: PharmacyType.sans(
              fontSize: PharmacyType.caption,
              color: PharmacyColors.textTertiary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _reviewGroup(
    String title,
    int step,
    List<(String, String)> rows,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PharmacySectionTitle(title, action: 'Edit', onAction: () => _goTo(step)),
      PharmacyGroup(
        children: [
          for (final (i, r) in rows.indexed) ...[
            if (i > 0) const PharmacyHairline(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      r.$1,
                      style: PharmacyType.sans(
                        fontSize: PharmacyType.small,
                        color: PharmacyColors.textTertiary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.$2,
                      textAlign: TextAlign.right,
                      style: PharmacyType.sans(
                        fontSize: PharmacyType.small,
                        fontWeight: FontWeight.w600,
                        color: PharmacyColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ],
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: PharmacyType.sans(
        fontSize: PharmacyType.caption,
        fontWeight: FontWeight.w500,
        color: PharmacyColors.textSecondary,
      ),
    ),
  );

  Widget _fieldError(String text) => Padding(
    padding: const EdgeInsets.only(top: 4, left: 2),
    child: Row(
      children: [
        const Icon(
          LucideIcons.circleAlert,
          size: 13,
          color: PharmacyColors.error,
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: PharmacyType.sans(
            fontSize: PharmacyType.caption,
            color: PharmacyColors.error,
          ),
        ),
      ],
    ),
  );
}

/// A three-segment meter under the password. Advisory only — the server's
/// rule is 6+ characters, enforced by the step's validation.
class _PasswordStrength extends StatelessWidget {
  final String password;
  const _PasswordStrength({required this.password});

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox(height: 4);
    var score = 0;
    if (password.length >= 6) score++;
    if (password.length >= 10) score++;
    if (RegExp(r'\d').hasMatch(password) &&
        RegExp(r'[A-Za-z]').hasMatch(password)) {
      score++;
    }
    final (label, color) = switch (score) {
      0 || 1 => ('Weak', PharmacyColors.error),
      2 => ('Okay', PharmacyColors.warning),
      _ => ('Strong', PharmacyColors.success),
    };
    return Row(
      children: [
        for (var i = 0; i < 3; i++)
          Expanded(
            child: AnimatedContainer(
              duration: PharmacyMotion.fast,
              height: 3,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: i < score ? color : PharmacyColors.panel,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        const SizedBox(width: 6),
        Text(
          label,
          style: PharmacyType.sans(
            fontSize: PharmacyType.micro,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
