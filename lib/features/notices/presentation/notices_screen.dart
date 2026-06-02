import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../features/onboarding/domain/snu_departments.dart';
import '../../../shared/providers/settings_provider.dart';
import '../data/notice_repository.dart';
import '../domain/department_notice_source.dart';
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

  /// 사용자 학과명으로 첫 탭 라벨 구성 (미설정 시 '학과 공지').
  String _deptTabLabel() {
    final code = ref.watch(departmentCodeProvider);
    if (code == null) return '학과 공지';
    for (final c in snuColleges) {
      for (final d in c.departments) {
        if (d.code == code) return d.name;
      }
    }
    return '학과 공지';
  }

  void _showProfileSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _ProfileSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('공지/기회', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.manage_accounts_outlined),
            tooltip: '내 정보 설정',
            onPressed: () => _showProfileSheet(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: [
            Tab(text: _deptTabLabel()),
            const Tab(text: 'SNU 비교과'),
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

class _SportsTab extends ConsumerStatefulWidget {
  const _SportsTab();

  @override
  ConsumerState<_SportsTab> createState() => _SportsTabState();
}

class _SportsTabState extends ConsumerState<_SportsTab> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final deptCode = ref.watch(departmentCodeProvider);
    final source = noticeSourceFor(deptCode);

    // 상태 1: 학과 매핑 없음 (미설정 또는 아직 미지원 학과)
    if (source == null) {
      return _DeptUnsupportedView(hasDept: deptCode != null);
    }
    // 상태 2: 피드/게시판 소스가 둘 다 없음 → 홈페이지 fallback
    if (source.rssFeedUrl == null && source.noticeListUrl == null) {
      return _DeptHomepageFallback(homepageUrl: source.homepageUrl);
    }

    // 상태 3: RSS 또는 서버 HTML 게시판
    final async = ref.watch(departmentNoticesProvider);
    final now = DateTime.now();

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        message: '공지를 불러오지 못했어요.\n네트워크 상태를 확인해 주세요.',
        onRetry: () => ref.invalidate(departmentNoticesProvider),
      ),
      data: (notices) {
        if (notices.isEmpty) {
          return _ErrorView(
            message: '공지 정보가 없어요.\n잠시 후 다시 시도해 주세요.',
            onRetry: () => ref.invalidate(departmentNoticesProvider),
          );
        }

        final visible =
            notices.where((n) => shouldShowSportsNotice(n, now)).toList();
        final hiddenCount = notices.length - visible.length;

        // 현재 공지가 하나도 없으면 안내 + 지난 공지 버튼
        if (visible.isEmpty && !_showAll) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.event_busy_outlined,
                    size: 48, color: Color(0xFFCCCCCC)),
                const SizedBox(height: 12),
                const Text(
                  '현재 진행 중인 공지가 없어요.',
                  style: TextStyle(fontSize: 14, color: Color(0xFF999999)),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() => _showAll = true),
                  child: Text('지난 공지 $hiddenCount건 보기'),
                ),
              ],
            ),
          );
        }

        final displayed = _showAll ? notices : visible;
        final showMoreButton = hiddenCount > 0 && !_showAll;

        return RefreshIndicator(
          onRefresh: () async {
            final repo = ref.read(noticeRepositoryProvider);
            await repo.getDepartmentNotices(deptCode, forceRefresh: true);
            ref.invalidate(departmentNoticesProvider);
            if (_showAll) setState(() => _showAll = false);
          },
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: displayed.length + (showMoreButton ? 1 : 0),
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 16),
            itemBuilder: (_, i) {
              if (i == displayed.length) {
                return TextButton.icon(
                  onPressed: () => setState(() => _showAll = true),
                  icon: const Icon(Icons.expand_more, size: 16),
                  label: Text('지난 공지 $hiddenCount건 더 보기'),
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF888888)),
                );
              }
              return _SportsNoticeItem(notice: displayed[i]);
            },
          ),
        );
      },
    );
  }
}

/// 학과 매핑 없음(미설정/미지원) 안내.
class _DeptUnsupportedView extends StatelessWidget {
  const _DeptUnsupportedView({required this.hasDept});
  final bool hasDept;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, size: 48, color: Color(0xFFCCCCCC)),
            const SizedBox(height: 12),
            Text(
              hasDept
                  ? '이 학과의 공지는 아직 지원하지 않아요.\n곧 추가될 예정이에요.'
                  : '학과를 먼저 설정해주세요.\n(우측 상단 내 정보 설정)',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF888888)),
            ),
          ],
        ),
      ),
    );
  }
}

/// RSS 미지원 학과 → 홈페이지 열기 fallback.
class _DeptHomepageFallback extends StatelessWidget {
  const _DeptHomepageFallback({required this.homepageUrl});
  final String homepageUrl;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.open_in_browser, size: 48, color: Color(0xFFCCCCCC)),
            const SizedBox(height: 12),
            const Text(
              '이 학과 공지는 앱에서 아직 불러올 수 없어요.\n학과 홈페이지에서 확인해 주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF888888)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('학과 홈페이지 열기'),
              onPressed: () async {
                final uri = Uri.parse(homepageUrl);
                final ok = await canLaunchUrl(uri);
                if (ok) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('홈페이지를 열 수 없어요.')),
                  );
                }
              },
            ),
          ],
        ),
      ),
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

