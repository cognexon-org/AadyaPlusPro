import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/mr_provider.dart';

class MrWork extends ConsumerStatefulWidget {
  const MrWork({super.key});

  @override
  ConsumerState<MrWork> createState() => _MrWorkState();
}

class _MrWorkState extends ConsumerState<MrWork> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    Future.microtask(() async {
      final n = ref.read(mrProvider.notifier);
      await Future.wait([n.loadPlans(), n.loadExpenses(), n.loadPob(), n.loadAccounts()]);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updated successfully')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _id(dynamic value) {
    if (value is Map) return '${value['_id'] ?? value['id'] ?? ''}';
    return '$value';
  }

  String _monthKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  bool _belongsToMe(dynamic profile, String? own) {
    if (own == null || own.isEmpty) return true;
    return _id(profile) == own;
  }

  Future<void> _addTourDay() async {
    var date = DateTime.now();
    final area = TextEditingController();
    final objective = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Add tour-plan day'),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month_outlined),
                title: Text('${date.day}/${date.month}/${date.year}'),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: () async {
                  final picked = await showDatePicker(context: context, initialDate: date, firstDate: DateTime.now().subtract(const Duration(days: 30)), lastDate: DateTime.now().add(const Duration(days: 365)));
                  if (picked != null) setLocal(() => date = picked);
                },
              ),
              TextField(controller: area, decoration: const InputDecoration(labelText: 'Area / route')),
              const SizedBox(height: 10),
              TextField(controller: objective, decoration: const InputDecoration(labelText: 'Objective')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save draft')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _run(() => ref.read(mrProvider.notifier).saveTourDay(month: _monthKey(date), date: date, area: area.text.trim(), objective: objective.text.trim()));
    }
  }

  Future<void> _newExpense() async {
    String category = 'travel';
    final amount = TextEditingController();
    final description = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('New expense'),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                value: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: const ['travel', 'daily_allowance', 'lodging', 'meals', 'local_conveyance', 'phone', 'meeting', 'other']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v.replaceAll('_', ' '))))
                    .toList(),
                onChanged: (v) => setLocal(() => category = v ?? 'travel'),
              ),
              const SizedBox(height: 10),
              TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount ₹')),
              const SizedBox(height: 10),
              TextField(controller: description, decoration: const InputDecoration(labelText: 'Description')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save draft')),
          ],
        ),
      ),
    );
    final value = num.tryParse(amount.text.trim());
    if (ok == true && value != null && value >= 0) {
      await _run(() => ref.read(mrProvider.notifier).createExpense(category: category, amount: value, description: description.text));
    }
  }

  Future<void> _newPob() async {
    final state = ref.read(mrProvider);
    final eligible = state.accounts.where((a) => const {'chemist', 'stockist', 'hospital'}.contains('${a['type']}')).toList();
    String? accountId;
    final product = TextEditingController();
    final qty = TextEditingController(text: '1');
    final rate = TextEditingController(text: '0');
    final notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('New POB order'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 460,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  value: accountId,
                  decoration: const InputDecoration(labelText: 'Chemist / stockist / hospital'),
                  items: eligible.map((a) => DropdownMenuItem(value: _id(a['_id'] ?? a['id']), child: Text('${a['name'] ?? 'Account'}'))).toList(),
                  onChanged: (v) => setLocal(() => accountId = v),
                ),
                const SizedBox(height: 10),
                TextField(controller: product, decoration: const InputDecoration(labelText: 'Product')),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity'))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: rate, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Rate ₹'))),
                ]),
                const SizedBox(height: 10),
                TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes')),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: accountId == null ? null : () => Navigator.pop(context, true), child: const Text('Place POB')),
          ],
        ),
      ),
    );
    final q = num.tryParse(qty.text.trim());
    final r = num.tryParse(rate.text.trim());
    if (ok == true && accountId != null && product.text.trim().isNotEmpty && q != null && q > 0 && r != null && r >= 0) {
      await _run(() => ref.read(mrProvider.notifier).createPob(accountId: accountId!, productName: product.text.trim(), quantity: q, rate: r, notes: notes.text));
    }
  }

  Future<void> _review(String kind, String id, String decision) async {
    final comment = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${decision == 'approve' ? 'Approve' : 'Reject'} $kind'),
        content: TextField(controller: comment, decoration: const InputDecoration(labelText: 'Manager comment')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(decision == 'approve' ? 'Approve' : 'Reject')),
        ],
      ),
    );
    if (ok != true) return;
    final n = ref.read(mrProvider.notifier);
    if (kind == 'tour plan') {
      await _run(() => n.reviewTourPlan(id, decision, comment: comment.text.trim()));
    } else {
      await _run(() => n.reviewExpense(id, decision, comment: comment.text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mrProvider);
    final n = ref.read(mrProvider.notifier);
    final own = n.ownProfileId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plans & Field Work'),
        bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Tour'), Tab(text: 'Expenses'), Tab(text: 'POB')]),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          RefreshIndicator(
            onRefresh: n.loadPlans,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
              children: [
                FilledButton.icon(onPressed: _busy ? null : _addTourDay, icon: const Icon(Icons.add), label: const Text('Add tour-plan day')),
                const SizedBox(height: 10),
                if (state.tourPlans.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No tour plans yet.'))),
                ...state.tourPlans.map((plan) {
                  final mine = _belongsToMe(plan['profileId'], own);
                  final status = '${plan['status'] ?? 'draft'}';
                  final days = plan['days'] is List ? plan['days'] as List : const [];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text('${plan['month'] ?? ''} Tour Plan', style: const TextStyle(fontWeight: FontWeight.w700))),
                          Text(status, style: const TextStyle(color: AppTheme.textSecondary)),
                        ]),
                        const SizedBox(height: 6),
                        Text('${days.length} planned day(s)'),
                        if ('${plan['managerComment'] ?? ''}'.isNotEmpty) Text('Manager: ${plan['managerComment']}', style: const TextStyle(color: AppTheme.textSecondary)),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, children: [
                          if (mine && (status == 'draft' || status == 'rejected'))
                            FilledButton.tonal(onPressed: _busy ? null : () => _run(() => n.submitTourPlan(_id(plan['_id'] ?? plan['id']))), child: const Text('Submit')),
                          if (!mine && n.isManager && status == 'submitted') ...[
                            FilledButton.tonal(onPressed: _busy ? null : () => _review('tour plan', _id(plan['_id'] ?? plan['id']), 'approve'), child: const Text('Approve')),
                            OutlinedButton(onPressed: _busy ? null : () => _review('tour plan', _id(plan['_id'] ?? plan['id']), 'reject'), child: const Text('Reject')),
                          ],
                        ]),
                      ]),
                    ),
                  );
                }),
              ],
            ),
          ),
          RefreshIndicator(
            onRefresh: n.loadExpenses,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
              children: [
                FilledButton.icon(onPressed: _busy ? null : _newExpense, icon: const Icon(Icons.add), label: const Text('New expense')),
                const SizedBox(height: 10),
                if (state.expenses.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No expenses yet.'))),
                ...state.expenses.map((row) {
                  final mine = _belongsToMe(row['profileId'], own);
                  final status = '${row['status'] ?? 'draft'}';
                  return Card(
                    child: ListTile(
                      title: Text('${row['category'] ?? 'Expense'} • ₹${row['amount'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${row['description'] ?? ''}\n$status', maxLines: 2),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        enabled: !_busy,
                        onSelected: (value) {
                          if (value == 'submit') _run(() => n.submitExpense(_id(row['_id'] ?? row['id'])));
                          if (value == 'approve') _review('expense', _id(row['_id'] ?? row['id']), 'approve');
                          if (value == 'reject') _review('expense', _id(row['_id'] ?? row['id']), 'reject');
                        },
                        itemBuilder: (_) => [
                          if (mine && (status == 'draft' || status == 'rejected')) const PopupMenuItem(value: 'submit', child: Text('Submit')),
                          if (!mine && n.isManager && status == 'submitted') ...[
                            const PopupMenuItem(value: 'approve', child: Text('Approve')),
                            const PopupMenuItem(value: 'reject', child: Text('Reject')),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          RefreshIndicator(
            onRefresh: n.loadPob,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
              children: [
                FilledButton.icon(onPressed: _busy ? null : _newPob, icon: const Icon(Icons.add_shopping_cart), label: const Text('New POB order')),
                const SizedBox(height: 10),
                if (state.pobOrders.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No POB orders yet.'))),
                ...state.pobOrders.map((row) {
                  final account = row['accountId'] is Map ? row['accountId'] as Map : const {};
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.receipt_long_outlined)),
                      title: Text('${row['orderNumber'] ?? 'POB'} • ₹${row['totalAmount'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${account['name'] ?? ''} • ${row['status'] ?? ''}'),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
