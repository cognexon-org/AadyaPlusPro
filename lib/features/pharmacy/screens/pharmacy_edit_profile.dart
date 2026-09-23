import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/network/api_service.dart';
import '../../auth/models/user_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/pharmacy_store_provider.dart';
import '../theme/pharmacy_colors.dart';
import '../theme/pharmacy_type.dart';
import '../widgets/pharmacy_ui.dart';

class PharmacyEditProfile extends ConsumerStatefulWidget {
  const PharmacyEditProfile({super.key});

  @override
  ConsumerState<PharmacyEditProfile> createState() =>
      _PharmacyEditProfileState();
}

class _PharmacyEditProfileState extends ConsumerState<PharmacyEditProfile> {
  final _name = TextEditingController();
  final _contactPerson = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _licence = TextEditingController();
  final _gstin = TextEditingController();
  final _street = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _pincode = TextEditingController();

  late final List<TextEditingController> _all = [
    _name,
    _contactPerson,
    _phone,
    _email,
    _licence,
    _gstin,
    _street,
    _city,
    _state,
    _pincode,
  ];

  bool _loading = true;
  bool _saving = false;
  bool _isDefaultBranch = true;
  String? _storeId;
  Map<String, String> _initial = const {};

  /// `PharmacyProfile.verificationStatus` straight from the server — the
  /// authoritative field, and the one the backend's own lock checks.
  String? _verificationStatus;

