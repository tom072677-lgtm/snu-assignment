import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../features/assignments/data/assignment_repository.dart';
import '../../../shared/widgets/error_view.dart';
import '../data/calendar_repository.dart';
import '../domain/calendar_event.dart';
import 'news_section.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  // 현재 날짜를 기준으로 focusedDay를 캘린더 범위 내로 고정
  static DateTime _clampToCalendarRange(DateTime d) {
    final first = DateTime(d.year - 1, 1, 1);
    final last = DateTime(d.year + 2, 12, 31);
    if (d.isBefore(first)) return first;
    if (d.isAfter(last)) return last;
    return d;
  }

  late DateTime _focusedDay = _clampToCalendarRange(DateTime.now());
  DateTime? _selectedDay;

  @override
  Widget build(BuildContext context) {
    final userEvents = ref.watch(calendarEventsMapProvider);
    final assignmentsAsync = ref.watch(assignmentsProvider);

    // 과제 마감일 맵 합치기
    final assignmentDays = assignmentsAsync.maybeWhen(
      data: (list) {
        final map = <DateTime, List<CalendarEvent>>{};
        for (final a in list) {
          final day = DateTime(a.dueDate.year, a.dueDate.month, a.dueDate.day);
          map.putIfAbsent(day, () => []).add(CalendarEvent(
            id: a.etlId,
            title: a.title,
            dateTime: a.dueDate,
            source: 'assignment',
          ));
        }
        return map;
      },
      orElse: () => <DateTime, List<CalendarEvent>>{},
    );

    // 공휴일 맵
    final holidayMap = <DateTime, List<CalendarEvent>>{};
    for (final h in [...holidays2026, ...holidays2027]) {
      final d = DateTime.parse(h.date);
      holidayMap
          .putIfAbsent(d, () => [])
          .add(CalendarEvent(id: h.date, title: h.title, dateTime: d, source: 'holiday'));
    }

    // 합친 이벤트 맵
    final allEvents = <DateTime, List<CalendarEvent>>{};
    for (final m in [userEvents, assignmentDays, holidayMap]) {
      m.forEach((k, v) => allEvents.putIfAbsent(k, () => []).addAll(v));
    }

    // 선택된 날 이벤트
    final selectedEvents = _selectedDay != null
        ? (allEvents[DateTime(
                _selectedDay!.year, _selectedDay!.month, _selectedDay!.day)] ??
            [])
        : <CalendarEvent>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('달력', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        children: [
          TableCalendar(
            firstDay: DateTime(_focusedDay.year - 1, 1, 1),
            lastDay: DateTime(_focusedDay.year + 2, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (d) => isSameDay(d, _selectedDay),
            eventLoader: (d) =>
                allEvents[DateTime(d.year, d.month, d.day)] ?? [],
            calendarFormat: CalendarFormat.month,
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
            ),
            calendarStyle: CalendarStyle(
              markerDecoration: const BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
              todayDecoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              todayTextStyle: const TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
              ),
              selectedDecoration: const BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
            ),
            onDaySelected: (selected, focused) {
              setState(() {
                _selectedDay = selected;
                _focusedDay = focused;
              });
            },
            onPageChanged: (focused) {
              _focusedDay = focused;
            },
          ),
          // 선택 날 상세
          if (_selectedDay != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Text(
                    DateFormat('M월 d일 (E)', 'ko').format(_selectedDay!),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('추가'),
                    onPressed: () => _showAddDialog(_selectedDay!),
                  ),
                ],
              ),
            ),
            if (selectedEvents.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('일정 없음', style: TextStyle(color: Colors.grey)),
              )
            else
              ...selectedEvents.map(
                (e) => ListTile(
                  leading: Icon(
                    e.source == 'assignment'
                        ? Icons.assignment
                        : e.source == 'holiday'
                            ? Icons.celebration
                            : Icons.event,
                    color: e.source == 'assignment'
                        ? Colors.orange
                        : e.source == 'holiday'
                            ? Colors.red
                            : Colors.blue,
                  ),
                  title: Text(e.title),
                  subtitle: Text(
                    e.source == 'holiday'
                        ? '공휴일'
                        : DateFormat('HH:mm').format(e.dateTime),
                  ),
                  trailing: e.source == 'user'
                      ? IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => ref
                              .read(calendarRepositoryProvider.notifier)
                              .remove(e.id),
                        )
                      : null,
                ),
              ),
            const Divider(),
          ],
          // 학교 소식
          const NewsSection(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Future<void> _showAddDialog(DateTime date) async {
    TimeOfDay time = TimeOfDay.now();
    final titleCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(DateFormat('M월 d일', 'ko').format(date)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                decoration: const InputDecoration(hintText: '일정 제목'),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.access_time),
                title: Text(time.format(ctx)),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: ctx,
                    initialTime: time,
                  );
                  if (picked != null) setState(() => time = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소')),
            FilledButton(
              onPressed: () {
                if (titleCtrl.text.isEmpty) return;
                final dt = DateTime(
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                );
                ref.read(calendarRepositoryProvider.notifier).add(
                      titleCtrl.text.trim(),
                      dt,
                    );
                Navigator.pop(ctx);
              },
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
  }
}
