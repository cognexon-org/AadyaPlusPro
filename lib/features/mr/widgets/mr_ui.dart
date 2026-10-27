import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../providers/mr_provider.dart';

/// Tabs of the field-force dashboard, in the shell's order.
class MrTab {
  MrTab._();
  static const today = 0;
  static const calls = 1;
  static const plan = 2;
  static const team = 3; // Customers for a rep
  static const profile = 4;
}

// Shared pieces of the field-force screens: how statuses read, account
// types, dates and money, the avatar, and the toast.

/// How a field status reads: a plain label and one tone.
({String label, Color color, IconData icon}) mrStatus(String? raw) {
  switch ((raw ?? '').toLowerCase()) {
    case 'planned':
      return (label: 'Planned', color: AppColors.textSecondary, icon: LucideIcons.calendarClock);
    case 'checked_in':
      return (label: 'Checked in', color: const Color(0xFF2563EB), icon: LucideIcons.mapPinCheck);
    case 'completed':
      return (label: 'Report due', color: AppColors.warning, icon: LucideIcons.filePen);
    case 'submitted':
    case 'pending':
      return (label: 'Awaiting review', color: const Color(0xFF7C3AED), icon: LucideIcons.hourglass);
    case 'approved':
      return (label: 'Approved', color: AppColors.success, icon: LucideIcons.circleCheck);
    case 'rejected':
      return (label: 'Sent back', color: AppColors.error, icon: LucideIcons.undo2);
    case 'draft':
      return (label: 'Draft', color: AppColors.textSecondary, icon: LucideIcons.pencil);
    case 'paid':
      return (label: 'Paid', color: AppColors.success, icon: LucideIcons.badgeIndianRupee);
    case 'placed':
      return (label: 'Placed', color: const Color(0xFF2563EB), icon: LucideIcons.receipt);
    case 'accepted':
      return (label: 'Accepted', color: const Color(0xFF7C3AED), icon: LucideIcons.circleCheck);
    case 'fulfilled':
      return (label: 'Fulfilled', color: AppColors.success, icon: LucideIcons.packageCheck);
    case 'cancelled':
      return (label: 'Cancelled', color: AppColors.error, icon: LucideIcons.circleX);
    default:
      final s = (raw ?? '').replaceAll('_', ' ');
      return (label: s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1), color: AppColors.textSecondary, icon: LucideIcons.circleDot);
  }
}

class MrStatusPill extends StatelessWidget {
  final String? status;
  final bool icon;
  const MrStatusPill(this.status, {super.key, this.icon = false});

  @override
  Widget build(BuildContext context) {
    final s = mrStatus(status);
    return AppStatusPill(
      text: s.label,
      color: s.color,
      background: Color.alphaBlend(s.color.withValues(alpha: 0.1), Colors.white),
      icon: icon ? s.icon : null,
    );
  }
}

/// Doctor, chemist, stockist or hospital.
({String label, IconData icon}) accountKind(String? type) => switch (type) {
  'chemist' => (label: 'Chemist', icon: LucideIcons.pill),
  'stockist' => (label: 'Stockist', icon: LucideIcons.warehouse),
  'hospital' => (label: 'Hospital', icon: LucideIcons.hospital),
  _ => (label: 'Doctor', icon: LucideIcons.stethoscope),
};

const expenseCategories = <String, (String, IconData)>{
  'travel': ('Travel', LucideIcons.car),
  'daily_allowance': ('Daily allowance', LucideIcons.wallet),
  'lodging': ('Lodging', LucideIcons.bedDouble),
  'meals': ('Meals', LucideIcons.utensils),
  'local_conveyance': ('Local conveyance', LucideIcons.bike),
  'phone': ('Phone', LucideIcons.smartphone),
  'meeting': ('Meeting', LucideIcons.users),
  'other': ('Other', LucideIcons.receipt),
};