  @override
  void initState() {
    super.initState();
    for (final c in _all) {
      c.addListener(_onChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefill());
  }

  @override
  void dispose() {
    for (final c in _all) {
      c.removeListener(_onChanged);
      c.dispose();
    }
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _prefill() async {
    final state = ref.read(pharmacyStoreProvider);
    final store = state.selectedStore ?? const <String, dynamic>{};
    final storeAddress = Map<String, dynamic>.from(
      (store['address'] as Map?) ?? const {},
    );

    _storeId = store['_id']?.toString();
    _isDefaultBranch = store['isDefault'] == true || state.stores.length <= 1;

    // The registration record, for the fields it owns and — the reason this
    // request exists — for `verificationStatus`. The signed-in user's record
    // carries `isVerified`/`status`, which is about the *account*, not about
    // whether this pharmacy passed verification; reading the lock off that was
    // why nothing ever locked.
    Map<String, dynamic> profile = const {};
    if (_isDefaultBranch) {
      try {
        final response = await ApiService().getPharmacyProfile();
        final body = response.data;
        final raw = body is Map
            ? (body['pharmacy'] ?? body['profile'] ?? body['data'])
            : null;
        if (raw is Map) profile = Map<String, dynamic>.from(raw);
      } catch (_) {
        // A failed lookup must not silently unlock the form. The save is
        // still enforced server-side, and the fallback below keeps whatever
        // the account record claims.
      }
    }
    final profileAddress = Map<String, dynamic>.from(
      (profile['address'] as Map?) ?? const {},
    );

    String pick(String profileKey, String storeKey, [String? addressKey]) {
      if (addressKey != null) {
        final fromProfile = '${profileAddress[addressKey] ?? ''}'.trim();
        if (fromProfile.isNotEmpty) return fromProfile;
        return '${storeAddress[addressKey] ?? ''}'.trim();
      }
      final fromProfile = '${profile[profileKey] ?? ''}'.trim();
      if (fromProfile.isNotEmpty) return fromProfile;
      return '${store[storeKey] ?? ''}'.trim();
    }

    if (!mounted) return;
    _verificationStatus = profile['verificationStatus']?.toString();

    _name.text = pick('pharmacyName', 'name');
    _contactPerson.text = pick('contactPerson', 'contactPerson');
    _phone.text = pick('phone', 'phone');
    _email.text = pick('email', 'email');
    // gstin and drugLicenseNumber live only on the branch record.
    _licence.text =
        '${store['drugLicenseNumber'] ?? store['licenseNumber'] ?? profile['licenseNumber'] ?? ''}';
    _gstin.text = '${store['gstin'] ?? ''}';
    _street.text = pick('', '', 'street');
    _city.text = pick('', '', 'city');
    _state.text = pick('', '', 'state');
    _pincode.text = pick('', '', 'pincode');

    setState(() {
      _initial = _snapshot();
      _loading = false;
    });
  }

  Map<String, String> _snapshot() => {
    'name': _name.text.trim(),
    'contactPerson': _contactPerson.text.trim(),
    'phone': _phone.text.trim(),
    'email': _email.text.trim(),
    'licence': _licence.text.trim(),
    'gstin': _gstin.text.trim().toUpperCase(),
    'street': _street.text.trim(),
    'city': _city.text.trim(),
    'state': _state.text.trim(),
    'pincode': _pincode.text.trim(),
  };

  bool get _dirty {
    if (_initial.isEmpty) return false;
    final now = _snapshot();
    return now.keys.any((k) => now[k] != _initial[k]);
  }

  // ──────────────────────── What is locked ─────────────────────────

  /// The registered identity — trading name, drug licence and GSTIN — is what
  /// was checked during verification. Once a branch is approved those stop
  /// being free-text: editing the licence number on a verified pharmacy would
  /// leave an approval standing against a licence nobody checked, and
  /// `licenseNumber` is a unique index, so a typo collides with another
  /// pharmacy's record rather than failing cleanly.
  ///
  /// While a branch is still `pending` or was `rejected`, these stay editable
  /// — a rejected pharmacy usually needs to correct exactly these fields.
  /// A field is locked only if verification had something to look at. An
  /// empty GSTIN on an approved pharmacy was never verified, so locking it
  /// leaves no way to ever enter one — a dead end, not a safeguard.
  ///
  /// [key] is a key of [_snapshot], so this reads the value **as loaded from
  /// the server**, never the live controller. Reading the controller meant a
  /// blank GSTIN locked itself on the first character typed into it, and the
  /// half-finished value was then stuck there unsaved.
  bool _isLocked(String key) =>
      _identityLocked && (_initial[key] ?? '').trim().isNotEmpty;

  bool get _identityLocked {
    // Only an additional branch is never locked — it was not verified on its
    // own, and the backend agrees (the store lock only applies to isDefault).
    if (!_isDefaultBranch) return false;

    final status = _verificationStatus?.toLowerCase();
    if (status != null && status.isNotEmpty) {
      return status == 'approved' || status == 'suspended';
    }
    // Profile lookup failed — fall back to the account record rather than
    // assuming unlocked.
    final account = ref.watch(authProvider).user?.verificationStatus;
    return account == VerificationStatus.approved ||
        account == VerificationStatus.suspended;
  }

  // ─────────────────────────── Validation ──────────────────────────

  /// Returns the first problem, or null. Checked here rather than through
  /// `Form` because [PharmacyTextField] wraps a plain `TextField`, so
  /// `Form.validate()` would silently pass over every one of these.
  String? get _problem {
    if (_name.text.trim().isEmpty) return 'Pharmacy name is required.';
    final phone = _phone.text.trim();
    if (phone.isEmpty) return 'A contact phone number is required.';
    if (phone.replaceAll(RegExp(r'\D'), '').length < 10) {
      return 'Enter a 10-digit phone number.';
    }
    final email = _email.text.trim();
    if (email.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return "That email address doesn't look right.";
    }
    final pincode = _pincode.text.trim();
    if (pincode.isNotEmpty && !RegExp(r'^\d{6}$').hasMatch(pincode)) {
      return 'A pincode is 6 digits.';
    }
    final gstin = _gstin.text.trim();
    if (gstin.isNotEmpty && gstin.length != 15) {
      return 'A GSTIN is 15 characters.';
    }
    return null;
  }

  // ───────────────────────────── Save ──────────────────────────────

  Future<void> _save() async {
    final problem = _problem;
    if (problem != null) {
      _toast(problem, PharmacyColors.error);
      return;
    }

    final address = {
      'street': _street.text.trim(),
      'city': _city.text.trim(),
      'state': _state.text.trim(),
      'pincode': _pincode.text.trim(),
    };
    final licence = _licence.text.trim();
    final gstin = _gstin.text.trim().toUpperCase();

    setState(() => _saving = true);
    try {
      final api = ApiService();

      if (_isDefaultBranch) {
        await api.updatePharmacyProfile({
          'pharmacyName': _name.text.trim(),
          'contactPerson': _contactPerson.text.trim(),
          'phone': _phone.text.trim(),
          'email': _email.text.trim(),
          if (licence.isNotEmpty) 'licenseNumber': licence,
          'address': address,
        });
      }

      // Always write the branch too: it carries gstin and drugLicenseNumber,
      // which the profile endpoint has no field for, and for a non-default
      // branch it is the only record being edited at all.
      if (_storeId != null && _storeId!.isNotEmpty) {
        await api.updatePharmacyStore(_storeId!, {
          'name': _name.text.trim(),
          'phone': _phone.text.trim(),
          'email': _email.text.trim(),
          if (licence.isNotEmpty) 'licenseNumber': licence,
          if (licence.isNotEmpty) 'drugLicenseNumber': licence,
          'gstin': gstin,
          'address': address,
        });
      }

      await ref.read(pharmacyStoreProvider.notifier).refresh();
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Profile updated', PharmacyColors.success);
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final data = e.response?.data;
      final message = data is Map
          ? (data['message'] ?? data['error'])?.toString()
          : null;
      _toast(message ?? "Couldn't save your profile.", PharmacyColors.error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast("Couldn't save your profile.", PharmacyColors.error);
    }
  }

  void _toast(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: PharmacyType.sans(fontSize: 12.5, color: Colors.white),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return PharmacyDialog.confirm(
      context,
      title: 'Discard changes?',
      message: "Your edits haven't been saved yet.",
      confirmLabel: 'Discard',
      cancelLabel: 'Keep editing',
    );
  }

  // ───────────────────────────── Build ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: PharmacyColors.bg,
        appBar: AppBar(
          backgroundColor: PharmacyColors.bg,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          iconTheme: const IconThemeData(color: PharmacyColors.textPrimary),
          title: Text(
            'Edit Profile',
            style: PharmacyType.sans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: PharmacyColors.textPrimary,
            ),
          ),
        ),
        body: SafeArea(
          // An AppBar already covers the status bar; this is here for
          // the bottom inset, so content and buttons clear the device
          // gesture bar.
          top: false,
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: PharmacyFormSkeleton(fields: 5),
                )
              : ListView(
                  // Fields are not wrapped in bordered groups here. Every
                  // PharmacyTextField already draws its own filled, bordered box, so a
                  // group border around them nests a box inside a box — which is what
                  // made this screen look cluttered. The small-caps label carries the
                  // grouping instead.
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  children: [
                    if (!_isDefaultBranch) _branchNotice(),
                    if (_isLocked('name') ||
                        _isLocked('licence') ||
                        _isLocked('gstin'))
                      _lockNotice(),
                    _label('PHARMACY'),
                    if (_isLocked('name'))
                      _lockedField(
                        LucideIcons.store,
                        'Pharmacy name',
                        _name.text,
                      )
                    else
                      _field(
                        'Pharmacy name',
                        _name,
                        LucideIcons.store,
                        required: true,
                      ),
                    _field(
                      'Contact person',
                      _contactPerson,
                      LucideIcons.userRound,
                    ),
                    const SizedBox(height: 6),
                    _label('CONTACT'),
                    _field(
                      'Phone',
                      _phone,
                      LucideIcons.phone,
                      isNum: true,
                      required: true,
                    ),
                    _field('Email', _email, LucideIcons.mail),
                    const SizedBox(height: 6),
                    _label('LICENCES'),
                    if (_isLocked('licence'))
                      _lockedField(
                        LucideIcons.fileText,
                        'Drug licence number',
                        _licence.text,
                      )
                    else
                      _field(
                        'Drug licence number',
                        _licence,
                        LucideIcons.fileText,
                        hint: 'e.g. MH-20B-123456',
                      ),
                    if (_isLocked('gstin'))
                      _lockedField(LucideIcons.receipt, 'GSTIN', _gstin.text)
                    else
                      _field(
                        'GSTIN',
                        _gstin,
                        LucideIcons.receipt,
                        hint: '15 characters',
                        caps: true,
                      ),
                    const SizedBox(height: 6),
                    _label('ADDRESS'),
                    _field(
                      'Street / building',
                      _street,
                      LucideIcons.mapPin,
                      maxLines: 2,
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _field('City', _city, null)),
                        const SizedBox(width: 12),
                        Expanded(child: _field('State', _state, null)),
                      ],
                    ),
                    // A pincode is six characters — a full-width box for it only
                    // adds height to a form that is already long.
                    Row(
                      children: [
                        Expanded(
                          child: _field('Pincode', _pincode, null, isNum: true),
                        ),
                        const Spacer(),
                      ],
                    ),
                  ],
                ),
        ),
        bottomNavigationBar: _loading ? null : _saveBar(),
      ),
    );
  }

  // ──────────────────────────── Notices ────────────────────────────

  Widget _lockNotice() {
    final locked = [
      if (_isLocked('name')) 'name',
      if (_isLocked('licence')) 'drug licence',
      if (_isLocked('gstin')) 'GSTIN',
    ];
    final blank = [
      if (_identityLocked && !_isLocked('licence')) 'drug licence',
      if (_identityLocked && !_isLocked('gstin')) 'GSTIN',
    ];
    final list = locked.length == 1
        ? locked.first
        : '${locked.take(locked.length - 1).join(', ')} and ${locked.last}';

    return _notice(
      LucideIcons.lock,
      PharmacyColors.greenDark,
      PharmacyColors.greenVeryLight,
      PharmacyColors.greenLight,
      'Your pharmacy is verified, so the $list we checked can only be changed by support.'
      '${blank.isEmpty ? ' Everything else is yours to edit.' : ' Your ${blank.join(' and ')} was never submitted, so you can still add it here.'}',
    );
  }

  /// A second branch is not the registration record, and saying so here stops
  /// someone expecting an edit made on Branch 2 to show up on Branch 1.
  Widget _branchNotice() => _notice(
    LucideIcons.building2,
    PharmacyColors.warning,
    PharmacyTileStyle.amber.surface,
    PharmacyTileStyle.amber.border,
    "You're editing an additional branch. These details apply to this branch only — your registered pharmacy details are unchanged.",
  );

  Widget _notice(
    IconData icon,
    Color tone,
    Color surface,
    Color edge,
    String text,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: edge),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: tone),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: PharmacyType.sans(
                fontSize: 11.5,
                height: 1.45,
                color: PharmacyColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  // ───────────────────────────── Fields ────────────────────────────

  /// A value you cannot change, rendered as a read-only row rather than a
  /// greyed-out text box. A disabled input still invites a tap; this does not
  /// pretend to be editable in the first place.
  Widget _lockedField(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: PharmacyType.sans(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: PharmacyColors.textSecondary,
          ),
        ),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: PharmacyColors.bgSecondary,
            borderRadius: BorderRadius.circular(PharmacyColors.radiusInput),
            border: Border.all(color: PharmacyColors.borderStrong),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: PharmacyColors.textDisabled),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value.trim().isEmpty ? 'Not set' : value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PharmacyType.sans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: value.trim().isEmpty
                        ? PharmacyColors.textTertiary
                        : PharmacyColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                LucideIcons.lock,
                size: 14,
                color: PharmacyColors.textTertiary,
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _field(
    String label,
    TextEditingController controller,
    IconData? icon, {
    bool required = false,
    bool isNum = false,
    bool caps = false,
    int maxLines = 1,
    String? hint,
  }) {
    final field = PharmacyTextField(
      label: label,
      controller: controller,
      icon: icon,
      isNum: isNum,
      required: required,
      maxLines: maxLines,
      hint: hint,
      dense: true,
      margin: const EdgeInsets.only(bottom: 10),
    );
    if (!caps) return field;
    // GSTINs are stored uppercase server-side; echoing that back as you type
    // avoids a value that changes the moment you save it.
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (_, value, child) {
        final upper = value.text.toUpperCase();
        if (upper != value.text) {
          controller.value = value.copyWith(
            text: upper,
            selection: value.selection,
            composing: TextRange.empty,
          );
        }
        return child!;
      },
      child: field,
    );
  }

  // ─────────────────────────── Save bar ────────────────────────────

  Widget? _saveBar() {
    if (!_dirty && !_saving) return null;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: PharmacyColors.bg,
        border: Border(top: BorderSide(color: PharmacyColors.borderStrong)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            const Icon(
              LucideIcons.circleAlert,
              size: 15,
              color: PharmacyColors.warning,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Unsaved changes',
                style: PharmacyType.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: PharmacyColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 146,
              child: PharmacyButton(
                label: _saving ? 'Saving…' : 'Save changes',
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 0, 2, 9),
    child: Text(
      text,
      style: PharmacyType.sans(
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
        color: PharmacyColors.textTertiary,
      ),
    ),
  );
}
