import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../shared/providers/settings_provider.dart';
import '../data/timetable_repository.dart';
import '../domain/timetable_models.dart';
import '../domain/semester.dart';
import '../../library/presentation/library_screen.dart';
import '../data/ics_import_service.dart';
import 'mysnu_webview_screen.dart';
import 'timetable_grid.dart';

const _uuid = Uuid();

class TimetableScreen extends ConsumerWidget {
  const TimetableScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icalUrl    = ref.watch(icalUrlProvider);
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
            icon: const Icon(Icons.sync),
            tooltip: '마이스누 시간표 갱신',
            onPressed: () => _openMySNU(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(timetableProvider),
          ),
        ],
      ),
      body: icalUrl == null || icalUrl.isEmpty
          ? _CustomOnlyBody()
          : _TimetableBody(
              hasToken: canvasToken != null && canvasToken.isNotEmpty),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEventSheet(context, ref),
        tooltip: '일정 추가',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddEventSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddEventSheet(
        onSave: (event) =>
            ref.read(customEventsProvider.notifier).add(event),
      ),
    );
  }
}

// ── eTL 미연동 시에도 커스텀 이벤트 그리드 표시 ─────────────────────

class _CustomOnlyBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customEvents  = ref.watch(customEventsProvider);
    final mySNUSessions = ref.watch(mySNUSessionsProvider);
    final isStale = isTimetableStale(
      hasSessions: mySNUSessions.isNotEmpty,
      capturedAt: ref.watch(mySNUCapturedAtProvider),
      snoozedSemester: ref.watch(mySNUSnoozedSemesterProvider),
      now: DateTime.now(),
    );

    return Column(
      children: [
        if (isStale) _buildStaleBanner(context, ref),
        // 상태 배너
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          color: const Color(0xFFF0F4FF),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 18, color: Color(0xFF1A73E8)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  mySNUSessions.isNotEmpty
                      ? '마이스누에서 ${mySNUSessions.length}개 수업 불러옴.'
                      : 'eTL 연동 또는 마이스누 로그인으로 시간표를 불러올 수 있어요.',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF3C5A99), height: 1.4),
                ),
              ),
              if (mySNUSessions.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFF1A73E8)),
                  tooltip: '마이스누 데이터 초기화',
                  onPressed: () {
                    ref.read(mySNUSessionsProvider.notifier).clear();
                    ref.read(mySNUCapturedAtProvider.notifier).clear();
                    ref.read(mySNUSnoozedSemesterProvider.notifier).clear();
                  },
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => _openMySNU(context, ref),
                      child: const Text('마이스누', style: TextStyle(fontSize: 12)),
                    ),
                    TextButton(
                      onPressed: () => _importIcs(context, ref),
                      child: const Text('ICS', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        // 시간표 그리드 (mySNU 세션 우선)
        Expanded(
          child: TimetableGrid(
            sessions: mySNUSessions,
            customEvents: customEvents,
            onDeleteCustomEvent: (id) =>
                ref.read(customEventsProvider.notifier).remove(id),
            onDeleteCourse: mySNUSessions.isNotEmpty
                ? (summary) => _onDeleteCourse(context, ref, summary)
                : null,
          ),
        ),
      ],
    );
  }
}

// ── 시간표 본문 ──────────────────────────────────────────────────

