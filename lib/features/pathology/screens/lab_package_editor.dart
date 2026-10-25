import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/availability_save_bar.dart';
import '../../pharmacy/widgets/pharmacy_ui.dart'
    show PharmacyUpperCaseFormatter;
import '../providers/lab_providers.dart';
import '../widgets/lab_ui.dart';

/// Add or edit a package: several catalogue tests sold at one price.
class LabPackageEditor extends ConsumerStatefulWidget {
  final Map<String, dynamic>? package;
  const LabPackageEditor({super.key, this.package});

  @override
  ConsumerState<LabPackageEditor> createState() => _LabPackageEditorState();
}

class _LabPackageEditorState extends ConsumerState<LabPackageEditor> {
  late final Map<String, dynamic> _p = widget.package ?? const {};
  bool get _editing =>
      widget.package != null && '${_p['_id'] ?? ''}'.isNotEmpty;

  late final _code = TextEditingController(text: '${_p['packageCode'] ?? ''}');
  late final _name = TextEditingController(text: '${_p['packageName'] ?? ''}');
  late final _desc = TextEditingController(text: '${_p['description'] ?? ''}');
  late final _price = TextEditingController(text: _s(_p['price']));
  late final _mrp = TextEditingController(text: _s(_p['mrp']));
  late final _tat = TextEditingController(text: _s(_p['reportTime']));
  late final _fastingHours = TextEditingController(
    text: _s(_p['fastingHours']),
  );
  final _search = TextEditingController();
  late bool _fasting = _p['fastingRequired'] == true;
  late final Set<String> _codes = {
    for (final c in (_p['testCodes'] is List ? _p['testCodes'] as List : []))
      '$c'.toUpperCase(),
  };
  bool _mrpTouched = false;
  bool _saving = false;
  String _query = '';
  String? _error;

  static String _s(dynamic v) {
    final n = num.tryParse('${v ?? ''}');
    if (n == null || n == 0) return '';
    return n == n.roundToDouble() ? '${n.toInt()}' : '$n';
  }

  @override
  void initState() {
    super.initState();
    _mrpTouched = _mrp.text.isNotEmpty;
    _price.addListener(_onPrice);
    Future.microtask(() {
      if (mounted) ref.read(labCatalogProvider.notifier).ensureLoaded();
    });
  }

