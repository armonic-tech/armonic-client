import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../api/http_api.dart';
import '../l10n/app_strings.dart';
import '../util/invite_link.dart';

/// Platforms mobile_scanner has an implementation for; elsewhere (Linux,
/// Windows) the entry point is simply not offered.
bool get canScanQr =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// Full-screen camera that pops with the first invite link it reads, in the
/// `<backend>?invite=<token>` shape onboarding takes.
class ScanInviteScreen extends StatefulWidget {
  const ScanInviteScreen({super.key});

  @override
  State<ScanInviteScreen> createState() => _ScanInviteScreenState();
}

class _ScanInviteScreenState extends State<ScanInviteScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _done = false;
  String? _rejected;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final link = backendInviteLink(raw);
      if (inviteTokenFromUrl(link)?.isNotEmpty ?? false) {
        _done = true;
        Navigator.of(context).pop(link);
        return;
      }
      if (_rejected == null) setState(() => _rejected = strings.notAnInviteQr);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(strings.scanInviteQr)),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _ScanError(
              message:
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? strings.cameraPermissionDenied
                  : strings.cameraUnavailable,
            ),
          ),
          IgnorePointer(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final side = (constraints.biggest.shortestSide * 0.7).clamp(
                    160.0,
                    320.0,
                  );
                  return Container(
                    width: side,
                    height: side,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white70, width: 3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: SafeArea(
              child: Text(
                _rejected ?? strings.scanInviteHint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanError extends StatelessWidget {
  final String message;
  const _ScanError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, color: Colors.white70, size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
