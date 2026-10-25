import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/availability_save_bar.dart';
import '../../doctor/widgets/doctor_ui.dart';
import '../providers/physio_profile_provider.dart';
import '../widgets/physio_profile_widgets.dart';

/// How patients can book: which visit types are offered and at what fee,
/// how long a session is, how far ahead and how late they can book.
///
/// Reads and writes the physio profile (GET/PUT /physio/me/profile) — only
/// the fields below are sent. The server requires `consultationFee` and
/// `homeVisitFee` on every profile, so a fee is only sent when one is
/// entered: switching a type off keeps its existing fee on file.
class PhysioPracticeSettings extends ConsumerStatefulWidget {
  const PhysioPracticeSettings({super.key});

  @override
  ConsumerState<PhysioPracticeSettings> createState() =>
      _PhysioPracticeSettingsState();
}

class _ConsultType {
  final String key;
  final String label;
  final String subtitle;
  final IconData icon;
  final String enabledField;
  final String feeField;
  const _ConsultType(
    this.key,
    this.label,
    this.subtitle,
    this.icon,
    this.enabledField,
    this.feeField,
  );
}

const _types = [
  _ConsultType(
    'clinic',
    'Clinic visit',
    'Patients come to your clinic',
    LucideIcons.building2,
    'clinicConsultationEnabled',
    'consultationFee',
  ),
  _ConsultType(
    'home',
    'Home visit',
    'You treat the patient at home',
    LucideIcons.house,
    'homeVisitEnabled',
    'homeVisitFee',
  ),
  _ConsultType(
    'video',
    'Video session',
    'Guided session over a video call',
    LucideIcons.video,
    'teleconsultationEnabled',
    'videoCallFee',
  ),
];

const _slotChoices = [30, 45, 60, 90];

/// The server treats a notice of 0 as "use the default" (60 minutes), so
/// there is no "None" choice here — it would silently mean an hour.
const _noticeChoices = [15, 30, 60, 120, 240, 720, 1440];

const _windowChoices = [7, 14, 30, 60, 90];

