import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/network/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_form_fields.dart';

class PathologyTestCatalog extends StatefulWidget {
  const PathologyTestCatalog({super.key});
  @override
  State<PathologyTestCatalog> createState() => _PathologyTestCatalogState();
}

class _PathologyTestCatalogState extends State<PathologyTestCatalog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = false;
  List<Map<String, dynamic>> _tests = [], _packages = [];
  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await ApiService().getDiagnosticsCatalog();
      final d = Map<String, dynamic>.from(r.data as Map);
      if (mounted)
        setState(() {
          _tests = (d['tests'] as List? ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _packages = (d['packages'] as List? ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Catalog load failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addTest() async {
    final code = TextEditingController(),
        name = TextEditingController(),
        price = TextEditingController(),
        sample = TextEditingController(),
        tat = TextEditingController();
    bool fasting = false, home = true;
    final ok = await AppDialog.show<bool>(
      context,
      title: 'Add Test',
      subtitle: 'Add a diagnostic test to your catalog',
      icon: CupertinoIcons.lab_flask,
      content: StatefulBuilder(
        builder: (ctx, setS) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              label: 'Test code',
              controller: code,
              icon: CupertinoIcons.number,
              required: true,
            ),
            AppTextField(
              label: 'Test name',
              controller: name,
              icon: CupertinoIcons.textformat,
              required: true,
            ),
            AppTextField(
              label: 'Price (₹)',
              controller: price,
              icon: CupertinoIcons.money_dollar,
              isDecimal: true,
              required: true,
            ),
            AppTextField(
              label: 'Sample type',
              controller: sample,
              icon: CupertinoIcons.drop,
            ),
            AppTextField(
              label: 'Report TAT (hours)',
              controller: tat,
              icon: CupertinoIcons.clock,
              isNum: true,
            ),
            AppSwitchRow(
              label: 'Fasting required',
              value: fasting,
              onChanged: (v) => setS(() => fasting = v),
              margin: const EdgeInsets.only(bottom: 10),
            ),
            AppSwitchRow(
              label: 'Home collection eligible',
              value: home,
              onChanged: (v) => setS(() => home = v),
              margin: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        AppDialog.cancelButton(context),
        AppDialog.primaryButton('Create', () => Navigator.pop(context, true)),
      ],
    );
    if (ok != true || code.text.trim().isEmpty || name.text.trim().isEmpty)
      return;
    try {
      await ApiService().createDiagnosticsCatalogTest({
        'testCode': code.text.trim(),
        'testName': name.text.trim(),
        'price': double.tryParse(price.text) ?? 0,
        'sampleType': sample.text.trim(),
        'reportTime': int.tryParse(tat.text) ?? 0,
        'fastingRequired': fasting,
        'homeCollectionEligible': home,
      });
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _addPackage() async {
    final active = _tests
        .where(
          (t) => t['isActive'] != false && '${t['testCode'] ?? ''}'.isNotEmpty,
        )
        .toList();
    if (active.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Create a test first.')));
      return;
    }
    final code = TextEditingController(),
        name = TextEditingController(),
        price = TextEditingController();
    final selected = <String>{'${active.first['testCode']}'};
    final ok = await AppDialog.show<bool>(
      context,
      title: 'Add Package',
      subtitle: 'Bundle multiple tests into one package',
      icon: CupertinoIcons.square_stack_3d_up,
      content: StatefulBuilder(
        builder: (ctx, setS) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              label: 'Package code',
              controller: code,
              icon: CupertinoIcons.number,
              required: true,
            ),
            AppTextField(
              label: 'Package name',
              controller: name,
              icon: CupertinoIcons.textformat,
              required: true,
            ),
            AppTextField(
              label: 'Price (₹)',
              controller: price,
              icon: CupertinoIcons.money_dollar,
              isDecimal: true,
              required: true,
            ),
            Text(
              'Tests',
              style: GoogleFonts.manrope(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
            ...active.map((t) {
              final c = '${t['testCode']}';
              return CheckboxListTile(
                value: selected.contains(c),
                onChanged: (v) => setS(() {
                  if (v == true)
                    selected.add(c);
                  else
                    selected.remove(c);
                }),
                title: Text(
                  '${t['testName']} ($c)',
                  style: GoogleFonts.manrope(fontSize: 13.5),
                ),
                contentPadding: EdgeInsets.zero,
                dense: true,
              );
            }),
          ],
        ),
      ),
      actions: [
        AppDialog.cancelButton(context),
        AppDialog.primaryButton('Create', () => Navigator.pop(context, true)),
      ],
    );
    if (ok != true ||
        code.text.trim().isEmpty ||
        name.text.trim().isEmpty ||
        selected.isEmpty)
      return;
    try {
      await ApiService().createDiagnosticsPackage({
        'packageCode': code.text.trim(),
        'packageName': name.text.trim(),
        'price': double.tryParse(price.text) ?? 0,
        'testCodes': selected.toList(),
      });
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deactivate(Map<String, dynamic> row, bool package) async {
    try {
      if (package)
        await ApiService().deleteDiagnosticsPackage('${row['_id']}');
      else
        await ApiService().deleteDiagnosticsCatalogTest('${row['_id']}');
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.surface,
    appBar: AppBar(
      title: const Text('Diagnostics Catalog'),
      bottom: TabBar(
        controller: _tabs,
        tabs: const [
          Tab(text: 'Tests'),
          Tab(text: 'Packages'),
        ],
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _tabs.index == 0 ? _addTest() : _addPackage(),
      icon: const Icon(Icons.add),
      label: Text(_tabs.index == 0 ? 'Test' : 'Package'),
    ),
    body: Column(
      children: [
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [_list(_tests, false), _list(_packages, true)],
          ),
        ),
      ],
    ),
  );

  Widget _list(
    List<Map<String, dynamic>> rows,
    bool package,
  ) => RefreshIndicator(
    onRefresh: _load,
    child: rows.isEmpty
        ? ListView(
            children: [
              const SizedBox(height: 100),
              Center(
                child: Text(
                  package ? 'No packages configured.' : 'No tests configured.',
                ),
              ),
            ],
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final r = rows[i];
              return Card(
                child: ListTile(
                  title: Text(
                    '${package ? r['packageName'] : r['testName']}',
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${package ? r['packageCode'] : r['testCode']} • ₹${r['price'] ?? 0}${package ? ' • ${(r['testCodes'] as List? ?? const []).length} tests' : ' • ${r['sampleType'] ?? ''}'}',
                  ),
                  trailing: r['isActive'] == false
                      ? const Text('Inactive')
                      : IconButton(
                          onPressed: () => _deactivate(r, package),
                          icon: const Icon(Icons.visibility_off_outlined),
                        ),
                ),
              );
            },
          ),
  );
}
