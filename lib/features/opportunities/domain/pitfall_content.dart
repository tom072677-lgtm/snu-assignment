import 'opportunity.dart';

class Pitfall {
  final String title;
  final String body;
  const Pitfall(this.title, this.body);
}

/// 카테고리별 함정/체크리스트(앱 내장 정적 콘텐츠). API 비의존.
const Map<OppCategory, List<Pitfall>> kPitfalls = {
  OppCategory.scholarship: [
    Pitfall(
      '가구원 정보제공 동의 필수',
      '국가장학금은 신청만으로 끝이 아닙니다. 부모/배우자의 가구원 정보제공 동의를 안 하면 소득구간 산정이 안 돼 자동 탈락합니다. 신청현황에서 동의·서류 상태를 꼭 확인하세요.',
    ),
    Pitfall(
      '재학생은 1차에 신청',
      '재학생은 가급적 1차에 신청하세요. 2차 신청은 평생 2회만 구제되고 이후 학기 수혜에 제한이 생길 수 있습니다.',
    ),
    Pitfall(
      '중복수혜 한도 주의',
      '교내+외부+국가 장학을 합쳐 등록금을 초과하면 환수되거나 일부만 인정될 수 있습니다.',
    ),
  ],
  OppCategory.contest: [
    Pitfall(
      '저작권·참가비 조항 확인',
      '응모 전 요강의 저작권 조항을 확인하세요. 입상하지 않은 응모작까지 저작권이 주최 측에 귀속되거나 참가비를 선불로 받는 공모전은 주의가 필요합니다.',
    ),
  ],
};
