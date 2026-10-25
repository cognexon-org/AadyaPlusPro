import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/availability_save_bar.dart';
import '../../physio/widgets/physio_profile_widgets.dart';
import '../providers/lab_providers.dart';
import '../widgets/lab_ui.dart';

const _knownAccreditations = ['NABL', 'CAP', 'ISO 15189', 'NABH'];

/// The lab's public details: name, registration, who signs reports, how to
/// reach it and where it is. Home collection and booking rules live in
/// their own screen. PUT /pathology/me/profile merges these fields.
class LabEditProfile extends ConsumerStatefulWidget {
  const LabEditProfile({super.key});

  @override
  ConsumerState<LabEditProfile> createState() => _LabEditProfileState();
}

class _LabEditProfileState extends ConsumerState<LabEditProfile> {
  final _name = TextEditingController();
  final _registration = TextEditingController();
  final _contact = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _website = TextEditingController();
  final _street = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _pincode = TextEditingController();

  late final _all = [
    _name,
    _registration,
    _contact,
    _phone,
    _email,
    _website,
    _street,
    _city,
    _state,
    _pincode,
  ];

  List<String> _accreditation = [];

  bool _loading = true;
  bool _saving = false;
  bool _submitted = false;
  String? _error;
  Map<String, String> _initial = const {};

  @override
  void initState() {
    super.initState();
    final p = ref.read(labProfileProvider).data;
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
    final notifier = ref.read(labProfileProvider.notifier);
    await (retry ? notifier.load() : notifier.ensureLoaded());
    if (!mounted) return;
    final st = ref.read(labProfileProvider);
    if (st.data.isEmpty) {
      setState(() {
        _loading = false;
        _error = st.error ?? "Couldn't load your lab details.";
      });
      return;
    }
    _apply(st.data);
    setState(() {
      _loading = false;
      _initial = _snapshot();
    });
  }

  void _apply(Map<String, dynamic> p) {
    String s(dynamic v) => v == null ? '' : '$v'.trim();
    final a = p['address'] is Map
        ? Map<String, dynamic>.from(p['address'] as Map)
        : <String, dynamic>{};
    _name.text = s(p['labName']);
    _registration.text = s(p['registrationNumber']);
    _contact.text = s(p['contactPerson']);
    _phone.text = s(p['phone']);
    _email.text = s(p['email']);
    _website.text = s(p['website']);
    _street.text = s(a['street']);
    _city.text = s(a['city']);
    _state.text = s(a['state']);
    _pincode.text = s(a['pincode']);
    _accreditation = physioStrings(p['accreditation']);
  }

  Map<String, String> _snapshot() => {
    for (var i = 0; i < _all.length; i++) 'f$i': _all[i].text.trim(),
    'acc': _accreditation.join('|'),
  };

  bool get _dirty {
    if (_loading || _error != null || _initial.isEmpty) return false;
    final now = _snapshot();
    return now.keys.any((k) => now[k] != _initial[k]);
  }

  // ─────────────────────────── Validation ──────────────────────────

