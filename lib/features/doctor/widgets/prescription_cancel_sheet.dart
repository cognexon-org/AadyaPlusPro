import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import 'prescription_ui.dart';

/// Asks why a prescription is being cancelled. Returns the reason, or null
/// if the doctor backs out. Owns its own text controller.
Future<String?> showRxCancelSheet(BuildContext context) =>
    showAppSheet<String>(context, builder: (_) => const _RxCancelSheet());

class _RxCancelSheet extends StatefulWidget {
  const _RxCancelSheet();

  @override
  State<_RxCancelSheet> createState() => _RxCancelSheetState();
}

class _RxCancelSheetState extends State<_RxCancelSheet> {
  static const _reasons = [
    'Written for the wrong patient',
    'Wrong medicine or dose',
    'Patient’s condition changed',
    'Duplicate prescription',
  ];

  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _reason.text.trim();
    if (text.length < 3) {
      setState(() => _error = 'Tell the patient why it is being cancelled.');
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cancel prescription',
            style: AppType.sans(
              fontSize: AppType.title,
              fontWeight: FontWeight.w700,
              color: AppColors.textStrong,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'The patient and pharmacies will no longer be able to use it.',
            style: AppType.sans(
              fontSize: AppType.caption,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in _reasons)
                RxQuickChip(
                  label: r,
                  selected: _reason.text.trim() == r,
                  onTap: () => setState(() {
                    _reason.text = r;
                    _error = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 14),
          AppTextField(
            label: 'Reason',
            controller: _reason,
            icon: LucideIcons.messageSquareText,
            hint: 'Why is it being cancelled?',
            required: true,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            errorText: _error,
          ),
          Row(
            children: [
              Expanded(
                child: AppSecondaryButton(
                  label: 'Keep it',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppColors.radiusButton,
                      ),
                    ),
                  ),
                  child: Text(
                    'Continue',
                    style: AppType.sans(
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
