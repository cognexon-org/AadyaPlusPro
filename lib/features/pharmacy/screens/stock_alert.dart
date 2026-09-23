import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/pharmacy_type.dart';
import '../theme/pharmacy_colors.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../widgets/pharmacy_ui.dart';
import 'medicine_details.dart';

class StockAlertScreen extends ConsumerStatefulWidget {
  /// Which tab to land on: 0 = Low Stock, 1 = Expiring, 2 = Expired.
  /// Home's alert cards deep-link straight to the list they are about.
  final int initialTab;
  const StockAlertScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<StockAlertScreen> createState() => _StockAlertScreenState();
}

class _StockAlertScreenState extends ConsumerState<StockAlertScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(pharmacyDashboardProvider.notifier).loadLowStock();
      ref.read(pharmacyDashboardProvider.notifier).loadExpiring();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pharmacyDashboardProvider);
    final lowStock = state.lowStockMedicines;
    final now = DateTime.now();
    final expiring = state.expiringBatches
        .where(
          (b) => (DateTime.tryParse('${b['expiry_date'] ?? ''}') ?? now)
              .isAfter(now),
        )
        .toList();
    final expired = state.expiringBatches
        .where(
          (b) => (DateTime.tryParse('${b['expiry_date'] ?? ''}') ?? now)
              .isBefore(now),
        )
        .toList();

    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab.clamp(0, 2),
      child: Scaffold(
        backgroundColor: PharmacyColors.bg,
        appBar: AppBar(
          backgroundColor: PharmacyColors.bg,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          iconTheme: const IconThemeData(color: PharmacyColors.textPrimary),
          title: Text(
            'Stock & Expiry Alerts',
            style: PharmacyType.sans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: PharmacyColors.textPrimary,
            ),
          ),
          bottom: TabBar(
            labelColor: PharmacyColors.green,
            unselectedLabelColor: PharmacyColors.textSecondary,
            indicatorColor: PharmacyColors.green,
            labelStyle: PharmacyType.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: PharmacyType.sans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            tabs: [
              Tab(text: 'Low Stock (${lowStock.length})'),
              Tab(text: 'Expiring (${expiring.length})'),
              Tab(text: 'Expired (${expired.length})'),
            ],
          ),
        ),
        body: SafeArea(
          // An AppBar already covers the status bar; this is here for
          // the bottom inset, so content and buttons clear the device
          // gesture bar.
          top: false,
          child: TabBarView(
            children: [
              _LowStockList(items: lowStock),
              _ExpiringList(items: expiring, expired: false),
              _ExpiringList(items: expired, expired: true),
            ],
          ),
        ),
      ),
    );
  }
}

class _LowStockList extends ConsumerWidget {
  final List<Map<String, dynamic>> items;
  const _LowStockList({required this.items});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: PharmacyEmptyStateInline(
            icon: CupertinoIcons.exclamationmark_triangle,
            text: 'No critical low stock items',
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: PharmacyColors.green,
      onRefresh: () =>
          ref.read(pharmacyDashboardProvider.notifier).loadLowStock(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final m = items[index];
          final name = m['medicineName'] ?? m['name'] ?? 'Medicine';
          final quantity = m['quantity'] ?? m['stock_quantity'] ?? 0;
          final id = m['_id']?.toString();
          return PharmacyCard(
            onTap: id == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MedicineDetails(medicineId: id),
                    ),
                  ),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.exclamationmark_triangle,
                  size: 18,
                  color: PharmacyColors.warning,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.toString(),
                        style: PharmacyType.sans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: PharmacyColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Qty: $quantity',
                        style: PharmacyType.sans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: PharmacyColors.warning,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'View Medicine',
                  style: PharmacyType.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: PharmacyColors.green,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ExpiringList extends ConsumerWidget {
  final List<Map<String, dynamic>> items;
  final bool expired;
  const _ExpiringList({required this.items, required this.expired});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: PharmacyEmptyStateInline(
            icon: CupertinoIcons.clock,
            text: expired ? 'No expired batches' : 'No medicines expiring soon',
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: PharmacyColors.green,
      onRefresh: () =>
          ref.read(pharmacyDashboardProvider.notifier).loadExpiring(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final b = items[index];
          final medicine = b['medicine_id'] is Map
              ? Map<String, dynamic>.from(b['medicine_id'])
              : <String, dynamic>{};
          final medicineId = medicine['_id']?.toString();
          final name =
              medicine['name'] ?? medicine['medicineName'] ?? 'Medicine';
          final batchNumber = b['batch_number'] ?? '—';
          final quantity = b['quantity'] ?? 0;
          final expiryDate =
              b['expiry_date']?.toString().split('T').first ?? '—';
          return PharmacyCard(
            onTap: medicineId == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MedicineDetails(medicineId: medicineId),
                    ),
                  ),
            child: Row(
              children: [
                Icon(
                  expired ? CupertinoIcons.xmark_circle : CupertinoIcons.clock,
                  size: 18,
                  color: expired
                      ? PharmacyColors.error
                      : PharmacyColors.warning,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.toString(),
                        style: PharmacyType.sans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: PharmacyColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Batch $batchNumber · Qty: $quantity',
                        style: PharmacyType.sans(
                          fontSize: 12,
                          color: PharmacyColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Exp: $expiryDate',
                  style: PharmacyType.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: expired
                        ? PharmacyColors.error
                        : PharmacyColors.warning,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
