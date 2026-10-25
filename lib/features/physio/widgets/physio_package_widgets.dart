import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/doctor_ui.dart';

// A treatment package: N sessions for one price, valid for some days, at
// one visit type (or any). Shape of PhysioPackage on the server.

const kPackageVisitTypes = ['any', 'clinic', 'home', 'video'];

String packageVisitLabel(String type) => switch (type) {
  'clinic' => 'Clinic',
  'home' => 'Home visit',
  'video' => 'Video',
  _ => 'Any visit type',
};

IconData packageVisitIcon(String type) => switch (type) {
  'clinic' => LucideIcons.building2,
  'home' => LucideIcons.house,
  'video' => LucideIcons.video,
  _ => LucideIcons.layers,
};

int packageSessions(Map<String, dynamic> p) =>
    int.tryParse('${p['sessionCount'] ?? ''}') ?? 0;

num packagePrice(Map<String, dynamic> p) =>
    num.tryParse('${p['price'] ?? ''}') ?? 0;

/// Rounded to the rupee; null when there are no sessions.
num? packagePerSession(num price, int sessions) =>
    sessions > 0 ? (price / sessions).round() : null;

String packageValidityLabel(int days) {
  if (days <= 0) return '';
  if (days % 365 == 0) {
    final y = days ~/ 365;
    return '$y ${y == 1 ? 'year' : 'years'}';
  }
  if (days % 30 == 0) {
    final m = days ~/ 30;
    return '$m ${m == 1 ? 'month' : 'months'}';
  }
  return '$days days';
}

/// One package in the list. Tapping opens the editor.
class PhysioPackageCard extends StatelessWidget {
  final Map<String, dynamic> package;
  final VoidCallback onTap;

