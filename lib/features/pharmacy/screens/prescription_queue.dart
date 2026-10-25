import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/pharmacy_type.dart';
import '../theme/pharmacy_colors.dart';
import '../providers/pharmacy_orders_provider.dart';
import '../widgets/pharmacy_ui.dart';
import 'prescription_details_screen.dart';

class PrescriptionQueue extends ConsumerStatefulWidget {
  const PrescriptionQueue({super.key});
  @override
  ConsumerState<PrescriptionQueue> createState() => _PrescriptionQueueState();
}

class _PrescriptionQueueState extends ConsumerState<PrescriptionQueue> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final cached = ref.read(pharmacyOrdersProvider).prescriptionQueue;
      ref
          .read(pharmacyOrdersProvider.notifier)
          .loadPrescriptionQueue(silent: cached.isNotEmpty);
    });
  }

  Future<void> _load() => ref
      .read(pharmacyOrdersProvider.notifier)
      .loadPrescriptionQueue(force: true);

  /// Approval happens on the details screen, where the scan and the
  /// prescribed medicines are in front of the pharmacist — approving from a
  /// list row meant signing off a prescription nobody had looked at.
  Future<void> _open(Map<String, dynamic> order) async {
    await Navigator.of(context).push(
      PharmacyPageRoute(
        builder: (_) => PrescriptionDetailsScreen(order: order),
      ),
    );
    if (mounted) {
      ref
          .read(pharmacyOrdersProvider.notifier)
          .loadPrescriptionQueue(silent: true);
    }
  }

  /// Rejecting from the list stays available (a blurry or wrong upload is
  /// obvious without opening it), but it is confirmed first: the server
  /// cancels the whole order and refunds an online payment.
  Future<void> _reject(Map<String, dynamic> order) async {
    final id = '${order['_id'] ?? ''}';
    final note = await showPharmacySheet<String>(
      context,
      builder: (_) => const _RejectReasonSheet(),
    );
    if (note == null || note.trim().isEmpty) return;
    if (!mounted) return;
    final paidOnline =
        '${order['paymentMethod']}' == 'online' &&
        '${order['paymentStatus']}' == 'paid';
    final proceed = await PharmacyDialog.confirm(
      context,
      title: 'Reject and cancel this order?',
      message: paidOnline
          ? 'Rejecting the prescription cancels the order and refunds the customer’s online payment. This cannot be undone.'
          : 'Rejecting the prescription cancels the whole order. This cannot be undone.',
      confirmLabel: 'Reject & cancel',
      cancelLabel: 'Keep',
    );
    if (!proceed) return;
    try {
      await ref
          .read(pharmacyOrdersProvider.notifier)
          .reviewPrescription(id, approved: false, reason: note);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Prescription rejected. Order cancelled.'),
            backgroundColor: PharmacyColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
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
  }

  @override
  Widget build(BuildContext context) {
    final ordersState = ref.watch(pharmacyOrdersProvider);
    final orders = ordersState.prescriptionQueue;
    final isLoading = ordersState.isQueueLoading && orders.isEmpty;

    return Scaffold(
      backgroundColor: PharmacyColors.bg,
      appBar: AppBar(
        backgroundColor: PharmacyColors.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: PharmacyColors.textPrimary),
        title: Text(
          'Prescription queue',
          style: PharmacyType.sans(
            fontSize: 15,
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
        child: isLoading
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
                    if (orders.isEmpty)
                      const PharmacyEmptyStateInline(
                        icon: LucideIcons.fileText,
                        text: 'No prescriptions awaiting review.',
                      ),
                    ...orders.indexed.map((entry) {
                      final (index, o) = entry;
                      final id = '${o['_id'] ?? ''}';
                      final items = (o['items'] as List? ?? const []);
                      final number =
                          o['orderNumber'] ?? o['order_number'] ?? id;
                      final patient = o['patientId'] is Map
                          ? Map<String, dynamic>.from(o['patientId'])
                          : <String, dynamic>{};
                      return PharmacyEntrance(
                        key: ValueKey('rx-${o['_id']}'),
                        index: index,
                        child: PharmacyCard(
                          onTap: () => _open(o),
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
                                            fontSize: 13,
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
                                              fontSize: 11.5,
                                              color:
                                                  PharmacyColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 4),
                                        Text(
                                          '${items.length} ${items.length == 1 ? 'item' : 'items'} · ${pharmacyRupees(o['totalAmount'])}',
                                          style: PharmacyType.sans(
                                            fontSize: 11.5,
                                            color: PharmacyColors.textTertiary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  PharmacyStatusPill(
                                    text: 'Pending Review',
                                    color: PharmacyColors
                                        .statusPrescriptionReviewFg,
                                    background: PharmacyColors
                                        .statusPrescriptionReviewBg,
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
                                          : () => _reject(o),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 2,
                                    child: PharmacyButton(
                                      label: 'Review & approve',
                                      onPressed: id.isEmpty
                                          ? null
                                          : () => _open(o),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
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

/// Asks why a prescription is being rejected.
///
/// Owns its controller so it is disposed only when the sheet is gone.
/// Disposing it straight after `showPharmacySheet` returned crashed: the
/// sheet is still animating closed (and rebuilding as the keyboard hides)
/// when that future completes, and the TextField touched a dead controller.
class _RejectReasonSheet extends StatefulWidget {
  const _RejectReasonSheet();

  @override
  State<_RejectReasonSheet> createState() => _RejectReasonSheetState();
}

class _RejectReasonSheetState extends State<_RejectReasonSheet> {
  final _reason = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reason.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reason = _reason.text.trim();
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reject prescription',
            style: PharmacyType.sans(
              fontSize: PharmacyType.title,
              fontWeight: FontWeight.w700,
              color: PharmacyColors.textStrong,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'The customer sees this reason, and the order is cancelled.',
            style: PharmacyType.sans(
              fontSize: PharmacyType.caption,
              color: PharmacyColors.textTertiary,
            ),
          ),
          const SizedBox(height: 16),
          PharmacyTextField(
            label: 'Reason',
            controller: _reason,
            icon: LucideIcons.fileText,
            hint: 'e.g. Prescription is unclear or expired',
            maxLines: 3,
            required: true,
            textCapitalization: TextCapitalization.sentences,
            margin: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: PharmacySecondaryButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PharmacyButton(
                  label: 'Reject',
                  onPressed: reason.isEmpty
                      ? null
                      : () => Navigator.pop(context, reason),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