class _TimetableBody extends ConsumerWidget {
  final bool hasToken;
  const _TimetableBody({required this.hasToken});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async        = ref.watch(timetableProvider);
    final customEvents = ref.watch(customEventsProvider);

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
      data: (data) {
        final hasSessions = data.sessions.isNotEmpty || customEvents.isNotEmpty;
        final mySNUSessions = ref.watch(mySNUSessionsProvider);
        final isStale = isTimetableStale(
          hasSessions: mySNUSessions.isNotEmpty,
          capturedAt: ref.watch(mySNUCapturedAtProvider),
          snoozedSemester: ref.watch(mySNUSnoozedSemesterProvider),
          now: DateTime.now(),
        );
        return Column(
          children: [
            // ① 오늘 수업 배너
            _TodayBanner(sessions: data.todaySessions, customEvents: customEvents),
            // ②a 지난 학기 시간표면 갱신 권유 배너
            if (isStale) _buildStaleBanner(context, ref),
            // ②b 세션이 하나도 없으면 안내 배너
            if (!hasSessions)
              _buildNoSessionBanner(context, ref),
            // ③ 그리드 시간표 (항상 표시 — 커스텀 이벤트만 있어도 보여야 함)
            Expanded(
              child: TimetableGrid(
                sessions:     data.sessions,
                customEvents: customEvents,
                onDeleteCustomEvent: (id) =>
                    ref.read(customEventsProvider.notifier).remove(id),
                onDeleteCourse: mySNUSessions.isNotEmpty
                    ? (summary) => _onDeleteCourse(context, ref, summary)
                    : null,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── 수업 없음 안내 배너 ──────────────────────────────────────────

Widget _buildNoSessionBanner(BuildContext context, WidgetRef ref) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFF0F4FF),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFBBCCF8)),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline, size: 18, color: Color(0xFF1A73E8)),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'eTL에서 수업 일정을 가져오지 못했어요.\n마이스누 로그인으로 불러오거나 직접 추가해 보세요.',
            style: TextStyle(fontSize: 12, color: Color(0xFF3C5A99), height: 1.4),
          ),
        ),
        TextButton(
          onPressed: () => _openMySNU(context, ref),
          child: const Text('마이스누', style: TextStyle(fontSize: 12)),
        ),
        TextButton(
          onPressed: () => _importIcs(context, ref),
          child: const Text('ICS', style: TextStyle(fontSize: 12)),
        ),
      ],
    ),
  );
}

// ── 지난 학기 시간표 갱신 권유 배너 ───────────────────────────────

Widget _buildStaleBanner(BuildContext context, WidgetRef ref) {
  final captured = ref.read(mySNUCapturedAtProvider);
  final keyLabel = captured != null ? semesterKey(captured) : '';
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4E5),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFF5C77E)),
    ),
    child: Row(
      children: [
        const Icon(Icons.update, size: 18, color: Color(0xFFE8810C)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '지난 학기($keyLabel) 시간표예요.\n새 학기 시간표로 갱신할까요?',
            style: const TextStyle(
                fontSize: 12, color: Color(0xFF8A5A00), height: 1.4),
          ),
        ),
        TextButton(
          onPressed: () => _openMySNU(context, ref),
          child: const Text('갱신', style: TextStyle(fontSize: 12)),
        ),
        TextButton(
          onPressed: () => ref
              .read(mySNUSnoozedSemesterProvider.notifier)
              .set(semesterKey(DateTime.now())),
          child: const Text('나중에',
              style: TextStyle(fontSize: 12, color: Color(0xFF999999))),
        ),
      ],
    ),
  );
}

// ── 드랍한 과목 삭제(실행취소 지원) ────────────────────────────────

void _onDeleteCourse(BuildContext context, WidgetRef ref, String summary) {
  final removed = ref.read(mySNUSessionsProvider.notifier).removeCourse(summary);
  if (removed.isEmpty) return; // mySNU 세션이 아니면 무시
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text("'$summary' 삭제됨"),
    action: SnackBarAction(
      label: '실행취소',
      onPressed: () =>
          ref.read(mySNUSessionsProvider.notifier).restoreSessions(removed),
    ),
  ));
}

// ── mySNU 웹뷰 열기 ──────────────────────────────────────────────

