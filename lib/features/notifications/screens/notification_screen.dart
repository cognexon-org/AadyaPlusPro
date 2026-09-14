import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/notification_provider.dart';

class ProfessionalNotificationScreen extends ConsumerStatefulWidget {
  const ProfessionalNotificationScreen({super.key});

  @override
  ConsumerState<ProfessionalNotificationScreen> createState() =>
      _ProfessionalNotificationScreenState();
}

class _ProfessionalNotificationScreenState
    extends ConsumerState<ProfessionalNotificationScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(professionalNotificationProvider.notifier).refresh(),
    );
  }

  String _when(dynamic value) {
    if (value == null) return '';
    final dt = DateTime.tryParse(value.toString())?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(professionalNotificationProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (state.unreadCount > 0)
            TextButton(
              onPressed: () => ref
                  .read(professionalNotificationProvider.notifier)
                  .markAllRead(),
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(professionalNotificationProvider.notifier).refresh(),
        child: state.isLoading && state.notifications.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : state.notifications.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 180),
                      Icon(Icons.notifications_none, size: 54, color: AppTheme.textTertiary),
                      SizedBox(height: 12),
                      Center(child: Text('No notifications yet')),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    itemCount: state.notifications.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final row = state.notifications[index];
                      final id = '${row['_id'] ?? row['id'] ?? ''}';
                      final unread = row['read'] != true;
                      final title = '${row['title'] ?? 'Notification'}';
                      final message = '${row['message'] ?? ''}';
                      final type = '${row['type'] ?? 'update'}';
                      return Dismissible(
                        key: ValueKey(id.isEmpty ? 'notification-$index' : id),
                        direction: id.isEmpty
                            ? DismissDirection.none
                            : DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          decoration: BoxDecoration(
                            color: AppTheme.error,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.delete_outline, color: Colors.white),
                        ),
                        onDismissed: (_) => ref
                            .read(professionalNotificationProvider.notifier)
                            .delete(id),
                        child: Card(
                          color: unread ? const Color(0xFFF0F9FF) : Colors.white,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: id.isEmpty || !unread
                                ? null
                                : () => ref
                                    .read(professionalNotificationProvider.notifier)
                                    .markRead(id),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                                    child: const Icon(Icons.notifications_outlined, color: AppTheme.primary),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                title,
                                                style: TextStyle(
                                                  fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                                                  color: AppTheme.textPrimary,
                                                ),
                                              ),
                                            ),
                                            if (unread)
                                              Container(
                                                width: 8,
                                                height: 8,
                                                decoration: const BoxDecoration(
                                                  color: AppTheme.primary,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                          ],
                                        ),
                                        if (message.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(message, style: const TextStyle(color: AppTheme.textSecondary)),
                                        ],
                                        const SizedBox(height: 10),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          children: [
                                            Text(type.replaceAll('_', ' '), style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary)),
                                            Text(_when(row['createdAt']), style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
