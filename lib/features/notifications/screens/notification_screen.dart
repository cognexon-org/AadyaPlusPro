import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/notifications/professional_notification_navigation_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../pharmacy/theme/pharmacy_colors.dart';
import '../../pharmacy/theme/pharmacy_type.dart';
import '../../pharmacy/widgets/pharmacy_ui.dart';
import '../providers/notification_provider.dart';

/// The notification centre, in the app's minimal style: grouped by day,
/// one quiet row per notification, an icon that says what kind it is.
///
/// Shared by every professional role, so the accent (unread dot, actions)
/// is the role colour the bell passes in.
class ProfessionalNotificationScreen extends ConsumerStatefulWidget {
  final Color? accent;
  const ProfessionalNotificationScreen({super.key, this.accent});

  @override
  ConsumerState<ProfessionalNotificationScreen> createState() =>
      _ProfessionalNotificationScreenState();
}

class _ProfessionalNotificationScreenState
    extends ConsumerState<ProfessionalNotificationScreen> {
  Color get _accent => widget.accent ?? AppTheme.primary;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(professionalNotificationProvider.notifier).refresh(),
    );
  }

  static DateTime? _date(dynamic value) =>
      DateTime.tryParse('${value ?? ''}')?.toLocal();

  static String _when(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}';
  }

  static String _bucket(DateTime? dt) {
    if (dt == null) return 'Earlier';
    final now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(dt.year, dt.month, dt.day)).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    return 'Earlier';
  }

  /// An icon that says what the notification is about, read from its type
  /// or the entity it points at.
  static IconData _icon(Map<String, dynamic> row) {
    final key = '${row['relatedEntity'] ?? ''} ${row['type'] ?? ''}'
        .toLowerCase();
    if (key.contains('prescription')) return LucideIcons.fileText;
    if (key.contains('payment') ||
        key.contains('payout') ||
        key.contains('settlement')) {
      return LucideIcons.wallet;
    }
    if (key.contains('stock') || key.contains('expir')) {
      return LucideIcons.packageSearch;
    }
    if (key.contains('order')) return LucideIcons.shoppingBag;
    if (key.contains('appointment') || key.contains('booking')) {
      return LucideIcons.calendar;
    }
    if (key.contains('chat') || key.contains('message')) {
      return LucideIcons.messageSquare;
    }
    if (key.contains('verif')) return LucideIcons.badgeCheck;
    return LucideIcons.bell;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(professionalNotificationProvider);
    final rows = state.notifications;

    final groups = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      groups.putIfAbsent(_bucket(_date(r['createdAt'])), () => []).add(r);
    }
    const order = ['Today', 'Yesterday', 'Earlier'];

    return Scaffold(
      backgroundColor: PharmacyColors.bg,
      appBar: AppBar(
        backgroundColor: PharmacyColors.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: PharmacyColors.textPrimary),
        title: Text(
          'Notifications',
          style: PharmacyType.sans(
            fontSize: PharmacyType.title,
            fontWeight: FontWeight.w700,
            color: PharmacyColors.textStrong,
          ),
        ),
        actions: [
          if (state.unreadCount > 0)
            TextButton(
              onPressed: () => ref
                  .read(professionalNotificationProvider.notifier)
                  .markAllRead(),
              child: Text(
                'Mark all read',
                style: PharmacyType.sans(
                  fontSize: PharmacyType.small,
                  fontWeight: FontWeight.w600,
                  color: _accent,
                ),
              ),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: PharmacyScrollScope(
        child: RefreshIndicator(
          color: _accent,
          onRefresh: () =>
              ref.read(professionalNotificationProvider.notifier).refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (state.isLoading && rows.isEmpty)
                const PharmacyListSkeleton(count: 5)
              else if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: PharmacyEmptyStateInline(
                    icon: LucideIcons.bellOff,
                    text:
                        'No notifications yet.\nNew orders and updates will appear here.',
                  ),
                )
              else ...[
                if (state.unreadCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      '${state.unreadCount} unread',
                      style: PharmacyType.sans(
                        fontSize: PharmacyType.small,
                        fontWeight: FontWeight.w500,
                        color: PharmacyColors.textSecondary,
                      ),
                    ),
                  ),
                for (final (gi, title)
                    in order.where(groups.containsKey).indexed) ...[
                  if (gi > 0) const SizedBox(height: 22),
                  PharmacyEntrance(
                    index: gi,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PharmacySectionTitle(title),
                        PharmacyGroup(
                          children: [
                            for (final (i, row) in groups[title]!.indexed) ...[
                              if (i > 0) const PharmacyHairline(),
                              _row(row, i),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    'Swipe left on a notification to delete it',
                    style: PharmacyType.sans(
                      fontSize: PharmacyType.caption,
                      color: PharmacyColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(Map<String, dynamic> row, int index) {
    final id = '${row['_id'] ?? row['id'] ?? ''}';
    final unread = row['read'] != true;
    final title = '${row['title'] ?? 'Notification'}';
    final message = '${row['message'] ?? ''}'.trim();
    final when = _when(_date(row['createdAt']));

    final content = PharmacyPressable(
      scale: 0.99,
      // Tapping goes where the notification points — an order notification
      // opens that order — and marks it read on the way.
      onTap: () {
        if (id.isNotEmpty && unread) {
          ref.read(professionalNotificationProvider.notifier).markRead(id);
        }
        ProfessionalNotificationNavigationService.instance.openFromRecord(row);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: PharmacyColors.bg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _icon(row),
                size: 17,
                color: unread ? _accent : PharmacyColors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: PharmacyType.sans(
                            fontSize: PharmacyType.body,
                            fontWeight: unread
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: unread
                                ? PharmacyColors.textStrong
                                : PharmacyColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        when,
                        style: PharmacyType.sans(
                          fontSize: PharmacyType.caption,
                          color: PharmacyColors.textTertiary,
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(width: 6),
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: _accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (message.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: PharmacyType.sans(
                        fontSize: PharmacyType.small,
                        height: 1.4,
                        color: PharmacyColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (id.isEmpty) return content;
    return Dismissible(
      key: ValueKey(id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: PharmacyColors.error,
        child: const Icon(LucideIcons.trash2, color: Colors.white, size: 18),
      ),
      onDismissed: (_) =>
          ref.read(professionalNotificationProvider.notifier).delete(id),
      child: content,
    );
  }
}