Future<void> _openMySNU(BuildContext context, WidgetRef ref) async {
  final result = await Navigator.push<List<ClassSession>?>(
    context,
    MaterialPageRoute(builder: (_) => const MySNUWebViewScreen()),
  );
  if (result != null && result.isNotEmpty) {
    ref.read(mySNUSessionsProvider.notifier).setSessions(result);
    // 캡처 성공 시점 기록 → 학기 전환 감지의 기준. 스누즈는 새 캡처로 해제.
    ref.read(mySNUCapturedAtProvider.notifier).set(DateTime.now());
    ref.read(mySNUSnoozedSemesterProvider.notifier).clear();
    // timetableProvider는 mySNU 세션을 우선 사용하므로 invalidate 필요 없음
    // (mySNUSessionsProvider 변경이 timetableProvider를 자동으로 재계산)
  }
}

// ── ICS 파일 가져오기 ─────────────────────────────────────────────

Future<void> _importIcs(BuildContext context, WidgetRef ref) async {
  List<ClassSession>? sessions;
  try {
    sessions = await IcsImportService.pickAndParse();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류: $e'), backgroundColor: Colors.red),
      );
    }
    return;
  }

  if (sessions == null) return; // 취소
  if (!context.mounted) return;

  if (sessions.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('수업 일정을 찾을 수 없었어요. SnuTT나 에브리타임에서 내보낸 .ics 파일인지 확인해 주세요.')),
    );
    return;
  }

  // 프리뷰 다이얼로그
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => _IcsPreviewDialog(sessions: sessions!),
  );
  if (confirmed != true || !context.mounted) return;

  ref.read(mySNUSessionsProvider.notifier).setSessions(sessions);
  // ICS import도 "시간표를 마지막으로 설정한 시점"으로 기록(한계: .ics의 실제 학기는 알 수 없음).
  ref.read(mySNUCapturedAtProvider.notifier).set(DateTime.now());
  ref.read(mySNUSnoozedSemesterProvider.notifier).clear();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${sessions.length}개 수업을 시간표에 추가했어요.')),
    );
  }
}

// ── ICS 프리뷰 다이얼로그 ──────────────────────────────────────────

class _IcsPreviewDialog extends StatelessWidget {
  final List<ClassSession> sessions;
  const _IcsPreviewDialog({required this.sessions});

  static const _dayLabel = {'MO':'월','TU':'화','WE':'수','TH':'목','FR':'금','SA':'토','SU':'일'};

  String _formatDays(List<String> days) =>
      days.map((d) => _dayLabel[d] ?? d).join('·');

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${sessions.length}개 수업 확인'),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: sessions.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
          itemBuilder: (_, i) {
            final s = sessions[i];
            return ListTile(
              dense: true,
              title: Text(s.summary, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: Text(
                '${_formatDays(s.weekdays)}  ${s.startTime}–${s.endTime}'
                '${s.location.isNotEmpty ? '  ${s.location}' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('추가'),
        ),
      ],
    );
  }
}

// ── 오늘 배너 ────────────────────────────────────────────────────

class _TodayBanner extends StatelessWidget {
  final List<ClassSession> sessions;
  final List<CustomEvent>  customEvents;
  const _TodayBanner({required this.sessions, required this.customEvents});