const workTypes = <String, (String, IconData)>{
  'field': ('Field work', LucideIcons.mapPinned),
  'office': ('Office', LucideIcons.building2),
  'meeting': ('Meeting', LucideIcons.users),
  'training': ('Training', LucideIcons.graduationCap),
};

const leaveTypes = <String, String>{
  'casual': 'Casual',
  'sick': 'Sick',
  'earned': 'Earned',
  'other': 'Other',
};

DateTime? mrDate(dynamic v) => DateTime.tryParse('${v ?? ''}')?.toLocal();

String dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  if (day == today.add(const Duration(days: 1))) return 'Tomorrow';
  return DateFormat('EEE d MMM').format(d);
}

String timeLabel(DateTime d) => DateFormat('h:mm a').format(d);

/// "2h 14m" for a duration.
String durationLabel(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

/// The rep's name on a populated profile reference.
String repName(dynamic profile) {
  final p = mapOf(profile);
  final user = mapOf(p['userId']);
  final name = '${user['name'] ?? p['name'] ?? ''}'.trim();
  if (name.isNotEmpty) return name;
  return '${p['employeeCode'] ?? 'Field rep'}';
}

class MrAvatar extends StatelessWidget {
  final String name;
  final double size;
  final IconData? icon;
  const MrAvatar({super.key, required this.name, this.size = 40, this.icon});

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initials = words.isEmpty
        ? '?'
        : (words.first[0] + (words.length > 1 ? words.last[0] : '')).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: accent.veryLight, borderRadius: BorderRadius.circular(size * 0.32)),
      child: icon != null
          ? Icon(icon, size: size * 0.46, color: accent.color)
          : Text(initials, style: AppType.sans(fontSize: size * 0.36, fontWeight: FontWeight.w800, color: accent.color)),
    );
  }
}

void mrToast(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  if (error) HapticFeedback.heavyImpact();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message, style: AppType.sans(fontSize: AppType.caption, color: Colors.white)),
      backgroundColor: error ? AppColors.error : AppColors.textStrong,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Runs [action], toasting its error; true when it succeeded.
Future<bool> mrRun(BuildContext context, Future<void> Function() action, {String? done}) async {
  try {
    await action();
    if (done != null && context.mounted) mrToast(context, done);
    return true;
  } catch (e) {
    if (context.mounted) mrToast(context, '$e', error: true);
    return false;
  }
}

/// A screen header: title, a line under it, and room for actions.
class MrHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  const MrHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.sans(fontSize: AppType.heading, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.sans(fontSize: AppType.caption, color: AppColors.textSecondary)),
              ],
            ],
          ),
        ),
        ...actions,
      ],
    ),
  );
}

/// A segmented switch for tabs inside a screen.
class MrSegments extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  const MrSegments({super.key, required this.labels, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
    height: 40,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(color: AppColors.panel, borderRadius: BorderRadius.circular(12)),
    child: LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth / labels.length;
        return Stack(
          children: [
            AnimatedPositioned(
              duration: AppMotion.medium,
              curve: AppMotion.enter,
              left: w * index,
              top: 0,
              bottom: 0,
              width: w,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 5, offset: Offset(0, 1))],
                ),
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (i == index) return;
                        HapticFeedback.selectionClick();
                        onChanged(i);
                      },
                      child: Center(
                        child: Text(
                          labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.sans(
                            fontSize: AppType.small,
                            fontWeight: FontWeight.w700,
                            color: i == index ? AppColors.textStrong : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

/// Title row for a bottom sheet.
class MrSheetTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  const MrSheetTitle(this.title, {super.key, this.subtitle});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppType.sans(fontSize: AppType.heading, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(subtitle!, style: AppType.sans(fontSize: AppType.small, color: AppColors.textSecondary)),
        ],
      ],
    ),
  );
}

/// A sheet's content inside [showAppSheet] (which already pads for the
/// keyboard and sizes the sheet): scrolls when taller than the screen.
class MrSheetBody extends StatelessWidget {
  final List<Widget> children;
  const MrSheetBody({super.key, required this.children});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children),
  );
}
