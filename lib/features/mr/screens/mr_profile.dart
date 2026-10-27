import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/ui/app_ui.dart';
import '../../auth/providers/auth_provider.dart';
import '../../pharmacy/providers/pharmacy_nav_provider.dart';
import '../providers/mr_provider.dart';
import '../widgets/mr_manage.dart';
import '../widgets/mr_ui.dart';
import 'mr_accounts.dart';

/// Who the rep is in the field force and how to reach their manager, this
/// month's attendance, their territories, the samples and gifts they carry,
/// the e-detailing library, and account settings. Designation, HQ and
/// territories are set by the manager; the rep can fix their name and
/// change their password here.
class MrProfile extends ConsumerStatefulWidget {
  const MrProfile({super.key});

  @override
  ConsumerState<MrProfile> createState() => _MrProfileState();
}

class _MrProfileState extends ConsumerState<MrProfile> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(mrProvider.notifier).ensureLoaded());
  }

  void _openLeave() {
    ref.read(mrPlanSectionProvider.notifier).state = 1;
    ref.read(pharmacyTabRequestProvider.notifier).state = MrTab.plan;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(mrProvider);
    final accent = ModuleAccent.of(context);
    final p = s.profile;
    final user = mapOf(p['userId']);
    final manager = mapOf(p['managerId']);
    final managerUser = mapOf(manager['userId']);
    final territories = listOf(p['territoryIds']).isNotEmpty ? listOf(p['territoryIds']) : listOf(mapOf(s.dashboard['profile'])['territories']);
    final mine = s.sampleBalances.where((b) => s.isMine(b['profileId']) && ((b['balance'] as num?) ?? 0) != 0).toList();
    final month = monthKey(DateTime.now());
    final thisMonth = s.attendance.where((a) => s.isMine(a['profileId']) && '${a['dateKey']}'.startsWith(month)).toList();
    final worked = thisMonth.fold<num>(0, (a, r) => a + (r['status'] == 'present' ? 1 : r['status'] == 'half_day' ? 0.5 : 0));
    final leave = thisMonth.where((a) => a['status'] == 'leave').length;
    final pendingLeave = s.leaves.where((l) => s.isMine(l['profileId']) && l['status'] == 'pending').length;
    final details = [
      (LucideIcons.building2, 'Headquarters', p['headquarters']),
      (LucideIcons.layers, 'Division', p['division']),
      (LucideIcons.pill, 'Product line', p['productLine']),
      (LucideIcons.map, 'Zone', [p['zone'], p['state']].where((e) => e != null && '$e'.isNotEmpty).join(', ')),
      (LucideIcons.calendarDays, 'Joined', mrDate(p['dateOfJoining']) == null ? null : DateFormat('d MMM y').format(mrDate(p['dateOfJoining'])!)),
    ].where((d) => d.$3 != null && '${d.$3}'.isNotEmpty).toList();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: accent.color,
          onRefresh: () => ref.read(mrProvider.notifier).loadAll(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
            children: [
              // ── Identity ──
              AppEntrance(
                child: AppCard(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          MrAvatar(name: s.name, size: 60),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.name, style: AppType.sans(fontSize: AppType.figure, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
                                const SizedBox(height: 2),
                                Text(_designationName(s.designation), style: AppType.sans(fontSize: AppType.small, fontWeight: FontWeight.w600, color: accent.color)),
                                if ('${p['employeeCode'] ?? ''}'.isNotEmpty)
                                  Text('Employee code ${p['employeeCode']}', style: AppType.sans(fontSize: AppType.caption, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Edit name',
                            onPressed: () => showAppSheet<void>(context, builder: (_) => _NameSheet(initial: s.name)),
                            icon: Icon(LucideIcons.pencil, size: 18, color: accent.color),
                          ),
                        ],
                      ),
                      if ('${user['phone'] ?? ''}'.isNotEmpty || '${user['email'] ?? ''}'.isNotEmpty) ...[
                        const Divider(height: 26),
                        if ('${user['phone'] ?? ''}'.isNotEmpty) _InfoRow(icon: LucideIcons.phone, text: '${user['phone']}'),
                        if ('${user['email'] ?? ''}'.isNotEmpty) _InfoRow(icon: LucideIcons.mail, text: '${user['email']}'),
                        Text('You sign in with these. Ask your admin to change them.', style: AppType.sans(fontSize: AppType.caption, color: AppColors.textTertiary)),
                      ],
                    ],
                  ),
                ),
              ),

              // ── Manager ──
              if (manager.isNotEmpty) ...[
                const SizedBox(height: 12),
                AppCard(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      MrAvatar(name: repName(manager), size: 42),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Reports to', style: AppType.sans(fontSize: AppType.caption, color: AppColors.textSecondary)),
                            Text(repName(manager), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w700, color: AppColors.textStrong)),
                            Text(
                              [_designationName('${manager['designation'] ?? ''}'), manager['headquarters']].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
                              style: AppType.sans(fontSize: AppType.caption, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      if ('${managerUser['phone'] ?? ''}'.isNotEmpty) ...[
                        _RoundAction(icon: LucideIcons.messageCircle, tooltip: 'WhatsApp', onTap: () => launchUrl(Uri.parse('https://wa.me/91${'${managerUser['phone']}'.replaceAll(RegExp(r'\D'), '')}'), mode: LaunchMode.externalApplication)),
                        const SizedBox(width: 8),
                        _RoundAction(icon: LucideIcons.phone, tooltip: 'Call', onTap: () => launchUrl(Uri.parse('tel:${managerUser['phone']}'))),
                      ],
                    ],
                  ),
                ),
              ],

              // ── This month ──
              const SizedBox(height: 22),
              AppSectionTitle('This month · ${DateFormat('MMMM').format(DateTime.now())}'),
              Row(
                children: [
                  Expanded(
                    child: _TapTile(
                      onTap: () => showAppSheet<void>(context, builder: (_) => const _AttendanceSheet()),
                      child: AppMetricTile(label: 'Days worked', value: _num(worked), icon: LucideIcons.calendarCheck, color: accent.color, compact: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _TapTile(
                      onTap: _openLeave,
                      child: AppMetricTile(
                        label: pendingLeave > 0 ? 'Leave · $pendingLeave pending' : 'Leave',
                        value: '$leave',
                        icon: LucideIcons.palmtree,
                        color: AppColors.warning,
                        compact: true,
                      ),
                    ),
                  ),
                ],
              ),

              // ── Work details ──
              if (details.isNotEmpty) ...[
                const SizedBox(height: 22),
                const AppSectionTitle('Work details'),
                AppCard(
                  margin: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (icon, label, value) in details)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Icon(icon, size: 16, color: accent.color),
                              const SizedBox(width: 10),
                              SizedBox(width: 100, child: Text(label, style: AppType.sans(fontSize: AppType.small, color: AppColors.textSecondary))),
                              Expanded(child: Text('$value', style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w600, color: AppColors.textStrong))),
                            ],
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text('Set by your manager.', style: AppType.sans(fontSize: AppType.caption, color: AppColors.textTertiary)),
                    ],
                  ),
                ),
              ],

              // ── Territories ──
              if (territories.isNotEmpty || canManageTerritories(s)) ...[
                const SizedBox(height: 22),
                AppSectionTitle(
                  'Territories · ${territories.length}',
                  action: canManageTerritories(s) ? 'New' : null,
                  onAction: canManageTerritories(s) ? () => editTerritory(context) : null,
                ),
                for (final t in territories)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(12),
                      onTap: () => showAppSheet<void>(context, builder: (_) => _TerritorySheet(territory: t)),
                      child: Row(
                        children: [
                          AppIconBadge(icon: LucideIcons.mapPinned, color: accent.color),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${t['name'] ?? t['code'] ?? ''}', style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w700, color: AppColors.textStrong)),
                                Text(
                                  [t['code'], t['city'], '${_customersIn(s, t)} customer${_customersIn(s, t) == 1 ? '' : 's'}'].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
                                  style: AppType.sans(fontSize: AppType.caption, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          Icon(LucideIcons.chevronRight, size: 18, color: AppColors.textTertiary),
                        ],
                      ),
                    ),
                  ),
              ],

              // ── Samples & gifts ──
              const SizedBox(height: 22),
              const AppSectionTitle('Samples & gifts in hand'),
              if (mine.isEmpty)
                const AppEmptyState(icon: LucideIcons.package, text: 'No stock issued to you yet. Your manager issues samples and gifts.')
              else
                AppCard(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Column(
                    children: [
                      for (final (i, b) in mine.indexed) ...[
                        if (i > 0) const Divider(height: 1, indent: 12, endIndent: 12),
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => showAppSheet<void>(context, builder: (_) => _LedgerSheet(item: b)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            child: Row(
                              children: [
                                Icon(b['itemType'] == 'gift' ? LucideIcons.gift : LucideIcons.package, size: 17, color: accent.color),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '${b['productName']}${'${b['batchNumber'] ?? ''}'.isEmpty ? '' : ' · ${b['batchNumber']}'}',
                                    style: AppType.sans(fontSize: AppType.body, color: AppColors.textStrong),
                                  ),
                                ),
                                if (((b['balance'] as num?) ?? 0) <= 5)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Text('Low', style: AppType.sans(fontSize: AppType.caption, fontWeight: FontWeight.w700, color: AppColors.warning)),
                                  ),
                                Text('${b['balance']}', style: AppType.sans(fontSize: AppType.title, fontWeight: FontWeight.w800, color: ((b['balance'] as num?) ?? 0) <= 5 ? AppColors.warning : AppColors.textStrong)),
                                const SizedBox(width: 6),
                                Icon(LucideIcons.chevronRight, size: 16, color: AppColors.textTertiary),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              // ── E-detailing ──
              if (s.detailing.isNotEmpty || canPublishDetailing(s)) ...[
                const SizedBox(height: 22),
                AppSectionTitle(
                  'E-detailing · ${s.detailing.length}',
                  action: canPublishDetailing(s) ? 'Add' : null,
                  onAction: canPublishDetailing(s) ? () => editDetailing(context) : null,
                ),
                for (final d in s.detailing)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(12),
                      onTap: '${d['url'] ?? ''}'.startsWith('http') ? () => launchUrl(Uri.parse('${d['url']}'), mode: LaunchMode.externalApplication) : null,
                      child: Row(
                        children: [
                          AppIconBadge(
                            icon: switch ('${d['contentType']}') {
                              'video' => LucideIcons.circlePlay,
                              'pdf' => LucideIcons.fileText,
                              'image' => LucideIcons.image,
                              'presentation' => LucideIcons.presentation,
                              _ => LucideIcons.link,
                            },
                            color: accent.color,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${d['title'] ?? ''}', style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w700, color: AppColors.textStrong)),
                                if ('${d['productName'] ?? ''}'.isNotEmpty)
                                  Text('${d['productName']}', style: AppType.sans(fontSize: AppType.caption, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          if (canPublishDetailing(s))
                            IconButton(
                              tooltip: 'Edit',
                              onPressed: () => editDetailing(context, content: d),
                              icon: Icon(LucideIcons.pencil, size: 16, color: accent.color),
                            )
                          else
                            Icon(LucideIcons.externalLink, size: 16, color: AppColors.textTertiary),
                        ],
                      ),
                    ),
                  ),
              ],

              // ── Account ──
              const SizedBox(height: 22),
              const AppSectionTitle('Account'),
              AppCard(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Column(
                  children: [
                    if (s.isManager) ...[
                      _MenuRow(
                        icon: LucideIcons.contact,
                        label: 'Customers',
                        onTap: () => Navigator.of(context).push(AppPageRoute(builder: (_) => const MrAccountsScreen())),
                      ),
                      const Divider(height: 1, indent: 12, endIndent: 12),
                    ],
                    _MenuRow(
                      icon: LucideIcons.keyRound,
                      label: 'Change password',
                      onTap: () => showAppSheet<void>(context, builder: (_) => const _PasswordSheet()),
                    ),
                    const Divider(height: 1, indent: 12, endIndent: 12),
                    _MenuRow(
                      icon: LucideIcons.logOut,
                      label: 'Sign out',
                      color: AppColors.error,
                      onTap: () async {
                        final ok = await AppModal.show<bool>(
                          context,
                          title: 'Sign out?',
                          icon: LucideIcons.logOut,
                          content: const SizedBox.shrink(),
                          actions: [
                            AppSecondaryButton(label: 'Cancel', onPressed: () => Navigator.pop(context, false)),
                            AppButton(label: 'Sign out', onPressed: () => Navigator.pop(context, true)),
                          ],
                        );
                        if (ok == true) await ref.read(authProvider.notifier).logout();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static int _customersIn(MrState s, Map<String, dynamic> t) =>
      s.accounts.where((a) => a['isActive'] != false && idOf(a['territoryId']) == idOf(t)).length;
}

String _num(num n) => n == n.roundToDouble() ? '${n.toInt()}' : '$n';

String _designationName(String d) => switch (d.toUpperCase()) {
  'MR' => 'Medical representative',
  'ABM' => 'Area business manager',
  'RBM' => 'Regional business manager',
  'ZSM' => 'Zonal sales manager',
  _ => d,
};

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Icon(icon, size: 15, color: AppColors.textTertiary),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: AppType.sans(fontSize: AppType.body, color: AppColors.textPrimary))),
        Icon(LucideIcons.lock, size: 13, color: AppColors.textTertiary),
      ],
    ),
  );
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _RoundAction({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    return Tooltip(
      message: tooltip,
      child: AppPressable(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: accent.veryLight, shape: BoxShape.circle),
          child: Icon(icon, size: 17, color: accent.color),
        ),
      ),
    );
  }
}

class _TapTile extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  const _TapTile({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) => AppPressable(onTap: onTap, child: child);
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _MenuRow({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? ModuleAccent.of(context).color),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w600, color: color ?? AppColors.textStrong))),
          if (color == null) Icon(LucideIcons.chevronRight, size: 16, color: AppColors.textTertiary),
        ],
      ),
    ),
  );
}

