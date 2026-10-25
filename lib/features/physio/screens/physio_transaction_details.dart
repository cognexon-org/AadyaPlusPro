import 'package:flutter/material.dart';

import '../../doctor/screens/doctor_earnings.dart';

/// One session's money — the shared transaction details screen with physio
/// wording.
class PhysioTransactionDetails extends StatelessWidget {
  final Map<String, dynamic> transaction;

  /// Platform fee in percent, when the row doesn't state its own.
  final num? commissionRate;

  /// The full appointment, when known.
  final Map<String, dynamic>? appointment;

  const PhysioTransactionDetails({
    super.key,
    required this.transaction,
    this.commissionRate,
    this.appointment,
  });

  @override
  Widget build(BuildContext context) => TransactionDetailsScreen(
    transaction: transaction,
    commissionRate: commissionRate?.toDouble(),
    appointment: appointment,
    noun: 'session',
  );
}