  const PhysioPackageCard({
    super.key,
    required this.package,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = package;
    final active = p['isActive'] != false;
    final name = '${p['name'] ?? ''}'.trim();
    final sessions = packageSessions(p);
    final price = packagePrice(p);
    final per = packagePerSession(price, sessions);
    final duration = int.tryParse('${p['sessionDurationMin'] ?? ''}') ?? 0;
    final validity = int.tryParse('${p['validityDays'] ?? ''}') ?? 0;
    final type = '${p['visitType'] ?? 'any'}';
    final description = '${p['description'] ?? ''}'.trim();
    final accent = ModuleAccent.of(context).color;
    final ink = active ? AppColors.textStrong : AppColors.textSecondary;

    return AppPressable(
      scale: 0.985,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? 'Untitled package' : name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.sans(
                          fontSize: AppType.title,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          '$sessions ${sessions == 1 ? 'session' : 'sessions'}',
                          if (duration > 0) '$duration min each',
                        ].join(' · '),
                        style: AppType.sans(
                          fontSize: AppType.caption,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      appRupees(price),
                      style: AppType.number(
                        fontSize: AppType.title,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                    if (per != null)
                      Text(
                        '${appRupees(per)} / session',
                        style: AppType.sans(
                          fontSize: AppType.caption,
                          color: AppColors.textTertiary,
                        ),
                      ),
                  ],
                ),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.sans(
                  fontSize: AppType.small,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _meta(packageVisitIcon(type), packageVisitLabel(type)),
                if (validity > 0)
                  _meta(
                    LucideIcons.calendarClock,
                    'Valid ${packageValidityLabel(validity)}',
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: active ? accent : AppColors.textTertiary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      active ? 'Active' : 'Archived',
                      style: AppType.sans(
                        fontSize: AppType.caption,
                        fontWeight: FontWeight.w600,
                        color: active ? accent : AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: AppColors.textTertiary),
      const SizedBox(width: 4),
      Text(
        text,
        style: AppType.sans(
          fontSize: AppType.caption,
          color: AppColors.textSecondary,
        ),
      ),
    ],
  );
}

/// Opens the package editor. [onSave] does the request; the sheet stays
/// open showing the error if it throws, and closes with true on success.
/// [onArchiveToggle] (existing packages only) archives or restores; it
/// resolves to false when the physio backs out, keeping the sheet open.
Future<bool?> showPhysioPackageSheet(
  BuildContext context, {
  Map<String, dynamic>? initial,
  int defaultDuration = 45,
  required Future<void> Function(Map<String, dynamic> body) onSave,
  Future<bool> Function()? onArchiveToggle,
}) => showAppSheet<bool>(
  context,
  builder: (_) => PhysioPackageSheet(
    initial: initial,
    defaultDuration: defaultDuration,
    onSave: onSave,
    onArchiveToggle: onArchiveToggle,
  ),
);

class PhysioPackageSheet extends StatefulWidget {
  final Map<String, dynamic>? initial;
  final int defaultDuration;
  final Future<void> Function(Map<String, dynamic> body) onSave;
  final Future<bool> Function()? onArchiveToggle;

  const PhysioPackageSheet({
    super.key,
    this.initial,
    this.defaultDuration = 45,
    required this.onSave,
    this.onArchiveToggle,
  });

  @override
  State<PhysioPackageSheet> createState() => _PhysioPackageSheetState();
}

class _PhysioPackageSheetState extends State<PhysioPackageSheet> {
  late final Map<String, dynamic> _p = widget.initial ?? const {};
  late final _name = TextEditingController(text: '${_p['name'] ?? ''}');
  late final _sessions = TextEditingController(
    text: _p.isEmpty ? '' : '${packageSessions(_p)}',
  );
  late final _price = TextEditingController(
    text: _p.isEmpty ? '' : _num(_p['price']),
  );
  late final _duration = TextEditingController(
    text: _p.isEmpty
        ? '${widget.defaultDuration}'
        : _num(_p['sessionDurationMin']),
  );
  late final _validity = TextEditingController(
    text: _p.isEmpty ? '90' : _num(_p['validityDays']),
  );
  late final _description = TextEditingController(
    text: '${_p['description'] ?? ''}',
  );
  late String _type = kPackageVisitTypes.contains('${_p['visitType']}')
      ? '${_p['visitType']}'
      : 'any';

  late final _all = [
    _name,
    _sessions,
    _price,
    _duration,
    _validity,
    _description,
  ];

  bool _submitted = false;
  bool _saving = false;
  bool _archiving = false;
  String? _error;

  bool get _isNew => _p.isEmpty;
  bool get _active => _p['isActive'] != false;

  static String _num(dynamic v) {
    final n = num.tryParse('${v ?? ''}');
    if (n == null) return '';
    return n == n.roundToDouble() ? n.toInt().toString() : '$n';
  }

  @override
  void initState() {
    super.initState();
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

  // ─────────────────────────── Validation ──────────────────────────

  String? _err(String key) {
    if (!_submitted) return null;
    switch (key) {
      case 'name':
        return _name.text.trim().length < 2 ? 'Name the package.' : null;
      case 'sessions':
        final n = int.tryParse(_sessions.text.trim());
        return n == null || n < 1 || n > 100 ? 'Between 1 and 100.' : null;
      case 'price':
        final n = num.tryParse(_price.text.trim());
        if (n == null) return 'Enter the package price.';
        return n < 0 || n > 1000000 ? 'Enter a valid price.' : null;
      case 'duration':
        if (_duration.text.trim().isEmpty) return null;
        final n = int.tryParse(_duration.text.trim());
        return n == null || n < 5 || n > 480 ? '5 to 480 minutes.' : null;
      case 'validity':
        if (_validity.text.trim().isEmpty) return null;
        final n = int.tryParse(_validity.text.trim());
        return n == null || n < 1 || n > 730 ? '1 to 730 days.' : null;
    }
    return null;
  }

  bool get _valid => const [
    'name',
    'sessions',
    'price',
    'duration',
    'validity',
  ].every((k) => _err(k) == null);

  Future<void> _save() async {
    setState(() {
      _submitted = true;
      _error = null;
    });
    if (!_valid) return;
    final description = _description.text.trim();
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'sessionCount': int.parse(_sessions.text.trim()),
      'price': num.parse(_price.text.trim()),
      'visitType': _type,
      'sessionDurationMin': ?int.tryParse(_duration.text.trim()),
      'validityDays': ?int.tryParse(_validity.text.trim()),
      // An edit may clear the description; a new package just omits it.
      if (description.isNotEmpty || !_isNew) 'description': description,
    };
    setState(() => _saving = true);
    try {
      await widget.onSave(body);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = doctorError(e, fallback: "Couldn't save the package.");
      });
    }
  }

  Future<void> _toggleArchive() async {
    final toggle = widget.onArchiveToggle;
    if (toggle == null) return;
    setState(() {
      _archiving = true;
      _error = null;
    });
    try {
      final done = await toggle();
      if (!mounted) return;
      if (!done) {
        setState(() => _archiving = false);
        return;
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _archiving = false;
        _error = doctorError(
          e,
          fallback: _active
              ? "Couldn't archive the package."
              : "Couldn't restore the package.",
        );
      });
    }
  }

