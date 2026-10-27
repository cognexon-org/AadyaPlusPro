import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../providers/mr_provider.dart';
import 'mr_ui.dart';

/// Who a manager adds directly: ZSM → RBM → ABM → MR.
const directReport = {'ZSM': 'RBM', 'RBM': 'ABM', 'ABM': 'MR'};

const designationNames = {
  'MR': 'Medical representative',
  'ABM': 'Area business manager',
  'RBM': 'Regional business manager',
  'ZSM': 'Zonal sales manager',
};

bool canManageTerritories(MrState s) => s.designation == 'RBM' || s.designation == 'ZSM';
bool canPublishDetailing(MrState s) => s.designation == 'ZSM';

String? _err(String? Function() check) => check();

/// Territory chips; a manager hands out the ones they cover.
class _TerritoryPicker extends ConsumerWidget {
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  const _TerritoryPicker({required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final territories = ref.watch(mrProvider).territories;
    if (territories.isEmpty) {
      return Text('No territories to assign yet.', style: AppType.sans(fontSize: AppType.small, color: AppColors.textTertiary));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in territories)
          AppFilterChip(label: '${t['name'] ?? t['code']}', selected: selected.contains(idOf(t)), onTap: () => onToggle(idOf(t))),
      ],
    );
  }
}

Widget _label(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Text(text, style: AppType.sans(fontSize: AppType.small, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
);

Widget _errorText(String? e) => e == null
    ? const SizedBox.shrink()
    : Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(e, style: AppType.sans(fontSize: AppType.small, color: AppColors.error)));

// ─────────────────────────── Add a team member ───────────────────────────

Future<void> addTeamMember(BuildContext context) => showAppSheet<void>(context, builder: (_) => const _AddMemberSheet());

class _AddMemberSheet extends ConsumerStatefulWidget {
  const _AddMemberSheet();

  @override
  ConsumerState<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends ConsumerState<_AddMemberSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  late final _hq = TextEditingController(text: '${ref.read(mrProvider).profile['headquarters'] ?? ''}');
  final Set<String> _territories = {};
  DateTime _joined = DateTime.now();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _code, _password, _hq]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(String designation) async {
    final error = _err(() {
      if (_name.text.trim().length < 2) return 'Enter their full name';
      if (!RegExp(r'^\d{10}$').hasMatch(_phone.text.trim())) return 'Enter a 10-digit phone number';
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim())) return 'Enter a valid email';
      if (_code.text.trim().isEmpty) return 'Enter the employee code';
      if (_password.text.length < 6) return 'The first password needs at least 6 characters';
      return null;
    });
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final p = ref.read(mrProvider).profile;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(mrProvider.notifier).addTeamMember({
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'email': _email.text.trim().toLowerCase(),
        'employeeCode': _code.text.trim().toUpperCase(),
        'password': _password.text,
        'designation': designation,
        if (_hq.text.trim().isNotEmpty) 'headquarters': _hq.text.trim(),
        'division': ?p['division'],
        'zone': ?p['zone'],
        'state': ?p['state'],
        'productLine': ?p['productLine'],
        'territoryIds': _territories.toList(),
        'dateOfJoining': DateTime(_joined.year, _joined.month, _joined.day, 12).toUtc().toIso8601String(),
      });
      if (!mounted) return;
      Navigator.pop(context);
      mrToast(context, '${_name.text.trim()} added. Share the email and password with them.');
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
  Widget build(BuildContext context) {
    final s = ref.watch(mrProvider);
    final designation = directReport[s.designation];
    if (designation == null) {
      return const MrSheetBody(children: [MrSheetTitle('Only managers add people')]);
    }
    return MrSheetBody(
      children: [
        MrSheetTitle('Add ${designationNames[designation]!.toLowerCase()}', subtitle: 'They’ll report to you and sign in with this email or phone'),
        AppTextField(label: 'Full name', controller: _name, required: true, textCapitalization: TextCapitalization.words),
        Row(
          children: [
            Expanded(child: AppTextField(label: 'Phone', controller: _phone, required: true, keyboardType: TextInputType.phone, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)])),
            const SizedBox(width: 10),
            Expanded(child: AppTextField(label: 'Employee code', controller: _code, required: true, textCapitalization: TextCapitalization.characters)),
          ],
        ),
        AppTextField(label: 'Email', controller: _email, required: true, keyboardType: TextInputType.emailAddress),
        AppTextField(label: 'First password', controller: _password, required: true, hint: 'They can change it from their profile'),
        Row(
          children: [
            Expanded(child: AppTextField(label: 'Headquarters', controller: _hq, textCapitalization: TextCapitalization.words)),
            const SizedBox(width: 10),
            Expanded(
              child: AppPickerField(
                label: 'Joined',
                valueText: DateFormat('d MMM y').format(_joined),
                icon: LucideIcons.calendar,
                onTap: () async {
                  final d = await showDatePicker(context: context, initialDate: _joined, firstDate: DateTime(2000), lastDate: DateTime.now());
                  if (d != null) setState(() => _joined = d);
                },
              ),
            ),
          ],
        ),
        _label('Territories'),
        _TerritoryPicker(selected: _territories, onToggle: (id) => setState(() => _territories.contains(id) ? _territories.remove(id) : _territories.add(id))),
        const SizedBox(height: 16),
        _errorText(_error),
        AppButton(label: 'Add to team', icon: LucideIcons.userPlus, loading: _busy, onPressed: () => _save(designation)),
      ],
    );
  }
}

