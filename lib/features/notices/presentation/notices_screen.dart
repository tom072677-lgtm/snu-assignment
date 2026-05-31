import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../data/notice_repository.dart';
import '../domain/notice.dart';
import 'notice_detail_screen.dart';

/// 공지/기회 탭 메인 화면
/// - 체육교육과 탭: 공지 목록 (HTML 스크래핑)
/// - 비교과 탭: SNU 비교과 사이트 임베드 WebView
class NoticesScreen extends ConsumerStatefulWidget {
  const NoticesScreen({super.key});

  @override
  ConsumerState<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends ConsumerState<NoticesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('공지/기회', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: false,
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: '체육교육과 공지'),
            Tab(text: 'SNU 비교과'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: const [
          _SportsTab(),
          _ExtraTab(),
        ],
      ),
    );
  }
}

// ─── 체육교육과 공지 탭 ─────────────────────────────────────────────────────

class _SportsTab extends ConsumerWidget {
  const _SportsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sportsNoticesProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        message: e is ScrapingException
            ? '사이트 구조가 변경되어 공지를 불러오지 못했어요.\n개발자에게 문의해 주세요.'
            : '공지를 불러오지 못했어요.\n네트워크 상태를 확인해 주세요.',
        onRetry: () => ref.invalidate(sportsNoticesProvider),
      ),
      data: (notices) {
        if (notices.isEmpty) {
          return _ErrorView(
            message: '공지 정보가 없어요.\n잠시 후 다시 시도해 주세요.',
            onRetry: () => ref.invalidate(sportsNoticesProvider),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            final repo = ref.read(noticeRepositoryProvider);
            await repo.getSportsNotices(forceRefresh: true);
            ref.invalidate(sportsNoticesProvider);
          },
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: notices.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
            itemBuilder: (_, i) => _SportsNoticeItem(notice: notices[i]),
          ),
        );
      },
    );
  }
}

class _SportsNoticeItem extends StatelessWidget {
  const _SportsNoticeItem({required this.notice});

  final Notice notice;

  @override
  Widget build(BuildContext context) {
    final dateStr = notice.date != null
        ? DateFormat('MM.dd').format(notice.date!)
        : '';

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NoticeDetailScreen(notice: notice)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 카테고리 배지
            if (notice.category != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF3FF),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  notice.category!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A73E8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            // 제목
            Expanded(
              child: Text(
                notice.title,
                style: const TextStyle(fontSize: 14, height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            // 날짜
            Text(
              dateStr,
              style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 비교과 탭 ──────────────────────────────────────────────────────────────

class _ExtraTab extends StatefulWidget {
  const _ExtraTab();

  @override
  State<_ExtraTab> createState() => _ExtraTabState();
}

class _ExtraTabState extends State<_ExtraTab> {
  late final WebViewController _ctrl;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _isLoading = true),
        onPageFinished: (_) => setState(() => _isLoading = false),
        onWebResourceError: (_) => setState(() => _isLoading = false),
      ))
      ..loadRequest(Uri.parse(kExtraProgramsUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 안내 배너
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: const Color(0xFFF0F4FF),
          child: const Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Color(0xFF1A73E8)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '로그인 후 신청할 수 있어요. 신청은 사이트에서 직접 진행됩니다.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF555555)),
                ),
              ),
            ],
          ),
        ),
        // 비교과 사이트 WebView (직접 임베드 — Scaffold 중첩 없음)
        Expanded(
          child: Stack(
            children: [
              WebViewWidget(controller: _ctrl),
              if (_isLoading)
                const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── 공통 에러 뷰 ───────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.signal_wifi_off_outlined, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF888888), fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}
