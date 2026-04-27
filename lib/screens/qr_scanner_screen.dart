// lib/screens/qr_scanner_screen.dart
// Real QR / barcode scanner screen using mobile_scanner package
//
// pubspec.yaml dependency required:
//   mobile_scanner: ^5.2.3
//
// Android: add to android/app/src/main/AndroidManifest.xml
//   <uses-permission android:name="android.permission.CAMERA"/>
//
// iOS: add to ios/Runner/Info.plist
//   <key>NSCameraUsageDescription</key>
//   <string>Camera is needed to scan QR codes for attendance.</string>

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerScreen extends StatefulWidget {
  /// Called when a QR code is successfully scanned.
  /// Return true from the callback to pop the screen automatically.
  final Future<bool> Function(String code)? onScanned;

  const QrScannerScreen({super.key, this.onScanned});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    returnImage: false,
  );

  bool _torchOn = false;
  bool _processing = false;
  String? _lastResult;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _controller.stop();
    } else if (state == AppLifecycleState.resumed) {
      _controller.start();
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    if (capture.barcodes.isEmpty) return;

    final code = capture.barcodes.first.rawValue;
    if (code == null || code == _lastResult) return;

    setState(() {
      _processing = true;
      _lastResult = code;
    });

    _controller.stop();

    if (widget.onScanned != null) {
      final shouldPop = await widget.onScanned!(code);
      if (shouldPop && mounted) {
        Navigator.of(context).pop(code);
        return;
      }
    } else {
      // Default: show result sheet
      if (mounted) await _showResultSheet(code);
    }

    if (mounted) {
      setState(() => _processing = false);
      _controller.start();
    }
  }

  Future<void> _showResultSheet(String code) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ResultSheet(code: code),
    );
  }

  void _toggleTorch() {
    _controller.toggleTorch();
    setState(() => _torchOn = !_torchOn);
  }

  void _switchCamera() => _controller.switchCamera();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera feed ───────────────────────────────────────────
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // ── Dark overlay with cutout ──────────────────────────────
          _ScannerOverlay(),

          // ── Top bar ───────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      // Back
                      _iconBtn(
                        icon: Icons.arrow_back_rounded,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      const Expanded(
                        child: Column(
                          children: [
                            Text('QR Scanner',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700)),
                            Text('Scan attendee QR code',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 12)),
                          ],
                        ),
                      ),
                      // Flip camera
                      _iconBtn(
                        icon: Icons.flip_camera_ios_outlined,
                        onTap: _switchCamera,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Scan frame label ──────────────────────────────────────
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 200), // push below center
                if (_processing)
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B2D5B).withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        ),
                        SizedBox(width: 10),
                        Text('Processing...',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // ── Bottom hint + torch ───────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  const Text(
                    'Align the QR code within the frame',
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  // Torch button
                  GestureDetector(
                    onTap: _toggleTorch,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: _torchOn
                            ? const Color(0xFFF5A623)
                            : Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 1.5),
                      ),
                      child: Icon(
                        _torchOn
                            ? Icons.flash_on_rounded
                            : Icons.flash_off_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

// ── Scanner overlay with corner brackets ─────────────────────────────
class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay();

  @override
  Widget build(BuildContext context) {
    const cutoutSize = 260.0;
    final screenSize = MediaQuery.of(context).size;
    final cutoutTop = (screenSize.height - cutoutSize) / 2 - 40;

    return CustomPaint(
      painter: _OverlayPainter(
        cutoutRect: Rect.fromLTWH(
          (screenSize.width - cutoutSize) / 2,
          cutoutTop,
          cutoutSize,
          cutoutSize,
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final Rect cutoutRect;
  const _OverlayPainter({required this.cutoutRect});

  @override
  void paint(Canvas canvas, Size size) {
    final darkPaint = Paint()..color = Colors.black.withOpacity(0.60);
    final clearPaint = Paint()..blendMode = BlendMode.clear;
    final cornerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    final accentPaint = Paint()
      ..color = const Color(0xFF1B2D5B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    // Dark overlay
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), darkPaint);

    // Clear cutout (rounded rect)
    final rrect =
        RRect.fromRectAndRadius(cutoutRect, const Radius.circular(16));
    canvas.drawRRect(rrect, clearPaint);
    canvas.restore();

    // Corner brackets
    const cLen = 28.0; // corner line length
    const r = 16.0; // corner radius matches rrect
    final l = cutoutRect.left;
    final t = cutoutRect.top;
    final ri = cutoutRect.right;
    final b = cutoutRect.bottom;

    void drawCorner(Offset origin, double dx, double dy, Paint paint) {
      final path = Path()
        ..moveTo(origin.dx, origin.dy + dy * cLen)
        ..lineTo(origin.dx, origin.dy + dy * r)
        ..arcToPoint(
          Offset(origin.dx + dx * r, origin.dy),
          radius: const Radius.circular(r),
          clockwise: dy > 0 ? dx < 0 : dx > 0,
        )
        ..lineTo(origin.dx + dx * cLen, origin.dy);
      canvas.drawPath(path, paint);
    }

    // White outer corners
    drawCorner(Offset(l, t), 1, 1, cornerPaint); // TL
    drawCorner(Offset(ri, t), -1, 1, cornerPaint); // TR
    drawCorner(Offset(l, b), 1, -1, cornerPaint); // BL
    drawCorner(Offset(ri, b), -1, -1, cornerPaint); // BR

    // Navy inner corners (offset slightly inward)
    const inset = 5.0;
    drawCorner(Offset(l + inset, t + inset), 1, 1, accentPaint);
    drawCorner(Offset(ri - inset, t + inset), -1, 1, accentPaint);
    drawCorner(Offset(l + inset, b - inset), 1, -1, accentPaint);
    drawCorner(Offset(ri - inset, b - inset), -1, -1, accentPaint);
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) =>
      old.cutoutRect != cutoutRect;
}

// ── Result bottom sheet ───────────────────────────────────────────────
class _ResultSheet extends StatelessWidget {
  final String code;
  const _ResultSheet({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: Color(0xFFD1FAE5),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                color: Color(0xFF059669), size: 28),
          ),
          const SizedBox(height: 14),
          const Text('QR Code Scanned',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1B2D5B))),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              code,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF374151),
                  fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFFDDE1EA)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Scan Again',
                      style: TextStyle(
                          color: Color(0xFF1B2D5B),
                          fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pop(code);
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: const Color(0xFF1B2D5B),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: const Text('Confirm',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
