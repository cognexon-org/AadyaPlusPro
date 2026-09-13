import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/network/api_service.dart';
import '../../dashboard/providers/dashboard_provider.dart';

class PathologyTestCatalog extends ConsumerStatefulWidget {
  const PathologyTestCatalog({super.key});

  @override
  ConsumerState<PathologyTestCatalog> createState() => _PathologyTestCatalogState();
}

class _PathologyTestCatalogState extends ConsumerState<PathologyTestCatalog> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(pathologyDashboardProvider.notifier).loadProfile();
    });
  }

  Future<void> _refresh() async {
    await ref.read(pathologyDashboardProvider.notifier).loadProfile();
  }

  @override
  Widget build(BuildContext context) {
    final dashData = ref.watch(pathologyDashboardProvider);
    // Services come from the profile document
    final profile = dashData.profile;
    final rawServices = (profile['services'] as List?) ?? [];
    final services = rawServices.map((s) => s is Map ? Map<String, dynamic>.from(s) : <String, dynamic>{}).toList();

    final filtered = services.where((s) {
      final name = s['testName']?.toString().toLowerCase() ?? '';
      return name.contains(_searchController.text.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Test Catalog', style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                    Text('${services.length} tests configured', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppTheme.textSecondary)),
                  ]),
                  GestureDetector(
                    onTap: () => _showAddTestDialog(context, profile),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(gradient: AppTheme.pathologyGradient, borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        const Icon(Iconsax.add, size: 16, color: Colors.white),
                        const SizedBox(width: 6),
                        Text('Add Test', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search tests...',
                  prefixIcon: const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Icon(Iconsax.search_normal, size: 18, color: AppTheme.textTertiary)),
                  filled: true, fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.border)),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            dashData.isLoading && services.isEmpty
                ? const Expanded(child: Center(child: CircularProgressIndicator(color: AppTheme.pathologyAccent)))
                : filtered.isEmpty
                    ? Expanded(child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Iconsax.microscope, size: 48, color: AppTheme.textTertiary.withValues(alpha: 0.5)),
                        const SizedBox(height: 12),
                        Text('No tests in catalog', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppTheme.textSecondary)),
                        const SizedBox(height: 4),
                        Text('Tap "Add Test" to configure your services', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textTertiary)),
                      ])))
                    : Expanded(
                        child: RefreshIndicator(
                          onRefresh: _refresh,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final t = filtered[i];
                              final name = t['testName'] ?? 'Lab Test';
                              final price = t['price'] ?? 0;
                              final isFasting = t['fastingRequired'] == true;
                              final reportTime = t['reportTime'];
                              final sampleType = t['sampleType'] ?? '--';
                              final description = t['description'] ?? '';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppTheme.border),
                                ),
                                child: Row(children: [
                                  Container(
                                    width: 44, height: 44,
                                    decoration: BoxDecoration(color: AppTheme.pathologyAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                                    child: const Center(child: Icon(Iconsax.microscope, size: 22, color: AppTheme.pathologyAccent)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(name, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                                    if (description.isNotEmpty)
                                      Text(description, maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppTheme.textSecondary)),
                                    const SizedBox(height: 4),
                                    Wrap(spacing: 6, children: [
                                      if (t['testCode'] != null)
                                        _chip(t['testCode'], AppTheme.pathologyAccent),
                                      _chip('Sample: $sampleType', AppTheme.primary),
                                      if (reportTime != null)
                                        _chip('${reportTime}h report', AppTheme.accent),
                                      if (isFasting)
                                        _chip('Fasting', AppTheme.warning),
                                    ]),
                                  ])),
                                  Text('₹$price', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.pathologyAccent)),
                                ]),
                              );
                            },
                          ),
                        ),
                      ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4)),
    child: Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w500, color: color)),
  );

  void _showAddTestDialog(BuildContext context, Map<String, dynamic> profile) {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final sampleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    bool fasting = false;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 24, left: 24, right: 24, top: 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Add Test to Catalog', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700)),
              IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 16),
            _inputField('Test Name *', nameCtrl),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _inputField('Price (₹) *', priceCtrl, type: TextInputType.number)),
              const SizedBox(width: 12),
              Expanded(child: _inputField('Sample Type', sampleCtrl)),
            ]),
            const SizedBox(height: 12),
            _inputField('Description', descCtrl, maxLines: 2),
            const SizedBox(height: 12),
            Row(children: [
              Checkbox(value: fasting, onChanged: (v) => setS(() => fasting = v ?? false), activeColor: AppTheme.pathologyAccent),
              Text('Fasting Required', style: GoogleFonts.plusJakartaSans(fontSize: 14)),
            ]),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: isSaving ? null : () async {
                  if (nameCtrl.text.trim().isEmpty || priceCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Test name and price are required')));
                    return;
                  }
                  setS(() => isSaving = true);
                  try {
                    final existingServices = List<Map<String, dynamic>>.from(
                      (profile['services'] as List? ?? []).map((s) => Map<String, dynamic>.from(s as Map))
                    );
                    existingServices.add({
                      'testName': nameCtrl.text.trim(),
                      'price': double.tryParse(priceCtrl.text.trim()) ?? 0,
                      'sampleType': sampleCtrl.text.trim(),
                      'description': descCtrl.text.trim(),
                      'fastingRequired': fasting,
                    });
                    await ApiService().updatePathologyProfile({'services': existingServices});
                    await ref.read(pathologyDashboardProvider.notifier).loadProfile();
                    if (mounted) Navigator.pop(ctx);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  } finally {
                    setS(() => isSaving = false);
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.pathologyAccent, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('Save Test', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _inputField(String label, TextEditingController ctrl, {TextInputType? type, int maxLines = 1}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: type,
          maxLines: maxLines,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.border)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            filled: true, fillColor: AppTheme.surface,
          ),
        ),
      ]);
}