  @override
  Widget build(BuildContext context) {
    final today     = DateFormat('M월 d일 (E)', 'ko').format(DateTime.now());
    final dayCode   = const ['MO','TU','WE','TH','FR','SA','SU']
        [DateTime.now().weekday - 1];

    // 오늘 커스텀 일정
    final todayCustom = customEvents
        .where((e) => e.weekdays.contains(dayCode))
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    // 합쳐서 시간 순 정렬
    final allToday = <(String startTime, String label, Color color)>[
      for (final s in sessions)
        (s.startTime, '${s.summary}${s.location.isNotEmpty ? ' · ${s.location}' : ''}',
         courseColor(s.summary)),
      for (final ce in todayCustom)
        (ce.startTime, ce.title, paletteColor(ce.colorIndex)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              '오늘 · $today',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          if (allToday.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text('오늘 수업 없음', style: TextStyle(color: Colors.grey, fontSize: 13)),
            )
          else
            SizedBox(
              height: 58,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                itemCount: allToday.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final item = allToday[i];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: item.$3.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: item.$3.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(item.$1,
                            style: TextStyle(
                                fontSize: 10,
                                color: item.$3,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(item.$2,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  );
                },
              ),
            ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}

// ── 커스텀 일정 추가 바텀시트 ────────────────────────────────────

class _AddEventSheet extends StatefulWidget {
  final void Function(CustomEvent) onSave;
  const _AddEventSheet({required this.onSave});

  @override
  State<_AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends State<_AddEventSheet> {
  final _titleCtrl    = TextEditingController();
  final _locationCtrl = TextEditingController();

  final Set<String> _selectedDays = {};
  TimeOfDay _startTime = const TimeOfDay(hour: 9,  minute: 0);
  TimeOfDay _endTime   = const TimeOfDay(hour: 10, minute: 0);
  int _colorIndex = 0;

  static const _dayItems = [
    ('MO', '월'), ('TU', '화'), ('WE', '수'),
    ('TH', '목'), ('FR', '금'),
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  bool get _valid {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return false;
    if (_selectedDays.isEmpty) return false;
    // 종료 > 시작
    final startMin = _startTime.hour * 60 + _startTime.minute;
    final endMin   = _endTime.hour   * 60 + _endTime.minute;
    return endMin > startMin;
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
        // 시작 >= 종료면 종료를 +1시간으로 자동 조정
        final sMin = picked.hour * 60 + picked.minute;
        final eMin = _endTime.hour * 60 + _endTime.minute;
        if (eMin <= sMin) {
          final newEMin = (sMin + 60).clamp(0, 23 * 60 + 59);
          _endTime = TimeOfDay(hour: newEMin ~/ 60, minute: newEMin % 60);
        }
      } else {
        _endTime = picked;
      }
    });
  }

  void _save() {
    if (!_valid) return;
    final event = CustomEvent(
      id:         _uuid.v4(),
      title:      _titleCtrl.text.trim(),
      location:   _locationCtrl.text.trim(),
      weekdays:   _selectedDays.toList(),
      startTime:  _fmt(_startTime),
      endTime:    _fmt(_endTime),
      colorIndex: _colorIndex,
    );
    widget.onSave(event);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 핸들
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Text('일정 추가',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // 제목
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: '제목 *',
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),

          // 장소 (선택)
          TextField(
            controller: _locationCtrl,
            decoration: const InputDecoration(
              labelText: '장소 (선택)',
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 14),

          // 요일 선택
          const Text('요일', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 6),
          Row(
            children: _dayItems.map((item) {
              final (code, label) = item;
              final sel = _selectedDays.contains(code);
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(label),
                  selected: sel,
                  onSelected: (_) => setState(() {
                    if (sel) {
                      _selectedDays.remove(code);
                    } else {
                      _selectedDays.add(code);
                    }
                  }),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // 시간 선택
          const Text('시간', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickTime(isStart: true),
                  child: Text('시작  ${_fmt(_startTime)}'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('~'),
              ),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickTime(isStart: false),
                  child: Text('종료  ${_fmt(_endTime)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 색상 선택
          const Text('색상', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 6),
          Row(
            children: List.generate(kTimetablePalette.length, (i) {
              final sel = _colorIndex == i;
              return GestureDetector(
                onTap: () => setState(() => _colorIndex = i),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: kTimetablePalette[i],
                    shape: BoxShape.circle,
                    border: sel
                        ? Border.all(color: Colors.black, width: 2.5)
                        : null,
                  ),
                  child: sel
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
              );
            }),
          ),
          const SizedBox(height: 20),

          // 저장 버튼
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton(
              onPressed: _valid ? _save : null,
              child: const Text('저장'),
            ),
          ),
        ],
      ),
    );
  }
}
