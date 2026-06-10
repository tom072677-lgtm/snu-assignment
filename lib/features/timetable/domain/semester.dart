// 학기 판정 — 순수 함수(테스트 가능). 학사일정 하드코딩 없이 월 범위만 사용.

/// 날짜 → 학기 키. 3~8월=1학기, 9~12월=2학기, 1~2월=직전 연도 2학기(겨울방학).
String semesterKey(DateTime d) {
  if (d.month >= 3 && d.month <= 8) return '${d.year}-1';
  if (d.month >= 9) return '${d.year}-2';
  return '${d.year - 1}-2';
}

/// 저장된 시간표가 '지난 학기' 것이라 갱신을 권해야 하는지 판정.
/// now를 주입받아 테스트 가능. capturedAt이 없으면(기존 사용자) 오탐 방지로 false.
bool isTimetableStale({
  required bool hasSessions,
  required DateTime? capturedAt,
  required String? snoozedSemester,
  required DateTime now,
}) {
  if (!hasSessions || capturedAt == null) return false;
  final cur = semesterKey(now);
  return semesterKey(capturedAt) != cur && snoozedSemester != cur;
}
