# PLAN — 시간표 갱신 리마인더 + 개별 과목 삭제

## 무엇을 / 왜
mySNU에서 가져온 시간표는 캡처 시점에 고정된다. eTL에는 수업 시간표가 없음이 이번 디버깅에서 확인됨(개인 iCal 피드 = 과제 마감 13건, 시간 없는 VALUE=DATE, 수업 이벤트 0). 따라서 시간표의 권위 소스는 mySNU이며, 다음 두 불편을 해소한다:

1. **학기 전환을 사용자가 잊는다** → 저장된 시간표가 "지난 학기" 것이면 자동으로 갱신 배너를 띄운다.
2. **과목 하나를 드랍했는데 갱신하려면 재로그인해야 한다** → 시간표에서 그 과목 블록을 탭해 **직접 삭제**할 수 있게 한다(로그인 불필요).

과외·동아리 같은 주기적 일정 직접 추가/삭제는 `CustomEvent`(➕ FAB + 탭 삭제)로 **이미 구현되어 있음** → 이번 작업 범위 아님(기기에서 동작만 확인).

## 핵심 설계 원칙
- **기존 시간표 렌더링 경로는 건드리지 않는다.** `mySNUSessionsProvider`의 상태 타입(`List<ClassSession>`)을 그대로 두고, 새 기능은 **순수 추가(additive)** 로만 넣어 회귀 위험을 0에 가깝게. (회귀 방지 메모리 준수)
- 학기 판정은 **월 범위만** 사용(학사일정 하드코딩 없음) → 다대학 확장에도 유지보수 부담 없음.

## 현재 코드 사실(조사 완료)
- `MySNUSessionsNotifier`(settings_provider.dart:253): `build`(prefs 로드), `setSessions`(저장), `clear`만 존재 → 개별 삭제·캡처시각 없음.
- `_openMySNU`/`_importIcs`(timetable_screen.dart:223,237) → `setSessions(result)`.
- `TimetableGrid`(timetable_grid.dart:100): 세션 블록 탭=`_onTapSession`→스낵바만(삭제 없음). 커스텀 블록 탭=`_onTapCustom`→정보+삭제 다이얼로그.
- `CustomEvent`+`customEventsProvider`: 주기적 일정 추가/삭제 완비.

## 단계별 접근

### 1. 상수 추가 → verify: 컴파일
`lib/core/constants.dart` (kMySNUSessions 근처):
```dart
const String kMySNUCapturedAt      = 'mysnu_captured_at';       // ISO8601 String
const String kMySNUSnoozedSemester = 'mysnu_snoozed_semester';  // 예: "2026-1"
```

### 2. 학기 키 헬퍼(순수 함수) + 단위 테스트 → verify: 테스트 통과(빌드 전)
신규 `lib/features/timetable/domain/semester.dart`:
```dart
/// 날짜 → 학기 키. 3~8월=1학기, 9~12월=2학기, 1~2월=직전 연도 2학기(겨울방학).
String semesterKey(DateTime d) {
  if (d.month >= 3 && d.month <= 8) return '${d.year}-1';
  if (d.month >= 9) return '${d.year}-2';
  return '${d.year - 1}-2';
}
```
테스트 `test/features/timetable/semester_test.dart`: 3·8월→`-1`, 9·12월→`-2`, 1·2월→`{year-1}-2`, 연말 경계(2026-12 vs 2027-01) 구분.

### 3. capturedAt / 스누즈 provider(별도, 추가만) → verify: 컴파일
`settings_provider.dart`에 신규(기존 `MySNUSessionsNotifier` 미수정):
```dart
class MySNUCapturedAtNotifier extends Notifier<DateTime?> {
  late SharedPreferences _prefs;
  @override DateTime? build() {
    _prefs = ref.watch(sharedPrefsProvider);
    final raw = _prefs.getString(kMySNUCapturedAt);
    return raw == null ? null : DateTime.tryParse(raw);
  }
  void set(DateTime t) { state = t; _prefs.setString(kMySNUCapturedAt, t.toIso8601String()); }
  void clear() { state = null; _prefs.remove(kMySNUCapturedAt); }
}
final mySNUCapturedAtProvider = NotifierProvider<MySNUCapturedAtNotifier, DateTime?>(MySNUCapturedAtNotifier.new);
```
스누즈 provider도 동일 패턴(`String?`, key=`kMySNUSnoozedSemester`, `set`/`clear`).

