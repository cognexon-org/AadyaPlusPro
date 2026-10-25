import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/availability_save_bar.dart';
import '../../doctor/widgets/doctor_ui.dart';
import '../providers/physio_profile_provider.dart';
import '../widgets/physio_profile_widgets.dart';

/// The physio's public details: who they are, where they practise, the
/// treatments they offer, and what patients read about them. Fees and
/// booking rules live in Practice settings, hours in Availability, home
/// visit areas in Service areas.
///
/// PUT /physio/me/profile whitelists its fields; this sends exactly the
/// fields on this screen.
class PhysioEditProfile extends ConsumerStatefulWidget {
  const PhysioEditProfile({super.key});

  @override
  ConsumerState<PhysioEditProfile> createState() => _PhysioEditProfileState();
}

class _PhysioEditProfileState extends ConsumerState<PhysioEditProfile> {
  final _name = TextEditingController();
  final _experience = TextEditingController();
  final _licence = TextEditingController();
  final _street = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _pincode = TextEditingController();
  final _about = TextEditingController();

  late final _all = [
    _name,
    _experience,
    _licence,
    _street,
    _city,
    _state,
    _pincode,
    _about,
  ];

  List<String> _specialisations = [];
  List<String> _degrees = [];
  List<String> _languages = [];
  List<PhysioService> _services = [];

  /// Kept so saving qualifications doesn't drop the university/year or
  /// certificate already on file for a degree.
  List<Map<String, dynamic>> _qualificationRecords = [];

  /// Kept so saving the address doesn't reset the clinic's map location —
  /// the server replaces the whole `clinicAddress` object.
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
    final p = ref.read(physioProfileProvider).profile;
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
    final notifier = ref.read(physioProfileProvider.notifier);
    await (retry ? notifier.load() : notifier.ensureLoaded());
    if (!mounted) return;
    final st = ref.read(physioProfileProvider);
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

  void _apply(Map<String, dynamic> p) {
    String s(dynamic v) => v == null ? '' : '$v'.trim();
    final address = p['clinicAddress'] is Map
        ? Map<String, dynamic>.from(p['clinicAddress'] as Map)
        : <String, dynamic>{};

    _name.text = s(p['name']);
    _experience.text = s(p['experienceYears']);
    _licence.text = s(p['licenseNumber']);
    _street.text = s(address['address'] ?? address['street']);
    _city.text = s(address['city']);
    _state.text = s(address['state']);
    _pincode.text = s(address['pincode']);
    _about.text = s(p['about']);
    _location = address['location'] is Map
        ? Map<String, dynamic>.from(address['location'] as Map)
        : null;

    _specialisations = physioStrings(p['specialization']);
    _languages = physioStrings(p['languages']);
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
      if (q is List)
        for (final e in q)
          if (e is String && e.trim().isNotEmpty) e.trim(),
    ];
    final services = p['services'];
    _services = services is List
        ? [for (final e in services) ?PhysioService.fromJson(e)]
        : [];
    _verification = s(p['verificationStatus']).isEmpty
        ? 'pending'
        : s(p['verificationStatus']);
  }

  Map<String, String> _snapshot() => {
    for (var i = 0; i < _all.length; i++) 'f$i': _all[i].text.trim(),
    'spec': _specialisations.join('|'),
    'deg': _degrees.join('|'),
    'lang': _languages.join('|'),
    'svc': _services.map((e) => e.key).join('||'),
  };

  bool get _dirty {
    if (_loading || _error != null || _initial.isEmpty) return false;
    final now = _snapshot();
    return now.keys.any((k) => now[k] != _initial[k]);
  }

  /// The server only accepts licence changes until the profile is approved.
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
      'clinicAddress': {
        'address': _street.text.trim(),
        'city': _city.text.trim(),
        'state': _state.text.trim(),
        'pincode': _pincode.text.trim(),
        'location': ?_location,
      },
      'services': [for (final s in _services) s.toJson()],
      'about': _about.text.trim(),
      'languages': _languages,
    };

    setState(() => _saving = true);
    try {
      await ref.read(physioProfileProvider.notifier).updateProfile(body);
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

  Future<void> _editService([int? index]) async {
    final result = await showPhysioServiceSheet(
      context,
      initial: index == null ? null : _services[index],
    );
    if (result == null || !mounted) return;
    setState(() {
      _services = [..._services];
      if (index == null) {
        _services.add(result);
      } else {
        _services[index] = result;
      }
    });
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
        PhysioChipsInput(
          label: 'Specialisations',
          hint: 'e.g. Sports physiotherapy',
          icon: LucideIcons.activity,
          values: _specialisations,
          required: true,
          errorText: _err('spec'),
          onChanged: (v) => setState(() => _specialisations = v),
        ),
        PhysioChipsInput(
          label: 'Qualifications',
          hint: 'e.g. BPT',
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
          'Registration no.',
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
                : 'We verify this with your council before patients can '
                      'book you.',
            style: AppType.sans(
              fontSize: AppType.caption,
              height: 1.45,
              color: AppColors.textTertiary,
            ),
          ),
        ),
        const AppSectionTitle('Clinic'),
        _field(
          'Clinic address',
          _street,
          LucideIcons.mapPin,
          maxLines: 2,
          hint: 'Building, street and area',
        ),
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
        AppSectionTitle(
          'Services',
          action: 'Add service',
          onAction: () => _editService(),
        ),
        _servicesList(),
        const SizedBox(height: 24),
        const AppSectionTitle('For patients'),
        _field(
          'About',
          _about,
          null,
          maxLines: 4,
          hint: 'Your approach, conditions you treat, and what to expect.',
          caps: TextCapitalization.sentences,
        ),
        PhysioChipsInput(
          label: 'Languages',
          hint: 'e.g. Hindi',
          icon: LucideIcons.languages,
          values: _languages,
          onChanged: (v) => setState(() => _languages = v),
        ),
      ],
    );
  }

  Widget _servicesList() {
    if (_services.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          'List the treatments you offer — e.g. post-surgery rehab, 45 min, '
          '₹800 — so patients know what to book.',
          style: AppType.sans(
            fontSize: AppType.caption,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
        ),
      );
    }
    return AppGroup(
      children: [
        for (var i = 0; i < _services.length; i++) ...[
          if (i > 0) const AppHairline(),
          _serviceRow(i),
        ],
      ],
    );
  }

  Widget _serviceRow(int i) {
    final s = _services[i];
    final meta = s.summary;
    return AppPressable(
      scale: 0.985,
      onTap: () => _editService(i),
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.fromLTRB(16, 11, 6, 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.sans(
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (meta.isNotEmpty || s.description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (meta.isNotEmpty) meta,
                        if (s.description.isNotEmpty) s.description,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.sans(
                        fontSize: AppType.caption,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  setState(() => _services = [..._services]..removeAt(i)),
              icon: const Icon(
                LucideIcons.trash2,
                size: 17,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
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
