import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 범용 인앱 WebView 화면.
/// 로그인이 필요한 페이지(예: SNU 비교과 view.do)를 앱 안에서 열고,
/// Android WebView의 앱 전역 쿠키 저장 덕분에 **최초 1회 로그인하면 세션이 유지**된다.
/// (외부 브라우저로 튕기지 않고 앱 안에서 본문·신청을 모두 처리)
class InAppWebScreen extends StatefulWidget {
  const InAppWebScreen({super.key, required this.url, required this.title});

  final String url;
  final String title;

  @override
  State<InAppWebScreen> createState() => _InAppWebScreenState();
}

class _InAppWebScreenState extends State<InAppWebScreen> {
  late final WebViewController _ctrl;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) {
          final scheme = Uri.tryParse(req.url)?.scheme.toLowerCase();
          // http/https만 허용(로그인 SSO 리다이렉트 포함). 그 외 scheme 차단.
          if (scheme == 'http' || scheme == 'https') {
            return NavigationDecision.navigate;
          }
          debugPrint('[inapp-web] 차단된 scheme: $scheme (${req.url})');
          return NavigationDecision.prevent;
        },
        onPageStarted: (_) => setState(() {
          _loading = true;
          _error = false;
        }),
        onPageFinished: (_) => setState(() => _loading = false),
        onWebResourceError: (e) {
          debugPrint('[inapp-web] err: ${e.description} (main=${e.isForMainFrame})');
          if (e.isForMainFrame ?? false) {
            setState(() {
              _error = true;
              _loading = false;
            });
          }
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _openExternal() async {
    final uri = Uri.parse(widget.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: () => _ctrl.reload(),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: '외부 브라우저로 열기',
            onPressed: _openExternal,
          ),
        ],
      ),
      body: Stack(children: [
        WebViewWidget(controller: _ctrl),
        if (_error)
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.cloud_off, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 16),
                const Text('페이지를 불러오지 못했어요',
                    style: TextStyle(fontSize: 15)),
                const SizedBox(height: 16),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _error = false;
                        _loading = true;
                      });
                      _ctrl.reload();
                    },
                    child: const Text('다시 시도'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _openExternal,
                    child: const Text('외부 브라우저'),
                  ),
                ]),
              ],
            ),
          ),
      ]),
    );
  }
}
