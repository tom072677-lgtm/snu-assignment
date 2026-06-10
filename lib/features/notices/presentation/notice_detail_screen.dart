import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../domain/notice.dart';

/// 공지 상세 화면 — 인앱 WebView로 원본 페이지 표시
class NoticeDetailScreen extends StatefulWidget {
  const NoticeDetailScreen({super.key, required this.notice});

  final Notice notice;

  @override
  State<NoticeDetailScreen> createState() => _NoticeDetailScreenState();
}

class _NoticeDetailScreenState extends State<NoticeDetailScreen> {
  late final WebViewController _ctrl;
  bool _isLoading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) {
          // 위험 scheme(javascript:, intent:, data: 등) 차단 — http/https만 허용
          final scheme = Uri.tryParse(req.url)?.scheme.toLowerCase();
          if (scheme == 'http' || scheme == 'https') {
            return NavigationDecision.navigate;
          }
          debugPrint('[notice] 차단된 navigation scheme: $scheme (${req.url})');
          return NavigationDecision.prevent;
        },
        onPageStarted: (_) => setState(() {
          _isLoading = true;
          _error = false;
        }),
        onPageFinished: (_) => setState(() => _isLoading = false),
        onWebResourceError: (e) {
          debugPrint('[notice] resourceErr: ${e.description}');
          setState(() {
            _error = true;
            _isLoading = false;
          });
        },
      ))
      ..loadRequest(Uri.parse(widget.notice.url));
  }

  Future<void> _openExternal() async {
    final uri = Uri.parse(widget.notice.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.notice.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // 신청하기 / 외부에서 열기
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: '외부 브라우저로 열기',
            onPressed: _openExternal,
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _ctrl),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _error = false;
                            _isLoading = true;
                          });
                          _ctrl.reload();
                        },
                        child: const Text('다시 시도'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: _openExternal,
                        child: const Text('외부 브라우저로 열기'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