class _ExtraTab extends ConsumerStatefulWidget {
  const _ExtraTab();

  @override
  ConsumerState<_ExtraTab> createState() => _ExtraTabState();
}

class _ExtraTabState extends ConsumerState<_ExtraTab> {
  bool _myCollegeOnly = false;

  String? _userCollegeName() {
    final code = ref.read(collegeCodeProvider);
    if (code == null) return null;
    try {
      return snuColleges.firstWhere((c) => c.code == code).name;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(extraProgramsProvider);
    final collegeCode = ref.watch(collegeCodeProvider);
    final hasCollege = collegeCode != null;
    final userStatus = ref.watch(academicStatusProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorView(
        message: '비교과 프로그램을 불러오지 못했어요.\n네트워크 상태를 확인해 주세요.',
        onRetry: () => ref.invalidate(extraProgramsProvider),
      ),
      data: (allPrograms) {
        final programs = (_myCollegeOnly && hasCollege)
            ? allPrograms
                .where((p) =>
                    p.matchesCollege(_userCollegeName()) &&
                    p.matchesStatus(userStatus))
                .toList()
            : allPrograms;

        return Column(
          children: [
            if (hasCollege)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    _FilterChip(
                      label: '전체',
                      selected: !_myCollegeOnly,
                      onTap: () => setState(() => _myCollegeOnly = false),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: '내 단과대만',
                      selected: _myCollegeOnly,
                      onTap: () => setState(() => _myCollegeOnly = true),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: programs.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.event_busy_outlined,
                              size: 56, color: Color(0xFFCCCCCC)),
                          SizedBox(height: 12),
                          Text(
                            '현재 신청 중이거나 곧 시작하는\n프로그램이 없어요.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Color(0xFF999999), fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        final repo = ref.read(noticeRepositoryProvider);
                        await repo.getExtraPrograms(forceRefresh: true);
                        ref.invalidate(extraProgramsProvider);
                      },
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: programs.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 16),
                        itemBuilder: (_, i) =>
                            _ExtraProgramTile(program: programs[i]),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF1A73E8);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? primary : Colors.transparent,
          border: Border.all(
            color: selected ? primary : const Color(0xFFCCCCCC),
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : const Color(0xFF555555),
          ),
        ),
      ),
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
    final daysToStart = (program.aplFrom != null &&
            today.isBefore(DateTime(program.aplFrom!.year,
                program.aplFrom!.month, program.aplFrom!.day)))
        ? DateTime(program.aplFrom!.year, program.aplFrom!.month,
                program.aplFrom!.day)
            .difference(today)
            .inDays
        : null;

    // Use status text from HTML scraper; fall back to date-derived label.
    final statusText = program.status.isNotEmpty
        ? program.status
        : (daysToStart != null ? 'D-$daysToStart일 후 시작' : '모집중');
    final statusColor = switch (statusText) {
      '마감임박' => Colors.red,
      '모집대기' || _ when daysToStart != null => Colors.orange,
      _ => Colors.green,
    };

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
            _badge(statusText, statusColor),
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
        if (program.targetOrg.isNotEmpty)
          _detailRow(Icons.people_outline, '신청대상', program.targetOrg),
        _detailRow(
          Icons.badge_outlined,
          '신청신분',
          program.targetStatus.isNotEmpty
              ? program.targetStatus.join(', ')
              : '제한없음',
        ),
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

// ─── 내 정보 설정 시트 ──────────────────────────────────────────────────────

class _ProfileSheet extends ConsumerWidget {
  const _ProfileSheet();

  static const _statusOptions = ['학사', '석사', '박사'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collegeCode = ref.watch(collegeCodeProvider);
    final currentStatus = ref.watch(academicStatusProvider);

    String? collegeName;
    if (collegeCode != null) {
      try {
        collegeName = snuColleges.firstWhere((c) => c.code == collegeCode).name;
      } catch (_) {}
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('내 정보',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          const Text('단과대',
              style: TextStyle(fontSize: 13, color: Color(0xFF888888))),
          const SizedBox(height: 6),
          Text(
            collegeName ?? '미설정',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: collegeName != null
                  ? const Color(0xFF1A73E8)
                  : const Color(0xFFAAAAAA),
            ),
          ),
          const SizedBox(height: 20),
          const Text('학적',
              style: TextStyle(fontSize: 13, color: Color(0xFF888888))),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              ..._statusOptions.map((s) => _FilterChip(
                    label: s,
                    selected: currentStatus == s,
                    onTap: () =>
                        ref.read(academicStatusProvider.notifier).set(s),
                  )),
              _FilterChip(
                label: '미설정',
                selected: currentStatus == null,
                onTap: () =>
                    ref.read(academicStatusProvider.notifier).set(null),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
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
