import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../providers/doctor_profile_provider.dart';
import '../widgets/availability_save_bar.dart';
import '../widgets/doctor_ui.dart';

/// The doctor's public details: who they are, where they practise, and what
/// patients read about them. Fees and booking rules live in Practice
/// settings, hours in Availability.
///
/// PUT /doctor/me/profile takes any profile field except the server-managed
/// ones (verification, ratings, earnings), so this sends exactly the fields
/// on this screen and nothing else.
class DoctorEditProfile extends ConsumerStatefulWidget {
  const DoctorEditProfile({super.key});

  @override
  ConsumerState<DoctorEditProfile> createState() => _DoctorEditProfileState();
}

class _DoctorEditProfileState extends ConsumerState<DoctorEditProfile> {
  final _name = TextEditingController();
  final _experience = TextEditingController();
  final _licence = TextEditingController();
  final _clinic = TextEditingController();
  final _street = TextEditingController();
  final _locality = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _pincode = TextEditingController();
  final _about = TextEditingController();

  late final _all = [
    _name,
    _experience,
    _licence,
    _clinic,
    _street,
    _locality,
    _city,
    _state,
    _pincode,
    _about,
  ];

  List<String> _specialisations = [];
  List<String> _degrees = [];
  List<String> _languages = [];

  /// Kept so saving qualifications doesn't drop the university/year or
  /// certificate already on file for a degree.
  List<Map<String, dynamic>> _qualificationRecords = [];

  /// Kept so saving the address doesn't reset the clinic's map location —
  /// `$set` on `clinicAddress` replaces the whole object.
  Map<String, dynamic>? _location;

  String _verification = 'pending';
  bool _loading = true;
  bool _saving = false;
  bool _submitted = false;
  String? _error;
  Map<String, String> _initial = const {};

  @override
  void initState() {
    super.initState();
    // Already loaded (the usual case, from the Profile tab): fill the form
    // now, before the listeners, so the first frame is the form.
    final p = ref.read(doctorProfileProvider).profile;
    if (p.isNotEmpty) {
      _apply(p);
      _loading = false;
      _initial = _snapshot();
    } else {
      Future.microtask(_load);
    }
    for (final c in _all) {
      c.addListener(_changed);
    }
  }

