import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../domain/notice.dart';

/// 공지 상세 화면.
/// - 본문(RSS content)이 있으면 **앱 내에서 본문을 바로 표시**(로그인 불필요).
/// - 본문이 없으면(서버 스크랩 게시판 등) 기존처럼 인앱 WebView로 원본 표시.
class NoticeDetailScreen extends StatefulWidget {
  const NoticeDetailScreen({super.key, required this.notice});

  final Notice notice;

  @override
  State<NoticeDetailScreen> createState() => _NoticeDetailScreenState();
}

class _NoticeDetailScreenState extends State<NoticeDetailScreen> {
  WebViewController? _ctrl;
  bool _isLoading = true;
  bool _error = false;

  bool get _hasBody => widget.notice.hasBody;

  @override
  void initState() {
    super.initState();
    if (!_hasBody) _initWebView();
  }

  void _initWebView() {
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) {
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
          debugPrint('[notice] resourceErr: ${e.description} (mainFrame=${e.isForMainFrame})');
          if (e.isForMainFrame ?? false) {
            setState(() {
              _error = true;
              _isLoading = false;
            });
          }
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
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: '원문(브라우저)에서 열기',
            onPressed: _openExternal,
          ),
        ],
      ),
      body: _hasBody ? _buildBodyView(context) : _buildWebView(context),
    );
  }

  // ── 본문 인앱 표시 ──────────────────────────────────────────────
  Widget _buildBodyView(BuildContext context) {
    final n = widget.notice;
    final dateStr =
        n.date != null ? DateFormat('yyyy.MM.dd').format(n.date!) : null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (n.category != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF3FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(n.category!,
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF1A73E8),
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
            ],
            if (dateStr != null)
              Text(dateStr,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
          const SizedBox(height: 12),
          Text(n.title,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, height: 1.4)),
          const Divider(height: 28),
          SelectableText(
            n.body!,
            style: const TextStyle(fontSize: 15, height: 1.7),
          ),
          const SizedBox(height: 28),
          // 신청/원문 안내: 본문은 보여주되 실제 신청은 외부.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📌 신청·첨부파일은 원문에서',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('신청은 원문 페이지(학교 사이트 로그인)에서 진행하세요.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF555555))),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.open_in_browser, size: 18),
                    label: const Text('원문 열기 / 신청하기'),
                    onPressed: _openExternal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── WebView (본문 없을 때 폴백) ─────────────────────────────────
  Widget _buildWebView(BuildContext context) {
    return Stack(
      children: [
        if (_ctrl != null) WebViewWidget(controller: _ctrl!),
        if (_isLoading) const Center(child: CircularProgressIndicator()),
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
                        _ctrl?.reload();
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
    );
  }
}
