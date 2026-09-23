import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_form_fields.dart';
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
      await Future.wait([
        notifier.loadVisits(),
        notifier.loadAccounts(),
        notifier.loadMe(),
      ]);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Updated successfully')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
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
    final accountId = ValueNotifier<String?>(null);
    final result = await AppDialog.show<bool>(
      context,
      title: 'Plan field call',
      subtitle: 'Schedule a visit to a doctor, chemist or account',
      icon: CupertinoIcons.calendar_badge_plus,
      content: ValueListenableBuilder<String?>(
        valueListenable: accountId,
        builder: (context, value, _) => AppDropdownField<String>(
          label: 'Doctor / chemist / account',
          value: value,
          icon: CupertinoIcons.person_2,
          margin: EdgeInsets.zero,
          items: state.accounts.map((account) {
            final id = _id(account['_id'] ?? account['id']);
            return DropdownMenuItem(
              value: id,
              child: Text(
                '${account['name'] ?? 'Account'} • ${account['type'] ?? ''}',
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: (v) => accountId.value = v,
        ),
      ),
      actions: [
        AppDialog.cancelButton(context),
        ValueListenableBuilder<String?>(
          valueListenable: accountId,
          builder: (context, value, _) => AppDialog.primaryButton(
            'Create',
            value == null ? null : () => Navigator.pop(context, true),
          ),
        ),
      ],
    );
    if (result == true && accountId.value != null) {
      await _run(
        () => ref.read(mrProvider.notifier).createVisit(accountId.value!),
      );
    }
  }

  Future<void> _completeCall(Map<String, dynamic> visit) async {
    final notes = TextEditingController(
      text: '${visit['discussionNotes'] ?? ''}',
    );
    final feedback = TextEditingController(
      text: '${visit['doctorFeedback'] ?? ''}',
    );
    final product = TextEditingController();
    final sample = TextEditingController();
    final sampleQty = TextEditingController(text: '0');
    final gift = TextEditingController();
    final giftQty = TextEditingController(text: '0');
    final pob = TextEditingController(text: '${visit['pobAmount'] ?? 0}');

    final ok = await AppDialog.show<bool>(
      context,
      title: 'Complete call / DCR notes',
      subtitle: 'Record what happened during this visit',
      icon: CupertinoIcons.doc_checkmark,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            label: 'Discussion notes',
            controller: notes,
            icon: CupertinoIcons.chat_bubble_text,
            maxLines: 3,
          ),
          AppTextField(
            label: 'Doctor / account feedback',
            controller: feedback,
            icon: CupertinoIcons.quote_bubble,
            maxLines: 2,
          ),
          AppTextField(
            label: 'Product discussed',
            controller: product,
            icon: CupertinoIcons.cube_box,
            hint: 'Optional',
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Sample product',
                  controller: sample,
                  icon: CupertinoIcons.bag,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(
                  label: 'Sample qty',
                  controller: sampleQty,
                  isNum: true,
                  icon: CupertinoIcons.number,
                ),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Gift item',
                  controller: gift,
                  icon: CupertinoIcons.gift,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppTextField(
                  label: 'Gift qty',
                  controller: giftQty,
                  isNum: true,
                  icon: CupertinoIcons.number,
                ),
              ),
            ],
          ),
          AppTextField(
            label: 'POB amount',
            controller: pob,
            isDecimal: true,
            icon: CupertinoIcons.money_dollar,
            hint: 'Optional',
            margin: EdgeInsets.zero,
          ),
        ],
      ),
      actions: [
        AppDialog.cancelButton(context),
        AppDialog.primaryButton(
          'Check out',
          () => Navigator.pop(context, true),
        ),
      ],
    );

    if (ok != true) return;
    final products = product.text.trim().isEmpty
        ? null
        : <Map<String, dynamic>>[
            {'productName': product.text.trim()},
          ];
    final sq = num.tryParse(sampleQty.text.trim()) ?? 0;
    final samples = sample.text.trim().isEmpty || sq <= 0
        ? null
        : <Map<String, dynamic>>[
            {'productName': sample.text.trim(), 'quantity': sq},
          ];
    final gq = num.tryParse(giftQty.text.trim()) ?? 0;
    final gifts = gift.text.trim().isEmpty || gq <= 0
        ? null
        : <Map<String, dynamic>>[
            {'itemName': gift.text.trim(), 'quantity': gq},
          ];
    await _run(
      () => ref
          .read(mrProvider.notifier)
          .checkOutVisit(
            _id(visit['_id'] ?? visit['id']),
            discussionNotes: notes.text.trim(),
            doctorFeedback: feedback.text.trim(),
            productsDiscussed: products,
            samples: samples,
            gifts: gifts,
            pobAmount: num.tryParse(pob.text.trim()),
          ),
    );
  }

  Future<void> _review(Map<String, dynamic> visit, String decision) async {
    final comment = TextEditingController();
    final approve = decision == 'approve';
    final ok = await AppDialog.show<bool>(
      context,
      title: '${approve ? 'Approve' : 'Reject'} DCR',
      icon: approve ? CupertinoIcons.checkmark_seal : CupertinoIcons.xmark_seal,
      accentColor: approve ? AppTheme.success : AppTheme.error,
      content: AppTextField(
        label: 'Manager comment',
        controller: comment,
        icon: CupertinoIcons.chat_bubble_text,
        maxLines: 2,
        margin: EdgeInsets.zero,
      ),
      actions: [
        AppDialog.cancelButton(context),
        AppDialog.primaryButton(
          approve ? 'Approve' : 'Reject',
          () => Navigator.pop(context, true),
          color: approve ? AppTheme.success : AppTheme.error,
        ),
      ],
    );
    if (ok == true) {
      await _run(
        () => ref
            .read(mrProvider.notifier)
            .reviewVisit(
              _id(visit['_id'] ?? visit['id']),
              decision,
              comment: comment.text.trim(),
            ),
      );
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
        actions: [
          IconButton(
            onPressed: _busy ? null : _newCall,
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Plan call',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async =>
            Future.wait([notifier.loadVisits(), notifier.loadAccounts()]),
        child: state.visits.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 180),
                  Center(child: Text('No field calls yet.')),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                itemCount: state.visits.length,
                itemBuilder: (context, index) {
                  final visit = state.visits[index];
                  final account = visit['accountId'] is Map
                      ? visit['accountId'] as Map
                      : const {};
                  final profile = visit['profileId'];
                  final ownerId = _id(profile);
                  final mine =
                      ownId == null || ownId.isEmpty || ownerId == ownId;
                  final status = '${visit['status'] ?? 'planned'}';
                  final geofence = '${visit['geofenceStatus'] ?? 'unknown'}';
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${account['name'] ?? 'Field call'}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              _StatusChip(status),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${account['type'] ?? ''}${account['specialty'] != null ? ' • ${account['specialty']}' : ''}',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          if (geofence == 'outside') ...[
                            const SizedBox(height: 6),
                            const Text(
                              'Outside configured geofence',
                              style: TextStyle(
                                color: AppTheme.warning,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if ('${visit['discussionNotes'] ?? ''}'
                              .trim()
                              .isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              '${visit['discussionNotes']}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (mine && status == 'planned')
                                FilledButton.tonal(
                                  onPressed: _busy
                                      ? null
                                      : () => _run(
                                          () => notifier.checkInVisit(
                                            _id(visit['_id'] ?? visit['id']),
                                          ),
                                        ),
                                  child: const Text('GPS check-in'),
                                ),
                              if (mine && status == 'checked_in')
                                FilledButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _completeCall(visit),
                                  child: const Text('Check out + DCR'),
                                ),
                              if (mine &&
                                  (status == 'completed' ||
                                      status == 'rejected'))
                                FilledButton.tonal(
                                  onPressed: _busy
                                      ? null
                                      : () => _run(
                                          () => notifier.submitVisit(
                                            _id(visit['_id'] ?? visit['id']),
                                          ),
                                        ),
                                  child: const Text('Submit DCR'),
                                ),
                              if (!mine &&
                                  notifier.isManager &&
                                  status == 'submitted') ...[
                                FilledButton.tonal(
                                  onPressed: _busy
                                      ? null
                                      : () => _review(visit, 'approve'),
                                  child: const Text('Approve'),
                                ),
                                OutlinedButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _review(visit, 'reject'),
                                  child: const Text('Reject'),
                                ),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _newCall,
        icon: const Icon(Icons.add),
        label: const Text('Plan call'),
      ),
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
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        value.replaceAll('_', ' '),
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
