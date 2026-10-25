import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
      ref.read(pharmacyDashboardProvider.notifier).loadExpired();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pharmacyDashboardProvider);
    final lowStock = state.lowStockMedicines;
    // Two endpoints, because `/medicine/expiring` only returns batches that
    // have not expired yet (the next 30 days). Filtering that list for past
    // dates left the Expired tab permanently empty.
    final expiring = state.expiringBatches;
    final expired = state.expiredBatches;

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
            'Stock & expiry alerts',
            style: PharmacyType.sans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: PharmacyColors.textPrimary,
            ),
          ),
          bottom: TabBar(
            labelColor: PharmacyColors.green,
            unselectedLabelColor: PharmacyColors.textSecondary,
            indicatorColor: PharmacyColors.green,
            labelStyle: PharmacyType.sans(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: PharmacyType.sans(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
            tabs: [
              Tab(text: 'Low stock (${lowStock.length})'),
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
              _LowStockList(
                items: lowStock,
                loaded: state.loadedAlerts.contains('lowStock'),
              ),
              _ExpiringList(
                items: expiring,
                expired: false,
                loaded: state.loadedAlerts.contains('expiring'),
              ),
              _ExpiringList(
                items: expired,
                expired: true,
                loaded: state.loadedAlerts.contains('expired'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LowStockList extends ConsumerWidget {
  final List<Map<String, dynamic>> items;

  /// False until the first fetch finishes; an empty list before then means
  /// "not loaded yet", not "nothing low".
  final bool loaded;
  const _LowStockList({required this.items, required this.loaded});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty && !loaded) return const _AlertSkeleton();
    if (items.isEmpty) {
      return _AlertEmpty(
        icon: LucideIcons.triangleAlert,
        text: 'No critical low stock items',
        onRefresh: () =>
            ref.read(pharmacyDashboardProvider.notifier).loadLowStock(),
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
          return PharmacyEntrance(
            index: index,
            child: PharmacyCard(
              onTap: id == null
                  ? null
                  : () => Navigator.of(context).push(
                      PharmacyPageRoute(
                        builder: (_) =>
                            MedicineDetails(medicineId: id, initialMedicine: m),
                      ),
                    ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.triangleAlert,
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
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: PharmacyColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Qty: $quantity',
                          style: PharmacyType.sans(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: PharmacyColors.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    LucideIcons.chevronRight,
                    size: 18,
                    color: PharmacyColors.textDisabled,
                  ),
                ],
              ),
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
  final bool loaded;
  const _ExpiringList({
    required this.items,
    required this.expired,
    required this.loaded,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty && !loaded) return const _AlertSkeleton();
    if (items.isEmpty) {
      return _AlertEmpty(
        icon: LucideIcons.clock,
        text: expired ? 'No expired batches' : 'No medicines expiring soon',
        onRefresh: () => expired
            ? ref.read(pharmacyDashboardProvider.notifier).loadExpired()
            : ref.read(pharmacyDashboardProvider.notifier).loadExpiring(),
      );
    }

    return RefreshIndicator(
      color: PharmacyColors.green,
      onRefresh: () => expired
          ? ref.read(pharmacyDashboardProvider.notifier).loadExpired()
          : ref.read(pharmacyDashboardProvider.notifier).loadExpiring(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final b = items[index];
          // Expiring rows nest the medicine under `medicine_id`; expired rows
          // are the medicine itself with the batch fields merged in.
          final medicine = b['medicine_id'] is Map
              ? Map<String, dynamic>.from(b['medicine_id'])
              : b;
          final medicineId = medicine['_id']?.toString();
          final name =
              medicine['name'] ?? medicine['medicineName'] ?? 'Medicine';
          final batchNumber = b['batch_number'] ?? '—';
          final quantity = b['quantity'] ?? 0;
          final expiryDate =
              b['expiry_date']?.toString().split('T').first ?? '—';
          return PharmacyEntrance(
            index: index,
            child: PharmacyCard(
              onTap: medicineId == null
                  ? null
                  : () => Navigator.of(context).push(
                      PharmacyPageRoute(
                        // No initialMedicine: this row's quantity is the
                        // batch's, and the details screen would briefly show it
                        // as the medicine's total stock.
                        builder: (_) => MedicineDetails(medicineId: medicineId),
                      ),
                    ),
              child: Row(
                children: [
                  Icon(
                    expired ? LucideIcons.circleX : LucideIcons.clock,
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
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: PharmacyColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Batch $batchNumber · Qty: $quantity',
                          style: PharmacyType.sans(
                            fontSize: 11.5,
                            color: PharmacyColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'Exp: $expiryDate',
                    style: PharmacyType.sans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: expired
                          ? PharmacyColors.error
                          : PharmacyColors.warning,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AlertSkeleton extends StatelessWidget {
  const _AlertSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: const [PharmacyListSkeleton(count: 5)],
  );
}

/// Empty tab: the message sits at the top like every other list in the
/// module (not floating mid-screen), and the tab can still be pulled to
/// refresh.
class _AlertEmpty extends StatelessWidget {
  final IconData icon;
  final String text;
  final Future<void> Function() onRefresh;
  const _AlertEmpty({
    required this.icon,
    required this.text,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    color: PharmacyColors.green,
    onRefresh: onRefresh,
    child: ListView(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [PharmacyEmptyStateInline(icon: icon, text: text)],
    ),
  );
}
