import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/doctor_ui.dart';
import '../providers/physio_care_provider.dart';

/// Opens the "Start a course" sheet; resolves to the created course.
Future<Map<String, dynamic>?> showStartCourseSheet(
  BuildContext context, {
  required String patientId,
  required String patientName,
  Map<String, dynamic>? patient,
}) => showAppSheet<Map<String, dynamic>>(
  context,
  builder: (_) => StartCourseSheet(
    patientId: patientId,
    patientName: patientName,
    patient: patient,
  ),
);

/// Asks how the patient paid; resolves to `cash` / `upi` / `online`.
Future<String?> showPaymentMethodSheet(BuildContext context) =>
    showAppSheet<String>(context, builder: (_) => const _PaymentMethodSheet());

/// A package or a custom number of sessions and price, plus whether the
/// patient has paid. Owns its controllers.
class StartCourseSheet extends ConsumerStatefulWidget {
  final String patientId;
  final String patientName;
  final Map<String, dynamic>? patient;
  const StartCourseSheet({
    super.key,
    required this.patientId,
    required this.patientName,
    this.patient,
  });

  @override
  ConsumerState<StartCourseSheet> createState() => _StartCourseSheetState();
}

class _StartCourseSheetState extends ConsumerState<StartCourseSheet> {
  /// Selected package id; null = custom.
  String? _packageId;
  bool _custom = false;
  final _title = TextEditingController();
  final _sessions = TextEditingController(text: '10');
  final _price = TextEditingController();
  final _validity = TextEditingController(text: '90');
  bool _paid = false;
  String _method = 'cash';
  bool _tried = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _sessions.dispose();
    _price.dispose();
    _validity.dispose();
    super.dispose();
  }

  String? get _sessionsError {
    final n = int.tryParse(_sessions.text.trim());
    if (n == null) return 'Enter the number of sessions';
    if (n < 1 || n > 100) return 'Between 1 and 100';
    return null;
  }

  String? get _priceError {
    final p = num.tryParse(_price.text.trim());
    if (p == null) return 'Enter the course price';
    if (p < 0) return 'Can’t be negative';
    return null;
  }

  String? get _validityError {
    final t = _validity.text.trim();
    if (t.isEmpty) return null;
    final n = int.tryParse(t);
    if (n == null || n < 1 || n > 730) return 'Between 1 and 730 days';
    return null;
  }

  Future<void> _save() async {
    setState(() {
      _tried = true;
      _error = null;
    });
    if (!_custom && _packageId == null) {
      setState(() => _error = 'Pick a package or choose custom.');
      return;
    }
    if (_custom &&
        (_sessionsError != null ||
            _priceError != null ||
            _validityError != null)) {
      return;
    }
    final body = <String, dynamic>{
      if (!_custom) 'packageId': _packageId,
      if (_custom) ...{
        'totalSessions': int.parse(_sessions.text.trim()),
        'price': num.parse(_price.text.trim()),
        if (_validity.text.trim().isNotEmpty)
          'validityDays': int.parse(_validity.text.trim()),
        if (_title.text.trim().isNotEmpty) 'title': _title.text.trim(),
      },
      if (_paid) ...{'paymentStatus': 'paid', 'paymentMethod': _method},
    };
    setState(() => _saving = true);
    try {
      final course = await ref
          .read(physioCoursesProvider.notifier)
          .create(widget.patientId, body, patient: widget.patient);
      if (!mounted) return;
      Navigator.pop(context, course);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = doctorError(e, fallback: 'Couldn’t start the course.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final packages = ref.watch(physioCoursePackagesProvider);
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Start a course',
            style: AppType.sans(
              fontSize: AppType.title,
              fontWeight: FontWeight.w700,
              color: AppColors.textStrong,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Sessions for ${widget.patientName}, counted as you see them.',
            style: AppType.sans(
              fontSize: AppType.caption,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 16),
          const AppSectionTitle('Package'),
          ...packages.when(
            loading: () => const [AppListSkeleton(count: 2)],
            error: (e, _) => [
              AppErrorBanner(
                message: doctorError(e, fallback: 'Couldn’t load packages.'),
                onRetry: () => ref.invalidate(physioCoursePackagesProvider),
              ),
              const SizedBox(height: 8),
            ],
            data: (list) => [
              for (final p in list)
                _OptionTile(
                  selected: !_custom && _packageId == '${p['_id']}',
                  title: '${p['name'] ?? 'Package'}',
                  subtitle: [
                    '${p['sessionCount'] ?? '—'} sessions',
                    if (p['validityDays'] != null)
                      'valid ${p['validityDays']} days',
                  ].join(' · '),
                  trailing: appRupees(p['price'] ?? 0),
                  onTap: () => setState(() {
                    _custom = false;
                    _packageId = '${p['_id']}';
                  }),
                ),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'No packages yet — set them up under Profile › Packages, '
                    'or enter a custom course.',
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
            ],
          ),
          _OptionTile(
            selected: _custom,
            title: 'Custom course',
            subtitle: 'Set sessions and price yourself',
            onTap: () => setState(() {
              _custom = true;
              _packageId = null;
            }),
          ),
          AnimatedSize(
            duration: AppMotion.medium,
            curve: AppMotion.enter,
            alignment: Alignment.topCenter,
            child: !_custom
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      children: [
                        AppTextField(
                          label: 'Title',
                          controller: _title,
                          dense: true,
                          hint: 'e.g. Knee rehab after ACL repair',
                          textCapitalization: TextCapitalization.sentences,
                          margin: const EdgeInsets.only(bottom: 12),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: AppTextField(
                                label: 'Sessions',
                                controller: _sessions,
                                isNum: true,
                                dense: true,
                                required: true,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                errorText: _tried ? _sessionsError : null,
                                margin: const EdgeInsets.only(bottom: 12),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: AppTextField(
                                label: 'Price (₹)',
                                controller: _price,
                                isNum: true,
                                dense: true,
                                required: true,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                errorText: _tried ? _priceError : null,
                                margin: const EdgeInsets.only(bottom: 12),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: AppTextField(
                                label: 'Valid (days)',
                                controller: _validity,
                                isNum: true,
                                dense: true,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                errorText: _tried ? _validityError : null,
                                margin: const EdgeInsets.only(bottom: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          AppSwitchRow(
            label: 'Paid upfront',
            subtitle: _paid ? 'Recorded as paid today' : 'Mark paid later',
            value: _paid,
            onChanged: (v) => setState(() => _paid = v),
          ),
          if (_paid) ...[
            const SizedBox(height: 8),
            _MethodChips(
              value: _method,
              onChanged: (m) => setState(() => _method = m),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            AppErrorBanner(message: _error!),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: AppSecondaryButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: AppButton(
                  label: 'Start course',
                  loading: _saving,
                  onPressed: _save,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final String? trailing;
  final VoidCallback onTap;
  const _OptionTile({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppPressable(
        scale: 0.985,
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.medium,
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
          decoration: BoxDecoration(
            color: selected ? accent.veryLight : AppColors.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent.color : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? LucideIcons.circleCheck : LucideIcons.circle,
                size: 18,
                color: selected ? accent.color : AppColors.textDisabled,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.sans(
                        fontSize: AppType.body,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textStrong,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.sans(
                        fontSize: AppType.caption,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Text(
                  trailing!,
                  style: AppType.number(
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textStrong,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MethodChips extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _MethodChips({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final m in const ['cash', 'upi', 'online']) ...[
        if (m != 'cash') const SizedBox(width: 8),
        Expanded(
          child: AppFilterChip(
            block: true,
            label: paymentMethodLabel(m),
            selected: value == m,
            onTap: () => onChanged(m),
          ),
        ),
      ],
    ],
  );
}

class _PaymentMethodSheet extends StatefulWidget {
  const _PaymentMethodSheet();

  @override
  State<_PaymentMethodSheet> createState() => _PaymentMethodSheetState();
}

class _PaymentMethodSheetState extends State<_PaymentMethodSheet> {
  String _method = 'cash';

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Mark course paid',
        style: AppType.sans(
          fontSize: AppType.title,
          fontWeight: FontWeight.w700,
          color: AppColors.textStrong,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'How did the patient pay?',
        style: AppType.sans(
          fontSize: AppType.caption,
          color: AppColors.textTertiary,
        ),
      ),
      const SizedBox(height: 14),
      _MethodChips(
        value: _method,
        onChanged: (m) => setState(() => _method = m),
      ),
      const SizedBox(height: 18),
      AppButton(
        label: 'Mark paid',
        onPressed: () => Navigator.pop(context, _method),
      ),
    ],
  );
}