// ─────────────────────────── Edit a team member ───────────────────────────

Future<void> editTeamMember(BuildContext context, Map<String, dynamic> person) =>
    showAppSheet<void>(context, builder: (_) => _EditMemberSheet(person: person));

class _EditMemberSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> person;
  const _EditMemberSheet({required this.person});

  @override
  ConsumerState<_EditMemberSheet> createState() => _EditMemberSheetState();
}

class _EditMemberSheetState extends ConsumerState<_EditMemberSheet> {
  late final _hq = TextEditingController(text: '${widget.person['headquarters'] ?? ''}');
  late final _division = TextEditingController(text: '${widget.person['division'] ?? ''}');
  late final _line = TextEditingController(text: '${widget.person['productLine'] ?? ''}');
  late final Set<String> _territories = {for (final t in listOf(widget.person['territories'])) idOf(t)};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_hq, _division, _line]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(mrProvider.notifier).updateTeamMember(idOf(widget.person), {
        'headquarters': _hq.text.trim(),
        'division': _division.text.trim(),
        'productLine': _line.text.trim(),
        'territoryIds': _territories.toList(),
      });
      if (!mounted) return;
      Navigator.pop(context);
      mrToast(context, 'Saved');
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _setActive(bool active) async {
    final name = '${widget.person['name'] ?? repName(widget.person)}';
    if (!active) {
      final ok = await AppModal.show<bool>(
        context,
        title: 'Deactivate $name?',
        icon: LucideIcons.userX,
        content: Text('They won’t be able to sign in. Their calls, orders and expenses stay on record, and you can bring them back later.', style: AppType.sans(fontSize: AppType.body, color: AppColors.textPrimary)),
        actions: [
          AppSecondaryButton(label: 'Cancel', onPressed: () => Navigator.pop(context, false)),
          AppButton(label: 'Deactivate', onPressed: () => Navigator.pop(context, true)),
        ],
      );
      if (ok != true || !mounted) return;
    }
    final done = await mrRun(context, () => ref.read(mrProvider.notifier).updateTeamMember(idOf(widget.person), {'isActive': active}), done: active ? '$name is active again' : '$name deactivated');
    if (done && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.person['isActive'] != false;
    return MrSheetBody(
      children: [
        MrSheetTitle('Work details', subtitle: '${widget.person['name'] ?? repName(widget.person)} · ${widget.person['employeeCode'] ?? ''}'),
        AppTextField(label: 'Headquarters', controller: _hq, textCapitalization: TextCapitalization.words),
        Row(
          children: [
            Expanded(child: AppTextField(label: 'Division', controller: _division, textCapitalization: TextCapitalization.words)),
            const SizedBox(width: 10),
            Expanded(child: AppTextField(label: 'Product line', controller: _line, textCapitalization: TextCapitalization.words)),
          ],
        ),
        _label('Territories'),
        _TerritoryPicker(selected: _territories, onToggle: (id) => setState(() => _territories.contains(id) ? _territories.remove(id) : _territories.add(id))),
        const SizedBox(height: 16),
        _errorText(_error),
        if (active) ...[
          AppButton(label: 'Save', icon: LucideIcons.check, loading: _busy, onPressed: _save),
          const SizedBox(height: 8),
          AppSecondaryButton(label: 'Deactivate', icon: LucideIcons.userX, color: AppColors.error, onPressed: _busy ? null : () => _setActive(false)),
        ] else
          AppButton(label: 'Reactivate', icon: LucideIcons.userCheck, onPressed: () => _setActive(true)),
      ],
    );
  }
}

