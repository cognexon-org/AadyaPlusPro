import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/network/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/pharmacy_store_provider.dart';

class PharmacyOnlineSettings extends ConsumerStatefulWidget {
  const PharmacyOnlineSettings({super.key});
  @override
  ConsumerState<PharmacyOnlineSettings> createState() => _PharmacyOnlineSettingsState();
}

class _PharmacyOnlineSettingsState extends ConsumerState<PharmacyOnlineSettings> {
  bool _loading = false;
  List<Map<String, dynamic>> _coupons = [];
  final _minOrder = TextEditingController();
  final _deliveryFee = TextEditingController();
  final _freeDelivery = TextEditingController();
  final _eta = TextEditingController();
  final _pincodes = TextEditingController();
  bool _enabled = true, _cod = true, _online = true, _returns = true;
  String? _loadedStoreId;

  @override
  void initState() { super.initState(); Future.microtask(_load); }
  @override
  void dispose() { _minOrder.dispose(); _deliveryFee.dispose(); _freeDelivery.dispose(); _eta.dispose(); _pincodes.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await ref.read(pharmacyStoreProvider.notifier).initialize(force: true);
      final state = ref.read(pharmacyStoreProvider);
      final store = state.selectedStore ?? const <String, dynamic>{};
      final ecommerce = Map<String, dynamic>.from((store['ecommerce'] as Map?) ?? const {});
      final r = await ApiService().getMerchantCoupons();
      final d = Map<String, dynamic>.from(r.data as Map);
      if (!mounted) return;
      setState(() {
        _loadedStoreId = state.selectedStoreId;
        _coupons = (d['coupons'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _enabled = ecommerce['enabled'] != false;
        _cod = ecommerce['codEnabled'] != false;
        _online = ecommerce['onlinePaymentEnabled'] != false;
        _returns = ecommerce['allowReturns'] != false;
        _minOrder.text = '${ecommerce['minOrderAmount'] ?? 0}';
        _deliveryFee.text = '${ecommerce['deliveryFee'] ?? 0}';
        _freeDelivery.text = '${ecommerce['freeDeliveryThreshold'] ?? 0}';
        _eta.text = '${ecommerce['estimatedDeliveryMinutes'] ?? 120}';
        _pincodes.text = (ecommerce['serviceablePincodes'] as List? ?? const []).join(', ');
      });
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load online store settings: $e'))); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _saveSettings() async {
    try {
      await ApiService().updateMerchantSettings({
        'enabled': _enabled,
        'serviceablePincodes': _pincodes.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        'minOrderAmount': double.tryParse(_minOrder.text) ?? 0,
        'deliveryFee': double.tryParse(_deliveryFee.text) ?? 0,
        'freeDeliveryThreshold': double.tryParse(_freeDelivery.text) ?? 0,
        'codEnabled': _cod,
        'onlinePaymentEnabled': _online,
        'estimatedDeliveryMinutes': int.tryParse(_eta.text) ?? 120,
        'allowReturns': _returns,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Online store settings saved')));
      await _load();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }

  Future<void> _addCoupon() async {
    final code = TextEditingController(), value = TextEditingController(), minOrder = TextEditingController(); String type = 'percent';
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(title: const Text('New Coupon'), content: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: code, decoration: const InputDecoration(labelText: 'Code')),
      DropdownButtonFormField<String>(value: type, items: const [DropdownMenuItem(value: 'percent', child: Text('Percent')), DropdownMenuItem(value: 'fixed', child: Text('Fixed amount'))], onChanged: (v) => setS(() => type = v ?? type), decoration: const InputDecoration(labelText: 'Discount type')),
      TextField(controller: value, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Value')),
      TextField(controller: minOrder, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minimum order')),
    ]), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create'))])));
    if (ok != true || code.text.trim().isEmpty) return;
    try {
      await ApiService().createMerchantCoupon({'code': code.text.trim().toUpperCase(), 'discountType': type, 'value': double.tryParse(value.text) ?? 0, 'minOrderAmount': double.tryParse(minOrder.text) ?? 0, 'isActive': true});
      await _load();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }

  Future<void> _toggleCoupon(Map<String, dynamic> c, bool value) async {
    try { await ApiService().updateMerchantCoupon('${c['_id']}', {'isActive': value}); await _load(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(pharmacyStoreProvider);
    if (store.selectedStoreId != null && store.selectedStoreId != _loadedStoreId && !_loading) Future.microtask(_load);
    return Scaffold(
    backgroundColor: AppTheme.surface,
    appBar: AppBar(title: const Text('Online Store Settings')),
    floatingActionButton: FloatingActionButton.extended(onPressed: _addCoupon, icon: const Icon(Icons.add), label: const Text('Coupon')),
    body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
      const PharmacyStoreSelector(),
      const SizedBox(height: 12),
      if (_loading) const LinearProgressIndicator(),
      _section('Store availability', [
        SwitchListTile(value: _enabled, onChanged: (v) => setState(() => _enabled = v), title: const Text('Accept online orders')),
        SwitchListTile(value: _cod, onChanged: (v) => setState(() => _cod = v), title: const Text('Cash on delivery')),
        SwitchListTile(value: _online, onChanged: (v) => setState(() => _online = v), title: const Text('Online payment')),
        SwitchListTile(value: _returns, onChanged: (v) => setState(() => _returns = v), title: const Text('Allow returns')),
        TextField(controller: _pincodes, decoration: const InputDecoration(labelText: 'Serviceable pincodes (comma separated)')),
        TextField(controller: _minOrder, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minimum order amount')),
        TextField(controller: _deliveryFee, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Delivery fee')),
        TextField(controller: _freeDelivery, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Free delivery threshold')),
        TextField(controller: _eta, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Estimated delivery minutes')),
        const SizedBox(height: 12), SizedBox(width: double.infinity, child: FilledButton(onPressed: _saveSettings, child: const Text('Save online settings'))),
      ]),
      const SizedBox(height: 16),
      Text('Coupons', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      if (_coupons.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('No coupons configured.'))),
      ..._coupons.map((c) => Card(child: SwitchListTile(value: c['isActive'] != false, onChanged: (v) => _toggleCoupon(c, v), title: Text('${c['code'] ?? 'COUPON'}'), subtitle: Text('${c['discountType'] == 'percent' ? '${c['value']}%' : '₹${c['value']}'} off • min ₹${c['minOrderAmount'] ?? 0}')))),
      const SizedBox(height: 80),
    ])),
  );
  }

  Widget _section(String title, List<Widget> children) => Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700)), const SizedBox(height: 8), ...children]));
}