  // ───────────────────────────── Build ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sessions = int.tryParse(_sessions.text.trim()) ?? 0;
    final price = num.tryParse(_price.text.trim());
    final per = price == null ? null : packagePerSession(price, sessions);
    final busy = _saving || _archiving;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isNew ? 'New package' : 'Edit package',
            style: AppType.sans(
              fontSize: AppType.title,
              fontWeight: FontWeight.w700,
              color: AppColors.textStrong,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Patients pay once; sessions are counted off as you see them.',
            style: AppType.sans(
              fontSize: AppType.caption,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Package name',
            controller: _name,
            hint: 'e.g. Knee rehab — 10 sessions',
            required: true,
            dense: true,
            errorText: _err('name'),
            textCapitalization: TextCapitalization.sentences,
            margin: const EdgeInsets.only(bottom: 12),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Sessions',
                  controller: _sessions,
                  icon: LucideIcons.repeat,
                  isNum: true,
                  required: true,
                  dense: true,
                  errorText: _err('sessions'),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  margin: const EdgeInsets.only(bottom: 12),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(
                  label: 'Total price',
                  controller: _price,
                  icon: LucideIcons.indianRupee,
                  isNum: true,
                  required: true,
                  dense: true,
                  errorText: _err('price'),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(7),
                  ],
                  margin: const EdgeInsets.only(bottom: 12),
                ),
              ),
            ],
          ),
          if (per != null && sessions > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Works out to ${appRupees(per)} per session.',
                style: AppType.sans(
                  fontSize: AppType.caption,
                  fontWeight: FontWeight.w600,
                  color: ModuleAccent.of(context).color,
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Minutes per session',
                  controller: _duration,
                  icon: LucideIcons.clock,
                  isNum: true,
                  dense: true,
                  errorText: _err('duration'),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  margin: const EdgeInsets.only(bottom: 12),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(
                  label: 'Valid for (days)',
                  controller: _validity,
                  icon: LucideIcons.calendarClock,
                  isNum: true,
                  dense: true,
                  errorText: _err('validity'),
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  margin: const EdgeInsets.only(bottom: 12),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Visit type',
              style: AppType.sans(
                fontSize: AppType.caption,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Row(
            children: [
              for (final t in kPackageVisitTypes) ...[
                if (t != kPackageVisitTypes.first) const SizedBox(width: 6),
                Expanded(
                  child: AppFilterChip(
                    label: t == 'any'
                        ? 'Any'
                        : t == 'home'
                        ? 'Home'
                        : packageVisitLabel(t),
                    selected: _type == t,
                    block: true,
                    onTap: () => setState(() => _type = t),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          AppTextField(
            label: 'Description',
            controller: _description,
            hint: 'What the package covers (optional)',
            maxLines: 3,
            dense: true,
            textCapitalization: TextCapitalization.sentences,
            margin: const EdgeInsets.only(bottom: 14),
          ),
          if (_error != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(
                    LucideIcons.circleAlert,
                    size: 14,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _error!,
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          AppButton(
            label: _saving
                ? 'Saving…'
                : (_isNew ? 'Create package' : 'Save changes'),
            loading: _saving,
            onPressed: busy ? null : _save,
          ),
          if (!_isNew && widget.onArchiveToggle != null) ...[
            const SizedBox(height: 10),
            AppSecondaryButton(
              label: _archiving
                  ? (_active ? 'Archiving…' : 'Restoring…')
                  : (_active ? 'Archive package' : 'Restore package'),
              icon: _active ? LucideIcons.archive : LucideIcons.archiveRestore,
              color: _active ? AppColors.error : null,
              onPressed: busy ? null : _toggleArchive,
            ),
            const SizedBox(height: 6),
            Text(
              _active
                  ? 'Archived packages are hidden from patients. Courses '
                        'already bought keep running.'
                  : 'Restoring shows the package to patients again.',
              style: AppType.sans(
                fontSize: AppType.caption,
                height: 1.4,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
