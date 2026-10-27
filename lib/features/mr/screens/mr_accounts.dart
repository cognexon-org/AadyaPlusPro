import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/ui/app_ui.dart';
import '../providers/mr_provider.dart';
import '../widgets/mr_manage.dart';
import '../widgets/mr_sheets.dart';
import '../widgets/mr_ui.dart';

/// The rep's customers — doctors, chemists, stockists and hospitals — with
/// how often each was visited this month against how often they should be.
class MrAccountsScreen extends ConsumerStatefulWidget {
  /// Shown as a dashboard tab (no back button) or pushed.
  final bool asTab;
  const MrAccountsScreen({super.key, this.asTab = false});

  @override
  ConsumerState<MrAccountsScreen> createState() => _MrAccountsScreenState();
}

class _MrAccountsScreenState extends ConsumerState<MrAccountsScreen> {
  final _q = TextEditingController();
  String? _type;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(mrProvider.notifier).ensureLoaded());
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(mrProvider);
    final accent = ModuleAccent.of(context);
    final q = _q.text.trim().toLowerCase();
    final visitsBy = <String, int>{};
    for (final v in s.visits) {
      if (const {'completed', 'submitted', 'approved'}.contains(v['status'])) {
        final id = idOf(v['accountId']);
        visitsBy[id] = (visitsBy[id] ?? 0) + 1;
      }
    }
    final list = s.accounts.where((a) {
      if (a['isActive'] == false) return false;
      if (_type != null && a['type'] != _type) return false;
      if (q.isEmpty) return true;
      return [a['name'], a['specialty'], a['organizationName'], mapOf(a['address'])['city']].join(' ').toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => '${a['classification']}'.compareTo('${b['classification']}'));
    final counts = <String, int>{};
    for (final a in s.accounts) {
      counts['${a['type']}'] = (counts['${a['type']}'] ?? 0) + 1;
    }
    final due = list.where((a) => (visitsBy[idOf(a)] ?? 0) < ((a['visitFrequencyPerMonth'] as num?) ?? 1)).length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                if (!widget.asTab)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 4),
                    child: IconButton(tooltip: 'Back', icon: const Icon(LucideIcons.arrowLeft, size: 22), onPressed: () => Navigator.of(context).maybePop()),
                  ),
                Expanded(
                  child: MrHeader(
                    title: 'Customers',
                    subtitle: '${s.accounts.length} in your territory · $due still due a visit',
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: AppSearchField(controller: _q, hint: 'Name, specialty or city', onChanged: (_) => setState(() {})),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final (t, label) in const [(null, 'All'), ('doctor', 'Doctors'), ('chemist', 'Chemists'), ('stockist', 'Stockists'), ('hospital', 'Hospitals')]) ...[
                    AppFilterChip(
                      label: t == null ? '$label · ${s.accounts.length}' : '$label${counts[t] != null ? ' · ${counts[t]}' : ''}',
                      selected: _type == t,
                      onTap: () => setState(() => _type = t),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                color: accent.color,
                onRefresh: () => ref.read(mrProvider.notifier).loadAccounts(),
                child: s.isLoading && !s.hasLoaded
                    ? const AppListSkeleton(count: 6)
                    : list.isEmpty
                    ? ListView(padding: const EdgeInsets.all(16), children: const [AppEmptyState(icon: LucideIcons.contact, text: 'No customers here yet. Add the doctors and chemists you visit.')])
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => AppEntrance(
                          index: i.clamp(0, 8),
                          child: _AccountCard(account: list[i], visits: visitsBy[idOf(list[i])] ?? 0),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: AppFab(label: 'Add customer', icon: LucideIcons.userPlus, onPressed: () => showAppSheet<void>(context, builder: (_) => const _NewAccountSheet())),
    );
  }
}

class _AccountCard extends ConsumerWidget {
  final Map<String, dynamic> account;
  final int visits;
  const _AccountCard({required this.account, required this.visits});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = account;
    final kind = accountKind(a['type']?.toString());
    final accent = ModuleAccent.of(context);
    final freq = ((a['visitFrequencyPerMonth'] as num?) ?? 1).toInt();
    final cls = '${a['classification'] ?? ''}';
    final city = '${mapOf(a['address'])['city'] ?? ''}';
    final phone = '${a['phone'] ?? ''}';
    return AppCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      onTap: () async {
        final action = await showAppSheet<String>(context, builder: (_) => _AccountSheet(accountId: idOf(a)));
        if (!context.mounted) return;
        if (action == 'plan') planCall(context, ref, account: a);
        if (action == 'edit') editAccount(context, a);
        if (action == 'order') newOrder(context, ref, account: a);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MrAvatar(name: '${a['name'] ?? ''}', icon: kind.icon, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text('${a['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.sans(fontSize: AppType.body + 1, fontWeight: FontWeight.w800, color: AppColors.textStrong))),
                        if (isLinked(a)) ...[
                          const SizedBox(width: 5),
                          Tooltip(message: 'On Aadya Plus', child: Icon(LucideIcons.badgeCheck, size: 15, color: accent.color)),
                        ],
                      ],
                    ),
                    Text(
                      [kind.label, a['specialty'], if (city.isNotEmpty) city].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.sans(fontSize: AppType.caption, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (cls.length == 1) AppStatusPill(text: 'Class $cls', color: cls == 'A' ? accent.color : AppColors.textSecondary),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Visits this month against the planned frequency.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$visits of $freq visit${freq == 1 ? '' : 's'} this month',
                      style: AppType.sans(fontSize: AppType.caption, fontWeight: FontWeight.w600, color: visits >= freq ? AppColors.success : AppColors.textPrimary),
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: freq == 0 ? 1 : (visits / freq).clamp(0, 1).toDouble(),
                        minHeight: 5,
                        backgroundColor: accent.veryLight,
                        color: visits >= freq ? AppColors.success : accent.color,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (phone.isNotEmpty)
                IconButton(
                  tooltip: 'Call',
                  onPressed: () => launchUrl(Uri.parse('tel:$phone')),
                  icon: Icon(LucideIcons.phone, size: 18, color: accent.color),
                ),
              if (a['type'] != 'doctor')
                IconButton(
                  tooltip: 'Book order',
                  onPressed: () => newOrder(context, ref, account: a),
                  icon: Icon(LucideIcons.shoppingCart, size: 18, color: accent.color),
                ),
              AppButton(label: 'Plan call', compact: true, fullWidth: false, onPressed: () => planCall(context, ref, account: a)),
            ],
          ),
        ],
      ),
    );
  }
}

