import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/availability_save_bar.dart';
import '../providers/lab_providers.dart';
import '../widgets/lab_ui.dart';

/// The starter library: everyday tests with parameters and reference ranges
/// filled in. Tick what the lab runs, adjust prices, add them in one go.
class LabTestLibrary extends ConsumerStatefulWidget {
  const LabTestLibrary({super.key});

  @override
  ConsumerState<LabTestLibrary> createState() => _LabTestLibraryState();
}

class _LabTestLibraryState extends ConsumerState<LabTestLibrary> {
  List<Map<String, dynamic>>? _items;
  String? _error;
  bool _adding = false;
  final Map<String, TextEditingController> _prices = {};
  final Set<String> _picked = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    for (final c in _prices.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await ref.read(labCatalogProvider.notifier).library();
      if (!mounted) return;
      for (final t in items) {
        final code = '${t['testCode']}';
        _prices.putIfAbsent(
          code,
          () => TextEditingController(text: '${t['price'] ?? ''}'),
        );
      }
      setState(() => _items = items);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = labError(e, fallback: 'Couldn’t load the library.'),
        );
      }
    }
  }

  void _toggle(String code) => setState(() {
    if (!_picked.remove(code)) _picked.add(code);
  });

  void _toggleAll(List<Map<String, dynamic>> group) {
    final codes = group
        .where((t) => t['added'] != true)
        .map((t) => '${t['testCode']}')
        .toList();
    setState(() {
      if (codes.every(_picked.contains)) {
        _picked.removeAll(codes);
      } else {
        _picked.addAll(codes);
      }
    });
  }

  Future<void> _add() async {
    setState(() => _adding = true);
    try {
      final msg = await ref.read(labCatalogProvider.notifier).importTests([
        for (final code in _picked)
          {
            'testCode': code,
            'price': num.tryParse(_prices[code]?.text.trim() ?? ''),
          },
      ]);
      if (!mounted) return;
      doctorToast(context, msg);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _adding = false);
        doctorToast(context, labError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final t in items ?? const <Map<String, dynamic>>[]) {
      groups.putIfAbsent('${t['category'] ?? 'Other'}', () => []).add(t);
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: doctorSettingsAppBar('Test library'),
      bottomNavigationBar: _picked.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: const BoxDecoration(
                color: AppColors.bg,
                border: Border(top: BorderSide(color: AppColors.borderStrong)),
              ),
              child: SafeArea(
                top: false,
                child: AppButton(
                  label:
                      'Add ${_picked.length} test${_picked.length == 1 ? '' : 's'}',
                  icon: LucideIcons.plus,
                  loading: _adding,
                  onPressed: _adding ? null : _add,
                ),
              ),
            ),
      body: RefreshIndicator(
        color: ModuleAccent.of(context).color,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            Text(
              'Parameters and adult reference ranges come filled in — you can '
              'edit any of them after adding.',
              style: AppType.sans(
                fontSize: AppType.small,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              AppErrorBanner(message: _error!, onRetry: _load)
            else if (items == null)
              const AppListSkeleton(count: 6)
            else
              for (final entry in groups.entries) ...[
                _groupTitle(entry.key, entry.value),
                AppGroup(
                  children: [
                    for (var i = 0; i < entry.value.length; i++) ...[
                      if (i > 0) const AppHairline(),
                      _row(entry.value[i]),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
              ],
          ],
        ),
      ),
    );
  }

  Widget _groupTitle(String name, List<Map<String, dynamic>> group) {
    final open = group.where((t) => t['added'] != true).toList();
    final all =
        open.isNotEmpty &&
        open.every((t) => _picked.contains('${t['testCode']}'));
    return AppSectionTitle(
      name,
      action: open.isEmpty ? null : (all ? 'Clear' : 'Select all'),
      onAction: open.isEmpty ? null : () => _toggleAll(group),
    );
  }

  Widget _row(Map<String, dynamic> t) {
    final accent = ModuleAccent.of(context).color;
    final code = '${t['testCode']}';
    final added = t['added'] == true;
    final picked = _picked.contains(code);
    final params = t['parameters'] is List
        ? (t['parameters'] as List).length
        : 0;
    return InkWell(
      onTap: added ? null : () => _toggle(code),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        child: Row(
          children: [
            Icon(
              added || picked ? LucideIcons.squareCheck : LucideIcons.square,
              size: 19,
              color: added
                  ? AppColors.textDisabled
                  : (picked ? accent : AppColors.textTertiary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${t['testName']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.sans(
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w600,
                      color: added
                          ? AppColors.textTertiary
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 10,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        code,
                        style: AppType.sans(
                          fontSize: AppType.caption,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textTertiary,
                        ),
                      ),
                      TubeChip('${t['sampleType'] ?? ''}'),
                      Text(
                        '$params parameter${params == 1 ? '' : 's'}',
                        style: AppType.sans(
                          fontSize: AppType.caption,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (added)
              Text(
                'Added',
                style: AppType.sans(
                  fontSize: AppType.caption,
                  fontWeight: FontWeight.w700,
                  color: AppColors.success,
                ),
              )
            else if (picked)
              SizedBox(
                width: 84,
                child: TextField(
                  controller: _prices[code],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.right,
                  style: AppType.sans(
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textStrong,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixText: '₹ ',
                    prefixStyle: AppType.sans(
                      fontSize: AppType.body,
                      color: AppColors.textTertiary,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    filled: true,
                    fillColor: AppColors.bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppColors.borderStrong,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppColors.borderStrong,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: accent),
                    ),
                  ),
                ),
              )
            else
              Text(
                appRupees(t['price']),
                style: AppType.sans(
                  fontSize: AppType.body,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
