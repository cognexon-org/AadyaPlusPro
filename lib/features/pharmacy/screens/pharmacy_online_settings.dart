import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/network/api_service.dart';
import '../providers/pharmacy_store_provider.dart';
import '../theme/pharmacy_colors.dart';
import '../theme/pharmacy_type.dart';
import '../widgets/pharmacy_ui.dart';
import 'pharmacy_coupons.dart';

/// Online store settings.
///
/// The screen is organised around the one decision that governs every other
/// setting on it — whether the store accepts online orders at all. That lives
/// in a status panel at the top that states plainly what is true right now;
/// everything it governs sits below it and dims when it is off.
///
/// Saving is a sticky bar that only appears once something has actually
/// changed, so the state of the form is never ambiguous: no bar means what
/// you see is what is live.
class PharmacyOnlineSettings extends ConsumerStatefulWidget {
  const PharmacyOnlineSettings({super.key});

  @override
  ConsumerState<PharmacyOnlineSettings> createState() =>
      _PharmacyOnlineSettingsState();
}

class _PharmacyOnlineSettingsState
    extends ConsumerState<PharmacyOnlineSettings> {
  final _minOrder = TextEditingController();
  final _deliveryFee = TextEditingController();
  final _freeDelivery = TextEditingController();
  final _eta = TextEditingController();
  final _pincodes = TextEditingController();

  bool _enabled = true;
  bool _cod = true;
  bool _online = true;
  bool _returns = true;

  bool _loading = true;
  bool _saving = false;
  bool _pausing = false;

  /// When the store resumes taking orders. Null while it is open.
  DateTime? _pausedUntil;
  String? _loadedStoreId;

  /// The settings exactly as the server last gave them to us. [_dirty] is the
  /// comparison against this, which is what drives the save bar.
  Map<String, dynamic> _saved = const {};

  @override
  void initState() {
    super.initState();
    for (final c in [_minOrder, _deliveryFee, _freeDelivery, _eta, _pincodes]) {
      c.addListener(_onFormChanged);
    }
    Future.microtask(_load);
  }

  @override
  void dispose() {
    for (final c in [_minOrder, _deliveryFee, _freeDelivery, _eta, _pincodes]) {
      c.removeListener(_onFormChanged);
      c.dispose();
    }
    super.dispose();
  }

  void _onFormChanged() {
    if (!_loading && mounted) setState(() {});
  }

  // ───────────────────────────── Data ──────────────────────────────

  Map<String, dynamic> get _payload => {
    'enabled': _enabled,
    'serviceablePincodes': _parsedPincodes,
    'minOrderAmount': double.tryParse(_minOrder.text.trim()) ?? 0,
    'deliveryFee': double.tryParse(_deliveryFee.text.trim()) ?? 0,
    'freeDeliveryThreshold': double.tryParse(_freeDelivery.text.trim()) ?? 0,
    'codEnabled': _cod,
    'onlinePaymentEnabled': _online,
    'estimatedDeliveryMinutes': int.tryParse(_eta.text.trim()) ?? 120,
    'allowReturns': _returns,
  };

  List<String> get _parsedPincodes => _pincodes.text
      .split(RegExp(r'[,\s]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  bool get _dirty {
    if (_saved.isEmpty) return false;
    final now = _payload;
    for (final key in now.keys) {
      final a = now[key];
      final b = _saved[key];
      if (a is List && b is List) {
        if (a.length != b.length || !a.every(b.contains)) return true;
      } else if ('$a' != '$b') {
        return true;
      }
    }
    return false;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await ref.read(pharmacyStoreProvider.notifier).initialize(force: true);
      final state = ref.read(pharmacyStoreProvider);
      final store = state.selectedStore ?? const <String, dynamic>{};
      final ecommerce = Map<String, dynamic>.from(
        (store['ecommerce'] as Map?) ?? const {},
      );
      if (!mounted) return;
      setState(() {
        _loadedStoreId = state.selectedStoreId;
        _enabled = ecommerce['enabled'] != false;
        _cod = ecommerce['codEnabled'] != false;
        _online = ecommerce['onlinePaymentEnabled'] != false;
        _returns = ecommerce['allowReturns'] != false;
        _pausedUntil = DateTime.tryParse('${ecommerce['pausedUntil'] ?? ''}');
        _minOrder.text = '${ecommerce['minOrderAmount'] ?? 0}';
        _deliveryFee.text = '${ecommerce['deliveryFee'] ?? 0}';
        _freeDelivery.text = '${ecommerce['freeDeliveryThreshold'] ?? 0}';
        _eta.text = '${ecommerce['estimatedDeliveryMinutes'] ?? 120}';
        _pincodes.text = (ecommerce['serviceablePincodes'] as List? ?? const [])
            .join(', ');
        _loading = false;
      });
      setState(() => _saved = _payload);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast(
        "Couldn't load your online store settings. Pull down to try again.",
        PharmacyColors.error,
      );
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ApiService().updateMerchantSettings(_payload);
      if (!mounted) return;
      setState(() {
        _saved = _payload;
        _saving = false;
      });
      _toast('Online store settings saved', PharmacyColors.success);
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final data = e.response?.data;
      final message = data is Map
          ? (data['message'] ?? data['error'])?.toString()
          : null;
      _toast(message ?? "Couldn't save your settings.", PharmacyColors.error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast("Couldn't save your settings.", PharmacyColors.error);
    }
  }

  void _toast(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: PharmacyType.sans(fontSize: 12.5, color: Colors.white),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ───────────────────────────── Build ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(pharmacyStoreProvider);
    if (store.selectedStoreId != null &&
        store.selectedStoreId != _loadedStoreId &&
        !_loading) {
      Future.microtask(_load);
    }

    return Scaffold(
      backgroundColor: PharmacyColors.bg,
      appBar: AppBar(
        backgroundColor: PharmacyColors.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: PharmacyColors.textPrimary),
        title: Text(
          'Online Store',
          style: PharmacyType.sans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: PharmacyColors.textPrimary,
          ),
        ),
        // Loading is shown as a shaped skeleton in the body, not a bar.
      ),
      body: SafeArea(
        // An AppBar already covers the status bar; this is here for
        // the bottom inset, so content and buttons clear the device
        // gesture bar.
        top: false,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: PharmacyFormSkeleton(fields: 5),
              )
            : RefreshIndicator(
                color: PharmacyColors.green,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: [
                    _statusPanel(),
                    _pausePanel(),
                    const SizedBox(height: 22),
                    _label('PAYMENTS & RETURNS'),
                    _group([
                      _switchRow(
                        'Cash on delivery',
                        'Customer pays when the order is handed over',
                        _cod,
                        (v) => setState(() => _cod = v),
                      ),
                      _hairline,
                      _switchRow(
                        'Online payment',
                        'UPI, cards and netbanking at checkout',
                        _online,
                        (v) => setState(() => _online = v),
                      ),
                      _hairline,
                      _switchRow(
                        'Allow returns',
                        'Customers can raise a return after delivery',
                        _returns,
                        (v) => setState(() => _returns = v),
                      ),
                    ]),
                    const SizedBox(height: 22),
                    _label('DELIVERY AREA'),
                    _group([
                      Padding(
                        padding: const EdgeInsets.fromLTRB(13, 13, 13, 6),
                        child: PharmacyTextField(
                          label: 'Serviceable pincodes',
                          controller: _pincodes,
                          icon: LucideIcons.mapPin,
                          hint: '400001, 400002, 400003',
                          margin: EdgeInsets.zero,
                        ),
                      ),
                      _pincodePreview(),
                    ]),
                    const SizedBox(height: 22),
                    _label('CHARGES & TIMING'),
                    _group([
                      Padding(
                        padding: const EdgeInsets.fromLTRB(13, 13, 13, 0),
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: PharmacyTextField(
                                    label: 'Minimum order (₹)',
                                    controller: _minOrder,
                                    icon: LucideIcons.shoppingBag,
                                    isNum: true,
                                    margin: const EdgeInsets.only(bottom: 12),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: PharmacyTextField(
                                    label: 'Delivery fee (₹)',
                                    controller: _deliveryFee,
                                    icon: LucideIcons.truck,
                                    isNum: true,
                                    margin: const EdgeInsets.only(bottom: 12),
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: PharmacyTextField(
                                    label: 'Free delivery above (₹)',
                                    controller: _freeDelivery,
                                    icon: LucideIcons.ticketPercent,
                                    isNum: true,
                                    margin: const EdgeInsets.only(bottom: 13),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: PharmacyTextField(
                                    label: 'Delivery time (min)',
                                    controller: _eta,
                                    icon: LucideIcons.timer,
                                    isNum: true,
                                    margin: const EdgeInsets.only(bottom: 13),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      _hairline,
                      _chargesSummary(),
                    ]),
                    // Merchant-funded coupons are commented out: in a
                    // marketplace the platform runs promotions, not each
                    // store. The coupons screen and endpoints are untouched.
                    // const SizedBox(height: 22),
                    // _label('MORE'),
                    // _group([
                    //   _linkRow(
                    //     LucideIcons.ticketPercent,
                    //     'Manage coupons',
                    //     'Discount codes customers can apply at checkout',
                    //     () => Navigator.of(context).push(
                    //       MaterialPageRoute(
                    //         builder: (_) => const PharmacyCoupons(),
                    //       ),
                    //     ),
                    //   ),
                    // ]),
                  ],
                ),
              ),
      ),
      bottomNavigationBar: _saveBar(),
    );
  }

  // ──────────────────────────── Status ─────────────────────────────

  /// The master switch, stated as a fact about the store rather than a row in
  /// a list. It was the first of four identical switches before, which gave
  /// no hint that it governs the other three.
  bool get _isPaused =>
      _pausedUntil != null && _pausedUntil!.isAfter(DateTime.now());

  Future<void> _setPause(int minutes) async {
    setState(() => _pausing = true);
    try {
      final res = await ApiService().setStorePause(minutes: minutes);
      final data = res.data;
      final until = data is Map ? data['pausedUntil'] : null;
      if (!mounted) return;
      setState(() {
        _pausedUntil = DateTime.tryParse('${until ?? ''}');
        _pausing = false;
      });
      _toast(
        minutes == 0 ? 'Taking orders again' : 'Paused for $minutes minutes',
        minutes == 0 ? PharmacyColors.success : PharmacyColors.warning,
      );
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _pausing = false);
      final d = e.response?.data;
      _toast(
        d is Map
            ? (d['message'] ?? d['error'])?.toString() ?? "Couldn't update"
            : "Couldn't update",
        PharmacyColors.error,
      );
    }
  }

  Widget _statusPanel() {
    final live = _enabled && !_isPaused;
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 14, 13, 15),
      decoration: BoxDecoration(
        color: live
            ? PharmacyColors.greenVeryLight
            : PharmacyColors.bgSecondary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: live ? PharmacyColors.greenLight : PharmacyColors.borderStrong,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: live ? PharmacyColors.greenLight : PharmacyColors.border,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isPaused
                  ? LucideIcons.pause
                  : live
                  ? LucideIcons.globe
                  : LucideIcons.power,
              size: 18,
              color: live
                  ? PharmacyColors.greenDark
                  : PharmacyColors.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _isPaused
                          ? 'Paused until ${_pauseLabel()}'
                          : live
                          ? 'Accepting online orders'
                          : 'Not accepting orders',
                      style: PharmacyType.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: PharmacyColors.textStrong,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _isPaused
                      ? 'Your store stays listed but cannot be ordered from until the pause ends. It reopens on its own.'
                      : live
                      ? 'Your store is listed in the customer app. The settings below apply to those orders.'
                      : 'Your store is hidden from the customer app. Counter billing and stock are unaffected.',
                  style: PharmacyType.sans(
                    fontSize: 11.5,
                    height: 1.45,
                    color: PharmacyColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          PharmacySwitch(
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
        ],
      ),
    );
  }

  /// A short stop for a rush, a stock check, a staff break — the store stays
  /// on the platform and reopens by itself, which is safer than relying on
  /// someone remembering to switch it back on.
  Widget _pausePanel() {
    if (!_enabled) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: _isPaused
          ? Row(
              children: [
                Expanded(
                  child: Text(
                    'Not taking orders until ${_pauseLabel()}',
                    style: PharmacyType.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: PharmacyColors.warning,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 132,
                  child: PharmacyButton(
                    label: _pausing ? 'Resuming…' : 'Resume now',
                    loading: _pausing,
                    onPressed: _pausing ? null : () => _setPause(0),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Text(
                  'Pause for',
                  style: PharmacyType.sans(
                    fontSize: 11.5,
                    color: PharmacyColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                for (final minutes in const [15, 30, 60])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: PharmacyFilterChip(
                      label: minutes < 60 ? '$minutes min' : '1 hr',
                      selected: false,
                      onTap: _pausing ? () {} : () => _setPause(minutes),
                    ),
                  ),
              ],
            ),
    );
  }

  String _pauseLabel() {
    final until = _pausedUntil;
    if (until == null) return '';
    return DateFormat('h:mm a').format(until.toLocal());
  }

  // ──────────────────────── Derived summaries ──────────────────────

  Widget _pincodePreview() {
    final codes = _parsedPincodes;
    if (codes.isEmpty) {
      // An empty list means "no restriction", not "no service": the server's
      // isPincodeServiceable() returns true when the list is empty. Saying
      // the opposite sent pharmacies hunting for a problem that was not
      // there — and hid the real risk, which is delivering anywhere.
      return _noteRow(
        LucideIcons.globe,
        PharmacyColors.info,
        'No restriction — customers at any pincode can order from you. '
        'Add pincodes to limit delivery to the areas you actually serve.',
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 0, 13, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            codes.length == 1
                ? 'Delivering to 1 pincode only'
                : 'Delivering to ${codes.length} pincodes only',
            style: PharmacyType.sans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: PharmacyColors.textTertiary,
            ),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final code in codes)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: PharmacyColors.greenVeryLight,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: PharmacyColors.greenLight),
                  ),
                  child: Text(
                    code,
                    style: PharmacyType.number(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: PharmacyColors.greenDark,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Reads the four numbers back as the sentence the customer effectively
  /// sees. Four separate boxes make it easy to set a combination that does
  /// not say what you meant.
  Widget _chargesSummary() {
    final minOrder = double.tryParse(_minOrder.text.trim()) ?? 0;
    final fee = double.tryParse(_deliveryFee.text.trim()) ?? 0;
    final free = double.tryParse(_freeDelivery.text.trim()) ?? 0;
    final eta = int.tryParse(_eta.text.trim()) ?? 0;

    final parts = <String>[
      if (minOrder > 0)
        'Orders below ₹${minOrder.toStringAsFixed(0)} are not accepted'
      else
        'No minimum order',
      if (fee <= 0)
        'delivery is free'
      else if (free > 0)
        'delivery ₹${fee.toStringAsFixed(0)}, free above ₹${free.toStringAsFixed(0)}'
      else
        'delivery ₹${fee.toStringAsFixed(0)}',
      if (eta > 0) 'arriving in about $eta min',
    ];

    final contradiction = free > 0 && minOrder > 0 && free < minOrder;

    return Column(
      children: [
        _noteRow(
          LucideIcons.circleCheck,
          PharmacyColors.textTertiary,
          '${parts.join(' · ')}.',
        ),
        if (contradiction)
          _noteRow(
            LucideIcons.circleAlert,
            PharmacyColors.warning,
            'Free delivery starts below your minimum order, so every order gets free delivery.',
          ),
      ],
    );
  }

  Widget _noteRow(IconData icon, Color tone, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: tone),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: PharmacyType.sans(
              fontSize: 11.5,
              height: 1.45,
              color: PharmacyColors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );

  // ──────────────────────────── Save bar ───────────────────────────

  Widget? _saveBar() {
    if (!_dirty && !_saving) return null;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: PharmacyColors.bg,
        border: Border(top: BorderSide(color: PharmacyColors.borderStrong)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            const Icon(
              LucideIcons.circleAlert,
              size: 15,
              color: PharmacyColors.warning,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Unsaved changes',
                style: PharmacyType.sans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: PharmacyColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 146,
              child: PharmacyButton(
                label: _saving ? 'Saving…' : 'Save changes',
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────── Section chrome ───────────────────────

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 0, 2, 9),
    child: Text(
      text,
      style: PharmacyType.sans(
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
        color: PharmacyColors.textTertiary,
      ),
    ),
  );

  Widget _group(List<Widget> children) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: PharmacyColors.borderStrong),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Column(children: children),
    ),
  );

  static Widget get _hairline =>
      Container(height: 1, color: PharmacyColors.border);

  Widget _switchRow(
    String label,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 2),
    child: PharmacySwitchRow(
      label: label,
      subtitle: subtitle,
      value: value,
      onChanged: onChanged,
      // These only take effect on online orders, so they go quiet when the
      // store is not taking any.
      enabled: _enabled,
      margin: EdgeInsets.zero,
    ),
  );

  Widget _linkRow(
    IconData icon,
    String label,
    String subtitle,
    VoidCallback onTap,
  ) => Material(
    color: PharmacyColors.bg,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 12, 11, 12),
        child: Row(
          children: [
            Icon(icon, size: 17, color: PharmacyColors.greenDark),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: PharmacyType.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: PharmacyColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: PharmacyType.sans(
                      fontSize: 11,
                      color: PharmacyColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              LucideIcons.chevronRight,
              size: 15,
              color: PharmacyColors.textDisabled,
            ),
          ],
        ),
      ),
    ),
  );
}