class _NewAccountSheet extends ConsumerStatefulWidget {
  const _NewAccountSheet();

  @override
  ConsumerState<_NewAccountSheet> createState() => _NewAccountSheetState();
}

class _NewAccountSheetState extends ConsumerState<_NewAccountSheet> {
  String _type = 'doctor';
  String _class = 'B';
  final _name = TextEditingController();
  final _specialty = TextEditingController();
  final _org = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _line = TextEditingController();
  int _freq = 2;
  bool _here = false;
  Map<String, dynamic>? _linked;
  Map<String, dynamic>? _linkedLocation;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _specialty, _org, _phone, _city, _line]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Enter the name');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      Map<String, dynamic>? location;
      if (_here) {
        final geo = await _location();
        location = {'lat': geo['lat'], 'lng': geo['lng']};
      }
      await ref.read(mrProvider.notifier).createAccount({
        'type': _type,
        'name': _name.text.trim(),
        if (_specialty.text.trim().isNotEmpty) 'specialty': _specialty.text.trim(),
        if (_org.text.trim().isNotEmpty) 'organizationName': _org.text.trim(),
        if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
        'address': {
          if (_line.text.trim().isNotEmpty) 'line1': _line.text.trim(),
          if (_city.text.trim().isNotEmpty) 'city': _city.text.trim(),
        },
        'location': location ?? _linkedLocation,
        if (_linked != null) 'linkedEntity': {'kind': _linked!['kind'], 'refId': _linked!['refId']},
        if (_linked != null && '${_linked!['registrationNumber'] ?? ''}'.isNotEmpty) 'registrationNumber': _linked!['registrationNumber'],
        'classification': _class,
        'visitFrequencyPerMonth': _freq,
      });
      if (!mounted) return;
      Navigator.pop(context);
      mrToast(context, 'Customer added');
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  Future<Map<String, dynamic>> _location() async {
    try {
      return await ref.read(mrProvider.notifier).currentLocation();
    } catch (e) {
      throw MrException('$e');
    }
  }

  Future<void> _find() async {
    final kind = directoryKind(_type);
    if (kind == null) return;
    final r = await findOnAadya(context, kind, initial: _name.text.trim());
    if (r == null || !mounted) return;
    final address = mapOf(r['address']);
    void fill(TextEditingController c, dynamic v) {
      if ('${v ?? ''}'.isNotEmpty) c.text = '$v';
    }
    setState(() {
      _linked = r;
      _linkedLocation = r['location'] is Map ? mapOf(r['location']) : null;
      fill(_name, r['name']);
      fill(_specialty, r['specialty']);
      fill(_org, r['organizationName']);
      fill(_phone, '${r['phone'] ?? ''}'.replaceAll(RegExp(r'\D'), '').characters.takeLast(10).toString());
      fill(_city, address['city']);
      fill(_line, [address['line1'], address['locality']].where((e) => e != null && '$e'.isNotEmpty).join(', '));
    });
  }

  @override
  Widget build(BuildContext context) => MrSheetBody(
    children: [
      const MrSheetTitle('Add a customer'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (t, l) in const [('doctor', 'Doctor'), ('chemist', 'Chemist'), ('stockist', 'Stockist'), ('hospital', 'Hospital')])
            AppFilterChip(
              label: l,
              selected: _type == t,
              onTap: () => setState(() {
                if (_type != t) _linked = null;
                _type = t;
              }),
            ),
        ],
      ),
      const SizedBox(height: 14),
      if (directoryKind(_type) != null)
        AppCard(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(12),
          onTap: _linked == null ? _find : null,
          borderColor: _linked != null ? ModuleAccent.of(context).color.withValues(alpha: 0.35) : null,
          child: Row(
            children: [
              AppIconBadge(icon: _linked == null ? LucideIcons.search : LucideIcons.badgeCheck, color: ModuleAccent.of(context).color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _linked == null ? 'Already on Aadya Plus?' : 'Linked to ${_linked!['name']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w700, color: AppColors.textStrong),
                    ),
                    Text(
                      _linked == null ? 'Find them to fill this in and link the account' : 'Details filled from their account',
                      style: AppType.sans(fontSize: AppType.caption, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (_linked != null)
                GestureDetector(
                  onTap: () => setState(() {
                    _linked = null;
                    _linkedLocation = null;
                  }),
                  child: Icon(LucideIcons.x, size: 18, color: AppColors.textTertiary),
                )
              else
                Icon(LucideIcons.chevronRight, size: 18, color: AppColors.textTertiary),
            ],
          ),
        ),
      AppTextField(label: _type == 'doctor' ? 'Doctor’s name' : 'Name', controller: _name, required: true, textCapitalization: TextCapitalization.words),
      if (_type == 'doctor') AppTextField(label: 'Specialty', controller: _specialty, hint: 'e.g. General physician', textCapitalization: TextCapitalization.words),
      AppTextField(label: _type == 'doctor' ? 'Clinic or hospital' : 'Business name', controller: _org, textCapitalization: TextCapitalization.words),
      Row(
        children: [
          Expanded(child: AppTextField(label: 'Phone', controller: _phone, keyboardType: TextInputType.phone, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)])),
          const SizedBox(width: 10),
          Expanded(child: AppTextField(label: 'City', controller: _city, textCapitalization: TextCapitalization.words)),
        ],
      ),
      AppTextField(label: 'Address', controller: _line, textCapitalization: TextCapitalization.words),
      AppSwitchRow(
        label: 'I’m here now',
        subtitle: 'Save this spot so check-ins are matched to it',
        icon: LucideIcons.locateFixed,
        value: _here,
        onChanged: (v) => setState(() => _here = v),
      ),
      const SizedBox(height: 8),
      Text('Class and visits a month', style: AppType.sans(fontSize: AppType.small, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
      const SizedBox(height: 8),
      Row(
        children: [
          for (final c in const ['A', 'B', 'C']) ...[
            AppFilterChip(label: 'Class $c', selected: _class == c, onTap: () => setState(() => _class = c)),
            const SizedBox(width: 8),
          ],
          const Spacer(),
          IconButton(onPressed: _freq > 1 ? () => setState(() => _freq--) : null, icon: const Icon(LucideIcons.minus, size: 16)),
          Text('$_freq', style: AppType.sans(fontSize: AppType.title, fontWeight: FontWeight.w800)),
          IconButton(onPressed: _freq < 8 ? () => setState(() => _freq++) : null, icon: const Icon(LucideIcons.plus, size: 16)),
        ],
      ),
      if (_error != null)
        Padding(padding: const EdgeInsets.only(top: 6, bottom: 6), child: Text(_error!, style: AppType.sans(fontSize: AppType.small, color: AppColors.error))),
      const SizedBox(height: 8),
      AppButton(label: 'Add customer', icon: LucideIcons.userPlus, loading: _busy, onPressed: _save),
    ],
  );
}

