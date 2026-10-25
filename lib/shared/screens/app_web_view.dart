import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../ui/app_ui.dart';

/// In-app browser, used mainly for video consultations (Jitsi).
///
/// A video call needs two permissions: the phone's (Android/iOS runtime
/// permission for camera and microphone, asked before the page loads) and
/// the page's (the WebView's own getUserMedia prompt, granted in
/// [WebViewController.new]'s onPermissionRequest). Without both the call
/// opened with no camera or mic. "Open in browser" is the fallback for phones
/// whose system WebView still can't run the call.
class AppWebView extends StatefulWidget {
  final String url;
  final String title;

  const AppWebView({
    super.key,
    required this.url,
    this.title = 'Aadya Plus Pro',
  });

  @override
  State<AppWebView> createState() => _AppWebViewState();
}

class _AppWebViewState extends State<AppWebView> {
  late final WebViewController _controller;
  late final String _url;
  bool _loading = true;
  double _progress = 0;
  bool _mediaDenied = false;

  bool get _isCall => _url.contains('meet.jit.si') || _url.contains('jitsi');

  @override
  void initState() {
    super.initState();
    var url = widget.url;
    if (url.contains('meet.jit.si')) {
      // Skip Jitsi's "open in app / browser" landing page.
      url += url.contains('#')
          ? '&config.disableDeepLinking=true'
          : '#config.disableDeepLinking=true';
    }
    _url = url;

    _controller =
        WebViewController(onPermissionRequest: (request) => request.grant())
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.white)
          ..setNavigationDelegate(
            NavigationDelegate(
              onProgress: (p) {
                if (mounted) setState(() => _progress = p / 100);
              },
              onPageStarted: (_) {
                if (mounted) setState(() => _loading = true);
              },
              onPageFinished: (_) {
                if (mounted) setState(() => _loading = false);
              },
            ),
          );
    _start();
  }

  Future<void> _start() async {
    if (_isCall) {
      final results = await [
        Permission.camera,
        Permission.microphone,
      ].request();
      final denied = results.values.any((s) => !s.isGranted);
      if (mounted && denied) setState(() => _mediaDenied = true);
    }
    await _controller.loadRequest(Uri.parse(_url));
  }

  Future<void> _openExternally() =>
      launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context).color;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleSpacing: 0,
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.sans(
            fontSize: AppType.title,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(LucideIcons.rotateCw, size: 19),
            onPressed: () => _controller.reload(),
          ),
          IconButton(
            tooltip: 'Open in browser',
            icon: const Icon(LucideIcons.externalLink, size: 19),
            onPressed: _openExternally,
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 2,
            child: _loading
                ? LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress,
                    backgroundColor: Colors.transparent,
                    color: accent,
                    minHeight: 2,
                  )
                : null,
          ),
          if (_mediaDenied)
            Container(
              width: double.infinity,
              color: AppColors.warningBg,
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.cameraOff,
                    size: 16,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Camera or microphone is off for this app. Allow both in settings for the call to work.',
                      style: AppType.sans(
                        fontSize: AppType.small,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: openAppSettings,
                    child: Text(
                      'Settings',
                      style: AppType.sans(
                        fontSize: AppType.small,
                        fontWeight: FontWeight.w700,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
