import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../domain/timetable_models.dart';

// ── 색상 팔레트 ───────────────────────────────────────────────────
const List<Color> kTimetablePalette = [
  Color(0xFF4285F4), // 파랑
  Color(0xFF34A853), // 초록
  Color(0xFFEA4335), // 빨강
  Color(0xFFFBBC05), // 노랑
  Color(0xFF9C27B0), // 보라
  Color(0xFF00BCD4), // 청록
  Color(0xFFFF5722), // 주황
  Color(0xFF795548), // 갈색
];

/// 과목명 → 안정적 색상 (앱 재시작 후도 동일)
Color courseColor(String name) {
  int hash = 0;
  for (final c in name.codeUnits) {
    hash = (hash * 31 + c) & 0x7FFFFFFF;
  }
  return kTimetablePalette[hash % kTimetablePalette.length];
}

Color paletteColor(int index) =>
    kTimetablePalette[index.clamp(0, kTimetablePalette.length - 1)];

// ── 그리드 상수 ───────────────────────────────────────────────────
const _days      = ['MO', 'TU', 'WE', 'TH', 'FR'];
const _dayLabels = ['월', '화', '수', '목', '금'];
const double _timeColW  = 34;
const double _hourH     = 60.0; // 1시간 = 60px
const int    _startHour = 8;   // 08:00부터 표시 (조기 수업·커스텀 이벤트 수용)
const int    _endHour   = 21;

// ── 내부 이벤트 모델 ──────────────────────────────────────────────
class _GridEvent {
  final String id;
  final String title;
  final String location;
  final int    startMin; // 자정 기준 분
  final int    endMin;
  final Color  color;
  final bool   isCustom;

  const _GridEvent({
    required this.id,
    required this.title,
    required this.location,
    required this.startMin,
    required this.endMin,
    required this.color,
    required this.isCustom,
  });
}