class _PhysioPracticeSettingsState
    extends ConsumerState<PhysioPracticeSettings> {
  final _fees = {for (final t in _types) t.key: TextEditingController()};
  final _window = TextEditingController();

  final Map<String, bool> _enabled = {for (final t in _types) t.key: false};
  int _slot = 45;
  int _notice = 60;

  bool _loading = true;
  bool _saving = false;
  bool _submitted = false;
  String? _error;
  Map<String, String> _initialSnapshot = const {};

  @override
  void initState() {
    super.initState();
    // Already loaded (the usual case, from the Profile tab): fill the form
    // now, before the listeners, so the first frame is the form.
    final p = ref.read(physioProfileProvider).profile;
    if (p.isNotEmpty) {
      _apply(p);
      _loading = false;
      _initialSnapshot = _snapshot();
    } else {
      Future.microtask(_load);
    }
    for (final c in [..._fees.values, _window]) {
      c.addListener(_changed);
    }
  }

  @override
  void dispose() {
    for (final c in [..._fees.values, _window]) {
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
        _error = st.error ?? "Couldn't load your settings.";
      });
      return;
    }
    _apply(st.profile);
    setState(() {
      _loading = false;
      _initialSnapshot = _snapshot();
    });
  }

  void _apply(Map<String, dynamic> p) {
    for (final t in _types) {
      // GET /physio/me/profile sends resolved flags; this is the server's
      // own rule for a response without them: clinic is on unless switched
      // off; home/video are on when switched on, or when the flag was never
      // set but a fee was.
      final flag = p[t.enabledField];
      _enabled[t.key] = t.key == 'clinic'
          ? flag != false
          : flag == true ||
                (flag == null &&
                    (num.tryParse('${p[t.feeField] ?? ''}') ?? 0) > 0);
      _fees[t.key]!.text = physioAmountText(p[t.feeField]);
    }
    _slot = int.tryParse('${p['slotDurationMinutes'] ?? ''}') ?? 45;
    if (_slot <= 0) _slot = 45;
    _notice = int.tryParse('${p['minimumNoticeMinutes'] ?? ''}') ?? 60;
    if (_notice <= 0) _notice = 60;
    _window.text = '${int.tryParse('${p['bookingWindowDays'] ?? ''}') ?? 30}';
  }

  Map<String, String> _snapshot() => {
    for (final t in _types) ...{
      '${t.key}On': '${_enabled[t.key]}',
      '${t.key}Fee': _fees[t.key]!.text.trim(),
    },
    'slot': '$_slot',
    'notice': '$_notice',
    'window': _window.text.trim(),
  };

  bool get _dirty {
    if (_loading || _error != null || _initialSnapshot.isEmpty) return false;
    final now = _snapshot();
    return now.keys.any((k) => now[k] != _initialSnapshot[k]);
  }

  // ─────────────────────────── Validation ──────────────────────────

  String? _feeError(String key) {
    if (!_submitted || _enabled[key] != true) return null;
    final n = num.tryParse(_fees[key]!.text.trim());
    if (n == null || n <= 0) return 'Enter a fee to offer this.';
    if (n > 100000) return 'That fee looks too high.';
    return null;
  }

  String? get _windowError {
    if (!_submitted) return null;
    final n = int.tryParse(_window.text.trim());
    if (n == null || n < 1 || n > 365) return 'Between 1 and 365 days.';
    return null;
  }

  bool get _noneEnabled => !_enabled.values.any((v) => v);

  Future<void> _save() async {
    setState(() => _submitted = true);
    final invalid =
        _types.any((t) => _feeError(t.key) != null) ||
        _windowError != null ||
        _noneEnabled;
    if (invalid) {
      doctorToast(
        context,
        _noneEnabled
            ? 'Turn on at least one visit type.'
            : 'Fix the highlighted fields.',
        error: true,
      );
      return;
    }

    num? fee(String key) => num.tryParse(_fees[key]!.text.trim());
    final body = <String, dynamic>{
      for (final t in _types) t.enabledField: _enabled[t.key],
      // Only send a fee that was entered: `consultationFee` and
      // `homeVisitFee` are required on the profile, so a blank one for a
      // switched-off type leaves the fee on file alone.
      for (final t in _types)
        if (fee(t.key) != null) t.feeField: fee(t.key),
      'slotDurationMinutes': _slot,
      'minimumNoticeMinutes': _notice,
      'bookingWindowDays': int.parse(_window.text.trim()),
    };

    setState(() => _saving = true);
    try {
      await ref.read(physioProfileProvider.notifier).updateProfile(body);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _initialSnapshot = _snapshot();
      });
      doctorToast(context, 'Practice settings saved');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      doctorToast(
        context,
        doctorError(e, fallback: "Couldn't save your settings."),
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
        appBar: doctorSettingsAppBar('Practice settings'),
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
        const AppSectionTitle('Visit types'),
        AppGroup(
          children: [
            for (final t in _types) ...[
              if (t != _types.first) const AppHairline(),
              _typeRow(t),
            ],
          ],
        ),
        if (_submitted && _noneEnabled)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Turn on at least one so patients can book you.',
              style: AppType.sans(
                fontSize: AppType.caption,
                color: AppColors.error,
              ),
            ),
          ),
        const SizedBox(height: 24),
        const AppSectionTitle('Session length'),
        _hint(
          'How long each session is. Patients book in slots of this length.',
        ),
        _chips<int>(
          row: true,
          choices: {..._slotChoices, _slot}.toList()..sort(),
          selected: _slot,
          label: (m) => '$m min',
          onSelect: (m) => setState(() => _slot = m),
        ),
        const SizedBox(height: 24),
        const AppSectionTitle('Booking window'),
        _hint('How far ahead patients can book.'),
        _chips<int>(
          row: true,
          choices: _windowChoices,
          selected: int.tryParse(_window.text.trim()),
          label: (d) => '$d days',
          onSelect: (d) => _window.text = '$d',
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: AppTextField(
                label: 'Days ahead',
                controller: _window,
                icon: LucideIcons.calendarRange,
                isNum: true,
                dense: true,
                margin: EdgeInsets.zero,
                errorText: _windowError,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
              ),
            ),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 24),
        const AppSectionTitle('Minimum notice'),
        _hint('The latest a patient can book before a slot starts.'),
        _chips<int>(
          choices: {..._noticeChoices, _notice}.toList()..sort(),
          selected: _notice,
          label: _noticeLabel,
          onSelect: (m) => setState(() => _notice = m),
        ),
      ],
    );
  }

  static String _noticeLabel(int m) {
    if (m < 60) return '$m min';
    if (m % 1440 == 0) return m == 1440 ? '1 day' : '${m ~/ 1440} days';
    if (m % 60 == 0) return m == 60 ? '1 hour' : '${m ~/ 60} hours';
    return '${m ~/ 60} h ${m % 60} min';
  }

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: AppType.sans(
        fontSize: AppType.caption,
        color: AppColors.textSecondary,
      ),
    ),
  );

  Widget _chips<T>({
    required List<T> choices,
    required T? selected,
    required String Function(T) label,
    required ValueChanged<T> onSelect,
    bool row = false,
  }) => row && choices.length <= 6
      // A short fixed set reads best as one row of equal chips, with no
      // lone chip wrapping onto a second line.
      ? Row(
          children: [
            for (var i = 0; i < choices.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: AppFilterChip(
                  label: label(choices[i]),
                  selected: choices[i] == selected,
                  block: true,
                  onTap: () => onSelect(choices[i]),
                ),
              ),
            ],
          ],
        )
      : Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in choices)
              AppFilterChip(
                label: label(c),
                selected: c == selected,
                onTap: () => onSelect(c),
              ),
          ],
        );

  Widget _typeRow(_ConsultType t) {
    final on = _enabled[t.key] == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 10, 4),
      child: Column(
        children: [
          AppSwitchRow(
            label: t.label,
            subtitle: t.subtitle,
            icon: t.icon,
            value: on,
            margin: EdgeInsets.zero,
            onChanged: (v) => setState(() => _enabled[t.key] = v),
          ),
          AnimatedSize(
            duration: AppMotion.medium,
            curve: AppMotion.enter,
            alignment: Alignment.topCenter,
            child: on
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(30, 0, 6, 12),
                    child: _feeField(t),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  /// White on the grey group, so the field reads as an input, not a panel.
  Widget _feeField(_ConsultType t) {
    final error = _feeError(t.key);
    final accent = ModuleAccent.of(context).color;
    OutlineInputBorder border(Color? c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppColors.radiusInput),
      borderSide: c == null ? BorderSide.none : BorderSide(color: c, width: w),
    );
    return TextField(
      controller: _fees[t.key],
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d{0,6}(\.\d{0,2})?')),
      ],
      cursorColor: accent,
      style: AppType.sans(
        fontSize: AppType.body,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppColors.bg,
        hintText: 'Fee',
        hintStyle: AppType.sans(
          fontSize: AppType.small,
          color: AppColors.textTertiary,
        ),
        prefixIcon: const Icon(
          LucideIcons.indianRupee,
          size: 15,
          color: AppColors.textTertiary,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 36),
        suffixText: 'per session',
        suffixStyle: AppType.sans(
          fontSize: AppType.caption,
          color: AppColors.textTertiary,
        ),
        errorText: error,
        errorStyle: AppType.sans(fontSize: 11, color: AppColors.error),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: border(null),
        enabledBorder: border(null),
        focusedBorder: border(accent, 1.5),
        errorBorder: border(AppColors.error),
        focusedErrorBorder: border(AppColors.error, 1.5),
      ),
    );
  }
}
