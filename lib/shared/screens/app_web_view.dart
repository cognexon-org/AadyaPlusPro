import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/theme/app_theme.dart';

class AppWebView extends StatefulWidget {
  final String url;
  final String title;

  const AppWebView({
    super.key,
    required this.url,
    this.title = 'Aadya Plus Professional',
  });

  @override
  State<AppWebView> createState() => _AppWebViewState();
}

class _AppWebViewState extends State<AppWebView> {
  late final WebViewController _controller;
  bool _loading = true;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    String finalUrl = widget.url;
    if (finalUrl.contains('meet.jit.si')) {
      // Bypass Jitsi's landing page (Join via App/Browser)
      if (!finalUrl.contains('#')) {
        finalUrl += '#config.disableDeepLinking=true';
      } else if (!finalUrl.contains('config.disableDeepLinking=true')) {
        finalUrl += '&config.disableDeepLinking=true';
      }
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (mounted) {
              setState(() {
                _progress = progress / 100;
              });
            }
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _loading = true;
              });
            }
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _loading = false;
              });
            }
          },
          onWebResourceError: (WebResourceError error) {},
        ),
      )
      ..loadRequest(Uri.parse(finalUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            Text(
              widget.url,
              style: GoogleFonts.manrope(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.refresh, size: 20),
            onPressed: () => _controller.reload(),
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.doc_on_doc, size: 20),
            onPressed: () {
              // We could add clipboard here too
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading)
            LinearProgressIndicator(
              value: _progress,
              backgroundColor: Colors.white,
              color: AppTheme.primary,
              minHeight: 2,
            ),
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }
}
