import 'package:mcri_residents_app/config/env.dart';
import 'package:mcri_residents_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

const _accent = AppColors.primary;
const _targetPath = '/admin/audit-logs';

class AuditLogsWebViewScreen extends StatefulWidget {
  final String token;
  const AuditLogsWebViewScreen({super.key, required this.token});

  @override
  State<AuditLogsWebViewScreen> createState() => _AuditLogsWebViewScreenState();
}

class _AuditLogsWebViewScreenState extends State<AuditLogsWebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _navigatedToTarget = false;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            // This is the actual fix: the website's /auth/callback always
            // tries to hand off to the app first via this custom scheme —
            // which is exactly what our own AndroidManifest.xml registers
            // us to intercept. Blocking the navigation here (rather than
            // letting the OS see it) means Android never gets the chance
            // to bounce back into this app — the website's own 1.2s
            // fallback timer then just continues normally, inside this
            // WebView, as if no app were installed at all.
            if (uri == null || uri.scheme == AppConfig.deepLinkScheme) {
              return NavigationDecision.prevent;
            }
            // This WebView holds an admin session: never let it navigate
            // the main frame off the official website (or onto plain http).
            if (request.isMainFrame &&
                (uri.scheme != 'https' || uri.host != AppConfig.webHost)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (url) {
            setState(() => _loading = false);
            // Once the callback page has done its job and redirected to
            // the logged-in homepage, move on to the actual audit logs
            // page — this only fires once, after the real handoff completes.
            final uri = Uri.tryParse(url);
            if (!_navigatedToTarget &&
                uri != null &&
                uri.host == AppConfig.webHost &&
                uri.path != '/auth/callback' &&
                uri.path != _targetPath) {
              _navigatedToTarget = true;
              _controller.loadRequest(
                Uri.https(AppConfig.webHost, _targetPath),
              );
            }
          },
        ),
      )
      ..loadRequest(
        Uri.https(AppConfig.webHost, '/auth/callback', {'token': widget.token}),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit logs'),
        actions: [
          IconButton(
            onPressed: () => _controller.loadRequest(
              Uri.https(AppConfig.webHost, _targetPath),
            ),
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload audit logs',
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: _accent)),
        ],
      ),
    );
  }
}