  @override
  void dispose() {
    for (final c in _all) {
      c.removeListener(_changed);
      c.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load({bool retry = false}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final notifier = ref.read(doctorProfileProvider.notifier);
    await (retry ? notifier.load() : notifier.ensureLoaded());
    if (!mounted) return;
    final st = ref.read(doctorProfileProvider);
    if (st.profile.isEmpty) {
      setState(() {
        _loading = false;
        _error = st.error ?? "Couldn't load your profile.";
      });
      return;
    }
    _apply(st.profile);
    setState(() {
      _loading = false;
      _initial = _snapshot();
    });
  }

  static List<String> _strings(dynamic v) => v is List
      ? v.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList()
      : (v is String && v.trim().isNotEmpty ? [v.trim()] : <String>[]);

  void _apply(Map<String, dynamic> p) {
    String s(dynamic v) => v == null ? '' : '$v'.trim();
    final address = p['clinicAddress'] is Map
        ? Map<String, dynamic>.from(p['clinicAddress'] as Map)
        : <String, dynamic>{};

    _name.text = s(p['name']);
    _experience.text = s(p['experienceYears']);
    _licence.text = s(p['licenseNumber']);
    _clinic.text = s(p['clinicName']);
    _street.text = s(address['address'] ?? address['street']);
    _locality.text = s(address['locality']);
    _city.text = s(address['city']);
    _state.text = s(address['state']);
    _pincode.text = s(address['pincode']);
    _about.text = s(p['about']);
    _location = address['location'] is Map
        ? Map<String, dynamic>.from(address['location'] as Map)
        : null;

    _specialisations = _strings(p['specialization']);
    _languages = _strings(p['languages']);
    final q = p['qualifications'];
    _qualificationRecords = q is List
        ? [
            for (final e in q)
              if (e is Map) Map<String, dynamic>.from(e),
          ]
        : [];
    _degrees = [
      for (final r in _qualificationRecords)
        if (s(r['degree']).isNotEmpty) s(r['degree']),
      // Older records stored plain strings.
      if (q is List)
        for (final e in q)
          if (e is String && e.trim().isNotEmpty) e.trim(),
    ];
    _verification = s(p['verificationStatus']).isEmpty
        ? 'pending'
        : s(p['verificationStatus']);
  }

  Map<String, String> _snapshot() => {
    for (var i = 0; i < _all.length; i++) 'f$i': _all[i].text.trim(),
    'spec': _specialisations.join('|'),
    'deg': _degrees.join('|'),
    'lang': _languages.join('|'),
  };

  bool get _dirty {
    if (_loading || _error != null || _initial.isEmpty) return false;
    final now = _snapshot();
    return now.keys.any((k) => now[k] != _initial[k]);
  }

  /// A verified doctor's licence was checked by the team; changing the
  /// number would leave the approval standing against an unchecked licence.
  /// While pending or rejected it stays editable — a rejected application
  /// often needs exactly this corrected.
  bool get _licenceLocked =>
      (_verification == 'approved' || _verification == 'suspended') &&
      (_initial['f2'] ?? '').isNotEmpty;

  // ─────────────────────────── Validation ──────────────────────────

  String? _err(String key) {
    if (!_submitted) return null;
    switch (key) {
      case 'name':
        return _name.text.trim().length < 2 ? 'Enter your full name.' : null;
      case 'spec':
        return _specialisations.isEmpty
            ? 'Add at least one specialisation.'
            : null;
      case 'experience':
        final t = _experience.text.trim();
        if (t.isEmpty) return null;
        final n = int.tryParse(t);
        return n == null || n < 0 || n > 70 ? 'Between 0 and 70 years.' : null;
      case 'licence':
        return !_licenceLocked && _licence.text.trim().isEmpty
            ? 'Your registration number is required.'
            : null;
      case 'pincode':
        final t = _pincode.text.trim();
        return t.isNotEmpty && !RegExp(r'^\d{6}$').hasMatch(t)
            ? 'A pincode is 6 digits.'
            : null;
    }
    return null;
  }

  bool get _valid => const [
    'name',
    'spec',
    'experience',
    'licence',
    'pincode',
  ].every((k) => _err(k) == null);

  // ───────────────────────────── Save ──────────────────────────────

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (!_valid) {
      doctorToast(context, 'Fix the highlighted fields.', error: true);
      return;
    }

    final qualifications = [
      for (final d in _degrees)
        _qualificationRecords.firstWhere(
          (r) => '${r['degree'] ?? ''}'.trim() == d,
          orElse: () => {'degree': d},
        ),
    ];
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'specialization': _specialisations,
      'qualifications': qualifications,
      'experienceYears': int.tryParse(_experience.text.trim()) ?? 0,
      if (!_licenceLocked) 'licenseNumber': _licence.text.trim(),
      'clinicName': _clinic.text.trim(),
      'clinicAddress': {
        'address': _street.text.trim(),
        'locality': _locality.text.trim(),
        'city': _city.text.trim(),
        'state': _state.text.trim(),
        'pincode': _pincode.text.trim(),
        'location': ?_location,
      },
      'about': _about.text.trim(),
      'languages': _languages,
    };

    setState(() => _saving = true);
    try {
      await ref.read(doctorProfileProvider.notifier).updateProfile(body);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _initial = _snapshot();
      });
      doctorToast(context, 'Profile updated');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      doctorToast(
        context,
        doctorError(e, fallback: "Couldn't save your profile."),
        error: true,
      );
    }
  }

  // ───────────────────────────── Build ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DoctorDiscardGuard(
      dirty: _dirty,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: doctorSettingsAppBar('Edit profile'),
        body: SafeArea(top: false, child: _body()),
        bottomNavigationBar: doctorSaveBar(
          dirty: _dirty,
          saving: _saving,
          onSave: _save,
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: AppFormSkeleton(fields: 6),
      );
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          AppErrorBanner(message: _error!, onRetry: () => _load(retry: true)),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        const AppSectionTitle('About you'),
        _field(
          'Full name',
          _name,
          LucideIcons.userRound,
          required: true,
          error: _err('name'),
          caps: TextCapitalization.words,
        ),
        _DoctorChipsInput(
          label: 'Specialisations',
          hint: 'e.g. General physician',
          icon: LucideIcons.stethoscope,
          values: _specialisations,
          required: true,
          errorText: _err('spec'),
          onChanged: (v) => setState(() => _specialisations = v),
        ),
        _DoctorChipsInput(
          label: 'Qualifications',
          hint: 'e.g. MBBS',
          icon: LucideIcons.graduationCap,
          values: _degrees,
          onChanged: (v) => setState(() => _degrees = v),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _field(
                'Experience (years)',
                _experience,
                LucideIcons.briefcaseMedical,
                isNum: true,
                error: _err('experience'),
                formatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 8),
        const AppSectionTitle('Registration'),
        _field(
          'Medical registration no.',
          _licence,
          LucideIcons.fileBadge,
          required: !_licenceLocked,
          readOnly: _licenceLocked,
          error: _err('licence'),
          caps: TextCapitalization.characters,
          trailing: _licenceLocked
              ? const Icon(
                  LucideIcons.lock,
                  size: 14,
                  color: AppColors.textTertiary,
                )
              : null,
          margin: const EdgeInsets.only(bottom: 6),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            _licenceLocked
                ? 'Verified with your profile. To change it, contact '
                      'support — the new number will need re-verification.'
                : 'We verify this with your medical council before patients '
                      'can book you.',
            style: AppType.sans(
              fontSize: AppType.caption,
              height: 1.45,
              color: AppColors.textTertiary,
            ),
          ),
        ),
        const AppSectionTitle('Clinic'),
        _field('Clinic name', _clinic, LucideIcons.building2),
        _field('Street / building', _street, LucideIcons.mapPin, maxLines: 2),
        _field('Locality', _locality, null),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _field('City', _city, null)),
            const SizedBox(width: 12),
            Expanded(child: _field('State', _state, null)),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _field(
                'Pincode',
                _pincode,
                null,
                isNum: true,
                error: _err('pincode'),
                formatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 8),
        const AppSectionTitle('For patients'),
        _field(
          'About',
          _about,
          null,
          maxLines: 4,
          hint:
              'Your approach, areas of interest, and what patients can expect.',
          caps: TextCapitalization.sentences,
        ),
        _DoctorChipsInput(
          label: 'Languages',
          hint: 'e.g. Hindi',
          icon: LucideIcons.languages,
          values: _languages,
          onChanged: (v) => setState(() => _languages = v),
        ),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController c,
    IconData? icon, {
    bool required = false,
    bool isNum = false,
    bool readOnly = false,
    int maxLines = 1,
    String? hint,
    String? error,
    Widget? trailing,
    TextCapitalization caps = TextCapitalization.none,
    List<TextInputFormatter>? formatters,
    EdgeInsetsGeometry margin = const EdgeInsets.only(bottom: 12),
  }) => AppTextField(
    label: label,
    controller: c,
    icon: icon,
    required: required,
    isNum: isNum,
    readOnly: readOnly,
    maxLines: maxLines,
    hint: hint,
    errorText: error,
    trailing: trailing,
    textCapitalization: caps,
    inputFormatters: formatters,
    dense: true,
    margin: margin,
  );
}