// ─────────────────────────── Aadya Plus link ───────────────────────────

/// Linking applies to doctors and chemists — they have their own accounts.
String? directoryKind(dynamic type) => switch ('$type') {
  'doctor' => 'doctor',
  'chemist' => 'pharmacy',
  _ => null,
};

bool isLinked(Map<String, dynamic> a) => mapOf(a['linkedEntity'])['refId'] != null;

/// Finds the doctor or pharmacy's own Aadya Plus account.
Future<Map<String, dynamic>?> findOnAadya(BuildContext context, String kind, {String initial = ''}) =>
    showAppSheet<Map<String, dynamic>>(context, builder: (_) => _DirectorySheet(kind: kind, initial: initial));

class _DirectorySheet extends ConsumerStatefulWidget {
  final String kind;
  final String initial;
  const _DirectorySheet({required this.kind, required this.initial});

  @override
  ConsumerState<_DirectorySheet> createState() => _DirectorySheetState();
}

class _DirectorySheetState extends ConsumerState<_DirectorySheet> {
  late final _q = TextEditingController(text: widget.initial);
  Timer? _debounce;
  List<Map<String, dynamic>> _results = const [];
  bool _busy = false;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initial.trim().length >= 2) _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    final q = _q.text.trim();
    final seq = ++_seq;
    if (q.length < 2) {
      setState(() {
        _results = const [];
        _error = null;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await ref.read(mrProvider.notifier).searchDirectory(widget.kind, q);
      if (mounted && seq == _seq) {
        setState(() {
          _results = r;
          _busy = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && seq == _seq) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    final doctor = widget.kind == 'doctor';
    return MrSheetBody(
      children: [
        MrSheetTitle(doctor ? 'Find the doctor on Aadya Plus' : 'Find the pharmacy on Aadya Plus', subtitle: 'Linking keeps their details in step with their own account'),
        AppSearchField(controller: _q, hint: doctor ? 'Name, clinic, specialty or city' : 'Pharmacy name or city', onChanged: _changed),
        const SizedBox(height: 12),
        if (_busy)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: accent.color))),
          )
        else if (_error != null)
          Text(_error!, style: AppType.sans(fontSize: AppType.small, color: AppColors.error))
        else if (_q.text.trim().length < 2)
          Text('Type at least two letters.', style: AppType.sans(fontSize: AppType.small, color: AppColors.textTertiary))
        else if (_results.isEmpty)
          Text('No match on Aadya Plus. You can still add them yourself.', style: AppType.sans(fontSize: AppType.small, color: AppColors.textSecondary))
        else
          for (final r in _results)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.all(12),
                onTap: r['accountId'] != null ? null : () => Navigator.pop(context, r),
                child: Row(
                  children: [
                    MrAvatar(name: '${r['name'] ?? ''}', icon: doctor ? LucideIcons.stethoscope : LucideIcons.store, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${r['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w700, color: AppColors.textStrong)),
                          Text(
                            [r['specialty'], r['organizationName'], mapOf(r['address'])['city']].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.sans(fontSize: AppType.caption, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (r['accountId'] != null)
                      Text('In your list', style: AppType.sans(fontSize: AppType.caption, fontWeight: FontWeight.w700, color: AppColors.textTertiary))
                    else
                      Icon(LucideIcons.chevronRight, size: 18, color: AppColors.textTertiary),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

/// A customer's details, where they stand on Aadya Plus, and quick actions.
class _AccountSheet extends ConsumerWidget {
  final String accountId;
  const _AccountSheet({required this.accountId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(mrProvider);
    final a = s.accounts.firstWhere((x) => idOf(x) == accountId, orElse: () => const <String, dynamic>{});
    if (a.isEmpty) return const MrSheetBody(children: [MrSheetTitle('Customer not found')]);
    final accent = ModuleAccent.of(context);
    final kind = accountKind(a['type']?.toString());
    final dirKind = directoryKind(a['type']);
    final linked = mapOf(a['linkedEntity']);
    final address = mapOf(a['address']);
    final where = [address['line1'], address['locality'], address['city']].where((e) => e != null && '$e'.isNotEmpty).join(', ');
    final n = ref.read(mrProvider.notifier);
    return MrSheetBody(
      children: [
        MrSheetTitle('${a['name'] ?? ''}', subtitle: [kind.label, a['specialty'], a['organizationName']].where((e) => e != null && '$e'.isNotEmpty).join(' · ')),
        if (where.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(LucideIcons.mapPin, size: 15, color: AppColors.textTertiary),
                const SizedBox(width: 8),
                Expanded(child: Text(where, style: AppType.sans(fontSize: AppType.small, color: AppColors.textPrimary))),
              ],
            ),
          ),
        if ('${a['phone'] ?? ''}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(LucideIcons.phone, size: 15, color: AppColors.textTertiary),
                const SizedBox(width: 8),
                Text('${a['phone']}', style: AppType.sans(fontSize: AppType.small, color: AppColors.textPrimary)),
              ],
            ),
          ),
        if (dirKind != null) ...[
          const SizedBox(height: 10),
          AppCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.all(12),
            borderColor: linked.isNotEmpty ? accent.color.withValues(alpha: 0.35) : null,
            child: Row(
              children: [
                AppIconBadge(icon: linked.isNotEmpty ? LucideIcons.badgeCheck : LucideIcons.link2, color: linked.isNotEmpty ? accent.color : AppColors.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(linked.isNotEmpty ? 'On Aadya Plus' : 'Not linked to Aadya Plus', style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w700, color: AppColors.textStrong)),
                      Text(
                        linked.isNotEmpty ? 'Linked to ${linked['name'] ?? 'their account'}' : 'Link them if they already use the app',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.sans(fontSize: AppType.caption, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    if (linked.isNotEmpty) {
                      await mrRun(context, () => n.updateAccount(accountId, {'linkedEntity': null}), done: 'Unlinked');
                      return;
                    }
                    final r = await findOnAadya(context, dirKind, initial: '${a['name'] ?? ''}');
                    if (r == null || !context.mounted) return;
                    await mrRun(context, () => n.updateAccount(accountId, {'linkedEntity': {'kind': r['kind'], 'refId': r['refId']}}), done: 'Linked to Aadya Plus');
                  },
                  child: Text(linked.isNotEmpty ? 'Unlink' : 'Link', style: AppType.sans(fontSize: AppType.small, fontWeight: FontWeight.w800, color: linked.isNotEmpty ? AppColors.error : accent.color)),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        AppButton(
          label: 'Plan a call',
          icon: LucideIcons.calendarPlus,
          onPressed: () => Navigator.pop(context, 'plan'),
        ),
        const SizedBox(height: 8),
        AppSecondaryButton(label: 'Edit details', icon: LucideIcons.pencil, onPressed: () => Navigator.pop(context, 'edit')),
        if (a['type'] != 'doctor') ...[
          const SizedBox(height: 8),
          AppSecondaryButton(
            label: 'Book order',
            icon: LucideIcons.shoppingCart,
            onPressed: () => Navigator.pop(context, 'order'),
          ),
        ],
      ],
    );
  }
}
