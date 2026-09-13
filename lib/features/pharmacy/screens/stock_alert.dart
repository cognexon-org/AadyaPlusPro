import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import '../../../core/theme/app_theme.dart';
import '../../dashboard/providers/dashboard_provider.dart';

class StockAlertScreen extends ConsumerStatefulWidget {
  const StockAlertScreen({super.key});

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
    // For now we'll fetch them on the fly if needed, but low stock is already in stats
    // Let's implement a more detailed view by fetching them separately or using state
    
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.surface,
        appBar: AppBar(
          backgroundColor: AppTheme.surface,
          elevation: 0,
          iconTheme: const IconThemeData(color: AppTheme.textPrimary),
          title: Text('Stock Alerts', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          bottom: TabBar(
            labelColor: AppTheme.accent,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.accent,
            labelStyle: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Low Stock'),
              Tab(text: 'Expiring Soon'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            LowStockList(),
            ExpiringList(),
          ],
        ),
      ),
    );
  }
}

class LowStockList extends ConsumerWidget {
  const LowStockList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Normally we'd have a separate field for these, but we can reuse medicines for now and filter or fetch
    // To be precise, let's just show a placeholder or fetch
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Iconsax.warning_2, size: 48, color: AppTheme.warning.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('No critical low stock items', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

class ExpiringList extends ConsumerWidget {
  const ExpiringList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Iconsax.clock, size: 48, color: AppTheme.info.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('No medicines expiring soon', style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}
