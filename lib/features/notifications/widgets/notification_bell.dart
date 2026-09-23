import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/notification_provider.dart';
import '../screens/notification_screen.dart';

/// The floating notification button the dashboard shell pins over every tab
/// screen.
///
/// It has to read on two very different backdrops: the pharmacy Home's green
/// hero, and the plain white pages everywhere else. A white disc carried on a
/// drop shadow alone did the first job and disappeared on the second, so the
/// surface now carries a hairline border as well and the glyph takes the
/// signed-in role's accent colour rather than plain slate.
class NotificationBell extends ConsumerWidget {
  /// The role accent, from the shell's `_getRoleColor`. Defaults to the app
  /// primary so the widget is still usable outside the shell.
  final Color? color;

  const NotificationBell({super.key, this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(
      professionalNotificationProvider.select((value) => value.unreadCount),
    );
    final accent = color ?? AppTheme.primary;

    return Material(
      color: Colors.white,
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: accent.withValues(alpha: 0.18)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const ProfessionalNotificationScreen(),
            ),
          );
          ref
              .read(professionalNotificationProvider.notifier)
              .refresh(silent: true);
        },
        child: SizedBox(
          width: 42,
          height: 42,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(child: Icon(LucideIcons.bell, size: 19, color: accent)),
              if (unread > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    constraints: const BoxConstraints(minWidth: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.error,
                      borderRadius: BorderRadius.circular(9),
                      // A white ring keeps the count legible when the badge
                      // lands on a dark backdrop.
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
