import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/mr_provider.dart';

class MrCalls extends ConsumerStatefulWidget {
  const MrCalls({super.key});

  @override
  ConsumerState<MrCalls> createState() => _MrCallsState();
}

class _MrCallsState extends ConsumerState<MrCalls> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final notifier = ref.read(mrProvider.notifier);
      await Future.wait([notifier.loadVisits(), notifier.loadAccounts(), notifier.loadMe()]);
    });
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

  Future<void> _newCall() async {
    final state = ref.read(mrProvider);
    String? accountId;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Plan field call'),
          content: SizedBox(
            width: 440,
            child: DropdownButtonFormField<String>(
              value: accountId,
              decoration: const InputDecoration(labelText: 'Doctor / chemist / account'),
              items: state.accounts.map((account) {
                final id = _id(account['_id'] ?? account['id']);
                return DropdownMenuItem(
                  value: id,
                  child: Text('${account['name'] ?? 'Account'} • ${account['type'] ?? ''}', overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (v) => setLocal(() => accountId = v),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: accountId == null ? null : () => Navigator.pop(context, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (result == true && accountId != null) {
      await _run(() => ref.read(mrProvider.notifier).createVisit(accountId!));
    }
  }

  Future<void> _completeCall(Map<String, dynamic> visit) async {
    final notes = TextEditingController(text: '${visit['discussionNotes'] ?? ''}');
    final feedback = TextEditingController(text: '${visit['doctorFeedback'] ?? ''}');
    final product = TextEditingController();
    final sample = TextEditingController();
    final sampleQty = TextEditingController(text: '0');
    final gift = TextEditingController();
    final giftQty = TextEditingController(text: '0');
    final pob = TextEditingController(text: '${visit['pobAmount'] ?? 0}');

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Complete call / DCR notes'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Discussion notes')),
                const SizedBox(height: 10),
                TextField(controller: feedback, maxLines: 2, decoration: const InputDecoration(labelText: 'Doctor / account feedback')),
                const SizedBox(height: 10),
                TextField(controller: product, decoration: const InputDecoration(labelText: 'Product discussed (optional)')),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: sample, decoration: const InputDecoration(labelText: 'Sample product'))),
                  const SizedBox(width: 8),
                  SizedBox(width: 95, child: TextField(controller: sampleQty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Qty'))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: gift, decoration: const InputDecoration(labelText: 'Gift item'))),
                  const SizedBox(width: 8),
                  SizedBox(width: 95, child: TextField(controller: giftQty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Qty'))),
                ]),
                const SizedBox(height: 10),
                TextField(controller: pob, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'POB amount (optional)')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Check out')),
        ],
      ),
    );

    if (ok != true) return;
    final products = product.text.trim().isEmpty ? null : <Map<String, dynamic>>[{'productName': product.text.trim()}];
    final sq = num.tryParse(sampleQty.text.trim()) ?? 0;
    final samples = sample.text.trim().isEmpty || sq <= 0 ? null : <Map<String, dynamic>>[{'productName': sample.text.trim(), 'quantity': sq}];
    final gq = num.tryParse(giftQty.text.trim()) ?? 0;
    final gifts = gift.text.trim().isEmpty || gq <= 0 ? null : <Map<String, dynamic>>[{'itemName': gift.text.trim(), 'quantity': gq}];
    await _run(() => ref.read(mrProvider.notifier).checkOutVisit(
          _id(visit['_id'] ?? visit['id']),
          discussionNotes: notes.text.trim(),
          doctorFeedback: feedback.text.trim(),
          productsDiscussed: products,
          samples: samples,
          gifts: gifts,
          pobAmount: num.tryParse(pob.text.trim()),
        ));
  }

  Future<void> _review(Map<String, dynamic> visit, String decision) async {
    final comment = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${decision == 'approve' ? 'Approve' : 'Reject'} DCR'),
        content: TextField(controller: comment, maxLines: 2, decoration: const InputDecoration(labelText: 'Manager comment')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(decision == 'approve' ? 'Approve' : 'Reject')),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => ref.read(mrProvider.notifier).reviewVisit(_id(visit['_id'] ?? visit['id']), decision, comment: comment.text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mrProvider);
    final notifier = ref.read(mrProvider.notifier);
    final ownId = notifier.ownProfileId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('DCR / Field Calls'),
        actions: [IconButton(onPressed: _busy ? null : _newCall, icon: const Icon(Icons.add_circle_outline), tooltip: 'Plan call')],
      ),
      body: RefreshIndicator(
        onRefresh: () async => Future.wait([notifier.loadVisits(), notifier.loadAccounts()]),
        child: state.visits.isEmpty
            ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [SizedBox(height: 180), Center(child: Text('No field calls yet.'))])
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                itemCount: state.visits.length,
                itemBuilder: (context, index) {
                  final visit = state.visits[index];
                  final account = visit['accountId'] is Map ? visit['accountId'] as Map : const {};
                  final profile = visit['profileId'];
                  final ownerId = _id(profile);
                  final mine = ownId == null || ownId.isEmpty || ownerId == ownId;
                  final status = '${visit['status'] ?? 'planned'}';
                  final geofence = '${visit['geofenceStatus'] ?? 'unknown'}';
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(child: Text('${account['name'] ?? 'Field call'}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                            _StatusChip(status),
                          ]),
                          const SizedBox(height: 4),
                          Text('${account['type'] ?? ''}${account['specialty'] != null ? ' • ${account['specialty']}' : ''}', style: const TextStyle(color: AppTheme.textSecondary)),
                          if (geofence == 'outside') ...[
                            const SizedBox(height: 6),
                            const Text('Outside configured geofence', style: TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w600)),
                          ],
                          if ('${visit['discussionNotes'] ?? ''}'.trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text('${visit['discussionNotes']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                          ],
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (mine && status == 'planned')
                                FilledButton.tonal(onPressed: _busy ? null : () => _run(() => notifier.checkInVisit(_id(visit['_id'] ?? visit['id']))), child: const Text('GPS check-in')),
                              if (mine && status == 'checked_in')
                                FilledButton(onPressed: _busy ? null : () => _completeCall(visit), child: const Text('Check out + DCR')),
                              if (mine && (status == 'completed' || status == 'rejected'))
                                FilledButton.tonal(onPressed: _busy ? null : () => _run(() => notifier.submitVisit(_id(visit['_id'] ?? visit['id']))), child: const Text('Submit DCR')),
                              if (!mine && notifier.isManager && status == 'submitted') ...[
                                FilledButton.tonal(onPressed: _busy ? null : () => _review(visit, 'approve'), child: const Text('Approve')),
                                OutlinedButton(onPressed: _busy ? null : () => _review(visit, 'reject'), child: const Text('Reject')),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _busy ? null : _newCall, icon: const Icon(Icons.add), label: const Text('Plan call')),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String value;
  const _StatusChip(this.value);
  @override
  Widget build(BuildContext context) {
    final color = switch (value) {
      'approved' => AppTheme.success,
      'submitted' => AppTheme.info,
      'rejected' => AppTheme.error,
      'checked_in' => AppTheme.warning,
      _ => AppTheme.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(value.replaceAll('_', ' '), style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
    );
  }
}