### 4. 과목 단위 삭제 메서드 → verify: 컴파일 + (반환값) 단위 테스트
드랍은 "과목 전체"를 지워야 자연스럽다(한 과목이 시간대별로 다른 uid로 쪼개질 수 있음). **summary(과목명) 기준**으로 그 과목의 모든 세션을 제거하고, **실행취소용으로 제거분을 반환**한다. `MySNUSessionsNotifier`에 추가만:
```dart
/// 같은 과목명(summary) 세션을 모두 제거. 제거된 목록 반환(실행취소용).
List<ClassSession> removeCourse(String summary) {
  final removed = state.where((s) => s.summary == summary).toList();
  final next    = state.where((s) => s.summary != summary).toList();
  state = next;
  _prefs.setString(kMySNUSessions, jsonEncode(next.map((s) => s.toJson()).toList()));
  return removed;
}
/// 실행취소: 제거분을 다시 합쳐 저장.
void restoreSessions(List<ClassSession> restored) {
  if (restored.isEmpty) return;
  setSessions([...state, ...restored]);
}
```

### 5. stale 판정 = 순수 함수 + provider → verify: 단위 테스트(빌드 전)
테스트 용이성을 위해 **판정 로직을 순수 함수로 분리**(now 주입)하고, provider는 그걸 `DateTime.now()`로 호출만 한다.
`lib/features/timetable/domain/semester.dart`에 추가:
```dart
/// 저장된 시간표가 '지난 학기' 것인지 판정(순수 — 테스트 가능).
bool isTimetableStale({
  required bool hasSessions,
  required DateTime? capturedAt,
  required String? snoozedSemester,
  required DateTime now,
}) {
  if (!hasSessions || capturedAt == null) return false; // 오탐 방지
  final cur = semesterKey(now);
  return semesterKey(capturedAt) != cur && snoozedSemester != cur;
}
```
`settings_provider.dart`:
```dart
final isTimetableStaleProvider = Provider<bool>((ref) => isTimetableStale(
  hasSessions:     ref.watch(mySNUSessionsProvider).isNotEmpty,
  capturedAt:      ref.watch(mySNUCapturedAtProvider),
  snoozedSemester: ref.watch(mySNUSnoozedSemesterProvider),
  now:             DateTime.now(),
));
```
테스트: 지난 학기 capturedAt→true, 같은 학기→false, capturedAt=null→false, 스누즈=현재학기→false, 학기 경계(8/31 vs 9/1) 동작.

### 6. 그리드: 세션 블록 삭제 옵션 → verify: 빌드 + 탭 동작
`timetable_grid.dart`:
- `TimetableGrid`에 `final void Function(String summary)? onDeleteCourse;` 추가(nullable → 기존 호출부 무영향).
- `_onTapSession`을 스낵바 → **정보 + 삭제 다이얼로그**(기존 `_onTapCustom` 패턴 복제). 다이얼로그 문구에 **과목명 명시**("[과목명] 수업을 시간표에서 삭제할까요?"). 삭제 시 `onDeleteCourse?.call(ev.title)`(title=summary). customEvent 경로 불변.

### 7. 화면: capturedAt 기록 + 배너 + 배선 + 상시 갱신 → verify: 빌드
`timetable_screen.dart`:
- **capturedAt 기록(성공 시에만):** `_openMySNU`의 `if (result != null && result.isNotEmpty)` 블록 **안에서** `setSessions` 직후 `ref.read(mySNUCapturedAtProvider.notifier).set(DateTime.now())`. 취소·빈 결과면 기록 안 함. `_importIcs`도 확정(confirmed) 후 `setSessions` 직후 동일. 🗑 `clear` 시 capturedAt.clear()+스누즈 clear 동반.
- **stale 배너:** `isTimetableStaleProvider`가 true면 그리드 위에 배너 "지난 학기(키) 시간표예요. 갱신할까요? [갱신][나중에]". [갱신]=`_openMySNU`. [나중에]=`mySNUSnoozedSemesterProvider.set(semesterKey(now))`.
- **과목삭제 배선 + 실행취소:** `TimetableGrid(... onDeleteCourse: (summary) { final removed = ref.read(mySNUSessionsProvider.notifier).removeCourse(summary); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$summary 삭제됨'), action: SnackBarAction(label: '실행취소', onPressed: () => ref.read(mySNUSessionsProvider.notifier).restoreSessions(removed)))); })` 두 사용처(`_TimetableBody`, `_CustomOnlyBody`).
- **상시 "마이스누 갱신":** 세션이 있을 때도 보이는 갱신 액션(세션 있을 때 🗑 옆 ⟳) → `_openMySNU`.

