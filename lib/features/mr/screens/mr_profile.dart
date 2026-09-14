import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/mr_provider.dart';

class MrProfile extends ConsumerStatefulWidget {
  const MrProfile({super.key});

  @override
  ConsumerState<MrProfile> createState() => _MrProfileState();
}

class _MrProfileState extends ConsumerState<MrProfile> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final n = ref.read(mrProvider.notifier);
      await Future.wait([n.loadMe(), n.loadTerritories(), n.loadSamples(), n.loadDetailing()]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mrProvider);
    final profile = state.profile;
    final user = profile['userId'] is Map ? profile['userId'] as Map : const {};
    return Scaffold(
      appBar: AppBar(title: const Text('Field Profile')),
      body: RefreshIndicator(
        onRefresh: () async {
          final n = ref.read(mrProvider.notifier);
          await Future.wait([n.loadMe(), n.loadTerritories(), n.loadSamples(), n.loadDetailing()]);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const CircleAvatar(radius: 30, child: Icon(Icons.badge_outlined, size: 30)),
                  const SizedBox(height: 12),
                  Text('${user['name'] ?? profile['employeeCode'] ?? 'Field user'}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('${profile['designation'] ?? 'MR'} • ${profile['employeeCode'] ?? ''}', style: const TextStyle(color: AppTheme.textSecondary)),
                  if ('${profile['headquarters'] ?? ''}'.isNotEmpty) Text('HQ: ${profile['headquarters']}', style: const TextStyle(color: AppTheme.textSecondary)),
                  if ('${profile['division'] ?? ''}'.isNotEmpty) Text('Division: ${profile['division']}', style: const TextStyle(color: AppTheme.textSecondary)),
                  if ('${profile['productLine'] ?? ''}'.isNotEmpty) Text('Product line: ${profile['productLine']}', style: const TextStyle(color: AppTheme.textSecondary)),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Territories', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (state.territories.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No territories assigned.')))
            else
              ...state.territories.map((t) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.map_outlined, color: AppTheme.primary),
                      title: Text('${t['name'] ?? t['code'] ?? 'Territory'}'),
                      subtitle: Text([t['city'], t['state'], t['headquarters']].where((e) => e != null && '$e'.isNotEmpty).join(' • ')),
                    ),
                  )),
            const SizedBox(height: 14),
            const Text('Samples & gifts balance', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (state.sampleBalances.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No sample/gift ledger entries.')))
            else
              ...state.sampleBalances.take(12).map((b) => Card(
                    child: ListTile(
                      leading: Icon(b['itemType'] == 'gift' ? Icons.card_giftcard : Icons.science_outlined),
                      title: Text('${b['productName'] ?? 'Item'}'),
                      subtitle: Text('${b['itemType'] ?? 'sample'}${'${b['batchNumber'] ?? ''}'.isNotEmpty ? ' • Batch ${b['batchNumber']}' : ''}'),
                      trailing: Text('${b['balance'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  )),
            const SizedBox(height: 14),
            const Text('e-Detailing library', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (state.detailing.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No active detailing content.')))
            else
              ...state.detailing.take(10).map((d) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.slideshow_outlined, color: AppTheme.primary),
                      title: Text('${d['title'] ?? 'Detailing content'}'),
                      subtitle: Text('${d['productName'] ?? ''} • ${d['contentType'] ?? ''}'),
                    ),
                  )),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () async {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted) Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
              },
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