// ─────────────────────────── Edit a customer ───────────────────────────

Future<void> editAccount(BuildContext context, Map<String, dynamic> account) =>
    showAppSheet<void>(context, builder: (_) => _EditAccountSheet(account: account));

class _EditAccountSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> account;
  const _EditAccountSheet({required this.account});

  @override
  ConsumerState<_EditAccountSheet> createState() => _EditAccountSheetState();
}

class _EditAccountSheetState extends ConsumerState<_EditAccountSheet> {
  Map<String, dynamic> get a => widget.account;
  late final _name = TextEditingController(text: '${a['name'] ?? ''}');
  late final _specialty = TextEditingController(text: '${a['specialty'] ?? ''}');
  late final _org = TextEditingController(text: '${a['organizationName'] ?? ''}');
  late final _phone = TextEditingController(text: '${a['phone'] ?? ''}');
  late final _city = TextEditingController(text: '${mapOf(a['address'])['city'] ?? ''}');
  late final _line = TextEditingController(text: '${mapOf(a['address'])['line1'] ?? ''}');
  late String _class = const {'A', 'B', 'C'}.contains(a['classification']) ? '${a['classification']}' : 'B';
  late int _freq = ((a['visitFrequencyPerMonth'] as num?) ?? 1).toInt().clamp(1, 8);
  late String? _territory = idOf(a['territoryId']).isEmpty ? null : idOf(a['territoryId']);
  late final Set<String> _reps = {for (final r in (a['assignedProfileIds'] is List ? a['assignedProfileIds'] as List : const [])) idOf(r)};
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
    final s = ref.read(mrProvider);
    if (s.isManager && _reps.isEmpty) {
      setState(() => _error = 'Choose at least one person to cover this customer');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(mrProvider.notifier).updateAccount(idOf(a), {
        'name': _name.text.trim(),
        'specialty': _specialty.text.trim(),
        'organizationName': _org.text.trim(),
        'phone': _phone.text.trim(),
        'address': {...mapOf(a['address']), 'line1': _line.text.trim(), 'city': _city.text.trim()},
        'classification': _class,
        'visitFrequencyPerMonth': _freq,
        if (_territory != null) 'territoryId': _territory,
        if (s.isManager) 'assignedProfileIds': _reps.toList(),
      });
      if (!mounted) return;
      Navigator.pop(context);
      mrToast(context, 'Customer updated');
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _remove() async {
    final ok = await AppModal.show<bool>(
      context,
      title: 'Remove ${a['name']}?',
      icon: LucideIcons.userMinus,
      content: Text('They’ll leave the customer list. Past calls and orders stay on record.', style: AppType.sans(fontSize: AppType.body, color: AppColors.textPrimary)),
      actions: [
        AppSecondaryButton(label: 'Keep', onPressed: () => Navigator.pop(context, false)),
        AppButton(label: 'Remove', onPressed: () => Navigator.pop(context, true)),
      ],
    );
    if (ok != true || !mounted) return;
    final done = await mrRun(context, () => ref.read(mrProvider.notifier).updateAccount(idOf(a), {'isActive': false}), done: 'Customer removed');
    if (done && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(mrProvider);
    final doctor = a['type'] == 'doctor';
    final reps = s.team.where((p) => p['isActive'] != false).toList();
    return MrSheetBody(
      children: [
        const MrSheetTitle('Edit customer'),
        AppTextField(label: doctor ? 'Doctor’s name' : 'Name', controller: _name, required: true, textCapitalization: TextCapitalization.words),
        if (doctor) AppTextField(label: 'Specialty', controller: _specialty, textCapitalization: TextCapitalization.words),
        AppTextField(label: doctor ? 'Clinic or hospital' : 'Business name', controller: _org, textCapitalization: TextCapitalization.words),
        Row(
          children: [
            Expanded(child: AppTextField(label: 'Phone', controller: _phone, keyboardType: TextInputType.phone, inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)])),
            const SizedBox(width: 10),
            Expanded(child: AppTextField(label: 'City', controller: _city, textCapitalization: TextCapitalization.words)),
          ],
        ),
        AppTextField(label: 'Address', controller: _line, textCapitalization: TextCapitalization.words),
        _label('Class and visits a month'),
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
        if (s.territories.isNotEmpty) ...[
          const SizedBox(height: 10),
          _label('Territory'),
          _TerritoryPicker(selected: {?_territory}, onToggle: (id) => setState(() => _territory = _territory == id ? null : id)),
        ],
        if (s.isManager && reps.isNotEmpty) ...[
          const SizedBox(height: 16),
          _label('Covered by'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in reps)
                AppFilterChip(
                  label: idOf(p) == s.ownProfileId ? 'Me' : '${p['name'] ?? repName(p)}',
                  selected: _reps.contains(idOf(p)),
                  onTap: () => setState(() => _reps.contains(idOf(p)) ? _reps.remove(idOf(p)) : _reps.add(idOf(p))),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        _errorText(_error),
        AppButton(label: 'Save', icon: LucideIcons.check, loading: _busy, onPressed: _save),
        const SizedBox(height: 8),
        AppSecondaryButton(label: 'Remove customer', icon: LucideIcons.userMinus, color: AppColors.error, onPressed: _busy ? null : _remove),
      ],
    );
  }
}

// ─────────────────────────── Territory (RBM, ZSM) ───────────────────────────

Future<void> editTerritory(BuildContext context, {Map<String, dynamic>? territory}) =>
    showAppSheet<void>(context, builder: (_) => _TerritoryEditSheet(territory: territory));

class _TerritoryEditSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic>? territory;
  const _TerritoryEditSheet({this.territory});

  @override
  ConsumerState<_TerritoryEditSheet> createState() => _TerritoryEditSheetState();
}

class _TerritoryEditSheetState extends ConsumerState<_TerritoryEditSheet> {
  Map<String, dynamic> get t => widget.territory ?? const {};
  late final _code = TextEditingController(text: '${t['code'] ?? ''}');
  late final _name = TextEditingController(text: '${t['name'] ?? ''}');
  late final _city = TextEditingController(text: '${t['city'] ?? ''}');
  late final _state = TextEditingController(text: '${t['state'] ?? ''}');
  late final _pins = TextEditingController(text: (t['pincodes'] is List ? t['pincodes'] as List : const []).join(', '));
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_code, _name, _city, _state, _pins]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final pins = _pins.text.split(RegExp(r'[\s,]+')).where((p) => p.isNotEmpty).toList();
    final error = _err(() {
      if (_code.text.trim().isEmpty) return 'Enter a short code, e.g. BLR-E';
      if (_name.text.trim().length < 2) return 'Enter the territory name';
      if (pins.any((p) => !RegExp(r'^\d{6}$').hasMatch(p))) return 'Pincodes are 6 digits, separated by commas';
      return null;
    });
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(mrProvider.notifier).saveTerritory(widget.territory == null ? null : idOf(t), {
        'code': _code.text.trim().toUpperCase(),
        'name': _name.text.trim(),
        'city': _city.text.trim(),
        'state': _state.text.trim(),
        'pincodes': pins,
      });
      if (!mounted) return;
      Navigator.pop(context);
      mrToast(context, widget.territory == null ? 'Territory created' : 'Territory saved');
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
      MrSheetTitle(widget.territory == null ? 'New territory' : 'Edit territory'),
      Row(
        children: [
          Expanded(child: AppTextField(label: 'Code', controller: _code, required: true, textCapitalization: TextCapitalization.characters)),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: AppTextField(label: 'Name', controller: _name, required: true, textCapitalization: TextCapitalization.words)),
        ],
      ),
      Row(
        children: [
          Expanded(child: AppTextField(label: 'City', controller: _city, textCapitalization: TextCapitalization.words)),
          const SizedBox(width: 10),
          Expanded(child: AppTextField(label: 'State', controller: _state, textCapitalization: TextCapitalization.words)),
        ],
      ),
      AppTextField(label: 'Pincodes', controller: _pins, hint: '560008, 560038', maxLines: 2, keyboardType: TextInputType.number),
      _errorText(_error),
      AppButton(label: 'Save territory', icon: LucideIcons.check, loading: _busy, onPressed: _save),
    ],
  );
}