  void _onPrice() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _price.removeListener(_onPrice);
    for (final c in [
      _code,
      _name,
      _desc,
      _price,
      _mrp,
      _tat,
      _fastingHours,
      _search,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  num _worth(List<Map<String, dynamic>> tests) => tests
      .where((t) => _codes.contains('${t['testCode']}'.toUpperCase()))
      .fold<num>(0, (n, t) => n + (num.tryParse('${t['price']}') ?? 0));

  void _toggle(Map<String, dynamic> t, List<Map<String, dynamic>> tests) {
    final code = '${t['testCode']}'.toUpperCase();
    setState(() {
      if (!_codes.remove(code)) _codes.add(code);
      if (!_mrpTouched) {
        final w = _worth(tests);
        _mrp.text = w == 0 ? '' : _s(w);
      }
      // A package needs fasting if any of its tests does.
      if (t['fastingRequired'] == true && _codes.contains(code)) {
        _fasting = true;
      }
    });
  }

  Future<void> _save() async {
    final code = _code.text.trim().toUpperCase();
    final name = _name.text.trim();
    final price = num.tryParse(_price.text.trim());
    if (code.isEmpty || name.isEmpty || price == null || price < 0) {
      setState(() => _error = 'Code, name and a valid price are needed.');
      return;
    }
    if (_codes.isEmpty) {
      setState(() => _error = 'Pick at least one test.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(labCatalogProvider.notifier).savePackage({
        'packageCode': code,
        'packageName': name,
        'description': _desc.text.trim(),
        'testCodes': _codes.toList(),
        'price': price,
        'mrp': num.tryParse(_mrp.text.trim()) ?? price,
        'fastingRequired': _fasting,
        'fastingHours': _fasting
            ? (num.tryParse(_fastingHours.text.trim()) ?? 8)
            : 0,
        'reportTime': num.tryParse(_tat.text.trim()) ?? 0,
      }, id: _editing ? '${_p['_id']}' : null);
      if (!mounted) return;
      doctorToast(context, _editing ? 'Package updated' : 'Package created');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = labError(e, fallback: 'Couldn’t save the package.');
        });
      }
    }
  }

  Future<void> _toggleActive() async {
    final active = _p['isActive'] != false;
    if (active) {
      final ok = await AppModal.confirm(
        context,
        title: 'Stop selling this package?',
        message: 'Patients won’t see it any more. You can restore it later.',
        icon: LucideIcons.archive,
        confirmLabel: 'Deactivate',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(labCatalogProvider.notifier)
          .setPackageActive('${_p['_id']}', !active);
      if (!mounted) return;
      doctorToast(context, active ? 'Package deactivated' : 'Package restored');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        doctorToast(context, labError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(labCatalogProvider);
    final st = ref.read(labCatalogProvider);
    final tests =
        ref
            .read(labCatalogProvider.notifier)
            .tests
            .where((t) => t['isActive'] != false)
            .toList()
          ..sort(
            (a, b) => '${a['testName']}'.toLowerCase().compareTo(
              '${b['testName']}'.toLowerCase(),
            ),
          );
    final shown = _query.isEmpty
        ? tests
        : tests
              .where(
                (t) => '${t['testName']} ${t['testCode']}'
                    .toLowerCase()
                    .contains(_query.toLowerCase()),
              )
              .toList();
    final worth = _worth(tests);
    final price = num.tryParse(_price.text.trim()) ?? 0;
    final saving = worth > price && price > 0 ? worth - price : 0;
    final accent = ModuleAccent.of(context);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: doctorSettingsAppBar(_editing ? 'Edit package' : 'New package'),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(
          color: AppColors.bg,
          border: Border(top: BorderSide(color: AppColors.borderStrong)),
        ),
        child: SafeArea(
          top: false,
          child: AppButton(
            label: _editing ? 'Save changes' : 'Create package',
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          if (_error != null) ...[
            AppErrorBanner(message: _error!),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: AppTextField(
                  label: 'Code',
                  controller: _code,
                  required: true,
                  readOnly: _editing,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9_-]')),
                    PharmacyUpperCaseFormatter(),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppTextField(
                  label: 'Package name',
                  controller: _name,
                  required: true,
                  hint: 'e.g. Full body check-up',
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
            ],
          ),
          AppTextField(
            label: 'Description',
            controller: _desc,
            maxLines: 2,
            hint: 'Who it’s for, what it covers',
          ),
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: accent.veryLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.package, size: 18, color: accent.color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _codes.isEmpty
                        ? 'Pick the tests below'
                        : '${_codes.length} test${_codes.length == 1 ? '' : 's'} worth ${appRupees(worth)}',
                    style: AppType.sans(
                      fontSize: AppType.small,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textStrong,
                    ),
                  ),
                ),
                if (saving > 0)
                  Text(
                    'Saves ${appRupees(saving)}',
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                    ),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Price (₹)',
                  controller: _price,
                  isDecimal: true,
                  required: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Focus(
                  onFocusChange: (f) {
                    if (f) _mrpTouched = true;
                  },
                  child: AppTextField(
                    label: 'MRP (₹)',
                    controller: _mrp,
                    isDecimal: true,
                  ),
                ),
              ),
            ],
          ),
          AppTextField(
            label: 'Report ready in (hours)',
            controller: _tat,
            isNum: true,
            icon: LucideIcons.clock,
          ),
          AppSwitchRow(
            label: 'Fasting required',
            value: _fasting,
            onChanged: (v) => setState(() => _fasting = v),
          ),
          if (_fasting)
            AppTextField(
              label: 'Fasting hours',
              controller: _fastingHours,
              isNum: true,
              hint: '10',
            ),
          AppSectionTitle('Tests in this package'),
          if (!st.hasLoaded && st.error == null)
            const AppListSkeleton(count: 4)
          else if (st.error != null && !st.hasLoaded)
            AppErrorBanner(
              message: st.error!,
              onRetry: () => ref.read(labCatalogProvider.notifier).load(),
            )
          else if (tests.isEmpty)
            const AppEmptyState(
              icon: LucideIcons.flaskConical,
              text: 'Add tests to your catalogue first.',
            )
          else ...[
            AppSearchField(
              controller: _search,
              hint: 'Search tests',
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
            const SizedBox(height: 10),
            AppGroup(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) const AppHairline(),
                  _testRow(shown[i], tests),
                ],
              ],
            ),
          ],
          if (_editing) ...[
            const SizedBox(height: 20),
            AppSecondaryButton(
              label: _p['isActive'] == false
                  ? 'Restore this package'
                  : 'Stop selling this package',
              color: _p['isActive'] == false ? null : AppColors.error,
              onPressed: _saving ? null : _toggleActive,
            ),
          ],
        ],
      ),
    );
  }

  Widget _testRow(Map<String, dynamic> t, List<Map<String, dynamic>> tests) {
    final on = _codes.contains('${t['testCode']}'.toUpperCase());
    final accent = ModuleAccent.of(context).color;
    return InkWell(
      onTap: () => _toggle(t, tests),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        child: Row(
          children: [
            Icon(
              on ? LucideIcons.squareCheck : LucideIcons.square,
              size: 19,
              color: on ? accent : AppColors.textTertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${t['testName']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.sans(
                  fontSize: AppType.body,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Text(
              appRupees(t['price']),
              style: AppType.sans(
                fontSize: AppType.small,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
