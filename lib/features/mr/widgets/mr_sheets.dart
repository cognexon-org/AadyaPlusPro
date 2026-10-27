import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../providers/mr_provider.dart';
import '../screens/mr_visit_screen.dart';
import 'mr_claims.dart';
import 'mr_ui.dart';

/// A call in a list: who, when, where it stands, and anything off (a
/// check-in outside the geofence, a report sent back).
class MrVisitCard extends StatelessWidget {
  final Map<String, dynamic> visit;
  final bool showRep;
  final bool showDay;
  final VoidCallback onTap;
  final Widget? trailing;
  const MrVisitCard({super.key, required this.visit, required this.onTap, this.showRep = false, this.showDay = false, this.trailing});

  @override
  Widget build(BuildContext context) {
    final v = visit;
    final account = mapOf(v['accountId']);
    final kind = accountKind(account['type']?.toString());
    final when = mrDate(v['visitDate']);
    final outside = v['geofenceStatus'] == 'outside';
    final products = listOf(v['productsDiscussed']).map((p) => '${p['productName'] ?? ''}').where((p) => p.isNotEmpty).toList();
    final meta = [
      kind.label,
      if ('${account['specialty'] ?? ''}'.isNotEmpty) '${account['specialty']}',
      if (showRep) repName(v['profileId']),
    ].join(' · ');
    return AppCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showDay && when != null)
                  Text(dayLabel(when), style: AppType.sans(fontSize: AppType.micro, color: AppColors.textSecondary)),
                Text(when == null ? '' : timeLabel(when), style: AppType.sans(fontSize: AppType.small, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
              ],
            ),
          ),
          Container(width: 1, height: 42, margin: const EdgeInsets.only(right: 12), color: AppColors.borderStrong),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(kind.icon, size: 14, color: ModuleAccent.of(context).color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('${account['name'] ?? 'Customer'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.sans(fontSize: AppType.body + 1, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
                    ),
                    const SizedBox(width: 6),
                    MrStatusPill(v['status']?.toString()),
                  ],
                ),
                const SizedBox(height: 3),
                Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.sans(fontSize: AppType.caption, color: AppColors.textSecondary)),
                if (products.isNotEmpty || outside) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (outside)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.mapPinOff, size: 12, color: AppColors.warning),
                            const SizedBox(width: 3),
                            Text('Checked in away from clinic', style: AppType.sans(fontSize: AppType.micro, fontWeight: FontWeight.w700, color: AppColors.warning)),
                          ],
                        ),
                      if (products.isNotEmpty)
                        Text(products.take(3).join(', '), style: AppType.sans(fontSize: AppType.micro, color: AppColors.textTertiary)),
                    ],
                  ),
                ],
                if (trailing != null) ...[const SizedBox(height: 10), trailing!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Plan a call ───────────────────────────

/// Pick a customer and a time, create the call and open it.
Future<void> planCall(BuildContext context, WidgetRef ref, {Map<String, dynamic>? account}) async {
  final notifier = ref.read(mrProvider.notifier);
  final picked = account ?? await pickAccount(context, ref, title: 'Plan a call');
  if (picked == null || !context.mounted) return;
  final plan = await showAppSheet<(DateTime, List<String>)>(context, builder: (_) => _WhenSheet(account: picked));
  if (plan == null || !context.mounted) return;
  Map<String, dynamic>? visit;
  final ok = await mrRun(context, () async => visit = await notifier.createVisit(idOf(picked), when: plan.$1, jointWith: plan.$2), done: plan.$2.isEmpty ? 'Call planned' : 'Joint call planned');
  if (ok && context.mounted && visit != null && idOf(visit).isNotEmpty) {
    Navigator.of(context).push(AppPageRoute(builder: (_) => MrVisitScreen(visitId: idOf(visit))));
  }
}

class _WhenSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> account;
  const _WhenSheet({required this.account});

  @override
  ConsumerState<_WhenSheet> createState() => _WhenSheetState();
}

