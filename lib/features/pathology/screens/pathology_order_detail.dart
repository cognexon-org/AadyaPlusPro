import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/doctor_ui.dart' show DoctorAvatar;
import '../../pharmacy/widgets/pharmacy_barcode_scanner.dart';
import '../providers/lab_providers.dart';
import '../widgets/lab_ui.dart';
import 'lab_result_entry.dart';
import 'pathology_staff.dart';

/// One lab order, worked from top to bottom: when and who, where it is in
/// the pipeline, the tubes it needs, results, payment and its history. The
/// bar at the bottom always offers the next step — collect, assign, enter
/// results, release — so the lab never has to hunt for it.
class PathologyOrderDetail extends ConsumerStatefulWidget {
  final String orderId;

  /// The list's copy, so the screen paints immediately; it fetches the full
  /// order (with each test's parameters) itself.
  final Map<String, dynamic>? order;

  const PathologyOrderDetail({super.key, required this.orderId, this.order});

  @override
  ConsumerState<PathologyOrderDetail> createState() =>
      _PathologyOrderDetailState();
}

class _PathologyOrderDetailState extends ConsumerState<PathologyOrderDetail> {
  late Map<String, dynamic> _local = {
    '_id': widget.orderId,
    ...?widget.order,
  };
  Map<String, dynamic> _catalog = const {};
  bool _loaded = false;
  String? _loadError;
  String? _busy;

  @override
  void initState() {
    super.initState();
    Future.microtask(_reload);
  }

  /// The freshest copy: the shared list (updated by every action and poll),
  /// falling back to what this screen fetched.
  Map<String, dynamic> get _o {
    final all = ref.watch(labOrdersProvider).all;
    for (final o in all) {
      if ('${o['_id']}' == widget.orderId) return {..._local, ...o};
    }
    return _local;
  }

  Future<void> _reload() async {
    try {
      final r = await ref.read(labOrdersProvider.notifier).fetch(widget.orderId);
      if (!mounted) return;
      setState(() {
        if (r.order.isNotEmpty) _local = r.order;
        _catalog = r.catalog;
        _loaded = true;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _loadError = labError(e, fallback: 'Couldn’t load this order.');
      });
    }
  }

  Future<void> _run(
    String what,
    Future<void> Function() action, {
    String? done,
    String fallback = 'Something went wrong. Please try again.',
  }) async {
    if (_busy != null) return;
    setState(() => _busy = what);
    try {
      await action();
      if (done != null) _toast(done);
    } catch (e) {
      _toast(labError(e, fallback: fallback), error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppType.sans(fontSize: AppType.caption, color: Colors.white),
        ),
        backgroundColor: error ? AppColors.error : AppColors.textStrong,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  LabOrdersNotifier get _orders => ref.read(labOrdersProvider.notifier);
  String get _id => widget.orderId;

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _collect() async {
    final o = _o;
    final result = await showAppSheet<({String barcode, String by})>(
      context,
      builder: (_) => _CollectSheet(
        tests: labTests(o),
        collector: '${labPhlebotomist(o)['name'] ?? ''}',
        fasting: o['fastingRequired'] == true,
        fastingHours: int.tryParse('${o['fastingHours'] ?? 0}') ?? 0,
      ),
    );
    if (result == null) return;
    await _run(
      'collect',
      () => labIsHome(o)
          ? _orders.collection(
              _id,
              'collected',
              barcode: result.barcode,
              collectedBy: result.by,
            )
          : _orders.collectSample(
              _id,
              barcode: result.barcode,
              collectedBy: result.by,
              sampleType: labTests(o).firstOrNull?['sampleType'] as String?,
            ),
      done: 'Sample collected',
    );
  }

  Future<void> _assign() async {
    final picked = await showAppSheet<Map<String, dynamic>>(
      context,
      builder: (_) =>
          _AssignSheet(current: '${labPhlebotomist(_o)['_id'] ?? ''}'),
    );
    if (picked == null) return;
    await _run(
      'assign',
      () => _orders.assign(_id, '${picked['_id']}'),
      done: 'Assigned to ${picked['name']}',
    );
    ref.read(labStaffProvider.notifier).load(silent: true);
  }

  Future<void> _collectionStep(String status, String done) =>
      _run(status, () => _orders.collection(_id, status), done: done);

  Future<void> _failCollection() async {
    final reason = await _askReason(
      title: 'Collection didn’t happen',
      options: const [
        'Patient not available',
        'Patient not fasting',
        'Wrong address',
        'Patient refused',
      ],
      confirm: 'Mark failed',
    );
    if (reason == null) return;
    await _run(
      'failed',
      () => _orders.collection(_id, 'failed', note: reason),
      done: 'Marked as failed',
    );
  }

  Future<void> _enterResults() async {
    final saved = await Navigator.of(context).push<bool>(
      AppPageRoute(
        builder: (_) => LabResultEntry(order: _o, catalog: _catalog),
      ),
    );
    if (saved == true) await _reload();
  }

  Future<void> _release() async {
    final summary = labResultSummary(_o);
    final profile = ref.read(labProfileProvider).data;
    final signer = TextEditingController(
      text: '${profile['contactPerson'] ?? ''}'.trim(),
    );
    final ok = await AppModal.show<bool>(
      context,
      title: 'Release report?',
      subtitle:
          'A PDF report is generated from the results and sent to the patient.',
      icon: LucideIcons.fileCheck2,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (summary['critical']! > 0)
            _Notice(
              icon: LucideIcons.triangleAlert,
              color: AppColors.error,
              text:
                  '${summary['critical']} critical value${summary['critical'] == 1 ? '' : 's'} — call the patient or their doctor too.',
            )
          else if (summary['abnormal']! > 0)
            _Notice(
              icon: LucideIcons.activity,
              color: const Color(0xFFC2410C),
              text:
                  '${summary['abnormal']} value${summary['abnormal'] == 1 ? '' : 's'} outside the reference range.',
            ),
          AppTextField(
            label: 'Verified by',
            hint: 'e.g. Dr. Mehta, MD Pathology',
            controller: signer,
            textCapitalization: TextCapitalization.words,
            margin: EdgeInsets.zero,
          ),
        ],
      ),
      actions: [
        AppSecondaryButton(
          label: 'Not yet',
          fullWidth: false,
          onPressed: () => Navigator.pop(context, false),
        ),
        AppButton(
          label: 'Release',
          fullWidth: false,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    final by = signer.text;
    signer.dispose();
    if (ok != true) return;
    await _run(
      'release',
      () => _orders.release(_id, signedBy: by),
      done: 'Report released to ${labPatientName(_o)}',
      fallback: 'Couldn’t release the report.',
    );
  }

  Future<void> _upload() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    final path = picked?.files.single.path;
    if (path == null) return;
    await _run(
      'upload',
      () => _orders.uploadReport(_id, path),
      done: 'Report uploaded and sent to the patient',
      fallback: 'Couldn’t upload the report.',
    );
  }

  Future<void> _shareReport() => _run('share', () async {
    final bytes = await _orders.reportBytes(_id);
    if (bytes.isEmpty) throw Exception('empty');
    final dir = await getTemporaryDirectory();
    final name = labNumber(_o).replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final mime = '${(_o['reportFile'] as Map?)?['mimeType'] ?? 'application/pdf'}';
    final ext = mime.contains('png')
        ? 'png'
        : mime.contains('jp')
        ? 'jpg'
        : 'pdf';
    final file = File('${dir.path}/${name.isEmpty ? 'lab-report' : name}.$ext');
    await file.writeAsBytes(bytes, flush: true);
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mime)],
        subject: 'Lab report ${labNumber(_o)}',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }, fallback: 'Couldn’t open the report.');

