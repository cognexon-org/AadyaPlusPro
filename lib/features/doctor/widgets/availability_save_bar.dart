import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';

// Chrome shared by the doctor's settings screens — availability, practice
// settings and edit profile — so the three behave identically: a plain app
// bar, a save bar that appears only once something changed, and a confirm
// before leaving with unsaved edits.

PreferredSizeWidget doctorSettingsAppBar(String title) => AppBar(
  backgroundColor: AppColors.bg,
  elevation: 0,
  scrolledUnderElevation: 0,
  surfaceTintColor: Colors.transparent,
  iconTheme: const IconThemeData(color: AppColors.textPrimary),
  title: Text(
    title,
    style: AppType.sans(
      fontSize: AppType.title,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    ),
  ),
);

/// Sticky footer: "Unsaved changes" and a save button. Null when there is
/// nothing to save, so `bottomNavigationBar` collapses.
Widget? doctorSaveBar({
  required bool dirty,
  required bool saving,
  required VoidCallback onSave,
  String label = 'Save changes',
}) {
  if (!dirty && !saving) return null;
  return Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: const BoxDecoration(
      color: AppColors.bg,
      border: Border(top: BorderSide(color: AppColors.borderStrong)),
    ),
    child: SafeArea(
      top: false,
      child: Row(
        children: [
          const Icon(
            LucideIcons.circleAlert,
            size: 15,
            color: AppColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Unsaved changes',
              style: AppType.sans(
                fontSize: AppType.caption,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 146,
            child: AppButton(
              label: saving ? 'Saving…' : label,
              loading: saving,
              onPressed: saving ? null : onSave,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Wraps a settings screen so back asks before throwing edits away.
class DoctorDiscardGuard extends StatelessWidget {
  final bool dirty;
  final Widget child;
  const DoctorDiscardGuard({
    super.key,
    required this.dirty,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !dirty,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      final ok = await AppModal.confirm(
        context,
        title: 'Discard changes?',
        message: "Your edits haven't been saved yet.",
        confirmLabel: 'Discard',
        cancelLabel: 'Keep editing',
      );
      if (ok && context.mounted) Navigator.of(context).pop();
    },
    child: child,
  );
}

void doctorToast(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: AppType.sans(fontSize: AppType.caption, color: Colors.white),
        ),
        backgroundColor: error ? AppColors.error : AppColors.textStrong,
        behavior: SnackBarBehavior.floating,
      ),
    );
}

/// The `doctor` object out of a GET/PUT /doctor/me/profile response.
Map<String, dynamic> doctorFromResponse(dynamic body) {
  if (body is! Map) return const {};
  final raw = body['doctor'] ?? body['data'] ?? body['profile'];
  return raw is Map ? Map<String, dynamic>.from(raw) : const {};
}
