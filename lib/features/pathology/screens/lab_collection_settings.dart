import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/availability_save_bar.dart';
import '../providers/lab_providers.dart';
import '../widgets/lab_ui.dart';

/// How patients can book the lab: home collection (on/off, charge, how far,
/// which pincodes), booking rules (how far ahead, minimum notice, when
/// cancelling closes) and opening hours. Collection slots themselves are
/// set in Collection slots.
class LabCollectionSettings extends ConsumerStatefulWidget {
  const LabCollectionSettings({super.key});

  @override
  ConsumerState<LabCollectionSettings> createState() =>
      _LabCollectionSettingsState();
}

class _LabCollectionSettingsState extends ConsumerState<LabCollectionSettings> {
  final _charges = TextEditingController();
  final _pincodeInput = TextEditingController();

  bool _home = false;
  int _radius = 10;
  List<String> _pincodes = [];
  int _advance = 30;
  int _notice = 2;
  int _cancel = 4;
  String _wdOpen = '07:00';
  String _wdClose = '20:00';
  String _weOpen = '07:00';
  String _weClose = '14:00';

  /// Sent back untouched: the server replaces `operatingHours` whole.
  List<dynamic> _holidays = const [];

  bool _loading = true;
  bool _saving = false;
  bool _submitted = false;
  String? _error;
  String? _pincodeError;
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
    _charges.addListener(_changed);
  }

  @override
  void dispose() {
    _charges.removeListener(_changed);
    _charges.dispose();
    _pincodeInput.dispose();
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
        _error = st.error ?? "Couldn't load your settings.";
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
    int i(dynamic v, int d) => int.tryParse('${v ?? ''}') ?? d;
    String t(dynamic v, String d) {
      final s = '${v ?? ''}'.trim();
      return RegExp(r'^\d{2}:\d{2}$').hasMatch(s) ? s : d;
    }

    _home = p['homeCollectionAvailable'] == true;
    final c = num.tryParse('${p['homeCollectionCharges'] ?? ''}') ?? 0;
    _charges.text = c > 0 ? (c % 1 == 0 ? '${c.toInt()}' : '$c') : '';
    _radius = i(p['homeCollectionRadiusKm'], 10);
    _pincodes =
        (p['homeCollectionPincodes'] is List
                ? p['homeCollectionPincodes'] as List
                : const [])
            .map((e) => '$e'.trim())
            .where((e) => e.isNotEmpty)
            .toList();
    final b = p['bookingSettings'] is Map
        ? p['bookingSettings'] as Map
        : const {};
    _advance = i(b['advanceBookingDays'], 30);
    _notice = i(b['minimumNoticeHours'], 2);
    _cancel = i(b['cancellationWindowHours'], 4);
    final h = p['operatingHours'] is Map
        ? p['operatingHours'] as Map
        : const {};
    final wd = h['weekdays'] is Map ? h['weekdays'] as Map : const {};
    final we = h['weekends'] is Map ? h['weekends'] as Map : const {};
    _wdOpen = t(wd['open'], '07:00');
    _wdClose = t(wd['close'], '20:00');
    _weOpen = t(we['open'], '07:00');
    _weClose = t(we['close'], '14:00');
    _holidays = h['holidays'] is List ? List.of(h['holidays'] as List) : [];
  }

  Map<String, String> _snapshot() => {
    'home': '$_home',
    'charges': _charges.text.trim(),
    'radius': '$_radius',
    'pins': _pincodes.join('|'),
    'adv': '$_advance',
    'notice': '$_notice',
    'cancel': '$_cancel',
    'hours': '$_wdOpen-$_wdClose-$_weOpen-$_weClose',
  };

  bool get _dirty {
    if (_loading || _error != null || _initial.isEmpty) return false;
    final now = _snapshot();
    return now.keys.any((k) => now[k] != _initial[k]);
  }

  int _mins(String hhmm) {
    final p = hhmm.split(':');
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }

  String? get _chargesError {
    if (!_submitted || !_home) return null;
    final t = _charges.text.trim();
    if (t.isEmpty) return null;
    final n = num.tryParse(t);
    if (n == null || n < 0) return 'Enter an amount.';
    if (n > 5000) return 'That charge looks too high.';
    return null;
  }

  String? get _hoursError {
    if (!_submitted) return null;
    if (_mins(_wdClose) <= _mins(_wdOpen) ||
        _mins(_weClose) <= _mins(_weOpen)) {
      return 'Closing time must be after opening time.';
    }
    return null;
  }

  void _addPincode() {
    final v = _pincodeInput.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(v)) {
      setState(() => _pincodeError = 'A pincode is 6 digits.');
      return;
    }
    setState(() {
      _pincodeError = null;
      if (!_pincodes.contains(v)) _pincodes = [..._pincodes, v];
      _pincodeInput.clear();
    });
  }

  Future<void> _pickTime(String current, ValueChanged<String> onPicked) async {
    final p = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(p[0]) ?? 7,
        minute: int.tryParse(p[1]) ?? 0,
      ),
    );
    if (picked == null || !mounted) return;
    String two(int n) => n.toString().padLeft(2, '0');
    setState(() => onPicked('${two(picked.hour)}:${two(picked.minute)}'));
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (_chargesError != null || _hoursError != null) {
      doctorToast(context, 'Fix the highlighted fields.', error: true);
      return;
    }
    final body = <String, dynamic>{
      'homeCollectionAvailable': _home,
      'homeCollectionCharges': num.tryParse(_charges.text.trim()) ?? 0,
      'homeCollectionRadiusKm': _radius,
      'homeCollectionPincodes': _pincodes,
      'bookingSettings': {
        'advanceBookingDays': _advance,
        'minimumNoticeHours': _notice,
        'cancellationWindowHours': _cancel,
      },
      'operatingHours': {
        'weekdays': {'open': _wdOpen, 'close': _wdClose},
        'weekends': {'open': _weOpen, 'close': _weClose},
        'holidays': _holidays,
      },
    };
    setState(() => _saving = true);
    try {
      await ref.read(labProfileProvider.notifier).save(body);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _initial = _snapshot();
      });
      doctorToast(context, 'Settings saved');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      doctorToast(
        context,
        labError(e, fallback: "Couldn't save your settings."),
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
        appBar: doctorSettingsAppBar('Home collection & booking'),
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
        const AppSectionTitle('Home collection'),
        AppGroup(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 10, 4),
              child: AppSwitchRow(
                label: 'Collect samples at home',
                subtitle: 'A phlebotomist visits the patient',
                icon: LucideIcons.house,
                value: _home,
                margin: EdgeInsets.zero,
                onChanged: (v) => setState(() => _home = v),
              ),
            ),
          ],
        ),
        AnimatedSize(
          duration: AppMotion.medium,
          curve: AppMotion.enter,
          alignment: Alignment.topCenter,
          child: _home
              ? Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: _homeDetails(),
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 24),
        const AppSectionTitle('Booking rules'),
        AppGroup(
          children: [
            _StepperRow(
              icon: LucideIcons.calendarRange,
              label: 'Book ahead',
              hint: 'How far ahead patients can book',
              value: _advance,
              unit: (v) => v == 1 ? 'day' : 'days',
              min: 1,
              max: 60,
              step: _advance >= 14 ? 7 : 1,
              onChanged: (v) => setState(() => _advance = v),
            ),
            const AppHairline(),
            _StepperRow(
              icon: LucideIcons.timer,
              label: 'Minimum notice',
              hint: 'Latest a patient can book before a slot',
              value: _notice,
              unit: (v) => v == 1 ? 'hour' : 'hours',
              min: 0,
              max: 48,
              onChanged: (v) => setState(() => _notice = v),
            ),
            const AppHairline(),
            _StepperRow(
              icon: LucideIcons.calendarX,
              label: 'Cancellation closes',
              hint: 'How long before a slot patients can still cancel',
              value: _cancel,
              unit: (v) => v == 1 ? 'hour' : 'hours',
              min: 0,
              max: 48,
              onChanged: (v) => setState(() => _cancel = v),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const AppSectionTitle('Opening hours'),
        AppGroup(
          children: [
            _hoursRow(
              'Monday to Saturday',
              _wdOpen,
              _wdClose,
              (v) => _wdOpen = v,
              (v) => _wdClose = v,
            ),
            const AppHairline(),
            _hoursRow(
              'Sunday',
              _weOpen,
              _weClose,
              (v) => _weOpen = v,
              (v) => _weClose = v,
            ),
          ],
        ),
        if (_hoursError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _hoursError!,
              style: AppType.sans(
                fontSize: AppType.caption,
                color: AppColors.error,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Shown to patients on your lab page. Bookable times come from your '
          'collection slots.',
          style: AppType.sans(
            fontSize: AppType.caption,
            height: 1.45,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }

  Widget _homeDetails() {
    final accent = ModuleAccent.of(context).color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                label: 'Collection charge',
                controller: _charges,
                icon: LucideIcons.indianRupee,
                isNum: true,
                dense: true,
                hint: '0 for free',
                errorText: _chargesError,
                margin: EdgeInsets.zero,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^\d{0,5}(\.\d{0,2})?'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 14),
        AppGroup(
          children: [
            _StepperRow(
              icon: LucideIcons.mapPinned,
              label: 'Service radius',
              hint: 'How far your phlebotomists travel',
              value: _radius,
              unit: (_) => 'km',
              min: 1,
              max: 50,
              onChanged: (v) => setState(() => _radius = v),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Serviceable pincodes',
          style: AppType.sans(
            fontSize: AppType.small,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _pincodes.isEmpty
              ? 'Leave empty to accept any pincode within your radius.'
              : 'Only these pincodes can book home collection.',
          style: AppType.sans(
            fontSize: AppType.caption,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                label: '',
                controller: _pincodeInput,
                icon: LucideIcons.mapPin,
                hint: 'Add a pincode',
                isNum: true,
                dense: true,
                errorText: _pincodeError,
                margin: EdgeInsets.zero,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addPincode(),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AppButton(
              label: 'Add',
              compact: true,
              fullWidth: false,
              onPressed: _addPincode,
            ),
          ],
        ),
        if (_pincodes.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in _pincodes)
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
                  decoration: BoxDecoration(
                    color: ModuleAccent.of(context).veryLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        p,
                        style: AppType.number(
                          fontSize: AppType.small,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                      InkResponse(
                        radius: 14,
                        onTap: () => setState(
                          () => _pincodes = _pincodes
                              .where((x) => x != p)
                              .toList(),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Icon(LucideIcons.x, size: 13, color: accent),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _hoursRow(
    String label,
    String open,
    String close,
    ValueChanged<String> setOpen,
    ValueChanged<String> setClose,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppType.sans(
              fontSize: AppType.body,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        _timeChip(open, () => _pickTime(open, setOpen)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            'to',
            style: AppType.sans(
              fontSize: AppType.caption,
              color: AppColors.textTertiary,
            ),
          ),
        ),
        _timeChip(close, () => _pickTime(close, setClose)),
      ],
    ),
  );

  Widget _timeChip(String hhmm, VoidCallback onTap) {
    final p = hhmm.split(':');
    final label = timeLabel(
      DateTime(2000, 1, 1, int.tryParse(p[0]) ?? 0, int.tryParse(p[1]) ?? 0),
    );
    return AppPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: AppType.number(
            fontSize: AppType.small,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// A setting with − value + on the right.
class _StepperRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final int value;
  final String Function(int) unit;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  const _StepperRow({
    required this.icon,
    required this.label,
    required this.hint,
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textHeading),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppType.sans(
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  hint,
                  maxLines: 2,
                  style: AppType.sans(
                    fontSize: AppType.caption,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _button(
            LucideIcons.minus,
            value > min
                ? () => onChanged((value - step).clamp(min, max))
                : null,
          ),
          SizedBox(
            width: 62,
            child: Column(
              children: [
                Text(
                  '$value',
                  style: AppType.number(
                    fontSize: AppType.title,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textStrong,
                  ),
                ),
                Text(
                  unit(value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.sans(
                    fontSize: AppType.micro,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          _button(
            LucideIcons.plus,
            value < max
                ? () => onChanged((value + step).clamp(min, max))
                : null,
          ),
        ],
      ),
    );
  }

  Widget _button(IconData icon, VoidCallback? onTap) => InkResponse(
    radius: 20,
    onTap: onTap,
    child: Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(
        icon,
        size: 15,
        color: onTap == null ? AppColors.textDisabled : AppColors.textPrimary,
      ),
    ),
  );
}