  String? _err(String key) {
    if (!_submitted) return null;
    switch (key) {
      case 'name':
        return _name.text.trim().length < 2 ? 'Enter your lab’s name.' : null;
      case 'phone':
        final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
        return digits.length < 10 || digits.length > 12
            ? 'Enter a 10-digit phone number.'
            : null;
      case 'email':
        final t = _email.text.trim();
        return t.isNotEmpty &&
                !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)
            ? 'That email doesn’t look right.'
            : null;
      case 'pincode':
        final t = _pincode.text.trim();
        return t.isNotEmpty && !RegExp(r'^\d{6}$').hasMatch(t)
            ? 'A pincode is 6 digits.'
            : null;
    }
    return null;
  }

  bool get _valid =>
      const ['name', 'phone', 'email', 'pincode'].every((k) => _err(k) == null);

  // ───────────────────────────── Save ──────────────────────────────

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (!_valid) {
      doctorToast(context, 'Fix the highlighted fields.', error: true);
      return;
    }
    final body = <String, dynamic>{
      'labName': _name.text.trim(),
      'registrationNumber': _registration.text.trim(),
      'contactPerson': _contact.text.trim(),
      'phone': _phone.text.trim(),
      'email': _email.text.trim(),
      'website': _website.text.trim(),
      'address': {
        'street': _street.text.trim(),
        'city': _city.text.trim(),
        'state': _state.text.trim(),
        'pincode': _pincode.text.trim(),
      },
      'accreditation': _accreditation,
    };
    setState(() => _saving = true);
    try {
      await ref.read(labProfileProvider.notifier).save(body);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _initial = _snapshot();
      });
      doctorToast(context, 'Lab details saved');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      doctorToast(
        context,
        labError(e, fallback: "Couldn't save your lab details."),
        error: true,
      );
    }
  }

  void _toggleAccreditation(String a) {
    setState(() {
      _accreditation = _accreditation.contains(a)
          ? (_accreditation.where((x) => x != a).toList())
          : [..._accreditation, a];
    });
  }

  // ───────────────────────────── Build ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DoctorDiscardGuard(
      dirty: _dirty,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: doctorSettingsAppBar('Lab details'),
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
    final custom = _accreditation
        .where((a) => !_knownAccreditations.contains(a))
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        const AppSectionTitle('Your lab'),
        _field(
          'Lab name',
          _name,
          LucideIcons.building2,
          required: true,
          error: _err('name'),
          caps: TextCapitalization.words,
        ),
        _field(
          'Registration no.',
          _registration,
          LucideIcons.fileBadge,
          caps: TextCapitalization.characters,
          hint: 'State clinical establishment number',
        ),
        _field(
          'Contact person',
          _contact,
          LucideIcons.userRound,
          caps: TextCapitalization.words,
          hint: 'e.g. Dr. A. Mehta, Pathologist',
          margin: const EdgeInsets.only(bottom: 6),
        ),
        _hint('Shown on reports as the person who verified results.'),
        const SizedBox(height: 8),
        const AppSectionTitle('Accreditation'),
        _hint('Patients look for these when choosing a lab.'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in _knownAccreditations)
              AppFilterChip(
                label: a,
                selected: _accreditation.contains(a),
                onTap: () => _toggleAccreditation(a),
              ),
          ],
        ),
        const SizedBox(height: 12),
        PhysioChipsInput(
          label: 'Other accreditations',
          hint: 'e.g. ICMR approved',
          icon: LucideIcons.award,
          values: custom,
          onChanged: (v) => setState(
            () => _accreditation = [
              ..._accreditation.where(_knownAccreditations.contains),
              ...v,
            ],
          ),
        ),
        const SizedBox(height: 8),
        const AppSectionTitle('Contact'),
        _field(
          'Phone',
          _phone,
          LucideIcons.phone,
          required: true,
          error: _err('phone'),
          keyboard: TextInputType.phone,
          formatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
            LengthLimitingTextInputFormatter(15),
          ],
        ),
        _field(
          'Email',
          _email,
          LucideIcons.mail,
          error: _err('email'),
          keyboard: TextInputType.emailAddress,
        ),
        _field(
          'Website',
          _website,
          LucideIcons.globe,
          keyboard: TextInputType.url,
          hint: 'Optional',
        ),
        const SizedBox(height: 8),
        const AppSectionTitle('Address'),
        _field(
          'Street address',
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
      ],
    );
  }

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: AppType.sans(
        fontSize: AppType.caption,
        height: 1.45,
        color: AppColors.textTertiary,
      ),
    ),
  );

  Widget _field(
    String label,
    TextEditingController c,
    IconData? icon, {
    bool required = false,
    bool isNum = false,
    int maxLines = 1,
    String? hint,
    String? error,
    TextInputType? keyboard,
    TextCapitalization caps = TextCapitalization.none,
    List<TextInputFormatter>? formatters,
    EdgeInsetsGeometry margin = const EdgeInsets.only(bottom: 12),
  }) => AppTextField(
    label: label,
    controller: c,
    icon: icon,
    required: required,
    isNum: isNum,
    maxLines: maxLines,
    hint: hint,
    errorText: error,
    keyboardType: keyboard,
    textCapitalization: caps,
    inputFormatters: formatters,
    dense: true,
    margin: margin,
  );
}