// ─────────────────────────── Sheets ───────────────────────────

class _NameSheet extends ConsumerStatefulWidget {
  final String initial;
  const _NameSheet({required this.initial});

  @override
  ConsumerState<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends ConsumerState<_NameSheet> {
  late final _name = TextEditingController(text: widget.initial);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Enter your full name');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(mrProvider.notifier).updateName(_name.text);
      if (!mounted) return;
      Navigator.pop(context);
      mrToast(context, 'Name updated');
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => MrSheetBody(
    children: [
      const MrSheetTitle('Your name', subtitle: 'As it should appear to your manager and customers'),
      AppTextField(label: 'Full name', controller: _name, required: true, textCapitalization: TextCapitalization.words),
      if (_error != null)
        Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: AppType.sans(fontSize: AppType.small, color: AppColors.error))),
      AppButton(label: 'Save', icon: LucideIcons.check, loading: _busy, onPressed: _save),
    ],
  );
}

class _PasswordSheet extends ConsumerStatefulWidget {
  const _PasswordSheet();

  @override
  ConsumerState<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends ConsumerState<_PasswordSheet> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_current, _next, _again]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final err = _current.text.isEmpty
        ? 'Enter your current password'
        : _next.text.length < 6
        ? 'The new password needs at least 6 characters'
        : _next.text != _again.text
        ? 'The new passwords don’t match'
        : null;
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(mrProvider.notifier).changePassword(_current.text, _next.text);
      if (!mounted) return;
      Navigator.pop(context);
      mrToast(context, 'Password changed');
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => MrSheetBody(
    children: [
      const MrSheetTitle('Change password'),
      AppTextField(label: 'Current password', controller: _current, obscureText: true),
      AppTextField(label: 'New password', controller: _next, obscureText: true, hint: 'At least 6 characters'),
      AppTextField(label: 'New password again', controller: _again, obscureText: true),
      if (_error != null)
        Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: AppType.sans(fontSize: AppType.small, color: AppColors.error))),
      AppButton(label: 'Change password', icon: LucideIcons.keyRound, loading: _busy, onPressed: _save),
    ],
  );
}

