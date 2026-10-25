import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/pharmacy_colors.dart';
import '../theme/pharmacy_type.dart';
import 'pharmacy_ui.dart';

/// The checks a pharmacist is answerable for before dispensing against a
/// prescription. Shown when they tap Approve, so approval is a recorded
/// decision rather than one tap. Returns the checklist for
/// `POST /merchant/orders/:id/prescription`, or null if they back out.
///
/// The registration number and date also go into the Schedule H1/X register
/// when the order is accepted, which is why they are asked for here.
Future<Map<String, dynamic>?> showPrescriptionChecklist(
  BuildContext context, {
  String? prescriberName,
  String? registration,
  DateTime? issuedOn,
}) => showPharmacySheet<Map<String, dynamic>>(
  context,
  builder: (_) => _PrescriptionChecklistSheet(
    prescriberName: prescriberName,
    registration: registration,
    issuedOn: issuedOn,
  ),
);

class _PrescriptionChecklistSheet extends StatefulWidget {
  final String? prescriberName;
  final String? registration;
  final DateTime? issuedOn;
  const _PrescriptionChecklistSheet({
    this.prescriberName,
    this.registration,
    this.issuedOn,
  });

  @override
  State<_PrescriptionChecklistSheet> createState() =>
      _PrescriptionChecklistSheetState();
}

