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

/// 서버 HTML 게시판 — 게시판 URL이 학과 홈페이지와 다른 호스트이거나
/// 쿼리/인코딩이 있는 경우 전체 URL을 직접 지정. (host는 홈페이지용)
DepartmentNoticeSource _board(String code, String host, String noticeUrl) =>
    DepartmentNoticeSource(
      deptCode: code,
      noticeListUrl: noticeUrl,
      homepageUrl: 'https://$host/',
    );

/// 홈페이지 fallback 전용 — 인앱 추출 미지원(SPA/div기반/eGov-js) 학과.
/// "학과 홈페이지 열기" 버튼만 제공.
DepartmentNoticeSource _home(String code, String host) =>
    DepartmentNoticeSource(deptCode: code, homepageUrl: 'https://$host/');

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
  'physics': _board('physics', 'physics.snu.ac.kr',
      'https://physics.snu.ac.kr/boards/notice'),
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

  // ─── 2단계: 서버 HTML 게시판 ───
  'economics': _html('economics', 'econ.snu.ac.kr', '/announcement/notice'),
  'nursing': _html('nursing', 'nursing.snu.ac.kr', '/board/notice'),
  'chemistry': _html('chemistry', 'chem.snu.ac.kr', '/community/notice'),

  // 사회과학대학
  'psychology':
      _html('psychology', 'psych.snu.ac.kr', '/bbs/board.php?tbl=bbs61'),
  'geography': _html('geography', 'geog.snu.ac.kr', '/bbs/board.php?tbl=bbs61'),
  // 자연과학대학
  'life_sciences': _html('life_sciences', 'biosci.snu.ac.kr', '/board/notice'),
  'earth_sciences':
      _html('earth_sciences', 'sees.snu.ac.kr', '/community/notice'),
  // 경영대학
  'business_admin':
      _board('business_admin', 'cba.snu.ac.kr', 'https://cba.snu.ac.kr/newsroom/notice?sc=y'),
  // 공과대학
  'aerospace': _html('aerospace', 'aerospace.snu.ac.kr', '/board/notice'),
  'cse': _html('cse', 'cse.snu.ac.kr', '/community/notice'),
  'nuclear': _html('nuclear', 'nucleng.snu.ac.kr', '/community/notice'),
  'electrical':
      _board('electrical', 'ece.snu.ac.kr', 'https://ece.snu.ac.kr/community/academics?sc=y'),
  'chemical_engineering': _board('chemical_engineering', 'cbe.snu.ac.kr',
      'https://cbe.snu.ac.kr/cbe/bbs/BMSR00062/list.do?menuNo=300043'),
  // 인문대학
  'german_language': _board('german_language', 'german.snu.ac.kr',
      'https://german.snu.ac.kr/%EA%B3%B5%EC%A7%80%EC%82%AC%ED%95%AD/'),
  'religion':
      _board('religion', 'religion.snu.ac.kr', 'https://religion.snu.ac.kr/?page_id=1995'),
  // 역사학부(통합) — 앱의 3개 코드 모두 같은 사이트
  'korean_history': _html('korean_history', 'history.snu.ac.kr', '/notice/'),
  'eastern_history': _html('eastern_history', 'history.snu.ac.kr', '/notice/'),
  'western_history': _html('western_history', 'history.snu.ac.kr', '/notice/'),
  // 사범대학
  'social_edu':
      _html('social_edu', 'socialedu.snu.ac.kr', '/sub_notice/notice.php'),
  'ethics_edu':
      _html('ethics_edu', 'ethics.snu.ac.kr', '/sub_notice/board02.php'),
  'mechanical': _board('mechanical', 'me.snu.ac.kr',
      'https://me.snu.ac.kr/%EA%B3%B5%ED%86%B5-%EA%B3%B5%EC%A7%80%EC%82%AC%ED%95%AD/'),
  // 생활과학대학
  'textiles': _board('textiles', 'clothing.snu.ac.kr',
      'https://clothing.snu.ac.kr/%EA%B3%B5%EC%A7%80%EC%82%AC%ED%95%AD/'),
  // 자유전공학부
  'liberal': _html('liberal', 'cls.snu.ac.kr', '/notice/'),
  // 농업생명과학대학 — 6개 학과 공통 대학 게시판(cals)
  'food_agriculture':
      _board('food_agriculture', 'cals.snu.ac.kr', 'https://cals.snu.ac.kr/board/notice'),
  'forest_science':
      _board('forest_science', 'cals.snu.ac.kr', 'https://cals.snu.ac.kr/board/notice'),
  'landscape':
      _board('landscape', 'cals.snu.ac.kr', 'https://cals.snu.ac.kr/board/notice'),
  'biosystems':
      _board('biosystems', 'cals.snu.ac.kr', 'https://cals.snu.ac.kr/board/notice'),
  'food_animal':
      _board('food_animal', 'cals.snu.ac.kr', 'https://cals.snu.ac.kr/board/notice'),
  'food_nutrition':
      _board('food_nutrition', 'cals.snu.ac.kr', 'https://cals.snu.ac.kr/board/notice'),
  // 미술대학 — 6개 학과 공통 게시판(art)
  'painting': _board('painting', 'art.snu.ac.kr',
      'https://art.snu.ac.kr/notice/?catemenu=Notice&type=Events'),
  'sculpture': _board('sculpture', 'art.snu.ac.kr',
      'https://art.snu.ac.kr/notice/?catemenu=Notice&type=Events'),
  'crafts': _board('crafts', 'art.snu.ac.kr',
      'https://art.snu.ac.kr/notice/?catemenu=Notice&type=Events'),
  'design': _board('design', 'art.snu.ac.kr',
      'https://art.snu.ac.kr/notice/?catemenu=Notice&type=Events'),
  'visual_design': _board('visual_design', 'art.snu.ac.kr',
      'https://art.snu.ac.kr/notice/?catemenu=Notice&type=Events'),
  'industrial_design': _board('industrial_design', 'art.snu.ac.kr',
      'https://art.snu.ac.kr/notice/?catemenu=Notice&type=Events'),

  // ─── 홈페이지 fallback (인앱 추출 미지원 — SPA/div기반/eGov-js) ───
  'french_language': _home('french_language', 'www.snufrance.com'),
  'archaeology': _home('archaeology', 'www.archaeology-arthistory.or.kr'),
  'anthropology': _home('anthropology', 'www.anthropology.or.kr'),
  'philosophy': _home('philosophy', 'philosophy.snu.ac.kr'),
  'political_science': _home('political_science', 'polisci.snu.ac.kr'),
  'social_welfare': _home('social_welfare', 'socialwelfare.snu.ac.kr'),
  'mathematics': _home('mathematics', 'www.math.snu.ac.kr'),
  'civil': _home('civil', 'cee.snu.ac.kr'),
  'english_edu': _home('english_edu', 'engedu.snu.ac.kr'),
  'german_edu': _home('german_edu', 'germanedu.snu.ac.kr'),
  'medicine': _home('medicine', 'medicine.snu.ac.kr'),
  'law': _home('law', 'law.snu.ac.kr'),
  'dentistry': _home('dentistry', 'dentistry.snu.ac.kr'),
  // 음악대학 5개 학과 공통
  'composition': _home('composition', 'music.snu.ac.kr'),
  'piano': _home('piano', 'music.snu.ac.kr'),
  'voice': _home('voice', 'music.snu.ac.kr'),
  'orchestral': _home('orchestral', 'music.snu.ac.kr'),
  'korean_music': _home('korean_music', 'music.snu.ac.kr'),
};

/// deptCode로 공지 소스 조회. 없으면 null.
DepartmentNoticeSource? noticeSourceFor(String? deptCode) {
  if (deptCode == null) return null;
  return departmentNoticeSources[deptCode];
}
