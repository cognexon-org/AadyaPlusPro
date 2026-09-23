import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_service.dart';
import '../theme/pharmacy_colors.dart';
import '../theme/pharmacy_type.dart';
import '../widgets/pharmacy_ui.dart';

/// Everything a pharmacist needs to decide on one prescription: who the
/// patient is, who prescribed it, what was written, and the scan the patient
/// uploaded — with Approve / Reject at the foot.
///
/// Reached from the Prescription Queue and from the order it belongs to. It
/// always refetches the order by id, because the list endpoints do not carry
/// the prescription body: only `GET /merchant/orders/:id` populates the
/// issued prescription and its prescriber.
class PrescriptionDetailsScreen extends StatefulWidget {
  /// The order this prescription was attached to.
  final Map<String, dynamic> order;

  const PrescriptionDetailsScreen({super.key, required this.order});

  @override
  State<PrescriptionDetailsScreen> createState() =>
      _PrescriptionDetailsScreenState();
}

class _PrescriptionDetailsScreenState extends State<PrescriptionDetailsScreen> {
  final _api = ApiService();
  final _note = TextEditingController();

  late Map<String, dynamic> _order = widget.order;
  Map<String, String> _imageHeaders = const {};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      _imageHeaders = await ApiService.authImageHeaders();
      await _load();
    });
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String get _id => _order['_id']?.toString() ?? '';
  Map<String, dynamic> get _patient => _map(_order['patientId']);
  Map<String, dynamic> get _rx => _map(_order['prescriptionId']);
  Map<String, dynamic> get _upload => _map(_order['prescriptionUploadId']);
  String get _status => '${_order['prescriptionStatus'] ?? 'not_required'}';

  /// The upload may arrive populated or as a bare id, depending on which
  /// endpoint produced the record we were handed.
  String get _uploadId {
    final raw = _order['prescriptionUploadId'];
    if (raw is Map) return '${raw['_id'] ?? ''}';
    return '${raw ?? ''}';
  }

  Future<void> _load() async {
    if (_id.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'This order has no id, so its prescription cannot be opened.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.getMerchantOrder(_id);
      final data = res.data;
      if (!mounted) return;
      setState(() {
        if (data is Map && data['order'] is Map) {
          _order = Map<String, dynamic>.from(data['order'] as Map);
        }
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _message(e);
      });
    }
  }

  Future<void> _review(bool approved) async {
    final note = _note.text.trim();
    if (!approved) {
      if (note.isEmpty) {
        _toast(
          'A reason is required to reject a prescription',
          PharmacyColors.error,
        );
        return;
      }
      // Rejecting is not just a verdict on the prescription: the server
      // cancels the whole order, releases the coupon and refunds an online
      // payment. None of that is undoable, so it is confirmed first.
      final paidOnline =
          '${_order['paymentMethod']}' == 'online' &&
          '${_order['paymentStatus']}' == 'paid';
      final proceed = await PharmacyDialog.confirm(
        context,
        title: 'Reject and cancel this order?',
        message: paidOnline
            ? 'Rejecting the prescription cancels the order and refunds the customer’s online payment. This cannot be undone.'
            : 'Rejecting the prescription cancels the whole order. This cannot be undone.',
        confirmLabel: 'Reject & cancel',
        cancelLabel: 'Keep reviewing',
      );
      if (!proceed || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final res = await _api.reviewMerchantPrescription(
        _id,
        approved: approved,
        reason: note,
      );
      if (!mounted) return;
      final data = res.data;
      setState(() {
        if (data is Map && data['order'] is Map) {
          _order = Map<String, dynamic>.from(data['order'] as Map);
        }
        _busy = false;
      });
      // Report what actually happened, not just that the call succeeded.
      final refunded = data is Map && data['refund'] != null;
      _toast(
        approved
            ? 'Prescription approved — the order can now be confirmed'
            : refunded
            ? 'Prescription rejected. Order cancelled and refund raised.'
            : 'Prescription rejected. Order cancelled.',
        approved ? PharmacyColors.success : PharmacyColors.error,
      );
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(_message(e), PharmacyColors.error);
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
    final medicines = _maps(_rx['medicines']);

    return Scaffold(
      backgroundColor: PharmacyColors.bg,
      appBar: AppBar(
        backgroundColor: PharmacyColors.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: PharmacyColors.textPrimary),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Prescription',
              style: PharmacyType.sans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: PharmacyColors.textStrong,
              ),
            ),
            Text(
              '${_order['orderNumber'] ?? 'Order'}',
              style: PharmacyType.sans(
                fontSize: 10.5,
                color: PharmacyColors.textTertiary,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(child: _statusPill()),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: PharmacyErrorBanner(message: _error!, onRetry: _load),
              )
            : Column(
                children: [
                  Expanded(
                    child: RefreshIndicator(
                      color: PharmacyColors.green,
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                        children: [
                          _label('PATIENT'),
                          _patientGroup(),
                          const SizedBox(height: 22),
                          _label('PRESCRIBED BY'),
                          _prescriberGroup(),
                          if (_uploadId.isNotEmpty) ...[
                            const SizedBox(height: 22),
                            _label('UPLOADED SCAN'),
                            _scanGroup(),
                          ],
                          const SizedBox(height: 22),
                          if (_loading && medicines.isEmpty)
                            const PharmacyListSkeleton(count: 3)
                          else ...[
                            _label(
                              'PRESCRIBED MEDICINES (${medicines.length})',
                            ),
                            _medicinesGroup(medicines),
                          ],
                          ..._clinicalSections(),
                          const SizedBox(height: 22),
                          _label('ORDERED ITEMS'),
                          _orderedItemsGroup(),
                          if (_status == 'pending_review') ...[
                            const SizedBox(height: 22),
                            _label('REVIEW NOTE'),
                            PharmacyTextField(
                              label: 'Note',
                              controller: _note,
                              hint: 'Required when rejecting',
                              maxLines: 3,
                              dense: true,
                              margin: EdgeInsets.zero,
                            ),
                          ],
                          if (_status != 'pending_review' &&
                              '${_order['prescriptionReviewNotes'] ?? ''}'
                                  .trim()
                                  .isNotEmpty) ...[
                            const SizedBox(height: 22),
                            _label('REVIEW NOTE'),
                            _group([
                              Padding(
                                padding: const EdgeInsets.all(13),
                                child: Text(
                                  '${_order['prescriptionReviewNotes']}',
                                  style: PharmacyType.sans(
                                    fontSize: 12,
                                    height: 1.45,
                                    color: PharmacyColors.textSecondary,
                                  ),
                                ),
                              ),
                            ]),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (_status == 'pending_review')
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      decoration: const BoxDecoration(
                        color: PharmacyColors.bg,
                        border: Border(
                          top: BorderSide(color: PharmacyColors.borderStrong),
                        ),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Row(
                          children: [
                            Expanded(
                              child: PharmacySecondaryButton(
                                label: 'Reject',
                                color: PharmacyColors.error,
                                onPressed: _busy ? null : () => _review(false),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: PharmacyButton(
                                label: 'Approve',
                                loading: _busy,
                                onPressed: _busy ? null : () => _review(true),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  // ──────────────────────────── Sections ───────────────────────────

  Widget _statusPill() {
    final (fg, bg, text) = switch (_status) {
      'approved' => (
        PharmacyColors.greenDark,
        PharmacyColors.greenVeryLight,
        'Approved',
      ),
      'rejected' => (PharmacyColors.error, PharmacyColors.errorBg, 'Rejected'),
      'pending_review' => (
        PharmacyColors.warning,
        PharmacyColors.warningBg,
        'Awaiting review',
      ),
      _ => (
        PharmacyColors.textSecondary,
        PharmacyColors.bgSecondary,
        'Not required',
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        text,
        style: PharmacyType.sans(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  Widget _patientGroup() {
    final name = _patient['name']?.toString().trim();
    final display = (name == null || name.isEmpty) ? 'Patient' : name;
    final phone = _patient['phone']?.toString().trim() ?? '';
    final email = _patient['email']?.toString().trim() ?? '';

    return _group([
      Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: PharmacyColors.greenLight,
                shape: BoxShape.circle,
              ),
              child: Text(
                display[0].toUpperCase(),
                style: PharmacyType.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: PharmacyColors.greenDark,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    display,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PharmacyType.sans(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: PharmacyColors.textStrong,
                    ),
                  ),
                  if (phone.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      phone,
                      style: PharmacyType.number(
                        fontSize: 12.5,
                        color: PharmacyColors.textSecondary,
                      ),
                    ),
                  ],
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PharmacyType.sans(
                        fontSize: 11.5,
                        color: PharmacyColors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _prescriberGroup() {
    final doctor = _map(_rx['doctorId']);
    final physio = _map(_rx['physioId']);
    final professional = doctor.isNotEmpty ? doctor : physio;
    final kind = '${_rx['professionalType'] ?? ''}'.trim();

    if (professional.isEmpty) {
      // A patient-uploaded scan has no issued prescription behind it, so
      // there is no prescriber on record. Say that rather than leaving the
      // section blank or inventing a name.
      return _group([
        Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                LucideIcons.circleAlert,
                size: 15,
                color: PharmacyColors.warning,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _uploadId.isEmpty
                      ? 'No prescriber on record for this order.'
                      : 'The customer uploaded a scan rather than linking a prescription issued in the app, so no prescriber is on record. Read the doctor’s details from the scan below.',
                  style: PharmacyType.sans(
                    fontSize: 11.5,
                    height: 1.45,
                    color: PharmacyColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ]);
    }

    final specialisations = (professional['specialization'] as List?)
        ?.map((e) => '$e')
        .where((e) => e.trim().isNotEmpty)
        .join(', ');

    return _group([
      Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: PharmacyColors.greenVeryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                LucideIcons.stethoscope,
                size: 19,
                color: PharmacyColors.greenDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${professional['name'] ?? 'Prescriber'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PharmacyType.sans(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: PharmacyColors.textStrong,
                    ),
                  ),
                  if (specialisations != null && specialisations.isNotEmpty)
                    Text(
                      specialisations,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PharmacyType.sans(
                        fontSize: 11.5,
                        color: PharmacyColors.textSecondary,
                      ),
                    )
                  else if (kind.isNotEmpty)
                    Text(
                      kind == 'physio' ? 'Physiotherapist' : 'Doctor',
                      style: PharmacyType.sans(
                        fontSize: 11.5,
                        color: PharmacyColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      if ('${professional['licenseNumber'] ?? ''}'.trim().isNotEmpty) ...[
        _hairline,
        _dataRow('Registration', '${professional['licenseNumber']}'),
      ],
      if ('${professional['clinicName'] ?? ''}'.trim().isNotEmpty) ...[
        _hairline,
        _dataRow('Clinic', '${professional['clinicName']}'),
      ],
      if (_date(_rx['issuedAt']) != null) ...[
        _hairline,
        _dataRow('Issued on', _date(_rx['issuedAt'])!),
      ],
    ]);
  }

  /// The scan the patient photographed. Loaded with the bearer token attached
  /// because the file endpoint sits behind auth; tapping opens it full screen
  /// where it can be pinched, which is the only way to read a handwritten
  /// prescription on a phone.
  Widget _scanGroup() {
    final url = ApiConstants.prescriptionUploadFile(_uploadId);
    return _group([
      GestureDetector(
        onTap: () => _openFullScreen(url),
        child: Container(
          height: 240,
          width: double.infinity,
          color: PharmacyColors.bgSecondary,
          child: Image.network(
            url,
            headers: _imageHeaders,
            fit: BoxFit.contain,
            loadingBuilder: (_, child, progress) => progress == null
                ? child
                : const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: PharmacyColors.green,
                      ),
                    ),
                  ),
            errorBuilder: (_, _, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.fileWarning,
                      size: 22,
                      color: PharmacyColors.textTertiary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      // A PDF upload cannot render in an Image widget, and a
                      // missing file gives the same failure — say both.
                      'This file could not be previewed. It may be a PDF, or missing from storage.',
                      textAlign: TextAlign.center,
                      style: PharmacyType.sans(
                        fontSize: 11.5,
                        height: 1.4,
                        color: PharmacyColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      _hairline,
      _dataRow('File', '${_upload['originalName'] ?? 'Prescription'}'),
      if (_date(_upload['createdAt']) != null) ...[
        _hairline,
        _dataRow('Uploaded', _date(_upload['createdAt'])!),
      ],
    ]);
  }

  void _openFullScreen(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: Image.network(url, headers: _imageHeaders),
            ),
          ),
        ),
      ),
    );
  }

  Widget _medicinesGroup(List<Map<String, dynamic>> medicines) {
    if (medicines.isEmpty) {
      return _group([
        Padding(
          padding: const EdgeInsets.all(13),
          child: Text(
            _uploadId.isEmpty
                ? 'No prescription was recorded against this order.'
                : 'Nothing was typed up for this prescription — read it from the scan above.',
            style: PharmacyType.sans(
              fontSize: 11.5,
              height: 1.45,
              color: PharmacyColors.textTertiary,
            ),
          ),
        ),
      ]);
    }

    final rows = <Widget>[];
    for (final m in medicines) {
      if (rows.isNotEmpty) rows.add(_hairline);
      final dosage = [
        '${m['dosage'] ?? ''}'.trim(),
        '${m['frequency'] ?? ''}'.trim(),
        '${m['duration'] ?? ''}'.trim(),
      ].where((e) => e.isNotEmpty).join('  ·  ');
      final instructions = '${m['instructions'] ?? ''}'.trim();
      final qty = _num(m['prescribedQuantity'] ?? m['quantity']).toInt();

      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: PharmacyColors.greenVeryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  medicineCategoryIcon('${m['unit'] ?? ''}'),
                  size: 15,
                  color: PharmacyColors.greenDark,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${m['medicineName'] ?? m['genericName'] ?? 'Medicine'}',
                      style: PharmacyType.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: PharmacyColors.textPrimary,
                      ),
                    ),
                    if (dosage.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        dosage,
                        style: PharmacyType.sans(
                          fontSize: 11.5,
                          color: PharmacyColors.textSecondary,
                        ),
                      ),
                    ],
                    if (instructions.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        instructions,
                        style: PharmacyType.sans(
                          fontSize: 11,
                          height: 1.4,
                          color: PharmacyColors.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (qty > 0) ...[
                const SizedBox(width: 10),
                Text(
                  '×$qty',
                  style: PharmacyType.number(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: PharmacyColors.textStrong,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return _group(rows);
  }

  /// Diagnosis, symptoms and advice, each rendered only when the prescription
  /// actually carries them.
  List<Widget> _clinicalSections() {
    final out = <Widget>[];

    void listSection(String label, List<String> values) {
      if (values.isEmpty) return;
      out.addAll([
        const SizedBox(height: 22),
        _label(label),
        _group([
          Padding(
            padding: const EdgeInsets.all(13),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final v in values)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: PharmacyColors.bgSecondary,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: PharmacyColors.borderStrong),
                    ),
                    child: Text(
                      v,
                      style: PharmacyType.sans(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: PharmacyColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      ]);
    }

    List<String> strings(dynamic v) => v is List
        ? v.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList()
        : const [];

    listSection('DIAGNOSIS', strings(_rx['diagnosis']));
    listSection('SYMPTOMS', strings(_rx['symptoms']));

    final advice = _maps(_rx['advice'])
        .map((a) => '${a['advice'] ?? ''}'.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final notes = [
      '${_rx['patientInstructions'] ?? ''}'.trim(),
      '${_rx['notes'] ?? ''}'.trim(),
      ...advice,
    ].where((e) => e.isNotEmpty).toList();

    if (notes.isNotEmpty) {
      out.addAll([
        const SizedBox(height: 22),
        _label('NOTES & ADVICE'),
        _group([
          for (var i = 0; i < notes.length; i++) ...[
            if (i > 0) _hairline,
            Padding(
              padding: const EdgeInsets.all(13),
              child: Text(
                notes[i],
                style: PharmacyType.sans(
                  fontSize: 12,
                  height: 1.45,
                  color: PharmacyColors.textSecondary,
                ),
              ),
            ),
          ],
        ]),
      ]);
    }

    final followUp = _date(_rx['followUpDate']);
    if (followUp != null) {
      out.addAll([
        const SizedBox(height: 22),
        _label('FOLLOW-UP'),
        _group([_dataRow('Review on', followUp)]),
      ]);
    }
    return out;
  }

  /// What the customer actually put in the basket, so the pharmacist can see
  /// it against what was prescribed before approving.
  Widget _orderedItemsGroup() {
    final items = _maps(_order['items']);
    if (items.isEmpty) {
      return _group([
        Padding(
          padding: const EdgeInsets.all(13),
          child: Text(
            'No items on this order',
            style: PharmacyType.sans(
              fontSize: 12,
              color: PharmacyColors.textTertiary,
            ),
          ),
        ),
      ]);
    }
    final rows = <Widget>[];
    for (final item in items) {
      if (rows.isNotEmpty) rows.add(_hairline);
      final rxRequired = item['prescriptionRequired'] == true;
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${item['medicineName'] ?? 'Medicine'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PharmacyType.sans(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: PharmacyColors.textPrimary,
                        ),
                      ),
                    ),
                    if (rxRequired) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: PharmacyColors.warningBg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Rx',
                          style: PharmacyType.sans(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: PharmacyColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '×${_num(item['quantity']).toInt()}',
                style: PharmacyType.number(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: PharmacyColors.textStrong,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return _group(rows);
  }

  // ────────────────────────── Shared chrome ────────────────────────

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

  Widget _dataRow(String label, String value) => Container(
    color: PharmacyColors.bg,
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: PharmacyType.sans(
              fontSize: 12.5,
              color: PharmacyColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: PharmacyType.number(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: PharmacyColors.textStrong,
            ),
          ),
        ),
      ],
    ),
  );

  // ───────────────────────────── Helpers ───────────────────────────

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  static double _num(dynamic value) =>
      num.tryParse('${value ?? 0}')?.toDouble() ?? 0;

  static String? _date(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    if (d == null) return null;
    return DateFormat('d MMM yyyy, h:mm a').format(d.toLocal());
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
