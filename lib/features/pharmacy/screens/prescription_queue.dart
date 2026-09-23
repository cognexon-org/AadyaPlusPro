import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/pharmacy_type.dart';
import '../../../core/network/api_service.dart';
import '../theme/pharmacy_colors.dart';
import '../providers/pharmacy_store_provider.dart';
import '../widgets/pharmacy_ui.dart';
import 'prescription_details_screen.dart';

class PrescriptionQueue extends ConsumerStatefulWidget {
  const PrescriptionQueue({super.key});
  @override
  ConsumerState<PrescriptionQueue> createState() => _PrescriptionQueueState();
}

class _PrescriptionQueueState extends ConsumerState<PrescriptionQueue> {
  bool _loading = false;
  List<Map<String, dynamic>> _orders = [];
  String? _loadedStoreId;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await ref.read(pharmacyStoreProvider.notifier).initialize();
      final r = await ApiService().getMerchantOrders(
        queryParams: {'prescriptionStatus': 'pending_review', 'limit': 100},
      );
      final data = Map<String, dynamic>.from(r.data as Map);
      final rows = (data['orders'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (mounted) {
        setState(() {
          _loadedStoreId = ref.read(pharmacyStoreProvider).selectedStoreId;
          _orders = rows.where((o) {
            final rx = '${o['prescriptionStatus'] ?? o['rxStatus'] ?? ''}'
                .toLowerCase();
            return rx.contains('pending') ||
                rx.contains('review') ||
                o['prescriptionRequired'] == true;
          }).toList();
        });
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pharmacyErrorMessage(
                e,
                fallback: 'Couldn\'t load the prescription queue.',
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: PharmacyColors.error,
          ),
        );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _review(String id, bool approved) async {
    String? note;
    if (!approved) {
      final reasonController = TextEditingController();
      note = await showPharmacySheet<String>(
        context,
        builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reject Prescription',
              style: PharmacyType.sans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: PharmacyColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Let the customer know why this was declined',
              style: PharmacyType.sans(
                fontSize: 12,
                color: PharmacyColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            PharmacyTextField(
              label: 'Reason',
              controller: reasonController,
              icon: CupertinoIcons.doc_text,
              maxLines: 3,
              required: true,
              margin: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: PharmacySecondaryButton(
                    label: 'Cancel',
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PharmacyButton(
                    label: 'Reject',
                    onPressed: () =>
                        Navigator.pop(ctx, reasonController.text.trim()),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
      reasonController.dispose();
      if (note == null || note.trim().isEmpty) return;
    }
    try {
      await ApiService().reviewMerchantPrescription(
        id,
        approved: approved,
        reason: note,
      );
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              approved ? 'Prescription approved' : 'Prescription rejected',
            ),
            backgroundColor: PharmacyColors.success,
          ),
        );
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pharmacyErrorMessage(
                e,
                fallback: 'Something went wrong. Please try again.',
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: PharmacyColors.error,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(pharmacyStoreProvider);
    if (store.selectedStoreId != null &&
        store.selectedStoreId != _loadedStoreId &&
        !_loading)
      Future.microtask(_load);
    return Scaffold(
      backgroundColor: PharmacyColors.bg,
      appBar: AppBar(
        backgroundColor: PharmacyColors.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: PharmacyColors.textPrimary),
        title: Text(
          'Prescription Queue',
          style: PharmacyType.sans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: PharmacyColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        // An AppBar already covers the status bar; this is here for
        // the bottom inset, so content and buttons clear the device
        // gesture bar.
        top: false,
        child: _loading && _orders.isEmpty
            ? ListView(
                padding: const EdgeInsets.all(16),
                children: const [PharmacyListSkeleton(count: 4)],
              )
            : RefreshIndicator(
                color: PharmacyColors.green,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_orders.isEmpty)
                      const PharmacyEmptyStateInline(
                        icon: CupertinoIcons.doc_text,
                        text: 'No prescriptions awaiting review.',
                      ),
                    ..._orders.map((o) {
                      final id = '${o['_id'] ?? ''}';
                      final items = (o['items'] as List? ?? const []);
                      final number =
                          o['orderNumber'] ?? o['order_number'] ?? id;
                      final patient = o['patientId'] is Map
                          ? Map<String, dynamic>.from(o['patientId'])
                          : <String, dynamic>{};
                      return PharmacyCard(
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  PrescriptionDetailsScreen(order: o),
                            ),
                          );
                          if (mounted) await _load();
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '#$number',
                                        style: PharmacyType.sans(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13.5,
                                          color: PharmacyColors.textPrimary,
                                        ),
                                      ),
                                      if ((patient['name'] ?? '')
                                          .toString()
                                          .isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          patient['name'].toString(),
                                          style: PharmacyType.sans(
                                            fontSize: 12.5,
                                            color: PharmacyColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      Text(
                                        '${items.length} item(s) · ₹${o['totalAmount'] ?? 0}',
                                        style: PharmacyType.sans(
                                          fontSize: 12,
                                          color: PharmacyColors.textTertiary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                PharmacyStatusPill(
                                  text: 'Pending Review',
                                  color:
                                      PharmacyColors.statusPrescriptionReviewFg,
                                  background:
                                      PharmacyColors.statusPrescriptionReviewBg,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: PharmacySecondaryButton(
                                    label: 'Reject',
                                    color: PharmacyColors.error,
                                    onPressed: id.isEmpty
                                        ? null
                                        : () => _review(id, false),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: PharmacyButton(
                                    label: 'Approve',
                                    onPressed: id.isEmpty
                                        ? null
                                        : () => _review(id, true),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
      ),
    );
  }
}