### 8. 무결성 확인(규칙 14) → verify: Read 재검토
`timetable_screen.dart` 편집 후 기존 항목(➕ FAB, ICS 가져오기, 🗑 초기화, 도서관 버튼, 새로고침 아이콘, customEvent 삭제 배선)이 **전부 그대로** 인지 육안 확인.

## 동작 규칙(명시)
- 개별 삭제 = **로컬 수동 오버라이드.** 이후 "마이스누 갱신"으로 전체 재캡처 시 **mySNU 현재 상태로 덮어씀**(드랍을 mySNU에서도 했으면 안 돌아오고, 안 했으면 돌아옴 — 의도된 동작).
- capturedAt 없는 기존 사용자 → stale 판정 보류(오탐 0). 다음 갱신부터 기록.

## 성공 기준 (verify)
1. `semesterKey` 단위 테스트 통과(월 경계 포함). — 빌드 전 검증 가능.
2. 지난 학기 capturedAt → 배너 / 같은 학기 → 안 뜸 / capturedAt=null → 안 뜸.
3. 수업 블록 탭 → 삭제 → 그 과목만 사라지고 **나머지 시간표 유지**.
4. [갱신] → mySNU 열림 → 캡처 후 배너 소멸 + capturedAt 갱신.
5. [나중에] → 그 학기 동안 배너 안 뜸, 다음 학기 전환 시 재등장.
6. **기존 기능 회귀 0**: 시간표 렌더링, ➕ 추가, ICS 가져오기, 🗑 초기화, customEvent 삭제 모두 정상.
7. `flutter analyze` 무경고 + 빌드 성공.
8. 기기 확인.

## 범위 밖 / 리스크
- 비범위: 자동 백그라운드 동기화(자격증명 저장) — 보안·약관 위험으로 제외.
- 비범위: 과외·동아리 추가(이미 구현).
- 리스크: `timetable_screen.dart`가 여러 기능 집약 → 규칙 14 체크 필수. nullable 콜백·별도 provider로 회귀면 최소화.

## 리뷰 반영 결정사항 (v2 — Codex 피드백 후 확정)
1. **삭제 단위 = 과목 전체(summary 기준).** 드랍한 과목을 통째로 제거. 그리드 세션 블록 `ev.id=s.uid`, `ev.title=s.summary`이며 삭제는 title(summary)로. 같은 과목이 여러 uid 블록으로 쪼개져도 한 번에 제거.
2. **삭제 안전장치 = 다이얼로그(과목명 명시) + 실행취소 스낵바.** `removeCourse`가 제거분을 반환 → `restoreSessions`로 복구.
3. **capturedAt = "시간표를 마지막으로 설정한 시점"**, mySNU 캡처·ICS import **둘 다** 기록(성공 시에만). **한계 명시:** 과거에 export된 .ics를 import해도 "방금 설정"으로 기록됨 → 그 .ics의 실제 학기는 알 수 없음(import는 사용자가 현재 시간표로 의도한 것으로 간주). stale은 *다음 학기 경계*에서 정상 발화.
4. **판정 로직은 순수 함수 `isTimetableStale(now 주입)`** 로 분리 → 단위 테스트 가능. provider는 `DateTime.now()`로 호출만.
5. **capturedAt 파싱 실패(손상된 prefs):** `DateTime.tryParse`→null → stale false(배너 억제, 안전). 손상값은 다음 갱신 때 덮어씀(능동 삭제는 안 함).
6. **SharedPreferences fire-and-forget:** 기존 코드 스타일(`.ignore()`)과 동일하게 저장 실패는 처리 안 함(명시된 tradeoff).
7. **스누즈는 semesterKey 단위.** 8/31에 스누즈(키 2026-1) 후 9/1(키 2026-2)이면 키가 달라 배너 재등장 = **의도된 동작**(새 학기엔 다시 알림).
8. **capture 실패/취소 시 capturedAt 미갱신** — `_openMySNU`의 성공 분기 안에서만 set.
9. **설계 한계 명시:** capturedAt이 현재 학기여도 세션 내용이 실제와 다를 수 있음(캡처 시점 기반의 본질적 한계). 사용자는 상시 "마이스누 갱신"/개별 삭제로 교정.

## 추가 엣지 케이스 (반영)
- 같은 summary의 다른 과목(동명이인 과목): 드물고, 다이얼로그가 과목명을 보여줌 → 사용자가 확인. 동명 과목 동시 삭제는 허용(YAGNI).
- 실행취소 후 재삭제: `restoreSessions`가 setSessions로 합치므로 일관.
- 빈 시간표에서 삭제 콜백 호출 불가(세션 블록이 없으면 탭 자체가 없음).