  Future<void> _payment() async {
    final method = await showAppSheet<String>(
      context,
      builder: (ctx) => _PaymentSheet(amount: labTotal(_o)),
    );
    if (method == null) return;
    await _run(
      'payment',
      () => _orders.recordPayment(_id, method),
      done: 'Payment recorded',
    );
  }

  Future<void> _cancel() async {
    final reason = await _askReason(
      title: 'Cancel this order?',
      options: const [
        'Patient asked to cancel',
        'Slot not available',
        'Test not available',
        'Duplicate booking',
      ],
      confirm: 'Cancel order',
      note: labPaid(_o) ? 'The patient’s payment will be refunded.' : null,
    );
    if (reason == null) return;
    await _run(
      'cancel',
      () => _orders.cancel(_id, reason),
      done: 'Order cancelled',
    );
  }

  Future<String?> _askReason({
    required String title,
    required List<String> options,
    required String confirm,
    String? note,
  }) => showAppSheet<String>(
    context,
    builder: (_) => _ReasonSheet(
      title: title,
      options: options,
      confirm: confirm,
      note: note,
    ),
  );

  void _call(String phone) =>
      launchUrl(Uri(scheme: 'tel', path: phone.replaceAll(' ', '')));

  void _directions(Map<String, dynamic> o) {
    final loc = (o['collectionAddressDetails'] as Map?)?['location'];
    final coords = loc is Map ? loc['coordinates'] : null;
    final q = coords is List && coords.length == 2
        ? '${coords[1]},${coords[0]}'
        : Uri.encodeComponent('${o['collectionAddress'] ?? ''}');
    launchUrl(
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$q'),
      mode: LaunchMode.externalApplication,
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final o = _o;
    final accent = ModuleAccent.of(context);
    final stage = labStage(o);
    final showSkeleton = !_loaded && labTests(o).isEmpty;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleSpacing: 0,
        title: Text(
          labNumber(o).isEmpty ? 'Lab order' : labNumber(o),
          style: AppType.sans(
            fontSize: AppType.title,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [if (!showSkeleton) _menu(o, stage)],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                color: accent.color,
                onRefresh: _reload,
                child: showSkeleton
                    ? ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          if (_loadError != null)
                            AppErrorBanner(
                              message: _loadError!,
                              onRetry: _reload,
                            )
                          else
                            const AppDetailSkeleton(),
                        ],
                      )
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        children: _sections(o, stage, accent),
                      ),
              ),
            ),
            if (!showSkeleton) _actionBar(o, stage),
          ],
        ),
      ),
    );
  }

  Widget _menu(Map<String, dynamic> o, LabStage stage) {
    final items = <(String, IconData, String, VoidCallback, bool)>[
      if (!labPaid(o) && stage != LabStage.cancelled)
        ('pay', LucideIcons.wallet, 'Record payment', _payment, false),
      if (stage == LabStage.processing || stage == LabStage.reports)
        ('upload', LucideIcons.upload, 'Upload report file', _upload, false),
      if (stage == LabStage.completed && labHasReport(o))
        ('reupload', LucideIcons.upload, 'Replace report file', _upload, false),
      if ('${labPatient(o)['phone'] ?? ''}'.isNotEmpty)
        (
          'call',
          LucideIcons.phone,
          'Call patient',
          () => _call('${labPatient(o)['phone']}'),
          false,
        ),
      if (stage == LabStage.collect)
        ('cancel', LucideIcons.circleX, 'Cancel order', _cancel, true),
    ];
    if (items.isEmpty) return const SizedBox(width: 8);
    return PopupMenuButton<String>(
      icon: const Icon(LucideIcons.ellipsisVertical, size: 20),
      color: AppColors.bg,
      onSelected: (v) => items.firstWhere((i) => i.$1 == v).$4(),
      itemBuilder: (_) => [
        for (final i in items)
          PopupMenuItem(
            value: i.$1,
            child: Row(
              children: [
                Icon(
                  i.$2,
                  size: 17,
                  color: i.$5 ? AppColors.error : AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Text(
                  i.$3,
                  style: AppType.sans(
                    fontSize: AppType.body,
                    color: i.$5 ? AppColors.error : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  List<Widget> _sections(
    Map<String, dynamic> o,
    LabStage stage,
    ModuleAccent accent,
  ) {
    final p = labPatient(o);
    final slot = labSlot(o);
    final home = labIsHome(o);
    final tests = labTests(o);
    final phone = '${p['phone'] ?? ''}';
    final meta = [
      if (p['age'] != null) '${p['age']} yrs',
      if ('${p['gender'] ?? ''}'.isNotEmpty) capitalised('${p['gender']}'),
      if ('${p['bloodGroup'] ?? ''}'.isNotEmpty) '${p['bloodGroup']}',
    ].join(' · ');
    final summary = labResultSummary(o);
    final due = labTime(o, 'reportDueAt');
    var i = 0;
    Widget enter(Widget c) => AppEntrance(index: i++, child: c);

    return [
      // When + what's happening — what the lab checks first.
      enter(
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: accent.veryLight,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dayLabel(slot),
                          style: AppType.sans(
                            fontSize: AppType.small,
                            fontWeight: FontWeight.w600,
                            color: accent.color,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          timeLabel(slot),
                          style: AppType.sans(
                            fontSize: AppType.figure,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textStrong,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              home ? LucideIcons.house : LucideIcons.building2,
                              size: 13,
                              color: AppColors.textTertiary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              home ? 'Home collection' : 'Lab visit',
                              style: AppType.sans(
                                fontSize: AppType.caption,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      LabStageTag(o),
                      const SizedBox(height: 6),
                      Text(
                        appRupees(labTotal(o)),
                        style: AppType.sans(
                          fontSize: AppType.title,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textStrong,
                        ),
                      ),
                      Text(
                        labPaid(o)
                            ? 'Paid'
                            : stage == LabStage.cancelled
                            ? 'Not charged'
                            : 'To collect',
                        style: AppType.sans(
                          fontSize: AppType.caption,
                          fontWeight: FontWeight.w600,
                          color: labPaid(o)
                              ? accent.color
                              : stage == LabStage.cancelled
                              ? AppColors.textTertiary
                              : AppColors.warning,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _Progress(order: o),
              if (due != null &&
                  stage != LabStage.completed &&
                  stage != LabStage.cancelled) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      LucideIcons.timer,
                      size: 13,
                      color: labOverdue(o)
                          ? AppColors.error
                          : AppColors.textTertiary,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        labOverdue(o)
                            ? 'Report overdue — was due ${dayLabel(due).toLowerCase()} at ${timeLabel(due)}'
                            : 'Report due ${dayLabel(due).toLowerCase()} by ${timeLabel(due)}',
                        style: AppType.sans(
                          fontSize: AppType.caption,
                          fontWeight: labOverdue(o)
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: labOverdue(o)
                              ? AppColors.error
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),

      if (stage == LabStage.cancelled &&
          '${o['cancellationReason'] ?? ''}'.isNotEmpty) ...[
        const SizedBox(height: 12),
        enter(
          _Notice(
            icon: LucideIcons.circleX,
            color: AppColors.error,
            text: 'Cancelled — ${o['cancellationReason']}',
          ),
        ),
      ],

      const SizedBox(height: 20),
      const AppSectionTitle('Patient'),
      enter(
        AppGroup(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  DoctorAvatar(name: labPatientName(o), size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          labPatientName(o),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.sans(
                            fontSize: AppType.title,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textStrong,
                          ),
                        ),
                        if (meta.isNotEmpty)
                          Text(
                            meta,
                            style: AppType.sans(
                              fontSize: AppType.caption,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (phone.isNotEmpty)
                    IconButton(
                      tooltip: 'Call',
                      onPressed: () => _call(phone),
                      icon: Icon(
                        LucideIcons.phone,
                        size: 18,
                        color: accent.color,
                      ),
                    ),
                ],
              ),
            ),
            if (o['fastingRequired'] == true) ...[
              const AppHairline(),
              _Row(
                icon: LucideIcons.utensilsCrossed,
                label: 'Fasting',
                value:
                    '${int.tryParse('${o['fastingHours'] ?? 0}') ?? 8} hours before collection',
                valueColor: AppColors.warning,
              ),
            ],
            if ('${o['patientInstructions'] ?? ''}'.trim().isNotEmpty) ...[
              const AppHairline(),
              _Row(
                icon: LucideIcons.messageSquareText,
                label: 'Patient note',
                value: '${o['patientInstructions']}',
              ),
            ],
            if (o['prescriptionId'] is Map) ...[
              const AppHairline(),
              _Row(
                icon: LucideIcons.fileText,
                label: 'Prescription',
                value:
                    'Ordered by a doctor on Aadya — the report is shared with them too',
              ),
            ],
          ],
        ),
      ),

      if (home) ...[
        const SizedBox(height: 20),
        const AppSectionTitle('Home collection'),
        enter(_homeCard(o, stage)),
      ],

      const SizedBox(height: 20),
      AppSectionTitle(
        tests.length == 1 ? '1 test' : '${tests.length} tests',
      ),
      enter(
        AppGroup(
          children: [
            for (var t = 0; t < tests.length; t++) ...[
              if (t > 0) const AppHairline(),
              _TestRow(test: tests[t]),
            ],
            if (o['packages'] is List && (o['packages'] as List).isNotEmpty) ...[
              const AppHairline(),
              for (final pkg in (o['packages'] as List).whereType<Map>())
                _Row(
                  icon: LucideIcons.package,
                  label: '${pkg['packageName'] ?? 'Package'}',
                  value: appRupees(pkg['price']),
                ),
            ],
          ],
        ),
      ),

      if (o['sample'] is Map &&
          ('${(o['sample'] as Map)['barcode'] ?? ''}').isNotEmpty) ...[
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(
              LucideIcons.scanBarcode,
              size: 14,
              color: AppColors.textTertiary,
            ),
            const SizedBox(width: 6),
            Text(
              'Sample ${(o['sample'] as Map)['barcode']}'
              '${labTime(o, 'collectedAt') == null ? '' : ' · collected ${timeLabel(labTime(o, 'collectedAt'))}'}',
              style: AppType.sans(
                fontSize: AppType.caption,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ],

      if (summary['entered']! > 0) ...[
        const SizedBox(height: 20),
        AppSectionTitle(
          'Results',
          action: stage == LabStage.completed ? null : 'Edit',
          onAction: stage == LabStage.completed ? null : _enterResults,
        ),
        enter(_ResultsPreview(order: o)),
      ],

      const SizedBox(height: 20),
      const AppSectionTitle('Payment'),
      enter(_paymentCard(o, stage)),

      if (o['statusHistory'] is List &&
          (o['statusHistory'] as List).isNotEmpty) ...[
        const SizedBox(height: 20),
        const AppSectionTitle('History'),
        enter(_Timeline(history: (o['statusHistory'] as List))),
      ],
    ];
  }

  Widget _homeCard(Map<String, dynamic> o, LabStage stage) {
    final collector = labPhlebotomist(o);
    final cs = labCollection(o);
    final address = '${o['collectionAddress'] ?? ''}'.trim();
    final details = o['collectionAddressDetails'] is Map
        ? Map<String, dynamic>.from(o['collectionAddressDetails'] as Map)
        : const <String, dynamic>{};
    final contact = '${details['phone'] ?? ''}';
    return AppGroup(
      children: [
        if (address.isNotEmpty)
          InkWell(
            onTap: () => _directions(o),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    LucideIcons.mapPin,
                    size: 17,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      address,
                      style: AppType.sans(
                        fontSize: AppType.body,
                        color: AppColors.textPrimary,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Directions',
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      fontWeight: FontWeight.w700,
                      color: ModuleAccent.of(context).color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (contact.isNotEmpty && contact != '${labPatient(o)['phone']}') ...[
          const AppHairline(),
          _Row(
            icon: LucideIcons.phone,
            label: 'Contact at address',
            value: '${details['contactName'] ?? ''} $contact'.trim(),
            onTap: () => _call(contact),
          ),
        ],
        const AppHairline(),
        _Row(
          icon: LucideIcons.userRound,
          label: 'Phlebotomist',
          value: collector.isEmpty
              ? 'Not assigned yet'
              : '${collector['name']}${'${collector['phone'] ?? ''}'.isEmpty ? '' : ' · ${collector['phone']}'}',
          valueColor: collector.isEmpty ? AppColors.warning : null,
          onTap: stage == LabStage.collect ? _assign : null,
          trailing: stage == LabStage.collect
              ? Text(
                  collector.isEmpty ? 'Assign' : 'Change',
                  style: AppType.sans(
                    fontSize: AppType.caption,
                    fontWeight: FontWeight.w700,
                    color: ModuleAccent.of(context).color,
                  ),
                )
              : null,
        ),
        const AppHairline(),
        _Row(
          icon: LucideIcons.route,
          label: 'Status',
          value: labCollectionLabel(cs),
          valueColor: cs == 'failed' ? AppColors.error : null,
          trailing: cs == 'collected'
              ? AppButton(
                  label: 'At the lab',
                  compact: true,
                  fullWidth: false,
                  loading: _busy == 'delivered_to_lab',
                  onPressed: () => _collectionStep(
                    'delivered_to_lab',
                    'Sample received at the lab',
                  ),
                )
              : null,
        ),
        if (cs == 'failed' &&
            '${o['collectionFailureReason'] ?? ''}'.isNotEmpty) ...[
          const AppHairline(),
          _Row(
            icon: LucideIcons.info,
            label: 'Reason',
            value: '${o['collectionFailureReason']}',
          ),
        ],
      ],
    );
  }

  Widget _paymentCard(Map<String, dynamic> o, LabStage stage) {
    final subtotal = num.tryParse('${o['subtotal'] ?? 0}') ?? 0;
    final collection = num.tryParse('${o['collectionCharges'] ?? 0}') ?? 0;
    final discount = num.tryParse('${o['discountAmount'] ?? 0}') ?? 0;
    final paidVia = '${o['paymentId'] ?? ''}'.split('-').first.toLowerCase();
    final status = '${o['paymentStatus'] ?? 'pending'}';
    return AppGroup(
      children: [
        if (subtotal > 0)
          _Row(
            icon: LucideIcons.flaskConical,
            label: 'Tests',
            value: appRupees(subtotal),
          ),
        if (collection > 0) ...[
          const AppHairline(),
          _Row(
            icon: LucideIcons.house,
            label: 'Home collection',
            value: appRupees(collection),
          ),
        ],
        if (discount > 0) ...[
          const AppHairline(),
          _Row(
            icon: LucideIcons.badgePercent,
            label: 'Discount',
            value: '− ${appRupees(discount)}',
          ),
        ],
        const AppHairline(),
        _Row(
          icon: LucideIcons.wallet,
          label: switch (status) {
            'paid' => switch (paidVia) {
              'cash' => 'Paid in cash',
              'upi' => 'Paid by UPI',
              'card' => 'Paid by card',
              _ => 'Paid online',
            },
            'refunded' => 'Refunded',
            _ => o['refundPending'] == true ? 'Refund pending' : 'Not paid yet',
          },
          value: appRupees(labTotal(o)),
          valueBold: true,
          valueColor: status == 'paid' || stage == LabStage.cancelled
              ? null
              : AppColors.warning,
          trailing: status != 'paid' && stage != LabStage.cancelled
              ? AppButton(
                  label: 'Record',
                  compact: true,
                  fullWidth: false,
                  loading: _busy == 'payment',
                  onPressed: _payment,
                )
              : null,
        ),
      ],
    );
  }

  Widget _actionBar(Map<String, dynamic> o, LabStage stage) {
    Widget bar(Widget child) => Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: child,
    );
    Widget pair(Widget left, Widget right) => Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: right),
      ],
    );
    Widget primary(String label, IconData icon, String key, VoidCallback f) =>
        AppButton(
          label: label,
          icon: icon,
          loading: _busy == key,
          onPressed: _busy != null ? null : f,
        );
    Widget secondary(String label, VoidCallback f, {Color? color}) =>
        AppSecondaryButton(
          label: label,
          color: color,
          onPressed: _busy != null ? null : f,
        );

    switch (stage) {
      case LabStage.collect:
        if (!labIsHome(o)) {
          return bar(
            pair(
              secondary('Cancel', _cancel, color: AppColors.error),
              primary(
                'Collect sample',
                LucideIcons.testTube,
                'collect',
                _collect,
              ),
            ),
          );
        }
        return switch (labCollection(o)) {
          'unassigned' || 'failed' => bar(
            pair(
              secondary('Cancel', _cancel, color: AppColors.error),
              primary(
                labCollection(o) == 'failed'
                    ? 'Reassign'
                    : 'Assign phlebotomist',
                LucideIcons.userPlus,
                'assign',
                _assign,
              ),
            ),
          ),
          'assigned' => bar(
            pair(
              secondary('Change', _assign),
              primary(
                'On the way',
                LucideIcons.navigation,
                'en_route',
                () => _collectionStep('en_route', 'Patient will see you’re on the way'),
              ),
            ),
          ),
          'en_route' => bar(
            pair(
              secondary('Failed', _failCollection, color: AppColors.error),
              primary(
                'Arrived',
                LucideIcons.mapPinCheck,
                'arrived',
                () => _collectionStep('arrived', 'Marked as arrived'),
              ),
            ),
          ),
          _ => bar(
            pair(
              secondary('Failed', _failCollection, color: AppColors.error),
              primary(
                'Sample collected',
                LucideIcons.testTube,
                'collect',
                _collect,
              ),
            ),
          ),
        };
      case LabStage.processing:
        return bar(
          pair(
            secondary('Upload file', _upload),
            primary(
              labResultSummary(o)['entered']! > 0
                  ? 'Continue results'
                  : 'Enter results',
              LucideIcons.clipboardPen,
              'results',
              _enterResults,
            ),
          ),
        );
      case LabStage.reports:
        return bar(
          pair(
            secondary('Edit', _enterResults),
            primary(
              'Release report',
              LucideIcons.send,
              'release',
              _release,
            ),
          ),
        );
      case LabStage.completed:
        return bar(
          labHasReport(o)
              ? primary(
                  'Share report',
                  LucideIcons.share2,
                  'share',
                  _shareReport,
                )
              : primary(
                  'Upload report',
                  LucideIcons.upload,
                  'upload',
                  _upload,
                ),
        );
      case LabStage.cancelled:
        return const SizedBox.shrink();
    }
  }
}

// ─────────────────────────── Pieces ───────────────────────────

/// Booked → Collected → Processing → Results → Released.
class _Progress extends StatelessWidget {
  final Map<String, dynamic> order;
  const _Progress({required this.order});

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context).color;
    final cancelled = labStage(order) == LabStage.cancelled;
    final step = switch (labStatus(order)) {
      'requested' || 'scheduled' => 0,
      'sample_collected' => 1,
      'processing' => 2,
      'ready_for_review' => 3,
      'completed' => 4,
      _ => 0,
    };
    const labels = ['Booked', 'Collected', 'Testing', 'Results', 'Released'];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 2,
                        color: i == 0
                            ? Colors.transparent
                            : (i <= step && !cancelled
                                  ? accent
                                  : AppColors.borderStrong),
                      ),
                    ),
                    AnimatedContainer(
                      duration: AppMotion.medium,
                      width: i == step ? 14 : 10,
                      height: i == step ? 14 : 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cancelled
                            ? AppColors.borderStrong
                            : i < step
                            ? accent
                            : i == step
                            ? Colors.white
                            : AppColors.borderStrong,
                        border: i == step && !cancelled
                            ? Border.all(color: accent, width: 3)
                            : null,
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 2,
                        color: i == labels.length - 1
                            ? Colors.transparent
                            : (i < step && !cancelled
                                  ? accent
                                  : AppColors.borderStrong),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  labels[i],
                  maxLines: 1,
                  style: AppType.sans(
                    fontSize: AppType.micro,
                    fontWeight: i == step ? FontWeight.w700 : FontWeight.w500,
                    color: i <= step && !cancelled
                        ? AppColors.textStrong
                        : AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool valueBold;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.valueBold = false,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.textTertiary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppType.sans(
                    fontSize: AppType.caption,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: AppType.sans(
                    fontSize: AppType.body,
                    fontWeight: valueBold ? FontWeight.w700 : FontWeight.w500,
                    color: valueColor ?? AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    ),
  );
}

class _TestRow extends StatelessWidget {
  final Map<String, dynamic> test;
  const _TestRow({required this.test});

  @override
  Widget build(BuildContext context) {
    final tat = int.tryParse('${test['reportTime'] ?? 0}') ?? 0;
    final inPackage = test['includedInPackage'] == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${test['testName'] ?? test['testCode'] ?? 'Test'}',
                  style: AppType.sans(
                    fontSize: AppType.body,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textStrong,
                  ),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if ('${test['sampleType'] ?? ''}'.isNotEmpty)
                      TubeChip('${test['sampleType']}'),
                    if (tat > 0)
                      Text(
                        'Report in $tat h',
                        style: AppType.sans(
                          fontSize: AppType.caption,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    if (test['fastingRequired'] == true)
                      Text(
                        'Fasting',
                        style: AppType.sans(
                          fontSize: AppType.caption,
                          fontWeight: FontWeight.w600,
                          color: AppColors.warning,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            inPackage ? 'In package' : appRupees(test['price']),
            style: AppType.sans(
              fontSize: AppType.small,
              fontWeight: FontWeight.w600,
              color: inPackage ? AppColors.textTertiary : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsPreview extends StatelessWidget {
  final Map<String, dynamic> order;
  const _ResultsPreview({required this.order});

  @override
  Widget build(BuildContext context) {
    final tests = labTests(order)
        .where((t) => t['results'] is List && (t['results'] as List).isNotEmpty)
        .toList();
    return AppGroup(
      children: [
        for (var i = 0; i < tests.length; i++) ...[
          if (i > 0) const AppHairline(),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${tests[i]['testName'] ?? tests[i]['testCode']}',
                  style: AppType.sans(
                    fontSize: AppType.small,
                    fontWeight: FontWeight.w700,
                    color: ModuleAccent.of(context).color,
                  ),
                ),
                const SizedBox(height: 6),
                for (final r in (tests[i]['results'] as List).whereType<Map>())
                  if ('${r['value'] ?? ''}'.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${r['parameter']}',
                              style: AppType.sans(
                                fontSize: AppType.small,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            '${r['value']} ${r['unit'] ?? ''}'.trim(),
                            style: AppType.sans(
                              fontSize: AppType.small,
                              fontWeight: r['flag'] != null && r['flag'] != 'normal'
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: labFlagColor('${r['flag']}'),
                            ),
                          ),
                          SizedBox(
                            width: 64,
                            child: Text(
                              labFlagLabel('${r['flag']}'),
                              textAlign: TextAlign.right,
                              style: AppType.sans(
                                fontSize: AppType.micro,
                                fontWeight: FontWeight.w700,
                                color: labFlagColor('${r['flag']}'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],
        if ('${order['resultNotes'] ?? ''}'.trim().isNotEmpty) ...[
          const AppHairline(),
          _Row(
            icon: LucideIcons.notebookPen,
            label: 'Remarks',
            value: '${order['resultNotes']}',
          ),
        ],
      ],
    );
  }
}

class _Timeline extends StatelessWidget {
  final List history;
  const _Timeline({required this.history});

  @override
  Widget build(BuildContext context) {
    final rows = history.whereType<Map>().toList().reversed.take(12).toList();
    return AppGroup(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const AppHairline(),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == 0
                          ? ModuleAccent.of(context).color
                          : AppColors.borderStrong,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _note(rows[i]),
                    style: AppType.sans(
                      fontSize: AppType.small,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _when(rows[i]['at']),
                  style: AppType.sans(
                    fontSize: AppType.caption,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static String _note(Map r) {
    final note = '${r['note'] ?? ''}'.trim();
    if (note.isEmpty || note.startsWith('Status changed')) {
      return labStatusLabel('${r['status'] ?? ''}');
    }
    // "Collection status: en_route" → "On the way".
    if (note.startsWith('Collection status: ')) {
      return labCollectionLabel(note.substring(19).trim());
    }
    return note;
  }

  static String _when(dynamic raw) {
    final d = DateTime.tryParse('${raw ?? ''}')?.toLocal();
    if (d == null) return '';
    final now = DateTime.now();
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    return sameDay
        ? DateFormat('h:mm a').format(d)
        : DateFormat('d MMM, h:mm a').format(d);
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Notice({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AppType.sans(
              fontSize: AppType.small,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────── Sheets ───────────────────────────

/// Which tubes to draw (grouped by sample type) and the tube's barcode.
class _CollectSheet extends StatefulWidget {
  final List<Map<String, dynamic>> tests;
  final String collector;
  final bool fasting;
  final int fastingHours;
  const _CollectSheet({
    required this.tests,
    required this.collector,
    required this.fasting,
    required this.fastingHours,
  });

  @override
  State<_CollectSheet> createState() => _CollectSheetState();
}

class _CollectSheetState extends State<_CollectSheet> {
  final _barcode = TextEditingController();
  late final _by = TextEditingController(text: widget.collector);
  bool _fastingChecked = false;

  @override
  void dispose() {
    _barcode.dispose();
    _by.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await scanPharmacyBarcode(
      context,
      hint: 'Scan the label on the sample tube',
    );
    if (code != null && mounted) setState(() => _barcode.text = code);
  }

  @override
  Widget build(BuildContext context) {
    final byTube = <String, List<String>>{};
    for (final t in widget.tests) {
      final key = tubeFor('${t['sampleType'] ?? ''}').label;
      byTube.putIfAbsent(key, () => []).add('${t['testName'] ?? t['testCode']}');
    }
    final sampleFor = {
      for (final t in widget.tests)
        tubeFor('${t['sampleType'] ?? ''}').label: '${t['sampleType'] ?? ''}',
    };
    final canConfirm = !widget.fasting || _fastingChecked;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Collect sample',
            style: AppType.sans(
              fontSize: AppType.heading,
              fontWeight: FontWeight.w800,
              color: AppColors.textStrong,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tubes to draw',
            style: AppType.sans(
              fontSize: AppType.caption,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          for (final e in byTube.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    width: 14,
                    height: 22,
                    decoration: BoxDecoration(
                      color: tubeFor(sampleFor[e.key]).color,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                        bottom: Radius.circular(7),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sampleFor[e.key]!.isEmpty ? e.key : sampleFor[e.key]!,
                          style: AppType.sans(
                            fontSize: AppType.body,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textStrong,
                          ),
                        ),
                        Text(
                          e.value.join(', '),
                          style: AppType.sans(
                            fontSize: AppType.caption,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (widget.fasting)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _fastingChecked,
              activeColor: ModuleAccent.of(context).color,
              onChanged: (v) => setState(() => _fastingChecked = v ?? false),
              title: Text(
                'Patient has fasted ${widget.fastingHours > 0 ? widget.fastingHours : 8} hours',
                style: AppType.sans(
                  fontSize: AppType.body,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          const SizedBox(height: 8),
          AppTextField(
            label: 'Tube barcode',
            hint: 'Scan or type',
            controller: _barcode,
            icon: LucideIcons.scanBarcode,
            trailing: IconButton(
              tooltip: 'Scan',
              onPressed: _scan,
              icon: Icon(
                LucideIcons.scanLine,
                size: 18,
                color: ModuleAccent.of(context).color,
              ),
            ),
          ),
          AppTextField(
            label: 'Collected by',
            controller: _by,
            textCapitalization: TextCapitalization.words,
          ),
          AppButton(
            label: 'Mark collected',
            icon: LucideIcons.check,
            onPressed: canConfirm
                ? () => Navigator.pop(context, (
                    barcode: _barcode.text.trim(),
                    by: _by.text.trim(),
                  ))
                : null,
          ),
        ],
      ),
    );
  }
}

/// Phlebotomists with today's load, so work spreads evenly.
class _AssignSheet extends ConsumerStatefulWidget {
  final String current;
  const _AssignSheet({required this.current});

  @override
  ConsumerState<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends ConsumerState<_AssignSheet> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(labStaffProvider.notifier).load(silent: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(labStaffProvider);
    final people = ref.read(labStaffProvider.notifier).phlebotomists;
    final accent = ModuleAccent.of(context).color;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Assign phlebotomist',
            style: AppType.sans(
              fontSize: AppType.heading,
              fontWeight: FontWeight.w800,
              color: AppColors.textStrong,
            ),
          ),
          const SizedBox(height: 12),
          if (!state.hasLoaded && state.error == null)
            const AppListSkeleton(count: 3)
          else if (state.error != null && !state.hasLoaded)
            AppErrorBanner(
              message: state.error!,
              onRetry: () => ref.read(labStaffProvider.notifier).load(),
            )
          else if (people.isEmpty) ...[
            AppEmptyState(
              icon: LucideIcons.userPlus,
              text: 'No phlebotomists yet. Add your team to assign home collections.',
            ),
            const SizedBox(height: 12),
            AppButton(
              label: 'Add team member',
              icon: LucideIcons.plus,
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  AppPageRoute(builder: (_) => const PathologyStaffScreen()),
                );
              },
            ),
          ] else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final s in people)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: () => Navigator.pop(context, s),
                      leading: DoctorAvatar(name: '${s['name']}', size: 38),
                      title: Text(
                        '${s['name']}',
                        style: AppType.sans(
                          fontSize: AppType.body,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textStrong,
                        ),
                      ),
                      subtitle: Text(
                        [
                          '${s['todayAssigned'] ?? 0} today',
                          if (s['servicePincodes'] is List &&
                              (s['servicePincodes'] as List).isNotEmpty)
                            (s['servicePincodes'] as List).take(3).join(', '),
                        ].join(' · '),
                        style: AppType.sans(
                          fontSize: AppType.caption,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      trailing: '${s['_id']}' == widget.current
                          ? Icon(LucideIcons.check, color: accent, size: 18)
                          : null,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PaymentSheet extends StatelessWidget {
  final num amount;
  const _PaymentSheet({required this.amount});

  @override
  Widget build(BuildContext context) {
    Widget option(String key, IconData icon, String label) => ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => Navigator.pop(context, key),
      leading: Icon(icon, color: ModuleAccent.of(context).color),
      title: Text(
        label,
        style: AppType.sans(
          fontSize: AppType.body,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      trailing: const Icon(
        LucideIcons.chevronRight,
        size: 16,
        color: AppColors.textDisabled,
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Received ${appRupees(amount)}',
            style: AppType.sans(
              fontSize: AppType.heading,
              fontWeight: FontWeight.w800,
              color: AppColors.textStrong,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'How did the patient pay?',
            style: AppType.sans(
              fontSize: AppType.caption,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          option('upi', LucideIcons.smartphone, 'UPI'),
          option('cash', LucideIcons.banknote, 'Cash'),
          option('card', LucideIcons.creditCard, 'Card'),
        ],
      ),
    );
  }
}

class _ReasonSheet extends StatefulWidget {
  final String title;
  final List<String> options;
  final String confirm;
  final String? note;
  const _ReasonSheet({
    required this.title,
    required this.options,
    required this.confirm,
    this.note,
  });

  @override
  State<_ReasonSheet> createState() => _ReasonSheetState();
}

class _ReasonSheetState extends State<_ReasonSheet> {
  String? _picked;
  final _other = TextEditingController();

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  String get _reason =>
      _picked == 'Other' ? _other.text.trim() : (_picked ?? '');

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      8,
      20,
      MediaQuery.of(context).viewInsets.bottom + 20,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: AppType.sans(
            fontSize: AppType.heading,
            fontWeight: FontWeight.w800,
            color: AppColors.textStrong,
          ),
        ),
        if (widget.note != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.note!,
            style: AppType.sans(
              fontSize: AppType.caption,
              color: AppColors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in [...widget.options, 'Other'])
              AppFilterChip(
                label: o,
                selected: _picked == o,
                onTap: () => setState(() => _picked = o),
              ),
          ],
        ),
        if (_picked == 'Other') ...[
          const SizedBox(height: 12),
          AppTextField(
            label: 'Reason',
            controller: _other,
            textCapitalization: TextCapitalization.sentences,
            margin: EdgeInsets.zero,
          ),
        ],
        const SizedBox(height: 16),
        ListenableBuilder(
          listenable: _other,
          builder: (_, _) => AppButton(
            label: widget.confirm,
            onPressed: _reason.isEmpty
                ? null
                : () => Navigator.pop(context, _reason),
          ),
        ),
      ],
    ),
  );
}
