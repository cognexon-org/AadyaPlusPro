import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/availability_save_bar.dart';
import '../providers/lab_providers.dart';
import '../widgets/lab_ui.dart';

const _roles = [
  (key: 'phlebotomist', label: 'Phlebotomists', single: 'Phlebotomist'),
  (key: 'technician', label: 'Technicians', single: 'Technician'),
  (key: 'receptionist', label: 'Front desk', single: 'Front desk'),
];

/// The lab's team: who collects samples, who runs them, who's at the desk —
/// with each phlebotomist's collections for today, for assigning fairly.
class PathologyStaffScreen extends ConsumerStatefulWidget {
  const PathologyStaffScreen({super.key});

  @override
  ConsumerState<PathologyStaffScreen> createState() =>
      _PathologyStaffScreenState();
}

class _PathologyStaffScreenState extends ConsumerState<PathologyStaffScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(labStaffProvider.notifier).load();
    });
  }

  Future<void> _refresh() =>
      ref.read(labStaffProvider.notifier).load(silent: true);

  Future<void> _edit([Map<String, dynamic>? member]) async {
    final saved = await showAppSheet<bool>(
      context,
      builder: (_) => _StaffSheet(member: member),
    );
    if (saved == true && mounted) {
      doctorToast(context, member == null ? 'Team member added' : 'Saved');
    }
  }

  Future<void> _toggle(Map<String, dynamic> m) async {
    final active = m['isActive'] != false;
    if (active) {
      final ok = await AppModal.confirm(
        context,
        title: 'Deactivate ${m['name']}?',
        message:
            'They won’t be offered for new collections. Their past work stays '
            'on record, and you can reactivate them later.',
        icon: LucideIcons.userX,
        confirmLabel: 'Deactivate',
      );
      if (!ok || !mounted) return;
    }
    try {
      await ref
          .read(labStaffProvider.notifier)
          .setActive('${m['_id']}', !active);
      if (mounted) doctorToast(context, active ? 'Deactivated' : 'Reactivated');
    } catch (e) {
      if (mounted) doctorToast(context, labError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(labStaffProvider);
    final staff = ref.read(labStaffProvider.notifier).staff;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: doctorSettingsAppBar('Team'),
      floatingActionButton: st.hasLoaded && staff.isNotEmpty
          ? AppFab(
              label: 'Add member',
              icon: LucideIcons.userPlus,
              onPressed: () => _edit(),
            )
          : null,
      body: RefreshIndicator(
        color: ModuleAccent.of(context).color,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
          children: _body(st, staff),
        ),
      ),
    );
  }

  List<Widget> _body(LabResource st, List<Map<String, dynamic>> staff) {
    if (!st.hasLoaded) {
      return st.error != null
          ? [AppErrorBanner(message: st.error!, onRetry: _refresh)]
          : const [AppListSkeleton(count: 4)];
    }
    if (staff.isEmpty) {
      final accent = ModuleAccent.of(context);
      return [
        AppEntrance(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: accent.light,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.users, size: 26, color: accent.color),
                ),
                const SizedBox(height: 14),
                Text(
                  'Add your phlebotomists',
                  style: AppType.sans(
                    fontSize: AppType.heading,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textStrong,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Home collections are assigned to them, and patients see who '
                  'is coming. Add technicians and front desk staff too.',
                  textAlign: TextAlign.center,
                  style: AppType.sans(
                    fontSize: AppType.small,
                    color: AppColors.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                AppButton(
                  label: 'Add a team member',
                  icon: LucideIcons.userPlus,
                  onPressed: () => _edit(),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    var i = 0;
    return [
      if (st.error != null) ...[
        AppErrorBanner(message: st.error!, onRetry: _refresh),
        const SizedBox(height: 12),
      ],
      for (final r in _roles)
        if (staff.any((s) => (s['role'] ?? 'phlebotomist') == r.key)) ...[
          AppSectionTitle(
            '${r.label} · ${staff.where((s) => (s['role'] ?? 'phlebotomist') == r.key && s['isActive'] != false).length}',
          ),
          for (final m in _sorted(staff, r.key))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppEntrance(
                index: (i++).clamp(0, 8),
                child: _StaffRow(
                  member: m,
                  onTap: () => _edit(m),
                  onToggle: () => _toggle(m),
                ),
              ),
            ),
          const SizedBox(height: 8),
        ],
    ];
  }

  List<Map<String, dynamic>> _sorted(
    List<Map<String, dynamic>> staff,
    String role,
  ) => staff.where((s) => (s['role'] ?? 'phlebotomist') == role).toList()
    ..sort((a, b) {
      final x =
          (a['isActive'] == false ? 1 : 0) - (b['isActive'] == false ? 1 : 0);
      return x != 0
          ? x
          : '${a['name']}'.toLowerCase().compareTo(
              '${b['name']}'.toLowerCase(),
            );
    });
}

class _StaffRow extends StatelessWidget {
  final Map<String, dynamic> member;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  const _StaffRow({
    required this.member,
    required this.onTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final m = member;
    final accent = ModuleAccent.of(context);
    final active = m['isActive'] != false;
    final name = '${m['name'] ?? ''}'.trim();
    final initials = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    final phone = '${m['phone'] ?? ''}'.trim();
    final code = '${m['employeeCode'] ?? ''}'.trim();
    final pins =
        (m['servicePincodes'] is List ? m['servicePincodes'] as List : const [])
            .map((e) => '$e')
            .where((e) => e.isNotEmpty)
            .toList();
    final today = int.tryParse('${m['todayAssigned'] ?? 0}') ?? 0;
    final done = int.tryParse('${m['todayCollected'] ?? 0}') ?? 0;
    final phleb = (m['role'] ?? 'phlebotomist') == 'phlebotomist';

    return Opacity(
      opacity: active ? 1 : 0.55,
      child: AppPressable(
        scale: 0.985,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: accent.light,
                child: Text(
                  initials.isEmpty ? '?' : initials,
                  style: AppType.sans(
                    fontSize: AppType.small,
                    fontWeight: FontWeight.w700,
                    color: accent.color,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name.isEmpty ? 'Unnamed' : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.sans(
                              fontSize: AppType.body,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textStrong,
                            ),
                          ),
                        ),
                        if (code.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            code,
                            style: AppType.sans(
                              fontSize: AppType.caption,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                        if (!active) ...[
                          const SizedBox(width: 6),
                          Text(
                            'Inactive',
                            style: AppType.sans(
                              fontSize: AppType.caption,
                              fontWeight: FontWeight.w700,
                              color: AppColors.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (phone.isNotEmpty)
                      Text(
                        phone,
                        style: AppType.sans(
                          fontSize: AppType.caption,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    if (phleb && active) ...[
                      const SizedBox(height: 3),
                      Text(
                        today == 0
                            ? 'No collections today'
                            : '$today collection${today == 1 ? '' : 's'} today · $done done',
                        style: AppType.sans(
                          fontSize: AppType.caption,
                          fontWeight: FontWeight.w600,
                          color: today == 0
                              ? AppColors.textTertiary
                              : accent.color,
                        ),
                      ),
                    ],
                    if (pins.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final p in pins.take(6))
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.bg,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                p,
                                style: AppType.sans(
                                  fontSize: AppType.micro,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          if (pins.length > 6)
                            Text(
                              '+${pins.length - 6}',
                              style: AppType.sans(
                                fontSize: AppType.micro,
                                color: AppColors.textTertiary,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (phone.isNotEmpty && active)
                IconButton(
                  tooltip: 'Call',
                  onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
                  icon: Icon(LucideIcons.phone, size: 17, color: accent.color),
                ),
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: const Icon(
                  LucideIcons.ellipsisVertical,
                  size: 17,
                  color: AppColors.textTertiary,
                ),
                onSelected: (v) => v == 'edit' ? onTap() : onToggle(),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(active ? 'Deactivate' : 'Reactivate'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaffSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic>? member;
  const _StaffSheet({this.member});

  @override
  ConsumerState<_StaffSheet> createState() => _StaffSheetState();
}

class _StaffSheetState extends ConsumerState<_StaffSheet> {
  late final Map<String, dynamic> _m = widget.member ?? const {};
  late final _name = TextEditingController(text: '${_m['name'] ?? ''}');
  late final _phone = TextEditingController(text: '${_m['phone'] ?? ''}');
  late final _email = TextEditingController(text: '${_m['email'] ?? ''}');
  late final _code = TextEditingController(text: '${_m['employeeCode'] ?? ''}');
  late final _pins = TextEditingController(
    text:
        (_m['servicePincodes'] is List
                ? _m['servicePincodes'] as List
                : const [])
            .join(', '),
  );
  late final _notes = TextEditingController(text: '${_m['notes'] ?? ''}');
  late String _role = '${_m['role'] ?? 'phlebotomist'}';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _code, _pins, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty || phone.length < 10) {
      setState(() => _error = 'Name and a 10-digit phone number are needed.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = '${_m['_id'] ?? ''}';
      await ref.read(labStaffProvider.notifier).save({
        'name': name,
        'phone': phone,
        'email': _email.text.trim(),
        'employeeCode': _code.text.trim(),
        'role': _role,
        'servicePincodes': _pins.text
            .split(RegExp(r'[,\s]+'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        'notes': _notes.text.trim(),
      }, id: id.isEmpty ? null : id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = labError(e, fallback: 'Couldn’t save.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.member == null ? 'Add team member' : 'Edit team member',
            style: AppType.sans(
              fontSize: AppType.title,
              fontWeight: FontWeight.w700,
              color: AppColors.textStrong,
            ),
          ),
          const SizedBox(height: 14),
          if (_error != null) ...[
            AppErrorBanner(message: _error!),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              for (final r in _roles) ...[
                Expanded(
                  child: AppFilterChip(
                    label: r.single,
                    selected: _role == r.key,
                    block: true,
                    onTap: () => setState(() => _role = r.key),
                  ),
                ),
                if (r != _roles.last) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 14),
          AppTextField(
            label: 'Name',
            controller: _name,
            required: true,
            textCapitalization: TextCapitalization.words,
          ),
          AppTextField(
            label: 'Phone',
            controller: _phone,
            required: true,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: AppTextField(label: 'Employee code', controller: _code),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppTextField(
                  label: 'Email',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                ),
              ),
            ],
          ),
          if (_role == 'phlebotomist')
            AppTextField(
              label: 'Service pincodes',
              controller: _pins,
              hint: '452001, 452010',
              keyboardType: TextInputType.number,
            ),
          AppTextField(label: 'Notes', controller: _notes, maxLines: 2),
          AppButton(
            label: widget.member == null ? 'Add member' : 'Save',
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}
