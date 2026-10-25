import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/mr_provider.dart';

class MrHome extends ConsumerStatefulWidget {
  const MrHome({super.key});

  @override
  ConsumerState<MrHome> createState() => _MrHomeState();
}

class _MrHomeState extends ConsumerState<MrHome> {
  bool _actionBusy = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(mrProvider.notifier).loadAll());
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Updated successfully')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  bool _isToday(dynamic value) {
    if (value == null) return false;
    final s = value.toString();
    final now = DateTime.now();
    final key =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return s.startsWith(key);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mrProvider);
    final notifier = ref.read(mrProvider.notifier);
    final metrics = state.dashboard['metrics'] is Map
        ? Map<String, dynamic>.from(state.dashboard['metrics'])
        : <String, dynamic>{};
    final profile = state.dashboard['profile'] is Map
        ? Map<String, dynamic>.from(state.dashboard['profile'])
        : state.profile;
    final today = state.attendance.cast<Map<String, dynamic>?>().firstWhere(
      (row) => row != null && _isToday(row['dateKey']),
      orElse: () => null,
    );
    final punchIn = today?['punchIn'];
    final punchOut = today?['punchOut'];
    final punchedIn = punchIn is Map && punchIn['at'] != null;
    final punchedOut = punchOut is Map && punchOut['at'] != null;
    final recent = state.dashboard['recentVisits'] is List
        ? (state.dashboard['recentVisits'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : state.visits.take(5).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${state.dashboard['experience'] ?? profile['designation'] ?? 'MR'} Field Force',
        ),
      ),
      body: RefreshIndicator(
        onRefresh: notifier.loadAll,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
          children: [
            if (state.isLoading && state.dashboard.isEmpty)
              const LinearProgressIndicator(),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 27,
                      backgroundColor: Color(0xFFE0F2FE),
                      child: Icon(
                        Icons.badge_outlined,
                        color: AppTheme.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${profile['name'] ?? profile['userName'] ?? profile['employeeCode'] ?? 'Field user'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            [
                                  profile['employeeCode'],
                                  profile['headquarters'],
                                  profile['division'],
                                ]
                                .where(
                                  (e) => e != null && '$e'.trim().isNotEmpty,
                                )
                                .join(' • '),
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Today\'s workday',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _actionBusy || punchedIn
                                ? null
                                : () => _run(() => notifier.punchIn()),
                            icon: const Icon(Icons.login),
                            label: Text(punchedIn ? 'Started' : 'Start work'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _actionBusy || !punchedIn || punchedOut
                                ? null
                                : () => _run(notifier.punchOut),
                            icon: const Icon(Icons.logout),
                            label: Text(punchedOut ? 'Ended' : 'End work'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      punchedOut
                          ? 'Workday completed for today.'
                          : punchedIn
                          ? 'GPS attendance is active for today.'
                          : 'Start work records server time plus current GPS.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _Metric(
                  label: 'Calls',
                  value: '${metrics['calls'] ?? 0}',
                  icon: Icons.call_outlined,
                ),
                _Metric(
                  label: 'Doctors',
                  value: '${metrics['doctorCalls'] ?? 0}',
                  icon: Icons.medical_services_outlined,
                ),
                _Metric(
                  label: 'POB',
                  value: '₹${metrics['pobAmount'] ?? 0}',
                  icon: Icons.receipt_long_outlined,
                ),
                _Metric(
                  label: 'Work days',
                  value: '${metrics['workingDays'] ?? 0}',
                  icon: Icons.calendar_today_outlined,
                ),
                if ((metrics['teamSize'] ?? 0) != 0)
                  _Metric(
                    label: 'Team',
                    value: '${metrics['teamSize']}',
                    icon: Icons.groups_outlined,
                  ),
                if ((metrics['pendingApprovals'] ?? 0) != 0)
                  _Metric(
                    label: 'Approvals',
                    value: '${metrics['pendingApprovals']}',
                    icon: Icons.pending_actions_outlined,
                  ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Recent field calls',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (recent.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('No calls recorded yet.'),
                ),
              )
            else
              ...recent.map((visit) {
                final account = visit['accountId'] is Map
                    ? visit['accountId'] as Map
                    : const {};
                final profileRow = visit['profileId'] is Map
                    ? visit['profileId'] as Map
                    : const {};
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.location_on_outlined),
                    ),
                    title: Text('${account['name'] ?? 'Field call'}'),
                    subtitle: Text(
                      [
                        account['type'],
                        profileRow['employeeCode'],
                        visit['status'],
                      ].where((e) => e != null).join(' • '),
                    ),
                    trailing: visit['geofenceStatus'] == 'outside'
                        ? const Icon(
                            Icons.warning_amber,
                            color: AppTheme.warning,
                          )
                        : null,
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _Metric({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 42) / 2;
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
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
            ],
          ),
        ),
      ),
    );
  }
}
