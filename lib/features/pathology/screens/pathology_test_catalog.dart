import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../providers/lab_providers.dart';
import '../widgets/lab_ui.dart';
import 'lab_package_editor.dart';
import 'lab_test_editor.dart';
import 'lab_test_library.dart';

/// The Tests tab: what the lab offers. Tests grouped by category, packages
/// that bundle them, and a one-tap starter library for a new lab.
class PathologyTestCatalog extends ConsumerStatefulWidget {
  const PathologyTestCatalog({super.key});

  @override
  ConsumerState<PathologyTestCatalog> createState() =>
      _PathologyTestCatalogState();
}

class _PathologyTestCatalogState extends ConsumerState<PathologyTestCatalog> {
  final _search = TextEditingController();
  bool _packages = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(labCatalogProvider.notifier).ensureLoaded();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() =>
      ref.read(labCatalogProvider.notifier).load(silent: true);

  void _push(Widget page) =>
      Navigator.of(context).push(AppPageRoute(builder: (_) => page));

  Future<void> _addTest() async {
    final choice = await showAppSheet<String>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add a test',
            style: AppType.sans(
              fontSize: AppType.title,
              fontWeight: FontWeight.w700,
              color: AppColors.textStrong,
            ),
          ),
          const SizedBox(height: 14),
          _ChoiceRow(
            icon: LucideIcons.libraryBig,
            title: 'From the library',
            subtitle: 'CBC, LFT, lipid profile… with ranges filled in',
            onTap: () => Navigator.pop(ctx, 'library'),
          ),
          const SizedBox(height: 8),
          _ChoiceRow(
            icon: LucideIcons.flaskConical,
            title: 'Custom test',
            subtitle: 'Set your own code, price and parameters',
            onTap: () => Navigator.pop(ctx, 'custom'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    _push(choice == 'library' ? const LabTestLibrary() : const LabTestEditor());
  }

  static String _counts(
    List<Map<String, dynamic>> tests,
    List<Map<String, dynamic>> packages,
  ) {
    final t = tests.where((x) => x['isActive'] != false).length;
    final p = packages.where((x) => x['isActive'] != false).length;
    return '$t test${t == 1 ? '' : 's'} · $p package${p == 1 ? '' : 's'}';
  }

  bool _matches(Map<String, dynamic> m, List<String> keys) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return keys.any((k) => '${m[k] ?? ''}'.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(labCatalogProvider);
    final notifier = ref.read(labCatalogProvider.notifier);
    final accent = ModuleAccent.of(context).color;
    final tests = notifier.tests;
    final packages = notifier.packages;
    final hasTests = tests.any((t) => t['isActive'] != false);

    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: st.hasLoaded && (hasTests || _packages)
          ? AppFab(
              label: _packages ? 'New package' : 'Add test',
              icon: LucideIcons.plus,
              onPressed: _packages
                  ? () => _push(const LabPackageEditor())
                  : _addTest,
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: AppScreenHeader(
                title: 'Tests',
                subtitle: st.hasLoaded
                    ? _counts(tests, packages)
                    : 'Your catalogue',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: AppFilterChip(
                      label: 'Tests',
                      selected: !_packages,
                      block: true,
                      onTap: () => setState(() => _packages = false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppFilterChip(
                      label: 'Packages',
                      selected: _packages,
                      block: true,
                      onTap: () => setState(() => _packages = true),
                    ),
                  ),
                ],
              ),
            ),
            if (st.hasLoaded && (tests.isNotEmpty || packages.isNotEmpty))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: AppSearchField(
                  controller: _search,
                  hint: _packages ? 'Search packages' : 'Search tests or codes',
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                color: accent,
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  children: _packages
                      ? _packageList(st, packages)
                      : _testList(st, tests),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _head(LabResource st) => [
    if (st.error != null) ...[
      AppErrorBanner(message: st.error!, onRetry: _refresh),
      const SizedBox(height: 12),
    ],
  ];

  List<Widget> _testList(LabResource st, List<Map<String, dynamic>> tests) {
    if (!st.hasLoaded) {
      return st.error != null
          ? [AppErrorBanner(message: st.error!, onRetry: _refresh)]
          : const [AppListSkeleton(count: 6)];
    }
    if (!tests.any((t) => t['isActive'] != false)) {
      return [
        ..._head(st),
        AppEntrance(
          child: _EmptyPrompt(
            icon: LucideIcons.flaskConical,
            title: 'Add common tests in one tap',
            text:
                'Pick from 20 everyday tests — CBC, LFT, KFT, lipid profile, '
                'thyroid and more — with parameters and reference ranges '
                'already filled in. Edit prices as you go.',
            action: 'Open the library',
            onAction: () => _push(const LabTestLibrary()),
            secondary: 'Create a custom test',
            onSecondary: () => _push(const LabTestEditor()),
          ),
        ),
        ..._inactive(tests),
      ];
    }
    final active = tests
        .where((t) => t['isActive'] != false)
        .where((t) => _matches(t, ['testName', 'testCode', 'category']))
        .toList();
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final t in active) {
      final c = '${t['category'] ?? ''}'.trim();
      groups.putIfAbsent(c.isEmpty ? 'Other' : c, () => []).add(t);
    }
    final names = groups.keys.toList()..sort();
    var i = 0;
    return [
      ..._head(st),
      if (active.isEmpty)
        AppEmptyState(
          icon: LucideIcons.searchX,
          text: 'No tests match “$_query”.',
        ),
      for (final name in names) ...[
        AppSectionTitle('$name · ${groups[name]!.length}'),
        for (final t in groups[name]!..sort(_byName))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppEntrance(
              index: (i++).clamp(0, 8),
              child: _TestRow(
                test: t,
                onTap: () => _push(LabTestEditor(test: t)),
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
      ..._inactive(tests),
    ];
  }

  static int _byName(Map<String, dynamic> a, Map<String, dynamic> b) =>
      '${a['testName']}'.toLowerCase().compareTo(
        '${b['testName']}'.toLowerCase(),
      );

  List<Widget> _inactive(List<Map<String, dynamic>> tests) {
    final off = tests
        .where((t) => t['isActive'] == false)
        .where((t) => _matches(t, ['testName', 'testCode', 'category']))
        .toList();
    if (off.isEmpty) return const [];
    return [
      const SizedBox(height: 8),
      AppSectionTitle('Inactive · ${off.length}'),
      for (final t in off)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _TestRow(
            test: t,
            onTap: () => _push(LabTestEditor(test: t)),
            onRestore: () => _restoreTest(t),
          ),
        ),
    ];
  }

  Future<void> _restoreTest(Map<String, dynamic> t) async {
    try {
      await ref
          .read(labCatalogProvider.notifier)
          .setTestActive('${t['_id']}', true);
      if (mounted) _toast('${t['testName']} restored');
    } catch (e) {
      if (mounted) _toast(labError(e), error: true);
    }
  }

  List<Widget> _packageList(
    LabResource st,
    List<Map<String, dynamic>> packages,
  ) {
    if (!st.hasLoaded) {
      return st.error != null
          ? [AppErrorBanner(message: st.error!, onRetry: _refresh)]
          : const [AppListSkeleton(count: 4)];
    }
    final active = packages
        .where((p) => p['isActive'] != false)
        .where((p) => _matches(p, ['packageName', 'packageCode']))
        .toList();
    final off = packages.where((p) => p['isActive'] == false).toList();
    final hasTests = ref
        .read(labCatalogProvider.notifier)
        .tests
        .any((t) => t['isActive'] != false);
    return [
      ..._head(st),
      if (packages.where((p) => p['isActive'] != false).isEmpty)
        AppEntrance(
          child: _EmptyPrompt(
            icon: LucideIcons.packageOpen,
            title: 'Bundle tests into packages',
            text: hasTests
                ? 'A full body check-up or a diabetes panel at one price '
                      'sells better than single tests.'
                : 'Add a few tests first, then bundle them here.',
            action: hasTests ? 'Create a package' : 'Add tests',
            onAction: hasTests
                ? () => _push(const LabPackageEditor())
                : () => setState(() => _packages = false),
          ),
        )
      else
        for (var i = 0; i < active.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppEntrance(
              index: i.clamp(0, 8),
              child: _PackageRow(
                package: active[i],
                onTap: () => _push(LabPackageEditor(package: active[i])),
              ),
            ),
          ),
      if (off.isNotEmpty) ...[
        const SizedBox(height: 8),
        AppSectionTitle('Inactive · ${off.length}'),
        for (final p in off)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _PackageRow(
              package: p,
              onTap: () => _push(LabPackageEditor(package: p)),
            ),
          ),
      ],
    ];
  }

  void _toast(String m, {bool error = false}) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            m,
            style: AppType.sans(fontSize: AppType.caption, color: Colors.white),
          ),
          backgroundColor: error ? AppColors.error : AppColors.textStrong,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

num _num(dynamic v) => num.tryParse('${v ?? ''}') ?? 0;

class _TestRow extends StatelessWidget {
  final Map<String, dynamic> test;
  final VoidCallback onTap;
  final VoidCallback? onRestore;
  const _TestRow({required this.test, required this.onTap, this.onRestore});

  @override
  Widget build(BuildContext context) {
    final t = test;
    final inactive = t['isActive'] == false;
    final price = _num(t['price']);
    final mrp = _num(t['mrp']);
    final params = t['parameters'] is List
        ? (t['parameters'] as List).length
        : 0;
    final tat = _num(t['reportTime']);
    final fasting = t['fastingRequired'] == true;

    return Opacity(
      opacity: inactive ? 0.55 : 1,
      child: AppPressable(
        scale: 0.985,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${t['testName'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.sans(
                        fontSize: AppType.body,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textStrong,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 10,
                      runSpacing: 3,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${t['testCode'] ?? ''}',
                          style: AppType.sans(
                            fontSize: AppType.caption,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        if ('${t['sampleType'] ?? ''}'.isNotEmpty)
                          TubeChip('${t['sampleType']}'),
                        if (tat > 0)
                          _Tiny(LucideIcons.clock, '${tat.toInt()} h'),
                        if (params > 0)
                          _Tiny(
                            LucideIcons.listChecks,
                            '$params parameter${params == 1 ? '' : 's'}',
                          ),
                        if (fasting) const _Badge('Fasting'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (onRestore != null)
                AppButton(
                  label: 'Restore',
                  compact: true,
                  fullWidth: false,
                  onPressed: onRestore,
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      appRupees(price),
                      style: AppType.sans(
                        fontSize: AppType.body,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textStrong,
                      ),
                    ),
                    if (mrp > price)
                      Text(
                        appRupees(mrp),
                        style: AppType.sans(
                          fontSize: AppType.caption,
                          color: AppColors.textTertiary,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PackageRow extends StatelessWidget {
  final Map<String, dynamic> package;
  final VoidCallback onTap;
  const _PackageRow({required this.package, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = package;
    final accent = ModuleAccent.of(context);
    final price = _num(p['price']);
    final mrp = _num(p['mrp']);
    final count = p['testCodes'] is List ? (p['testCodes'] as List).length : 0;
    final off = mrp > price && mrp > 0
        ? ((mrp - price) / mrp * 100).round()
        : 0;
    return Opacity(
      opacity: p['isActive'] == false ? 0.55 : 1,
      child: AppPressable(
        scale: 0.985,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.light,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(LucideIcons.package, size: 18, color: accent.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${p['packageName'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.sans(
                        fontSize: AppType.body,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textStrong,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$count test${count == 1 ? '' : 's'} · ${p['packageCode'] ?? ''}',
                      style: AppType.sans(
                        fontSize: AppType.caption,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    appRupees(price),
                    style: AppType.sans(
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textStrong,
                    ),
                  ),
                  if (off > 0)
                    Text(
                      '$off% off',
                      style: AppType.sans(
                        fontSize: AppType.caption,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tiny extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Tiny(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 12, color: AppColors.textTertiary),
      const SizedBox(width: 3),
      Text(
        text,
        style: AppType.sans(
          fontSize: AppType.caption,
          color: AppColors.textSecondary,
        ),
      ),
    ],
  );
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge(this.text);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: AppColors.warningBg,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: AppType.sans(
        fontSize: AppType.micro,
        fontWeight: FontWeight.w700,
        color: AppColors.warning,
      ),
    ),
  );
}

class _ChoiceRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ChoiceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    return AppPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.light,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 19, color: accent.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppType.sans(
                      fontSize: AppType.body,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textStrong,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: AppColors.textDisabled,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPrompt extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final String action;
  final VoidCallback onAction;
  final String? secondary;
  final VoidCallback? onSecondary;
  const _EmptyPrompt({
    required this.icon,
    required this.title,
    required this.text,
    required this.action,
    required this.onAction,
    this.secondary,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: accent.light,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 26, color: accent.color),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppType.sans(
              fontSize: AppType.heading,
              fontWeight: FontWeight.w800,
              color: AppColors.textStrong,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppType.sans(
              fontSize: AppType.small,
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          AppButton(label: action, onPressed: onAction),
          if (secondary != null) ...[
            const SizedBox(height: 8),
            AppSecondaryButton(label: secondary!, onPressed: onSecondary),
          ],
        ],
      ),
    );
  }
}
