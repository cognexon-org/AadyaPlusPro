import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_service.dart';

class ProfessionalNotificationState {
  final List<Map<String, dynamic>> notifications;
  final int unreadCount;
  final bool isLoading;
  final String? error;

  const ProfessionalNotificationState({
    this.notifications = const [],
    this.unreadCount = 0,
    this.isLoading = false,
    this.error,
  });

  ProfessionalNotificationState copyWith({
    List<Map<String, dynamic>>? notifications,
    int? unreadCount,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return ProfessionalNotificationState(
      notifications: notifications ?? this.notifications,
      unreadCount: unreadCount ?? this.unreadCount,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class ProfessionalNotificationNotifier
    extends StateNotifier<ProfessionalNotificationState> {
  final ApiService _api = ApiService();

  ProfessionalNotificationNotifier()
      : super(const ProfessionalNotificationState());

  Future<void> refresh({bool silent = false}) async {
    if (!silent) state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await _api.getNotifications();
      final data = response.data;
      final raw = data is Map ? data['notifications'] : null;
      final list = raw is List
          ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      final unread = data is Map
          ? int.tryParse('${data['unreadCount'] ?? 0}') ?? 0
          : 0;
      state = ProfessionalNotificationState(
        notifications: list,
        unreadCount: unread,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> markRead(String id) async {
    try {
      await _api.markNotificationRead(id);
      final updated = state.notifications.map((row) {
        if ('${row['_id'] ?? row['id']}' != id) return row;
        return {...row, 'read': true, 'readAt': DateTime.now().toIso8601String()};
      }).toList();
      final unread = updated.where((row) => row['read'] != true).length;
      state = state.copyWith(notifications: updated, unreadCount: unread);
    } catch (_) {
      await refresh(silent: true);
    }
  }

  Future<void> markAllRead() async {
    try {
      await _api.markAllNotificationsRead();
      final updated = state.notifications
          .map((row) => {...row, 'read': true})
          .toList();
      state = state.copyWith(notifications: updated, unreadCount: 0);
    } catch (_) {
      await refresh(silent: true);
    }
  }

  Future<void> delete(String id) async {
    final previous = state;
    final updated = state.notifications
        .where((row) => '${row['_id'] ?? row['id']}' != id)
        .toList();
    final unread = updated.where((row) => row['read'] != true).length;
    state = state.copyWith(notifications: updated, unreadCount: unread);
    try {
      await _api.deleteNotification(id);
    } catch (_) {
      state = previous;
      await refresh(silent: true);
    }
  }
}

final professionalNotificationProvider = StateNotifierProvider<
    ProfessionalNotificationNotifier, ProfessionalNotificationState>(
  (ref) => ProfessionalNotificationNotifier(),
);