class _WhenSheetState extends ConsumerState<_WhenSheet> {
  late DateTime _day = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  late TimeOfDay _time = TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 15)));
  final Set<String> _joint = {};

  /// A rep can take their manager along; a manager, anyone in their team.
  List<(String, String)> _partners() {
    final s = ref.read(mrProvider);
    final out = <(String, String)>[];
    final manager = mapOf(s.profile['managerId']);
    if (idOf(manager).isNotEmpty) out.add((idOf(manager), '${repName(manager)} (manager)'));
    for (final p in s.team) {
      if (idOf(p) == s.ownProfileId || p['isActive'] == false) continue;
      out.add((idOf(p), '${p['name'] ?? repName(p)}'));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    final partners = _partners();
    final days = [for (var i = 0; i < 7; i++) DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day + i)];
    return MrSheetBody(
      children: [
        MrSheetTitle('When?', subtitle: '${widget.account['name'] ?? ''}'),
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: days.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final d = days[i];
              final sel = d == _day;
              return AppPressable(
                onTap: () => setState(() => _day = d),
                child: AnimatedContainer(
                  duration: AppMotion.fast,
                  width: 54,
                  decoration: BoxDecoration(color: sel ? accent.color : AppColors.panel, borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(i == 0 ? 'Today' : DateFormat('EEE').format(d), style: AppType.sans(fontSize: AppType.micro, color: sel ? Colors.white70 : AppColors.textSecondary)),
                      Text('${d.day}', style: AppType.sans(fontSize: 18, fontWeight: FontWeight.w800, color: sel ? Colors.white : AppColors.textStrong)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        AppPickerField(
          label: 'Time',
          valueText: _time.format(context),
          icon: LucideIcons.clock,
          onTap: () async {
            final t = await showTimePicker(context: context, initialTime: _time);
            if (t != null) setState(() => _time = t);
          },
        ),
        if (partners.isNotEmpty) ...[
          Text('Joint call with', style: AppType.sans(fontSize: AppType.small, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (id, label) in partners)
                AppFilterChip(label: label, selected: _joint.contains(id), onTap: () => setState(() => _joint.contains(id) ? _joint.remove(id) : _joint.add(id))),
            ],
          ),
          const SizedBox(height: 16),
        ],
        AppButton(
          label: _joint.isEmpty ? 'Plan call' : 'Plan joint call',
          icon: LucideIcons.calendarPlus,
          onPressed: () => Navigator.pop(context, (DateTime(_day.year, _day.month, _day.day, _time.hour, _time.minute), _joint.toList())),
        ),
      ],
    );
  }
}

/// Search the rep's customers and pick one. [types] limits the kinds shown
/// (orders go to chemists, stockists and hospitals only).
Future<Map<String, dynamic>?> pickAccount(BuildContext context, WidgetRef ref, {required String title, Set<String>? types}) {
  return showAppSheet<Map<String, dynamic>>(context, builder: (_) => _AccountPicker(title: title, types: types));
}

class _AccountPicker extends ConsumerStatefulWidget {
  final String title;
  final Set<String>? types;
  const _AccountPicker({required this.title, this.types});

  @override
  ConsumerState<_AccountPicker> createState() => _AccountPickerState();
}

class _AccountPickerState extends ConsumerState<_AccountPicker> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(mrProvider).accounts;
    final q = _q.text.trim().toLowerCase();
    final list = all.where((a) {
      if (a['isActive'] == false) return false;
      if (widget.types != null && !widget.types!.contains(a['type'])) return false;
      if (q.isEmpty) return true;
      return [a['name'], a['specialty'], a['organizationName'], mapOf(a['address'])['city']].join(' ').toLowerCase().contains(q);
    }).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MrSheetTitle(widget.title, subtitle: 'Choose a customer'),
          AppSearchField(controller: _q, hint: 'Name, specialty or city', onChanged: (_) => setState(() {})),
          const SizedBox(height: 10),
          Expanded(
            child: list.isEmpty
                ? const AppEmptyState(icon: LucideIcons.searchX, text: 'No customers match. Add them from Customers.')
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final a = list[i];
                      final kind = accountKind(a['type']?.toString());
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: MrAvatar(name: '${a['name'] ?? ''}', icon: kind.icon, size: 38),
                        title: Text('${a['name'] ?? ''}', style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w700, color: AppColors.textStrong)),
                        subtitle: Text(
                          [kind.label, a['specialty'], mapOf(a['address'])['city']].where((e) => e != null && '$e'.isNotEmpty).join(' · '),
                          style: AppType.sans(fontSize: AppType.caption, color: AppColors.textSecondary),
                        ),
                        trailing: '${a['classification'] ?? ''}'.length == 1
                            ? AppStatusPill(text: 'Class ${a['classification']}', color: ModuleAccent.of(context).color)
                            : null,
                        onTap: () => Navigator.pop(context, a),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Expense ───────────────────────────

Future<void> newExpense(BuildContext context, WidgetRef ref) =>
    showAppSheet<void>(context, builder: (_) => const _ExpenseSheet());

class _ExpenseSheet extends ConsumerStatefulWidget {
  const _ExpenseSheet();

  @override
  ConsumerState<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends ConsumerState<_ExpenseSheet> {
  String _category = 'travel';
  DateTime _date = DateTime.now();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _receipt;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save(bool submit) async {
    final amount = num.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter the amount');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(mrProvider.notifier).createExpense(category: _category, amount: amount, date: _date, description: _note.text, receiptPath: _receipt, submit: submit);
      if (!mounted) return;
      Navigator.pop(context);
      mrToast(context, submit ? 'Expense sent for approval' : 'Expense saved as draft');
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
      const MrSheetTitle('New expense'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in expenseCategories.entries)
            AppFilterChip(label: e.value.$1, selected: _category == e.key, onTap: () => setState(() => _category = e.key)),
        ],
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: AppTextField(
              label: 'Amount (₹)',
              controller: _amount,
              isDecimal: true,
              required: true,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AppPickerField(
              label: 'Date',
              valueText: DateFormat('d MMM y').format(_date),
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now().subtract(const Duration(days: 60)), lastDate: DateTime.now());
                if (d != null) setState(() => _date = d);
              },
            ),
          ),
        ],
      ),
      AppTextField(label: 'Details', hint: 'From – to, purpose', controller: _note, maxLines: 2, textCapitalization: TextCapitalization.sentences),
      AppCard(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        onTap: () async {
          final path = await pickReceipt(context);
          if (path != null) setState(() => _receipt = path);
        },
        child: Row(
          children: [
            AppIconBadge(icon: _receipt == null ? LucideIcons.paperclip : LucideIcons.fileCheck, color: _receipt == null ? ModuleAccent.of(context).color : AppColors.success),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _receipt == null ? 'Add receipt photo' : 'Receipt added',
                style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w600, color: AppColors.textStrong),
              ),
            ),
            if (_receipt != null)
              GestureDetector(onTap: () => setState(() => _receipt = null), child: Icon(LucideIcons.x, size: 18, color: AppColors.textTertiary)),
          ],
        ),
      ),
      if (_error != null)
        Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: AppType.sans(fontSize: AppType.small, color: AppColors.error))),
      AppButton(label: 'Send for approval', icon: LucideIcons.send, loading: _busy, onPressed: () => _save(true)),
      const SizedBox(height: 8),
      AppSecondaryButton(label: 'Save as draft', onPressed: _busy ? null : () => _save(false)),
    ],
  );
}