// ─────────────────────────── E-detailing (ZSM) ───────────────────────────

Future<void> editDetailing(BuildContext context, {Map<String, dynamic>? content}) =>
    showAppSheet<void>(context, builder: (_) => _DetailingSheet(content: content));

class _DetailingSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic>? content;
  const _DetailingSheet({this.content});

  @override
  ConsumerState<_DetailingSheet> createState() => _DetailingSheetState();
}

class _DetailingSheetState extends ConsumerState<_DetailingSheet> {
  Map<String, dynamic> get d => widget.content ?? const {};
  late final _title = TextEditingController(text: '${d['title'] ?? ''}');
  late final _product = TextEditingController(text: '${d['productName'] ?? ''}');
  late final _url = TextEditingController(text: '${d['url'] ?? ''}');
  late String _type = '${d['contentType'] ?? 'pdf'}';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_title, _product, _url]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save({bool? active}) async {
    final error = active != null
        ? null
        : _err(() {
            if (_title.text.trim().length < 2) return 'Enter a title';
            if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(_url.text.trim())) return 'Add a link that starts with https://';
            return null;
          });
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(mrProvider.notifier).saveDetailing(
        widget.content == null ? null : idOf(d),
        active != null
            ? {'isActive': active}
            : {'title': _title.text.trim(), 'productName': _product.text.trim(), 'url': _url.text.trim(), 'contentType': _type},
      );
      if (!mounted) return;
      Navigator.pop(context);
      mrToast(context, active == false ? 'Removed from the library' : 'Saved to the library');
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
      MrSheetTitle(widget.content == null ? 'Add e-detailing content' : 'Edit content', subtitle: 'Everyone in the field force sees it in their profile'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (k, l) in const [('pdf', 'PDF'), ('video', 'Video'), ('presentation', 'Slides'), ('image', 'Image'), ('url', 'Link')])
            AppFilterChip(label: l, selected: _type == k, onTap: () => setState(() => _type = k)),
        ],
      ),
      const SizedBox(height: 14),
      AppTextField(label: 'Title', controller: _title, required: true, textCapitalization: TextCapitalization.sentences),
      AppTextField(label: 'Product', controller: _product, textCapitalization: TextCapitalization.words),
      AppTextField(label: 'Link', controller: _url, required: true, hint: 'https://…', keyboardType: TextInputType.url),
      _errorText(_error),
      AppButton(label: 'Save', icon: LucideIcons.check, loading: _busy, onPressed: () => _save()),
      if (widget.content != null) ...[
        const SizedBox(height: 8),
        AppSecondaryButton(label: 'Remove from library', icon: LucideIcons.trash2, color: AppColors.error, onPressed: _busy ? null : () => _save(active: false)),
      ],
    ],
  );
}
