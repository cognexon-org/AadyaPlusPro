import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/pharmacy_colors.dart';
import '../theme/pharmacy_type.dart';
import 'pharmacy_motion.dart';

/// Opens the camera and returns the first barcode read, or null if the user
/// backs out. Used by Medicines search, Add medicine and Edit medicine.
Future<String?> scanPharmacyBarcode(BuildContext context, {String? hint}) {
  return Navigator.of(context).push<String>(
    PharmacyPageRoute(builder: (_) => _BarcodeScannerScreen(hint: hint)),
  );
}

class _BarcodeScannerScreen extends StatefulWidget {
  final String? hint;
  const _BarcodeScannerScreen({this.hint});

  @override
  State<_BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<_BarcodeScannerScreen> {
  // The formats printed on medicine packs: EAN/UPC on retail strips and
  // boxes, Code 128 on many Indian batches, and QR / Data Matrix on newer
  // packs carrying the government track-and-trace code.
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.qrCode,
      BarcodeFormat.dataMatrix,
    ],
  );
  bool _done = false;
  bool _torch = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final value = code.rawValue?.trim();
      if (value != null && value.isNotEmpty) {
        _done = true;
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final box = (size.width * 0.72).clamp(220.0, 320.0);
    final window = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: box,
      height: box * 0.62,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            scanWindow: window,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraError(error: error),
          ),
          // Dim everything outside the window so it is obvious where to aim.
          CustomPaint(painter: _WindowPainter(window)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  _RoundButton(
                    icon: LucideIcons.x,
                    label: 'Close',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  _RoundButton(
                    icon: _torch
                        ? LucideIcons.flashlightOff
                        : LucideIcons.flashlight,
                    label: _torch ? 'Torch off' : 'Torch on',
                    onTap: () async {
                      await _controller.toggleTorch();
                      if (mounted) setState(() => _torch = !_torch);
                    },
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            top: window.bottom + 28,
            child: Column(
              children: [
                Text(
                  'Point at the barcode on the pack',
                  textAlign: TextAlign.center,
                  style: PharmacyType.sans(
                    fontSize: PharmacyType.title,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.hint ?? 'It scans on its own — no button to press.',
                  textAlign: TextAlign.center,
                  style: PharmacyType.sans(
                    fontSize: PharmacyType.small,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => PharmacyPressable(
    onTap: onTap,
    semanticLabel: label,
    child: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 20, color: Colors.white),
    ),
  );
}

/// Darkens the preview outside [window] and draws green corner marks.
class _WindowPainter extends CustomPainter {
  final Rect window;
  _WindowPainter(this.window);

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(window, const Radius.circular(16));
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(rrect),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    final corner = Paint()
      ..color = PharmacyColors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    const l = 26.0;
    final r = window;
    for (final (p, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(p, p + Offset(l * dx, 0), corner);
      canvas.drawLine(p, p + Offset(0, l * dy), corner);
    }
  }

  @override
  bool shouldRepaint(_WindowPainter old) => old.window != window;
}

class _CameraError extends StatelessWidget {
  final MobileScannerException error;
  const _CameraError({required this.error});

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.cameraOff, size: 32, color: Colors.white),
            const SizedBox(height: 12),
            Text(
              denied
                  ? 'Camera permission is off. Allow it in your phone settings to scan barcodes.'
                  : "The camera couldn't start. Close this screen and try again.",
              textAlign: TextAlign.center,
              style: PharmacyType.sans(
                fontSize: PharmacyType.body,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
