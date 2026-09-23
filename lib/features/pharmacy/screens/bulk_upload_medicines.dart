import 'dart:io';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/pharmacy_type.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/network/api_service.dart';
import '../theme/pharmacy_colors.dart';
import '../../dashboard/providers/dashboard_provider.dart';
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
          'Import Medicines',
          style: PharmacyType.sans(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: PharmacyColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StepIndicator(current: _step),
            const SizedBox(height: 20),
            PharmacyCard(
              margin: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.arrow_down_doc,
                        size: 18,
                        color: PharmacyColors.info,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Get the template',
                              style: PharmacyType.sans(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: PharmacyColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Download the sample file with the exact columns to fill in',
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
                  const SizedBox(height: 14),
                  PharmacySecondaryButton(
                    label: _downloadingTemplate
                        ? 'Downloading…'
                        : 'Download Sample File',
                    icon: CupertinoIcons.arrow_down_doc,
                    onPressed: _downloadingTemplate ? null : _downloadTemplate,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            PharmacyCard(
              margin: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.arrow_up_doc,
                        size: 18,
                        color: PharmacyColors.green,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Select CSV or Excel file',
                              style: PharmacyType.sans(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: PharmacyColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Fill the template, then upload it here',
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
                  const SizedBox(height: 14),
                  _dropZone(),
                  const SizedBox(height: 14),
                  PharmacyButton(
                    label: _uploading ? 'Checking…' : 'Check File',
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
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: PharmacyMetricTile(
                      label: _isPreview ? 'Ready' : 'Added',
                      value: '$_validCount',
                      color: PharmacyColors.success,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PharmacyMetricTile(
                      label: 'Warnings',
                      value: '${_report!['warnings'] ?? 0}',
                      color: PharmacyColors.warning,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PharmacyMetricTile(
                      label: 'Errors',
                      value: '${_report!['failed'] ?? 0}',
                      color: PharmacyColors.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _confirmBar(),
              const SizedBox(height: 16),
              Text(
                _isPreview ? 'What will be imported' : 'Import result',
                style: PharmacyType.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: PharmacyColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              ...results.map((r) {
                final status = r['status']?.toString() ?? '';
                final failed = status == 'failed';
                final note = r['error'] ?? r['note'];
                return PharmacyCard(
                  borderColor: failed
                      ? PharmacyColors.error.withValues(alpha: 0.3)
                      : null,
                  child: Row(
                    children: [
                      Icon(
                        failed
                            ? CupertinoIcons.xmark_circle
                            : CupertinoIcons.checkmark_circle,
                        size: 18,
                        color: failed
                            ? PharmacyColors.error
                            : PharmacyColors.success,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Row ${r['row']}: ${r['medicineName'] ?? ''}',
                              style: PharmacyType.sans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: PharmacyColors.textPrimary,
                              ),
                            ),
                            if (note != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                '$note',
                                style: PharmacyType.sans(
                                  fontSize: 11.5,
                                  color: failed
                                      ? PharmacyColors.error
                                      : PharmacyColors.warning,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  /// Sits between the counts and the row list. In preview it is the commit
  /// control; after the import it is the receipt. Nothing reaches the
  /// database until the button here is pressed.
  Widget _confirmBar() {
    if (!_isPreview) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: PharmacyColors.greenVeryLight,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: PharmacyColors.greenLight),
        ),
        child: Row(
          children: [
            const Icon(
              LucideIcons.circleCheckBig,
              size: 17,
              color: PharmacyColors.greenDark,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$_validCount ${_validCount == 1 ? 'medicine' : 'medicines'} added to your inventory',
                style: PharmacyType.sans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: PharmacyColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final nothingToImport = _validCount == 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
      decoration: BoxDecoration(
        color: PharmacyColors.bgSecondary,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: PharmacyColors.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                nothingToImport
                    ? LucideIcons.circleAlert
                    : LucideIcons.hourglass,
                size: 16,
                color: nothingToImport
                    ? PharmacyColors.error
                    : PharmacyColors.warning,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  nothingToImport
                      ? 'Nothing to import yet'
                      : 'Nothing has been saved yet',
                  style: PharmacyType.sans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: PharmacyColors.textStrong,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 25),
            child: Text(
              nothingToImport
                  ? 'Every row has an error. Fix them in the file and check it again.'
                  : 'This is a preview of the file. Review the rows below, then confirm to add them.',
              style: PharmacyType.sans(
                fontSize: 11.5,
                height: 1.45,
                color: PharmacyColors.textSecondary,
              ),
            ),
          ),
          if (!nothingToImport) ...[
            const SizedBox(height: 12),
            PharmacyButton(
              label: _importing
                  ? 'Importing…'
                  : 'Confirm & Import $_validCount ${_validCount == 1 ? 'Medicine' : 'Medicines'}',
              icon: LucideIcons.circleCheckBig,
              loading: _importing,
              onPressed: _importing ? null : _confirmImport,
            ),
          ],
        ],
      ),
    );
  }

  /// The file picker, as a drop-zone: a tall dashed panel with the icon, the
  /// call to action and the accepted formats stacked in its centre.
  ///
  /// A dashed edge is the established signal for "put a file here" — a solid
  /// 1px box reads as a text input, which is what this looked like before and
  /// why it was easy to miss. Flutter has no dashed BorderSide, so the dashes
  /// are stroked by [_DashedBorderPainter] as a foreground painter; drawing
  /// them behind the child would put half of each dash under the panel fill.
  Widget _dropZone() {
    final picked = _pickedFileName != null;
    final edge = picked ? PharmacyColors.green : PharmacyColors.textDisabled;

    return InkWell(
      onTap: _pickFile,
      borderRadius: BorderRadius.circular(14),
      child: CustomPaint(
        foregroundPainter: _DashedBorderPainter(color: edge, radius: 14),
        child: Container(
          width: double.infinity,
          height: 186,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: picked
                ? PharmacyColors.greenVeryLight
                : PharmacyColors.bgSecondary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: picked
                      ? PharmacyColors.greenLight
                      : PharmacyColors.cardElevated,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: picked
                        ? PharmacyColors.greenLight
                        : PharmacyColors.borderStrong,
                  ),
                ),
                child: Icon(
                  picked ? LucideIcons.fileCheck2 : LucideIcons.cloudUpload,
                  size: 24,
                  color: picked
                      ? PharmacyColors.greenDark
                      : PharmacyColors.green,
                ),
              ),
              const SizedBox(height: 13),
              Text(
                picked ? _pickedFileName! : 'Choose file',
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: PharmacyType.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: PharmacyColors.textStrong,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                picked
                    ? 'Tap to pick a different file'
                    : 'Tap to browse files on this device',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PharmacyType.sans(
                  fontSize: 11.5,
                  color: PharmacyColors.textSecondary,
                ),
              ),
              const SizedBox(height: 13),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _formatPill('.CSV'),
                  const SizedBox(width: 7),
                  _formatPill('.XLSX'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _formatPill(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: PharmacyColors.cardElevated,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: PharmacyColors.borderStrong),
    ),
    child: Text(
      label,
      style: PharmacyType.sans(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: PharmacyColors.textSecondary,
      ),
    ),
  );
}

class _StepIndicator extends StatelessWidget {
  final int current;
  const _StepIndicator({required this.current});

  static const _labels = ['Upload', 'Preview', 'Confirm'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_labels.length * 2 - 1, (i) {
        if (i.isOdd) {
          final leftDone = (i - 1) ~/ 2 < current;
          return Expanded(
            child: Container(
              height: 2,
              color: leftDone ? PharmacyColors.green : PharmacyColors.border,
            ),
          );
        }
        final step = i ~/ 2;
        final done = step < current;
        final active = step == current;
        return Column(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done || active
                    ? PharmacyColors.green
                    : PharmacyColors.bgSecondary,
                border: Border.all(
                  color: done || active
                      ? PharmacyColors.green
                      : PharmacyColors.border,
                ),
              ),
              child: done
                  ? const Icon(
                      CupertinoIcons.checkmark,
                      size: 13,
                      color: Colors.white,
                    )
                  : Text(
                      '${step + 1}',
                      style: PharmacyType.sans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: active
                            ? Colors.white
                            : PharmacyColors.textTertiary,
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              _labels[step],
              style: PharmacyType.sans(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: done || active
                    ? PharmacyColors.textPrimary
                    : PharmacyColors.textTertiary,
              ),
            ),
          ],
        );
      }),
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