/// This month day by day: when the rep started and ended, and the kind of day.
class _AttendanceSheet extends ConsumerWidget {
  const _AttendanceSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(mrProvider);
    final accent = ModuleAccent.of(context);
    final month = monthKey(DateTime.now());
    final rows = s.attendance.where((a) => s.isMine(a['profileId']) && '${a['dateKey']}'.startsWith(month)).toList()
      ..sort((a, b) => '${b['dateKey']}'.compareTo('${a['dateKey']}'));
    return MrSheetBody(
      children: [
        MrSheetTitle('Attendance', subtitle: DateFormat('MMMM y').format(DateTime.now())),
        if (rows.isEmpty)
          Text('No days logged yet this month. Start your day from Today.', style: AppType.sans(fontSize: AppType.small, color: AppColors.textSecondary))
        else
          for (final r in rows) ...[
            Builder(
              builder: (_) {
                final day = DateTime.tryParse('${r['dateKey']}');
                final inAt = mrDate(mapOf(r['punchIn'])['at']);
                final outAt = mrDate(mapOf(r['punchOut'])['at']);
                final status = '${r['status']}';
                final (label, color) = switch (status) {
                  'leave' => ('Leave', AppColors.warning),
                  'half_day' => ('Half day', AppColors.warning),
                  'absent' => ('Absent', AppColors.error),
                  _ => (workTypes[r['workType']]?.$1 ?? 'Field work', accent.color),
                };
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 44,
                        child: Column(
                          children: [
                            Text(day == null ? '' : DateFormat('d').format(day), style: AppType.sans(fontSize: AppType.title, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
                            Text(day == null ? '' : DateFormat('EEE').format(day), style: AppType.sans(fontSize: AppType.caption, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label, style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w700, color: color)),
                            if (inAt != null)
                              Text(
                                outAt == null ? 'Started ${timeLabel(inAt)} · not ended' : '${timeLabel(inAt)} – ${timeLabel(outAt)} · ${durationLabel(outAt.difference(inAt))}',
                                style: AppType.sans(fontSize: AppType.caption, color: AppColors.textSecondary),
                              )
                            else if ('${r['notes'] ?? ''}'.isNotEmpty)
                              Text('${r['notes']}', style: AppType.sans(fontSize: AppType.caption, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const Divider(height: 1),
          ],
      ],
    );
  }
}

class _TerritorySheet extends ConsumerWidget {
  final Map<String, dynamic> territory;
  const _TerritorySheet({required this.territory});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(mrProvider);
    final t = territory;
    final accounts = s.accounts.where((a) => a['isActive'] != false && idOf(a['territoryId']) == idOf(t)).toList();
    final byType = <String, int>{};
    for (final a in accounts) {
      byType['${a['type']}'] = (byType['${a['type']}'] ?? 0) + 1;
    }
    final pincodes = (t['pincodes'] is List ? t['pincodes'] as List : const []).map((e) => '$e').toList();
    return MrSheetBody(
      children: [
        MrSheetTitle('${t['name'] ?? t['code'] ?? 'Territory'}', subtitle: [t['code'], t['headquarters'], t['city'], t['state']].where((e) => e != null && '$e'.isNotEmpty).toSet().join(' · ')),
        Row(
          children: [
            for (final (type, label) in const [('doctor', 'Doctors'), ('chemist', 'Chemists'), ('stockist', 'Stockists')]) ...[
              Expanded(child: AppMetricTile(label: label, value: '${byType[type] ?? 0}', icon: accountKind(type).icon, color: ModuleAccent.of(context).color, compact: true)),
              if (type != 'stockist') const SizedBox(width: 8),
            ],
          ],
        ),
        if (pincodes.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Pincodes covered', style: AppType.sans(fontSize: AppType.small, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final pin in pincodes) AppStatusPill(text: pin, color: AppColors.textPrimary, background: AppColors.panel)],
          ),
        ],
        if (canManageTerritories(s)) ...[
          const SizedBox(height: 16),
          AppSecondaryButton(
            label: 'Edit territory',
            icon: LucideIcons.pencil,
            onPressed: () {
              Navigator.pop(context);
              editTerritory(context, territory: t);
            },
          ),
        ],
        const SizedBox(height: 8),
        AppSecondaryButton(
          label: 'See customers',
          icon: LucideIcons.contact,
          onPressed: () {
            Navigator.pop(context);
            if (s.isManager) {
              Navigator.of(context).push(AppPageRoute(builder: (_) => const MrAccountsScreen()));
            } else {
              ref.read(pharmacyTabRequestProvider.notifier).state = MrTab.team;
            }
          },
        ),
      ],
    );
  }
}

/// Every movement of one sample or gift: issued by the manager, given out on
/// calls, returned or adjusted.
class _LedgerSheet extends ConsumerWidget {
  final Map<String, dynamic> item;
  const _LedgerSheet({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(mrProvider);
    final rows = s.sampleTransactions.where((r) =>
        s.isMine(r['profileId']) &&
        r['productName'] == item['productName'] &&
        (r['itemType'] ?? 'sample') == (item['itemType'] ?? 'sample') &&
        '${r['batchNumber'] ?? ''}' == '${item['batchNumber'] ?? ''}').toList();
    return MrSheetBody(
      children: [
        MrSheetTitle('${item['productName']}', subtitle: '${item['balance']} in hand${'${item['batchNumber'] ?? ''}'.isEmpty ? '' : ' · batch ${item['batchNumber']}'}'),
        if (rows.isEmpty)
          Text('No movements recorded yet.', style: AppType.sans(fontSize: AppType.small, color: AppColors.textSecondary))
        else
          for (final r in rows) ...[
            Builder(
              builder: (_) {
                final type = '${r['transactionType']}';
                final out = type == 'consume' || type == 'return' || (type == 'adjustment' && r['adjustmentDirection'] == 'out');
                final label = switch (type) {
                  'issue' => 'Issued to you',
                  'consume' => mapOf(r['accountId'])['name'] != null ? 'Given to ${mapOf(r['accountId'])['name']}' : 'Given on a call',
                  'return' => 'Returned',
                  _ => 'Adjusted',
                };
                final when = mrDate(r['transactionDate'] ?? r['createdAt']);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w600, color: AppColors.textStrong)),
                            if (when != null) Text(DateFormat('d MMM y').format(when), style: AppType.sans(fontSize: AppType.caption, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      Text(
                        '${out ? '−' : '+'}${r['quantity']}',
                        style: AppType.sans(fontSize: AppType.title, fontWeight: FontWeight.w800, color: out ? AppColors.textSecondary : AppColors.success),
                      ),
                    ],
                  ),
                );
              },
            ),
            const Divider(height: 1),
          ],
      ],
    );
  }
}