// ── 유틸 ─────────────────────────────────────────────────────────
int? _parseMin(String time) {
  final parts = time.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

String _minLabel(int min) {
  final h = min ~/ 60;
  final m = min % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// 겹치는 이벤트 컬럼 분할 — 이벤트 리스트가 startMin 정렬됐다고 가정
List<(int colIdx, int totalCols)> _assignColumns(List<_GridEvent> sorted) {
  if (sorted.isEmpty) return [];
  final colIdx = List.filled(sorted.length, 0);
  final colEnds = <int>[]; // 각 컬럼의 마지막 이벤트 종료 시각

  for (int i = 0; i < sorted.length; i++) {
    final ev = sorted[i];
    int col = -1;
    for (int c = 0; c < colEnds.length; c++) {
      if (colEnds[c] <= ev.startMin) { col = c; break; }
    }
    if (col == -1) {
      col = colEnds.length;
      colEnds.add(ev.endMin);
    } else {
      colEnds[col] = ev.endMin;
    }
    colIdx[i] = col;
  }

  final maxCols = colEnds.length;
  return List.generate(sorted.length, (i) => (colIdx[i], maxCols));
}

// ── 그리드 위젯 ───────────────────────────────────────────────────
class TimetableGrid extends StatelessWidget {
  final List<ClassSession>  sessions;
  final List<CustomEvent>   customEvents;
  final void Function(String eventId) onDeleteCustomEvent;

  const TimetableGrid({
    super.key,
    required this.sessions,
    required this.customEvents,
    required this.onDeleteCustomEvent,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final totalW  = box.maxWidth;
      final dayW    = (totalW - _timeColW) / 5;
      const gridH   = (_endHour - _startHour) * _hourH;

      return Column(
        children: [
          // 요일 헤더 (고정, 스크롤 안 됨)
          _buildHeader(dayW),
          const Divider(height: 1, color: Color(0xFFE0E0E0)),
          // 그리드 바디 (세로 스크롤)
          Expanded(
            child: SingleChildScrollView(
              child: SizedBox(
                height: gridH,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 시간 컬럼
                    SizedBox(width: _timeColW, child: _buildTimeCol()),
                    // 요일별 컬럼
                    ...List.generate(5, (i) {
                      final events = _collectEvents(_days[i]);
                      final sorted = [...events]
                        ..sort((a, b) => a.startMin.compareTo(b.startMin));
                      final layout = _assignColumns(sorted);
                      return Expanded(
                        child: Stack(
                          children: [
                            _buildGridLines(),
                            for (int j = 0; j < sorted.length; j++)
                              _buildBlock(
                                context,
                                sorted[j],
                                dayW,
                                layout[j].$1,
                                layout[j].$2,
                              ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  // ── 요일 헤더 ──────────────────────────────────────────────────

  Widget _buildHeader(double dayW) {
    final today = DateTime.now().weekday; // 1=월 … 5=금
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          const SizedBox(width: _timeColW),
          ...List.generate(5, (i) {
            final isToday = today - 1 == i;
            return SizedBox(
              width: dayW,
              child: Center(
                child: isToday
                    ? Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(
                          color: Color(0xFF1A73E8),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            _dayLabels[i],
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      )
                    : Text(
                        _dayLabels[i],
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF767676)),
                      ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── 시간 라벨 컬럼 ────────────────────────────────────────────

  Widget _buildTimeCol() {
    return Stack(
      children: [
        for (int h = _startHour; h <= _endHour; h++)
          Positioned(
            top: (h - _startHour) * _hourH - 6,
            right: 4,
            child: Text(
              '$h',
              style: const TextStyle(fontSize: 10, color: Color(0xFFAAAAAA)),
            ),
          ),
      ],
    );
  }

  // ── 수평 시간선 ───────────────────────────────────────────────

  Widget _buildGridLines() {
    return Stack(
      children: [
        for (int h = 0; h <= _endHour - _startHour; h++)
          Positioned(
            top: h * _hourH,
            left: 0,
            right: 0,
            child: Container(height: 1, color: const Color(0xFFF0F0F0)),
          ),
      ],
    );
  }

  // ── 이벤트 블록 ──────────────────────────────────────────────

  Widget _buildBlock(
    BuildContext context,
    _GridEvent ev,
    double dayW,
    int colIdx,
    int totalCols,
  ) {
    const gridStartMin = _startHour * 60;
    final top    = (ev.startMin - gridStartMin) / 60 * _hourH;
    final rawH   = (ev.endMin - ev.startMin) / 60 * _hourH;
    final height = math.max(18.0, rawH - 2);
    final colW   = (dayW - 2) / totalCols;
    final left   = colIdx * colW + 1;

    return Positioned(
      top:   top,
      left:  left,
      width: colW - 1,
      height: height,
      child: GestureDetector(
        onTap: () => ev.isCustom
            ? _onTapCustom(context, ev)
            : _onTapSession(context, ev),
        child: Container(
          decoration: BoxDecoration(
            color: ev.color,
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          child: height < 20
              ? null
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ev.title,
                      maxLines: height < 36 ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                    if (ev.location.isNotEmpty && height >= 38)
                      Text(
                        ev.location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 9, color: Colors.white70, height: 1.2),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  // ── 탭 핸들러 ─────────────────────────────────────────────────

  void _onTapCustom(BuildContext context, _GridEvent ev) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(ev.title),
        content: Text(
          '${_minLabel(ev.startMin)} ~ ${_minLabel(ev.endMin)}'
          '${ev.location.isNotEmpty ? '\n${ev.location}' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onDeleteCustomEvent(ev.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  void _onTapSession(BuildContext context, _GridEvent ev) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        '${ev.title}  ${_minLabel(ev.startMin)}~${_minLabel(ev.endMin)}'
        '${ev.location.isNotEmpty ? '  ${ev.location}' : ''}',
      ),
      duration: const Duration(seconds: 2),
    ));
  }

  // ── 이벤트 수집 ──────────────────────────────────────────────

  List<_GridEvent> _collectEvents(String day) {
    final list = <_GridEvent>[];

    for (final s in sessions) {
      if (!s.weekdays.contains(day)) continue;
      final start = _parseMin(s.startTime);
      final end   = _parseMin(s.endTime);
      if (start == null || end == null || end <= start) continue;
      // 그리드 범위 클리핑
      final s2 = math.max(start, _startHour * 60);
      final e2 = math.min(end,   _endHour * 60);
      if (e2 <= s2) continue;
      list.add(_GridEvent(
        id:       s.uid,
        title:    s.summary,
        location: s.location,
        startMin: s2,
        endMin:   e2,
        color:    courseColor(s.summary),
        isCustom: false,
      ));
    }

    for (final ce in customEvents) {
      if (!ce.weekdays.contains(day)) continue;
      final start = _parseMin(ce.startTime);
      final end   = _parseMin(ce.endTime);
      if (start == null || end == null || end <= start) continue;
      final s2 = math.max(start, _startHour * 60);
      final e2 = math.min(end,   _endHour * 60);
      if (e2 <= s2) continue;
      list.add(_GridEvent(
        id:       ce.id,
        title:    ce.title,
        location: ce.location,
        startMin: s2,
        endMin:   e2,
        color:    paletteColor(ce.colorIndex),
        isCustom: true,
      ));
    }

    return list;
  }
}
