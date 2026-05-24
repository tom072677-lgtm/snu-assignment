import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../shared/providers/settings_provider.dart';
import '../data/timetable_repository.dart';
import '../domain/timetable_models.dart';
import '../../library/presentation/library_screen.dart';

class TimetableScreen extends ConsumerWidget {
  const TimetableScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icalUrl = ref.watch(icalUrlProvider);
    final canvasToken = ref.watch(canvasTokenProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('시간표'),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book_outlined),
            tooltip: '도서관 좌석',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LibraryScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(timetableProvider),
          ),
        ],
      ),
      body: icalUrl == null || icalUrl.isEmpty
          ? const _NoEtlView()
          : _TimetableBody(
              hasToken: canvasToken != null && canvasToken.isNotEmpty),
    );
  }
}

class _NoEtlView extends StatelessWidget {
  const _NoEtlView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_view_week_outlined,
              size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text('eTL 연동 후 시간표를 볼 수 있어요',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          const Text('과제 탭 → 설정에서 eTL URL을 입력해 주세요',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _TimetableBody extends ConsumerWidget {
  final bool hasToken;
  const _TimetableBody({required this.hasToken});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(timetableProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('시간표를 불러오지 못했어요'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.invalidate(timetableProvider),
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
      data: (data) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _TodaySection(data: data),
          const SizedBox(height: 24),
          if (data.hasSchedule) ...[
            _WeeklyGrid(sessions: data.sessions),
            const SizedBox(height: 24),
          ],
          if (!hasToken && data.courses.isEmpty) ...[
            const _TokenPrompt(),
            const SizedBox(height: 24),
          ],
          if (data.courses.isNotEmpty) ...[
            Text('수강 과목 (${data.courses.length}개)',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            ...data.courses.map((c) => _CourseCard(course: c)),
          ],
          if (data.courses.isEmpty && data.sessions.isEmpty && hasToken)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('등록된 수강 과목이 없습니다',
                    style: TextStyle(color: Colors.grey)),
              ),
            ),
        ],
      ),
    );
  }
}

class _TodaySection extends StatelessWidget {
  final TimetableData data;
  const _TodaySection({required this.data});

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('M월 d일 (E)', 'ko').format(DateTime.now());
    final todaySessions = data.todaySessions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('오늘 · $today',
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        if (todaySessions.isEmpty && !data.hasSchedule)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.grey),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'eTL 캘린더에서 수업 일정을 가져오지 못했어요.\nCanvas API 토큰을 추가하면 과목 목록을 볼 수 있어요.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
          )
        else if (todaySessions.isEmpty)
          const Text('오늘 수업 없음', style: TextStyle(color: Colors.grey))
        else
          ...todaySessions.map((s) => _SessionTile(session: s, highlight: true)),
      ],
    );
  }
}

class _WeeklyGrid extends StatelessWidget {
  final List<ClassSession> sessions;
  const _WeeklyGrid({required this.sessions});

  static const _days = ['MO', 'TU', 'WE', 'TH', 'FR'];
  static const _dayLabels = ['월', '화', '수', '목', '금'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('주간 시간표',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        ...List.generate(5, (i) {
          final daySessions = sessions
              .where((s) => s.weekdays.contains(_days[i]))
              .toList()
            ..sort((a, b) => a.startTime.compareTo(b.startTime));
          if (daySessions.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  child: Text(_dayLabels[i],
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                Expanded(
                  child: Column(
                    children:
                        daySessions.map((s) => _SessionTile(session: s)).toList(),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _SessionTile extends StatelessWidget {
  final ClassSession session;
  final bool highlight;
  const _SessionTile({required this.session, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final color =
        highlight ? Theme.of(context).colorScheme.primary : Colors.grey[600];

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: highlight
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
            : Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: highlight
            ? Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.3))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(session.summary,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          if (session.startTime.isNotEmpty)
            Text('${session.startTime}~${session.endTime}',
                style: TextStyle(fontSize: 12, color: color)),
          if (session.location.isNotEmpty) ...[
            const SizedBox(width: 6),
            Icon(Icons.location_on_outlined, size: 12, color: color),
            Text(session.location,
                style: TextStyle(fontSize: 11, color: color)),
          ],
        ],
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  final TimetableCourse course;
  const _CourseCard({required this.course});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.book_outlined, size: 20),
        title: Text(course.name,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: course.courseCode.isNotEmpty
            ? Text(course.courseCode,
                style: const TextStyle(fontSize: 11))
            : null,
      ),
    );
  }
}

class _TokenPrompt extends StatelessWidget {
  const _TokenPrompt();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
      ),
      child: const Row(
        children: [
          Icon(Icons.tips_and_updates_outlined, size: 16, color: Colors.blue),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'eTL API 토큰을 추가하면 수강 과목 목록을 볼 수 있어요.\n과제 탭 → 설정에서 입력하세요.',
              style: TextStyle(fontSize: 12, color: Colors.blue),
            ),
          ),
        ],
      ),
    );
  }
}
