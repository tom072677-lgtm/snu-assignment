class OppUserPrefs {
  final Set<String> interests;
  const OppUserPrefs({this.interests = const {}});
}

/// 온보딩/필터에서 고르는 관심 분야(고정 어휘).
/// fixture/서버의 tags도 반드시 이 어휘를 사용해야 개인화 매칭이 동작한다.
const List<String> kInterestOptions = [
  'IT/개발',
  '디자인',
  '마케팅',
  '기획',
  '영상/콘텐츠',
  '이공계/연구',
  '경영/경제',
  '예술/문학',
];
