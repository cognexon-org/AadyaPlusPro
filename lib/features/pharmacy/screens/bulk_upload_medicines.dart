import 'dart:io';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/pharmacy_type.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/network/api_service.dart';
import '../theme/pharmacy_colors.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../providers/pharmacy_medicines_provider.dart';
import '../widgets/pharmacy_ui.dart';

class BulkUploadMedicines extends ConsumerStatefulWidget {
  const BulkUploadMedicines({super.key});

  @override
  ConsumerState<BulkUploadMedicines> createState() =>
      _BulkUploadMedicinesState();
}

class _BulkUploadMedicinesState extends ConsumerState<BulkUploadMedicines> {
  bool _downloadingTemplate = false;
  bool _uploading = false;
  bool _importing = false;
  String? _pickedFileName;
  String? _pickedFilePath;
  Map<String, dynamic>? _report;

  /// True while [_report] is a dry-run preview — nothing has been written yet
  /// and the user still has to confirm. False once the real import has run.
  bool _isPreview = false;

  int get _step {
    if (_report != null) return 2;
    if (_pickedFilePath != null) return 1;
    return 0;
  }

  int get _validCount =>
      num.tryParse('${_report?['created'] ?? 0}')?.toInt() ?? 0;

  Future<void> _downloadTemplate() async {
    setState(() => _downloadingTemplate = true);

    // Fetching and handing off are separate failure modes with different
    // fixes (bad connection vs. no app to receive the file), so they get
    // separate try blocks and separate messages. Collapsing them into one
    // catch tells the user "check your connection" for a problem that has
    // nothing to do with the network.
    final File file;
    try {
      final response = await ApiService().downloadMedicineBulkUploadTemplate();
      final bytes = response.data ?? const <int>[];
      if (bytes.isEmpty) throw StateError('empty template response');
      // Temp dir, not the documents dir: this file only needs to live long
      // enough to hand off to another app, and the OS can reclaim it after.
      final dir = await getTemporaryDirectory();
      file = File('${dir.path}/medicine_bulk_upload_template.xlsx');
      await file.writeAsBytes(bytes, flush: true);
    } catch (e, stack) {
      debugPrint('[bulk-upload] template download failed: $e\n$stack');
      _showError("Couldn't download the template. Check your connection.");
      if (mounted) setState(() => _downloadingTemplate = false);
      return;
    }

    try {
      if (!mounted) return;
      // Must go through the share sheet rather than `launchUrl(Uri.file(...))`:
      // since Android 7 handing a raw file:// URI to another app throws
      // FileUriExposedException, and this file lives in app-private storage
      // that other apps cannot read anyway. share_plus routes it through a
      // FileProvider, which grants the receiving app temporary read access.
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              file.path,
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            ),
          ],
          subject: 'Medicine bulk upload template',
          // iPad needs an anchor rect or the share sheet refuses to present.
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (e, stack) {
      debugPrint('[bulk-upload] template share failed: $e\n$stack');
      // The download itself worked, so say so — otherwise the user retries
      // the fetch over and over trying to fix the wrong thing.
      _showError('Template downloaded, but no app could open it.');
    } finally {
      if (mounted) setState(() => _downloadingTemplate = false);
    }
  }

  /// Raw exceptions must never reach the user: a platform stacktrace is
  /// hundreds of lines, and a SnackBar will happily grow to cover the whole
  /// screen trying to render it.
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
        backgroundColor: PharmacyColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() {
      _pickedFilePath = path;
      _pickedFileName = result!.files.single.name;
      _report = null;
      _isPreview = false;
    });
  }

  /// Step one: send the file for validation only. The server parses and
  /// checks every row but writes nothing, so the report below is a genuine
  /// preview of what an import *would* do.
  Future<void> _validate() async {
    final path = _pickedFilePath;
    if (path == null) return;
    setState(() {
      _uploading = true;
      _report = null;
      _isPreview = false;
    });
    try {
      final response = await ApiService().bulkUploadMedicines(
        path,
        dryRun: true,
      );
      if (!mounted) return;
      setState(() {
        _report = Map<String, dynamic>.from(response.data as Map);
        _isPreview = true;
      });
    } on DioException catch (e) {
      // Surface the server's own validation message when it sends one — that
      // is genuinely useful here ("row 4: invalid category") — otherwise a
      // plain fallback. Never the exception object itself.
      final data = e.response?.data;
      final serverMessage = data is Map
          ? (data['message'] ?? data['error'])?.toString()
          : null;
      _showError(serverMessage ?? 'Upload failed. Please try again.');
    } catch (_) {
      _showError("Couldn't read that file. Please try again.");
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Step two: the same file, for real. Only reachable from a preview that
  /// found at least one importable row.
  Future<void> _confirmImport() async {
    final path = _pickedFilePath;
    if (path == null || !_isPreview) return;

    final proceed = await PharmacyDialog.confirm(
      context,
      title:
          'Import $_validCount ${_validCount == 1 ? 'medicine' : 'medicines'}?',
      message:
          'They will be added to this branch straight away. Rows listed with '
          'an error are skipped and can be fixed and re-uploaded.',
      icon: LucideIcons.circleCheckBig,
      confirmLabel: 'Import',
      destructive: false,
    );
    if (!proceed || !mounted) return;

    setState(() => _importing = true);
    try {
      final response = await ApiService().bulkUploadMedicines(path);
      if (!mounted) return;
      setState(() {
        _report = Map<String, dynamic>.from(response.data as Map);
        _isPreview = false;
      });
      ref.read(pharmacyDashboardProvider.notifier).loadMedicines();
      ref.read(pharmacyMedicinesProvider.notifier).loadMedicines(silent: true);
    } on DioException catch (e) {
      final data = e.response?.data;
      final serverMessage = data is Map
          ? (data['message'] ?? data['error'])?.toString()
          : null;
      _showError(serverMessage ?? 'Import failed. Please try again.');
    } catch (_) {
      _showError('Import failed. Please try again.');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final results =
        (_report?['results'] as List?)?.whereType<Map>().toList() ?? const [];
    return Scaffold(
      backgroundColor: PharmacyColors.bg,
      appBar: AppBar(
        backgroundColor: PharmacyColors.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: PharmacyColors.textPrimary),
        title: Text(
          'Import medicines',
          style: PharmacyType.sans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: PharmacyColors.textStrong,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            PharmacyEntrance(child: _StepIndicator(current: _step)),
            const SizedBox(height: 24),
            PharmacyEntrance(
              index: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PharmacySectionTitle('1. Get the template'),
                  PharmacyGroup(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
                        child: Row(
                          children: [
                            const Icon(
                              LucideIcons.fileSpreadsheet,
                              size: 19,
                              color: PharmacyColors.textHeading,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Sample file', style: _body),
                                  Text(
                                    'Has the exact columns to fill in',
                                    style: _caption,
                                  ),
                                ],
                              ),
                            ),
                            _downloadingTemplate
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: PharmacyColors.green,
                                    ),
                                  )
                                : GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _downloadTemplate,
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Text(
                                        'Download',
                                        style: _body.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: PharmacyColors.greenDark,
                                        ),
                                      ),
                                    ),
                                  ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            PharmacyEntrance(
              index: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PharmacySectionTitle('2. Upload your file'),
                  _dropZone(),
                  const SizedBox(height: 14),
                  PharmacyButton(
                    label: _uploading ? 'Checking…' : 'Check file',
                    icon: LucideIcons.listChecks,
                    loading: _uploading,
                    onPressed: (_pickedFilePath == null || _uploading)
                        ? null
                        : _validate,
                  ),
                ],
              ),
            ),
            if (_report != null) ...[
              const SizedBox(height: 28),
              PharmacySectionTitle(
                _isPreview ? '3. Review and import' : 'Import result',
              ),
              _summary(),
              const SizedBox(height: 12),
              _confirmBar(),
              if (results.isNotEmpty) ...[
                const SizedBox(height: 24),
                PharmacySectionTitle(
                  _isPreview ? 'Rows in the file' : 'Rows imported',
                ),
                PharmacyGroup(
                  children: [
                    for (var i = 0; i < results.length; i++) ...[
                      if (i > 0) const PharmacyHairline(),
                      _resultRow(results[i]),
                    ],
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static final _body = PharmacyType.sans(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: PharmacyColors.textPrimary,
  );
  static final _caption = PharmacyType.sans(
    fontSize: 11.5,
    color: PharmacyColors.textSecondary,
  );

  /// Three counts in one panel — coloured numbers, no tinted tiles.
  Widget _summary() {
    Widget cell(String label, Object value, Color tone) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Text(
              '$value',
              style: PharmacyType.number(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: tone,
              ),
            ),
            const SizedBox(height: 1),
            Text(label, style: _caption),
          ],
        ),
      ),
    );
    Widget divider() =>
        Container(width: 1, height: 32, color: PharmacyColors.bg);
    final failed = num.tryParse('${_report!['failed'] ?? 0}') ?? 0;
    final warnings = num.tryParse('${_report!['warnings'] ?? 0}') ?? 0;
    return PharmacyGroup(
      children: [
        Row(
          children: [
            cell(
              _isPreview ? 'Ready' : 'Added',
              _validCount,
              PharmacyColors.greenDark,
            ),
            divider(),
            cell(
              'Warnings',
              warnings,
              warnings > 0
                  ? PharmacyColors.warning
                  : PharmacyColors.textSecondary,
            ),
            divider(),
            cell(
              'Errors',
              failed,
              failed > 0 ? PharmacyColors.error : PharmacyColors.textSecondary,
            ),
          ],
        ),
      ],
    );
  }

  Widget _resultRow(Map r) {
    final failed = '${r['status'] ?? ''}' == 'failed';
    final note = r['error'] ?? r['note'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              failed ? LucideIcons.circleX : LucideIcons.circleCheck,
              size: 17,
              color: failed ? PharmacyColors.error : PharmacyColors.greenDark,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${r['medicineName'] ?? 'Unnamed'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _body,
                ),
                Text(
                  note == null ? 'Row ${r['row']}' : 'Row ${r['row']} · $note',
                  style: _caption.copyWith(
                    color: note == null
                        ? PharmacyColors.textSecondary
                        : failed
                        ? PharmacyColors.error
                        : PharmacyColors.warning,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// In preview it is the commit control; after the import it is the
  /// receipt. Nothing reaches the database until the button here is pressed.
  Widget _confirmBar() {
    if (!_isPreview) {
      return PharmacyGroup(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.circleCheckBig,
                  size: 18,
                  color: PharmacyColors.greenDark,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    '$_validCount ${_validCount == 1 ? 'medicine' : 'medicines'} added to your inventory',
                    style: _body.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final nothingToImport = _validCount == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          nothingToImport
              ? 'Every row has an error. Fix them in the file and check it again.'
              : 'Nothing has been saved yet. Review the rows below, then import.',
          style: _caption.copyWith(height: 1.45),
        ),
        if (!nothingToImport) ...[
          const SizedBox(height: 12),
          PharmacyButton(
            label: _importing
                ? 'Importing…'
                : 'Import $_validCount ${_validCount == 1 ? 'medicine' : 'medicines'}',
            icon: LucideIcons.check,
            loading: _importing,
            onPressed: _importing ? null : _confirmImport,
          ),
        ],
      ],
    );
  }

  /// The file picker as a drop zone: a dashed panel — the established
  /// signal for "put a file here" — with the call to action in its centre.
  Widget _dropZone() {
    final picked = _pickedFileName != null;
    return PharmacyPressable(
      onTap: _pickFile,
      scale: 0.99,
      child: CustomPaint(
        foregroundPainter: _DashedBorderPainter(
          color: picked ? PharmacyColors.green : PharmacyColors.textDisabled,
          radius: 14,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
          decoration: BoxDecoration(
            color: PharmacyColors.panel,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: PharmacyColors.bg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  picked ? LucideIcons.fileCheck2 : LucideIcons.cloudUpload,
                  size: 21,
                  color: picked
                      ? PharmacyColors.greenDark
                      : PharmacyColors.textHeading,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                picked ? _pickedFileName! : 'Choose a file',
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: _body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: PharmacyColors.textStrong,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                picked ? 'Tap to pick a different file' : '.csv or .xlsx',
                style: _caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three steps as a thin segmented bar with the current step named — a row
/// of numbered circles was more chrome than the screen needed.
class _StepIndicator extends StatelessWidget {
  final int current;
  const _StepIndicator({required this.current});

  static const _labels = ['Upload', 'Preview', 'Import'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step ${current + 1} of 3 · ${_labels[current]}',
          style: PharmacyType.sans(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: PharmacyColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: AnimatedContainer(
                  duration: PharmacyMotion.medium,
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= current
                        ? PharmacyColors.green
                        : PharmacyColors.panel,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Strokes a dashed rounded rectangle around its full paint area. Used as a
/// `foregroundPainter` so the dashes sit on top of the panel fill.
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  // Fixed rather than configurable: there is one drop zone, and unused
  // optional parameters are just dead surface area.
  static const double dash = 6;
  static const double gap = 5;
  static const double strokeWidth = 1.4;

  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    // Inset by half the stroke so the dashes land inside the box rather than
    // being clipped along the outer edge.
    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