class _PrescriptionChecklistSheetState
    extends State<_PrescriptionChecklistSheet> {
  static const _checks = [
    ('signaturePresent', "Doctor's name, registration and signature are on it"),
    ('patientMatches', 'Patient name matches this order'),
    ('medicinesMatch', 'Every ordered medicine and quantity is prescribed'),
    ('withinValidity', 'The date is recent enough to dispense against'),
  ];

  final Map<String, bool> _ticked = {for (final c in _checks) c.$1: false};
  late final _name = TextEditingController(text: widget.prescriberName ?? '');
  late final _registration = TextEditingController(
    text: widget.registration ?? '',
  );
  late DateTime? _date = widget.issuedOn;

  @override
  void initState() {
    super.initState();
    // Rebuild so Approve enables as soon as the number is typed.
    _registration.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _registration.dispose();
    super.dispose();
  }

  bool get _complete =>
      _ticked.values.every((v) => v) && _registration.text.trim().isNotEmpty;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      helpText: 'Prescription date',
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Before you approve',
          style: PharmacyType.sans(
            fontSize: PharmacyType.title,
            fontWeight: FontWeight.w700,
            color: PharmacyColors.textStrong,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tick each check against the prescription. This is saved with the order.',
          style: PharmacyType.sans(
            fontSize: PharmacyType.caption,
            color: PharmacyColors.textTertiary,
          ),
        ),
        const SizedBox(height: 14),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PharmacyGroup(
                  children: [
                    for (final (i, c) in _checks.indexed) ...[
                      if (i > 0) const PharmacyHairline(),
                      _checkRow(c.$1, c.$2),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                PharmacyTextField(
                  label: "Doctor's registration no.",
                  controller: _registration,
                  hint: 'As written on the prescription',
                  required: true,
                  dense: true,
                  textCapitalization: TextCapitalization.characters,
                  margin: const EdgeInsets.only(bottom: 12),
                ),
                PharmacyTextField(
                  label: "Doctor's name",
                  controller: _name,
                  dense: true,
                  textCapitalization: TextCapitalization.words,
                  margin: const EdgeInsets.only(bottom: 12),
                ),
                PharmacyPickerField(
                  label: 'Prescription date',
                  valueText: _date == null
                      ? 'Select date'
                      : DateFormat('d MMM yyyy').format(_date!),
                  onTap: _pickDate,
                  margin: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: PharmacySecondaryButton(
                label: 'Back',
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: PharmacyButton(
                label: 'Approve',
                icon: LucideIcons.circleCheckBig,
                onPressed: !_complete
                    ? null
                    : () => Navigator.pop(context, {
                        ..._ticked,
                        'prescriberRegistration': _registration.text.trim(),
                        if (_name.text.trim().isNotEmpty)
                          'prescriberName': _name.text.trim(),
                        if (_date != null)
                          'prescriptionDate': _date!.toIso8601String(),
                      }),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _checkRow(String key, String label) {
    final on = _ticked[key] ?? false;
    return InkWell(
      onTap: () => setState(() => _ticked[key] = !on),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            AnimatedContainer(
              duration: PharmacyMotion.fast,
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: on ? PharmacyColors.green : PharmacyColors.bg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: on
                      ? PharmacyColors.green
                      : PharmacyColors.borderStrong,
                  width: 1.5,
                ),
              ),
              child: on
                  ? const Icon(LucideIcons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: PharmacyType.sans(
                  fontSize: PharmacyType.body,
                  color: PharmacyColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen scan with pinch zoom, double-tap zoom and rotation — phone
/// photos of prescriptions arrive sideways as often as not.
Future<void> openPrescriptionScan(
  BuildContext context, {
  required String url,
  required Map<String, String> headers,
}) => Navigator.of(context).push(
  PharmacyPageRoute(
    builder: (_) => _PrescriptionScanViewer(url: url, headers: headers),
  ),
);

class _PrescriptionScanViewer extends StatefulWidget {
  final String url;
  final Map<String, String> headers;
  const _PrescriptionScanViewer({required this.url, required this.headers});

  @override
  State<_PrescriptionScanViewer> createState() =>
      _PrescriptionScanViewerState();
}

class _PrescriptionScanViewerState extends State<_PrescriptionScanViewer>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  late final AnimationController _zoomAnim = AnimationController(
    vsync: this,
    duration: PharmacyMotion.medium,
  )..addListener(() => _transform.value = _zoomTween!.evaluate(_zoomAnim));
  Matrix4Tween? _zoomTween;
  int _turns = 0;
  TapDownDetails? _doubleTapAt;

  @override
  void dispose() {
    _zoomAnim.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _animateTo(Matrix4 target) {
    _zoomTween = Matrix4Tween(begin: _transform.value, end: target);
    _zoomAnim.forward(from: 0);
  }

  /// Double tap zooms 2.5x into the tapped spot, or back out if zoomed.
  void _onDoubleTap() {
    if (_transform.value.getMaxScaleOnAxis() > 1.05) {
      _animateTo(Matrix4.identity());
      return;
    }
    final p = _doubleTapAt?.localPosition ?? Offset.zero;
    const s = 2.5;
    _animateTo(
      Matrix4.identity()
        ..translateByDouble(-p.dx * (s - 1), -p.dy * (s - 1), 0, 1)
        ..scaleByDouble(s, s, 1, 1),
    );
  }

  void _rotate() {
    setState(() => _turns = (_turns + 1) % 4);
    _transform.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Prescription',
          style: PharmacyType.sans(
            fontSize: PharmacyType.title,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Rotate',
            icon: const Icon(LucideIcons.rotateCw, color: Colors.white),
            onPressed: _rotate,
          ),
          IconButton(
            tooltip: 'Fit to screen',
            icon: const Icon(LucideIcons.minimize2, color: Colors.white),
            onPressed: () => _animateTo(Matrix4.identity()),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onDoubleTapDown: (d) => _doubleTapAt = d,
              onDoubleTap: _onDoubleTap,
              child: InteractiveViewer(
                transformationController: _transform,
                minScale: 0.8,
                maxScale: 6,
                child: Center(
                  child: AnimatedRotation(
                    turns: _turns / 4,
                    duration: PharmacyMotion.medium,
                    curve: Curves.easeOutCubic,
                    child: Image.network(
                      widget.url,
                      headers: widget.headers,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Text(
                        'This file could not be shown.',
                        style: PharmacyType.sans(
                          fontSize: PharmacyType.body,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                'Pinch or double-tap to zoom · rotate from the top bar',
                textAlign: TextAlign.center,
                style: PharmacyType.sans(
                  fontSize: PharmacyType.caption,
                  color: Colors.white60,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