// ─────────────────────────── Order (POB) ───────────────────────────

Future<void> newOrder(BuildContext context, WidgetRef ref, {Map<String, dynamic>? account}) async {
  final picked = account ?? await pickAccount(context, ref, title: 'Book an order', types: const {'chemist', 'stockist', 'hospital'});
  if (picked == null || !context.mounted) return;
  await showAppSheet<void>(context, builder: (_) => _OrderSheet(account: picked));
}

class _OrderSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> account;
  const _OrderSheet({required this.account});

  @override
  ConsumerState<_OrderSheet> createState() => _OrderSheetState();
}

class _Line {
  final name = TextEditingController();
  final qty = TextEditingController();
  final rate = TextEditingController();
  void dispose() {
    name.dispose();
    qty.dispose();
    rate.dispose();
  }
}

class _OrderSheetState extends ConsumerState<_OrderSheet> {
  final _lines = [_Line()];
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  num get _total => _lines.fold<num>(0, (s, l) => s + (num.tryParse(l.qty.text) ?? 0) * (num.tryParse(l.rate.text) ?? 0));

  Future<void> _save() async {
    final items = <({String name, num qty, num rate})>[];
    for (final l in _lines) {
      final n = l.name.text.trim();
      final q = num.tryParse(l.qty.text.trim()) ?? 0;
      final r = num.tryParse(l.rate.text.trim()) ?? -1;
      if (n.isEmpty && l.qty.text.isEmpty) continue;
      if (n.isEmpty || q <= 0 || r < 0) {
        setState(() => _error = 'Each line needs a product, a quantity and a rate');
        return;
      }
      items.add((name: n, qty: q, rate: r));
    }
    if (items.isEmpty) {
      setState(() => _error = 'Add at least one product');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(mrProvider.notifier).createPob(accountId: idOf(widget.account), items: items, notes: _note.text);
      if (!mounted) return;
      Navigator.pop(context);
      mrToast(context, 'Order booked');
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
      MrSheetTitle('Book an order', subtitle: '${widget.account['name'] ?? ''}'),
      for (final (i, l) in _lines.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: AppTextField(label: i == 0 ? 'Product' : '', controller: l.name, dense: true, textCapitalization: TextCapitalization.words, margin: EdgeInsets.zero)),
              const SizedBox(width: 6),
              Expanded(flex: 2, child: AppTextField(label: i == 0 ? 'Qty' : '', controller: l.qty, isNum: true, dense: true, margin: EdgeInsets.zero, onSubmitted: (_) => setState(() {}))),
              const SizedBox(width: 6),
              Expanded(flex: 3, child: AppTextField(label: i == 0 ? 'Rate ₹' : '', controller: l.rate, isDecimal: true, dense: true, margin: EdgeInsets.zero, onSubmitted: (_) => setState(() {}))),
            ],
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _lines.add(_Line())),
          icon: const Icon(LucideIcons.plus, size: 16),
          label: const Text('Add product'),
          style: TextButton.styleFrom(foregroundColor: ModuleAccent.of(context).color),
        ),
      ),
      AppTextField(label: 'Note', controller: _note, hint: 'Delivery or scheme details (optional)'),
      ListenableBuilder(
        listenable: Listenable.merge([for (final l in _lines) ...[l.qty, l.rate]]),
        builder: (_, _) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Text('Order value', style: AppType.sans(fontSize: AppType.body, color: AppColors.textSecondary)),
              const Spacer(),
              Text(appRupees(_total), style: AppType.sans(fontSize: AppType.heading, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
            ],
          ),
        ),
      ),
      if (_error != null)
        Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: AppType.sans(fontSize: AppType.small, color: AppColors.error))),
      AppButton(label: 'Book order', icon: LucideIcons.shoppingCart, loading: _busy, onPressed: _save),
    ],
  );
}

