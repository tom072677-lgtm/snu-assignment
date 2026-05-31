import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/notice_repository.dart';
import '../domain/extra_program.dart';
import '../domain/notice.dart';
import 'notice_detail_screen.dart';

/// 공지/기회 탭 메인 화면
/// - 체육교육과 탭: 공지 목록 (HTML 스크래핑)
/// - 비교과 탭: 현재 신청중이거나 5일 이내 시작하는 프로그램 목록
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
    final dateStr =
        notice.date != null ? DateFormat('MM.dd').format(notice.date!) : '';

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
            Expanded(
              child: Text(
                notice.title,
                style: const TextStyle(fontSize: 14, height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
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

class _ExtraTab extends ConsumerWidget {
  const _ExtraTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(extraProgramsProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        message: '비교과 프로그램을 불러오지 못했어요.\n네트워크 상태를 확인해 주세요.',
        onRetry: () => ref.invalidate(extraProgramsProvider),
      ),
      data: (programs) {
        if (programs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_busy_outlined,
                    size: 56, color: Color(0xFFCCCCCC)),
                SizedBox(height: 12),
                Text(
                  '현재 신청 중이거나 곧 시작하는\n프로그램이 없어요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF999999), fontSize: 14),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            final repo = ref.read(noticeRepositoryProvider);
            await repo.getExtraPrograms(forceRefresh: true);
            ref.invalidate(extraProgramsProvider);
          },
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: programs.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
            itemBuilder: (_, i) => _ExtraProgramTile(program: programs[i]),
          ),
        );
      },
    );
  }
}

class _ExtraProgramTile extends StatelessWidget {
  const _ExtraProgramTile({required this.program});
  final ExtraProgram program;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isOpen = program.aplFrom != null &&
        program.aplTo != null &&
        !today.isBefore(DateTime(
            program.aplFrom!.year, program.aplFrom!.month, program.aplFrom!.day)) &&
        !today.isAfter(DateTime(
            program.aplTo!.year, program.aplTo!.month, program.aplTo!.day));
    final daysToStart = program.aplFrom != null
        ? DateTime(program.aplFrom!.year, program.aplFrom!.month,
                program.aplFrom!.day)
            .difference(today)
            .inDays
        : null;

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: Text(
        program.name,
        style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, height: 1.4),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            _badge(
              isOpen ? '모집중' : 'D-$daysToStart일 후 시작',
              isOpen ? Colors.green : Colors.orange,
            ),
            _badge(program.category, const Color(0xFF1A73E8)),
          ],
        ),
      ),
      children: [
        _detailRow(Icons.calendar_today_outlined, '신청기간',
            _fmtRange(program.aplFrom, program.aplTo)),
        if (program.eduFrom != null)
          _detailRow(Icons.school_outlined, '교육기간',
              _fmtRange(program.eduFrom, program.eduTo)),
        if (program.organizer?.isNotEmpty == true)
          _detailRow(
              Icons.business_outlined, '주관기관', program.organizer!),
        if (program.mode?.isNotEmpty == true)
          _detailRow(
              Icons.computer_outlined, '운영방식', program.mode!),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.open_in_browser, size: 16),
            label: const Text('신청 페이지 열기'),
            onPressed: () async {
              final uri = Uri.parse(program.detailUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color),
        ),
      );

  Widget _detailRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: const Color(0xFFAAAAAA)),
            const SizedBox(width: 6),
            SizedBox(
              width: 52,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF888888))),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );

  String _fmtRange(DateTime? from, DateTime? to) {
    if (from == null) return '-';
    final fmt = DateFormat('MM.dd');
    if (to == null) return fmt.format(from);
    return '${fmt.format(from)} ~ ${fmt.format(to)}';
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
          const Icon(Icons.signal_wifi_off_outlined,
              size: 48, color: Colors.grey),
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
