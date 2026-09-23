import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_form_fields.dart';
import '../providers/mr_provider.dart';

class MrTeam extends ConsumerStatefulWidget {
  const MrTeam({super.key});

  @override
  ConsumerState<MrTeam> createState() => _MrTeamState();
}

class _MrTeamState extends ConsumerState<MrTeam> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final n = ref.read(mrProvider.notifier);
      await Future.wait([
        n.loadMe(),
        n.loadTeam(),
        n.loadTargets(),
        n.loadVisits(),
        n.loadExpenses(),
        n.loadPlans(),
      ]);
      if (n.isManager) await n.loadAnalytics();
    });
  }

  String _id(dynamic value) {
    if (value is Map) return '${value['_id'] ?? value['id'] ?? ''}';
    return '$value';
  }

  String _monthKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  Future<void> _setTarget(Map<String, dynamic> profile) async {
    final calls = TextEditingController(text: '0');
    final pob = TextEditingController(text: '0');
    final days = TextEditingController(text: '0');
    final ok = await AppDialog.show<bool>(
      context,
      title: 'Set Target',
      subtitle: '${profile['name'] ?? profile['employeeCode'] ?? ''}',
      icon: CupertinoIcons.scope,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            label: 'Call target',
            controller: calls,
            isNum: true,
            icon: CupertinoIcons.phone,
          ),
          AppTextField(
            label: 'POB target (₹)',
            controller: pob,
            isDecimal: true,
            icon: CupertinoIcons.money_dollar,
          ),
          AppTextField(
            label: 'Working days target',
            controller: days,
            isNum: true,
            icon: CupertinoIcons.calendar,
            margin: EdgeInsets.zero,
          ),
        ],
      ),
      actions: [
        AppDialog.cancelButton(context),
        AppDialog.primaryButton('Save', () => Navigator.pop(context, true)),
      ],
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(mrProvider.notifier)
          .setTarget(
            profileId: _id(profile['id'] ?? profile['_id']),
            month: _monthKey(DateTime.now()),
            callTarget: num.tryParse(calls.text.trim()) ?? 0,
            pobTarget: num.tryParse(pob.text.trim()) ?? 0,
            workingDaysTarget: num.tryParse(days.text.trim()) ?? 0,
          );
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Target updated')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mrProvider);
    final n = ref.read(mrProvider.notifier);
    final totals = state.analytics['totals'] is Map
        ? state.analytics['totals'] as Map
        : const {};
    final performance = state.analytics['performance'] is List
        ? (state.analytics['performance'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : <Map<String, dynamic>>[];

    if (!n.isManager) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Targets')),
        body: RefreshIndicator(
          onRefresh: n.loadTargets,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
            children: [
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Manager analytics are available to ABM, RBM and ZSM. Your personal monthly target is shown below.',
                  ),
                ),
              ),
              ...state.targets.map((row) {
                final profile = row['profile'] is Map
                    ? row['profile'] as Map
                    : const {};
                final own =
                    _id(profile['id'] ?? profile['_id']) == n.ownProfileId;
                if (!own) return const SizedBox.shrink();
                final target = row['target'] is Map
                    ? row['target'] as Map
                    : const {};
                final ach = row['achievement'] is Map
                    ? row['achievement'] as Map
                    : const {};
                return _TargetCard(target: target, achievement: ach);
              }),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('${n.designation} Team')),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            n.loadTeam(),
            n.loadTargets(),
            n.loadVisits(),
            n.loadExpenses(),
            n.loadPlans(),
          ]);
          await n.loadAnalytics();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _Stat(
                  label: 'Field users',
                  value: '${totals['fieldUsers'] ?? state.team.length}',
                ),
                _Stat(label: 'Calls', value: '${totals['calls'] ?? 0}'),
                _Stat(label: 'POB', value: '₹${totals['pobAmount'] ?? 0}'),
                _Stat(label: 'Expenses', value: '₹${totals['expenses'] ?? 0}'),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Performance',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (performance.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No performance data for this month.'),
                ),
              )
            else
              ...performance.map((row) {
                final profile = row['profile'] is Map
                    ? row['profile'] as Map
                    : const {};
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.person_outline),
                    ),
                    title: Text(
                      '${profile['name'] ?? profile['employeeCode'] ?? 'Field user'}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${profile['designation'] ?? ''} • Calls ${row['calls'] ?? 0} • POB ₹${row['pobAmount'] ?? 0}',
                    ),
                    trailing: row['achievementPercent'] == null
                        ? null
                        : Text(
                            '${row['achievementPercent']}%',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primary,
                            ),
                          ),
                  ),
                );
              }),
            const SizedBox(height: 18),
            const Text(
              'Team & targets',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...state.team.map((profile) {
              final id = _id(profile['id'] ?? profile['_id']);
              final isSelf = id == n.ownProfileId;
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      '${profile['designation'] ?? 'MR'}'.substring(0, 1),
                    ),
                  ),
                  title: Text(
                    '${profile['name'] ?? profile['employeeCode'] ?? 'Field user'}',
                  ),
                  subtitle: Text(
                    '${profile['designation'] ?? ''} • ${profile['headquarters'] ?? ''}',
                  ),
                  trailing: isSelf || _busy
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.track_changes_outlined),
                          tooltip: 'Set target',
                          onPressed: () => _setTarget(profile),
                        ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 42) / 2;
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TargetCard extends StatelessWidget {
  final Map target;
  final Map achievement;
  const _TargetCard({required this.target, required this.achievement});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Month ${target['month'] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              'Calls: ${achievement['calls'] ?? 0} / ${target['callTarget'] ?? 0}',
            ),
            Text(
              'POB: ₹${achievement['pob'] ?? 0} / ₹${target['pobTarget'] ?? 0}',
            ),
            Text(
              'Working days: ${achievement['workingDays'] ?? 0} / ${target['workingDaysTarget'] ?? 0}',
            ),
          ],
        ),
      ),
    );
  }
}
