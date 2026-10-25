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
import 'new_sale.dart';
import 'sale_details_screen.dart';

/// Counter sales — every bill raised at the till, and the place a new one is
/// started.
///
/// Distinct from Orders, which is the online channel: these are walk-in sales
/// against `PharmacySale`, and the lifecycle is a single step (billed, then
/// dispensed) rather than the packing/shipping ladder an online order climbs.
class PharmacySales extends ConsumerStatefulWidget {
  const PharmacySales({super.key});

  @override
  ConsumerState<PharmacySales> createState() => _PharmacySalesState();
}

class _PharmacySalesState extends ConsumerState<PharmacySales> {
  final _api = ApiService();
  final _search = TextEditingController();

  List<Map<String, dynamic>> _sales = const [];
  Map<String, dynamic> _totals = const {};
  bool _loading = true;
  String? _error;
  String? _loadedStoreId;

  /// The window currently in view. Null means every sale ever billed.
  DateTimeRange? _range;

  /// Which preset produced [_range], so the right chip stays lit. 'custom'
  /// once a range has been picked from the calendar.
  String _preset = 'today';

  @override
  void initState() {
    super.initState();
    _range = _rangeFor(_preset);
    Future.microtask(() async {
      await ref.read(pharmacyStoreProvider.notifier).initialize();
      if (mounted) await _load();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Builds the range for a preset. Ranges are inclusive of both end days:
  /// `end` is pushed to 23:59:59 so a sale billed this afternoon is inside
  /// "Today" rather than just outside it.
  static DateTimeRange? _rangeFor(String preset) {
    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
    switch (preset) {
      case 'today':
        return DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: endOfToday,
        );
      case 'week':
        return DateTimeRange(
          start: DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(const Duration(days: 6)),
          end: endOfToday,
        );
      case 'month':
        return DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: endOfToday,
        );
      default:
        return null;
    }
  }

  Future<void> _load() async {
    final storeId = ref.read(pharmacyStoreProvider).selectedStoreId;
    if (storeId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // The window is a server query, not a filter over a fetched page: the
      // sales endpoint takes startDate/endDate and returns totals for exactly
      // the same filter, so a range covering last year finds last year's bills
      // instead of quietly showing nothing.
      final range = _range;
      final response = await _api.getPharmacySales(
        queryParams: {
          'limit': 200,
          if (_search.text.trim().isNotEmpty) 'search': _search.text.trim(),
          if (range != null) 'startDate': range.start.toIso8601String(),
          if (range != null) 'endDate': range.end.toIso8601String(),
        },
      );
      final data = response.data;
      if (!mounted) return;
      setState(() {
        _sales = _maps(data is Map ? (data['sales'] ?? data['data']) : data);
        _totals = data is Map && data['totals'] is Map
            ? Map<String, dynamic>.from(data['totals'] as Map)
            : const {};
        _loadedStoreId = storeId;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Recorded on failure too, or build() retries this branch forever.
        _loadedStoreId = storeId;
        _loading = false;
        _error = e is DioException
            ? _message(e)
            : pharmacyErrorMessage(e, fallback: "Couldn't load sales.");
      });
    }
  }

  void _applyPreset(String preset) {
    setState(() {
      _preset = preset;
      _range = _rangeFor(preset);
    });
    _load();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _range,
      helpText: 'Select sales period',
      saveText: 'Apply',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
            primary: PharmacyColors.green,
            onPrimary: Colors.white,
            surface: PharmacyColors.bg,
            onSurface: PharmacyColors.textStrong,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _preset = 'custom';
      // The picker hands back midnight on the end day, which would exclude
      // everything billed during it.
      _range = DateTimeRange(
        start: DateTime(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        ),
        end: DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        ),
      );
    });
    await _load();
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
      floatingActionButton: PharmacyFab(
        label: 'New Sale',
        icon: LucideIcons.plus,
        onPressed: () async {
          await Navigator.of(
            context,
          ).push(PharmacyPageRoute(builder: (_) => const NewSaleScreen()));
          if (mounted) await _load();
        },
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PharmacyScreenHeader(
                    title: 'Sales',
                    subtitle: 'Counter bills raised at this branch',
                    trailing: IconButton(
                      tooltip: 'Choose dates',
                      // Green once a custom range is in force, so the header
                      // shows at a glance that the list is not the default
                      // window.
                      icon: const Icon(LucideIcons.calendarDays, size: 22),
                      color: _preset == 'custom'
                          ? PharmacyColors.green
                          : PharmacyColors.textSecondary,
                      onPressed: _pickRange,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _summaryStrip(),
                  const SizedBox(height: 12),
                  PharmacySearchField(
                    controller: _search,
                    hint: 'Search by bill number or customer...',
                    onSubmitted: _load,
                    onRefresh: _load,
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final entry in _presets.entries)
                          Padding(
                            padding: const EdgeInsets.only(right: 7),
                            child: PharmacyFilterChip(
                              label: entry.value,
                              selected: _preset == entry.key,
                              onTap: () => _applyPreset(entry.key),
                            ),
                          ),
                        // The chosen range still reads as a chip, so the
                        // active window is visible without opening the picker.
                        if (_preset == 'custom')
                          Padding(
                            padding: const EdgeInsets.only(right: 7),
                            child: PharmacyFilterChip(
                              label: _rangeLabel(),
                              selected: true,
                              onTap: _pickRange,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
                      child: PharmacyListSkeleton(count: 5),
                    )
                  : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: PharmacyErrorBanner(
                        message: _error!,
                        onRetry: _load,
                      ),
                    )
                  : RefreshIndicator(
                      color: PharmacyColors.green,
                      onRefresh: _load,
                      child: _sales.isEmpty
                          ? ListView(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              children: [
                                const SizedBox(height: 40),
                                PharmacyEmptyStateInline(
                                  icon: LucideIcons.receiptText,
                                  text: _range == null
                                      ? 'No counter sales at this branch yet'
                                      : 'No sales in ${_rangeLabel()}',
                                ),
                              ],
                            )
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                              children: _groupedByDay(_sales),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Takings and bill count for the selected window. These come from the
  /// server's own aggregate over the same filter, so they cover the whole
  /// period rather than only the page of bills currently loaded.
  Widget _summaryStrip() {
    final gross = _totals.isEmpty
        ? _sales.fold<double>(0, (sum, s) => sum + _net(s))
        : _num(_totals['totalSales']);
    final bills = _totals.isEmpty
        ? _sales.length
        : _num(_totals['count']).toInt();
    final avg = bills == 0 ? 0.0 : gross / bills;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 13),
      decoration: BoxDecoration(
        color: PharmacyColors.greenVeryLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PharmacyColors.greenLight),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _summaryCell('Takings', _rupees(gross)),
            _divider(),
            _summaryCell('Bills', '$bills'),
            _divider(),
            _summaryCell('Average', _rupees(avg)),
          ],
        ),
      ),
    );
  }

  /// A range reads as one date when it covers a single day, and drops the
  /// repeated year and month where both ends share them.
  String _rangeLabel() {
    final range = _range;
    if (range == null) return 'all time';
    final start = range.start;
    final end = range.end;
    final sameDay =
        start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    if (sameDay) return DateFormat('d MMM yyyy').format(start);
    if (start.year != end.year) {
      return '${DateFormat('d MMM yy').format(start)} – ${DateFormat('d MMM yy').format(end)}';
    }
    if (start.month != end.month) {
      return '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM').format(end)}';
    }
    return '${DateFormat('d').format(start)} – ${DateFormat('d MMM').format(end)}';
  }

  Widget _divider() => Container(
    width: 1,
    color: PharmacyColors.greenLight,
    margin: const EdgeInsets.symmetric(vertical: 2),
  );

  Widget _summaryCell(String label, String value) => Expanded(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: PharmacyType.number(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: PharmacyColors.textStrong,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: PharmacyType.sans(
            fontSize: 10.5,
            color: PharmacyColors.textSecondary,
          ),
        ),
      ],
    ),
  );

  List<Widget> _groupedByDay(List<Map<String, dynamic>> sales) {
    final widgets = <Widget>[];
    String? lastBucket;
    for (final sale in sales) {
      final bucket = _dayBucket(_saleDate(sale));
      if (bucket != lastBucket) {
        widgets.add(
          Padding(
            padding: EdgeInsets.fromLTRB(2, widgets.isEmpty ? 2 : 14, 2, 8),
            child: Text(
              bucket.toUpperCase(),
              style: PharmacyType.sans(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: PharmacyColors.textTertiary,
              ),
            ),
          ),
        );
        lastBucket = bucket;
      }
      widgets.add(_saleCard(sale));
    }
    return widgets;
  }

  Widget _saleCard(Map<String, dynamic> sale) {
    final customer = sale['customerName']?.toString().trim();
    final name = (customer == null || customer.isEmpty) ? 'Walk-in' : customer;
    final bill =
        sale['invoiceNumber']?.toString() ??
        sale['saleNumber']?.toString() ??
        'Bill';
    final items = (sale['items'] as List?)?.length ?? 0;
    final status = '${sale['status'] ?? 'dispensed'}';
    final method = '${sale['paymentMethod'] ?? ''}'.trim();
    final balance = _num(sale['balanceAmount']);
    final returned = _num(sale['returnedAmount']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: PharmacyColors.bg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            await Navigator.of(context).push(
              PharmacyPageRoute(builder: (_) => SaleDetailsScreen(sale: sale)),
            );
            if (mounted) await _load();
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: PharmacyColors.borderStrong),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: PharmacyColors.greenLight,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            name[0].toUpperCase(),
                            style: PharmacyType.sans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: PharmacyColors.greenDark,
                            ),
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PharmacyType.sans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: PharmacyColors.textStrong,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$bill  ·  $items ${items == 1 ? 'item' : 'items'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PharmacyType.sans(
                                  fontSize: 11.5,
                                  color: PharmacyColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _rupees(_net(sale)),
                              style: PharmacyType.number(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                                color: PharmacyColors.textStrong,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              balance > 0
                                  ? '${_rupees(balance)} due'
                                  : method.isEmpty
                                  ? 'Paid'
                                  : _titleCase(method),
                              style: PharmacyType.sans(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: balance > 0
                                    ? PharmacyColors.warning
                                    : PharmacyColors.greenDark,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(height: 1, color: PharmacyColors.border),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
                    child: Row(
                      children: [
                        PharmacyStatusPill.status(status),
                        if (returned > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: PharmacyColors.errorBg,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              '${_rupees(returned)} returned',
                              style: PharmacyType.sans(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: PharmacyColors.error,
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        Text(
                          _timeOf(sale),
                          style: PharmacyType.sans(
                            fontSize: 10.5,
                            color: PharmacyColors.textTertiary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          LucideIcons.chevronRight,
                          size: 14,
                          color: PharmacyColors.textDisabled,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────────── Helpers ───────────────────────────

  static const _presets = <String, String>{
    'today': 'Today',
    'week': 'Last 7 days',
    'month': 'This month',
    'all': 'All',
  };

  static List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  static double _num(dynamic value) =>
      num.tryParse('${value ?? 0}')?.toDouble() ?? 0;

  /// What the branch actually kept: the bill less anything returned against it.
  static double _net(Map<String, dynamic> sale) =>
      _num(sale['totalAmount']) - _num(sale['returnedAmount']);

  static DateTime? _saleDate(Map<String, dynamic> sale) => DateTime.tryParse(
    '${sale['saleDate'] ?? sale['createdAt'] ?? ''}',
  )?.toLocal();

  static String _titleCase(String v) =>
      v.isEmpty ? v : '${v[0].toUpperCase()}${v.substring(1)}';

  static final _inr = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  static String _rupees(double value) => _inr.format(value);

  static String _timeOf(Map<String, dynamic> sale) {
    final d = _saleDate(sale);
    if (d == null) return '';
    return DateFormat('h:mm a').format(d);
  }

  static String _dayBucket(DateTime? d) {
    if (d == null) return 'Earlier';
    final now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (days == 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 7) return DateFormat('EEEE').format(d);
    return DateFormat('d MMMM').format(d);
  }

  static String _message(DioException e) {
    final d = e.response?.data;
    if (d is Map) {
      return d['message']?.toString() ??
          d['error']?.toString() ??
          'Request failed';
    }
    return e.message ?? 'Request failed';
  }
}
