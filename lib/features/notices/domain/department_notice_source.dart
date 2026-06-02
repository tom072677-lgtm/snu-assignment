/// 학과별 공지 소스 설정.
///
/// 1단계(RSS): WordPress `/feed/`에 **실제 최신 공지가 있음을 직접 검증한** 학과만 등록한다.
/// (RSS가 떠도 옛 글/테스트만 있는 학과는 제외 — 예: 기계공학부 me.snu)
///
/// 상태 3단계:
///  - `noticeSourceFor(code) == null`      → 학과 매핑 없음 (미설정/미지원)
///  - source 있음 + `rssFeedUrl == null`   → 홈페이지 fallback
///  - source 있음 + `rssFeedUrl != null`   → RSS 시도
class DepartmentNoticeSource {
  const DepartmentNoticeSource({
    required this.deptCode,
    this.rssFeedUrl,
    this.noticeListUrl,
    this.containerSelector,
    this.excludeTextPatterns = const [],
    required this.homepageUrl,
  });

  /// snu_departments.dart의 학과 code
  final String deptCode;

  /// 1단계: RSS/Atom 피드 URL (우선). null이면 RSS 미지원.
  final String? rssFeedUrl;

  /// 2단계: 서버 HTML 게시판 목록 URL. rssFeedUrl이 없을 때 사용.
  final String? noticeListUrl;

  /// (선택) 목록 컨테이너 강제 지정 — 범용 휴리스틱이 오탐할 때만.
  final String? containerSelector;

  /// (선택) 비게시글 링크 제외 패턴(부분일치) — "더보기","목록" 등.
  final List<String> excludeTextPatterns;

  /// 학과 홈페이지 (항상 존재) — "학과 홈페이지 열기"용
  final String homepageUrl;
}

DepartmentNoticeSource _wp(String code, String host) => DepartmentNoticeSource(
      deptCode: code,
      rssFeedUrl: 'https://$host/feed/',
      homepageUrl: 'https://$host/',
    );

/// 서버 HTML 게시판(2단계). listPath는 공지 목록 페이지 경로.
DepartmentNoticeSource _html(String code, String host, String listPath) =>
    DepartmentNoticeSource(
      deptCode: code,
      noticeListUrl: 'https://$host$listPath',
      homepageUrl: 'https://$host/',
    );

/// 검증 완료된 학과만 등록 (2026-06-02 피드 내용 직접 확인).
/// 미등록 학과는 `noticeSourceFor`가 null 반환 → UI에서 "준비 중" 안내.
final Map<String, DepartmentNoticeSource> departmentNoticeSources = {
  // 인문대학
  'korean_language': _wp('korean_language', 'korean.snu.ac.kr'),
  'chinese_language': _wp('chinese_language', 'snucll.snu.ac.kr'),
  'english_language': _wp('english_language', 'english.snu.ac.kr'),
  'russian_language': _wp('russian_language', 'russian.snu.ac.kr'),
  'spanish_language': _wp('spanish_language', 'spanish.snu.ac.kr'),
  'linguistics': _wp('linguistics', 'linguist.snu.ac.kr'),
  'aesthetics': _wp('aesthetics', 'meehak.snu.ac.kr'),
  // 사회과학대학
  'sociology': _wp('sociology', 'sociology.snu.ac.kr'),
  'communication': _wp('communication', 'communication.snu.ac.kr'),
  // 자연과학대학
  'statistics': _wp('statistics', 'stat.snu.ac.kr'),
  'physics': _wp('physics', 'astron.snu.ac.kr'),
  // 공과대학
  'material_science': _wp('material_science', 'mse.snu.ac.kr'),
  'architecture': _wp('architecture', 'architecture.snu.ac.kr'),
  'industrial': _wp('industrial', 'ie.snu.ac.kr'),
  // 사범대학
  'edu_admin': _wp('edu_admin', 'learning.snu.ac.kr'),
  'korean_edu': _wp('korean_edu', 'koredu.snu.ac.kr'),
  'french_edu': _wp('french_edu', 'french.snu.ac.kr'),
  'history_edu': _wp('history_edu', 'histoedu.snu.ac.kr'),
  'geography_edu': _wp('geography_edu', 'geoedu.snu.ac.kr'),
  'math_edu': _wp('math_edu', 'mathed.snu.ac.kr'),
  'physics_edu': _wp('physics_edu', 'physed.snu.ac.kr'),
  'chemistry_edu': _wp('chemistry_edu', 'chemedu.snu.ac.kr'),
  'biology_edu': _wp('biology_edu', 'biologyedu.snu.ac.kr'),
  'earth_edu': _wp('earth_edu', 'earthedu.snu.ac.kr'),
  'physical_edu': _wp('physical_edu', 'sports.snu.ac.kr'),
  // 생활과학대학
  'consumer_child': _wp('consumer_child', 'consumer.snu.ac.kr'),
  'food_nutrition_he': _wp('food_nutrition_he', 'foodnutrition.snu.ac.kr'),
  // 수의과대학
  'veterinary': _wp('veterinary', 'vet.snu.ac.kr'),
  // 약학대학
  'pharmacy': _wp('pharmacy', 'snupharm.snu.ac.kr'),

  // ─── 2단계: 서버 HTML 게시판 (공통 _skin/kor CMS 계열) ───
  'economics': _html('economics', 'econ.snu.ac.kr', '/announcement/notice'),
  'nursing': _html('nursing', 'nursing.snu.ac.kr', '/board/notice'),
  'chemistry': _html('chemistry', 'chem.snu.ac.kr', '/community/notice'),
};

/// deptCode로 공지 소스 조회. 없으면 null.
DepartmentNoticeSource? noticeSourceFor(String? deptCode) {
  if (deptCode == null) return null;
  return departmentNoticeSources[deptCode];
}