/// A list of short values — specialisations, degrees, languages — typed one
/// at a time and shown as removable chips. Owns its own text controller.
class _DoctorChipsInput extends StatefulWidget {
  final String label;
  final String hint;
  final IconData icon;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final bool required;
  final String? errorText;

  const _DoctorChipsInput({
    required this.label,
    required this.hint,
    required this.icon,
    required this.values,
    required this.onChanged,
    this.required = false,
    this.errorText,
  });

  @override
  State<_DoctorChipsInput> createState() => _DoctorChipsInputState();
}

class _DoctorChipsInputState extends State<_DoctorChipsInput> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _add() {
    final values = _controller.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    final next = [...widget.values];
    for (final v in values) {
      if (!next.any((e) => e.toLowerCase() == v.toLowerCase())) next.add(v);
    }
    _controller.clear();
    if (next.length != widget.values.length) widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context).color;
    final canAdd = _controller.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            label: widget.label,
            controller: _controller,
            icon: widget.icon,
            hint: widget.hint,
            required: widget.required,
            errorText: widget.errorText,
            dense: true,
            margin: EdgeInsets.zero,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _add(),
            trailing: TextButton(
              onPressed: canAdd ? _add : null,
              child: Text(
                'Add',
                style: AppType.sans(
                  fontSize: AppType.small,
                  fontWeight: FontWeight.w600,
                  color: canAdd ? accent : AppColors.textDisabled,
                ),
              ),
            ),
          ),
          if (widget.values.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final v in widget.values)
                  Container(
                    padding: const EdgeInsets.fromLTRB(11, 6, 6, 6),
                    decoration: BoxDecoration(
                      color: ModuleAccent.of(context).veryLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            v,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.sans(
                              fontSize: AppType.caption,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        AppPressable(
                          semanticLabel: 'Remove $v',
                          onTap: () =>
                              widget.onChanged([...widget.values]..remove(v)),
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(
                              LucideIcons.x,
                              size: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