/// Approve or send back, with an optional comment. Returns (decision, comment).
Future<(String, String)?> reviewSheet(BuildContext context, {required String title, String? subtitle, String rejectLabel = 'Send back', Widget? body}) =>
    showAppSheet<(String, String)>(context, builder: (_) => _ReviewSheet(title: title, subtitle: subtitle, rejectLabel: rejectLabel, body: body));

class _ReviewSheet extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String rejectLabel;
  final Widget? body;
  const _ReviewSheet({required this.title, this.subtitle, required this.rejectLabel, this.body});

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MrSheetBody(
    children: [
      MrSheetTitle(widget.title, subtitle: widget.subtitle),
      if (widget.body != null) ...[widget.body!, const SizedBox(height: 14)],
      AppTextField(label: 'Comment', hint: 'Needed for ${widget.rejectLabel.toLowerCase()}', controller: _comment, maxLines: 2, textCapitalization: TextCapitalization.sentences),
      Row(
        children: [
          Expanded(
            child: AppSecondaryButton(
              label: widget.rejectLabel,
              icon: LucideIcons.undo2,
              color: AppColors.error,
              onPressed: () {
                if (_comment.text.trim().isEmpty) {
                  mrToast(context, 'Add a comment for the rep', error: true);
                  return;
                }
                Navigator.pop(context, ('reject', _comment.text.trim()));
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: AppButton(label: 'Approve', icon: LucideIcons.check, onPressed: () => Navigator.pop(context, ('approve', _comment.text.trim())))),
        ],
      ),
    ],
  );
}
