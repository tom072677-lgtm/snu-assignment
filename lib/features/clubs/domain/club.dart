/// 동아리 데이터 모델 (서울대).
library;

import '../../onboarding/domain/snu_departments.dart';

/// 활동 분야 6분류.
const List<String> kClubCategories = [
  '학술',
  '봉사·종교',
  '운동',
  '음악·공연',
  '취미',
  '기타',
];

/// 가입 자격(tier) 값.
const String kTierCentral = 'central'; // 중앙동아리 — 전교생
const String kTierCollege = 'college'; // 단과대 동아리
const String kTierDorm = 'dorm';       // 기숙사(관악사) 동아리

class Club {
  final String id;
  final String name;
  final String tier;            // central | college | dorm
  final String category;        // kClubCategories 중 하나
  final List<String> colleges;  // 단과대 코드(college tier에서 의미), 그 외 빈 목록
  final String activity;        // 한 줄 활동 설명 (없으면 '')
  final String? registration;   // '정' | '가' | null(미상)

  const Club({
    required this.id,
    required this.name,
    required this.tier,
    required this.category,
    this.colleges = const [],
    this.activity = '',
    this.registration,
  });

  factory Club.fromJson(Map<String, dynamic> j) {
    final cat = j['category'] as String?;
    return Club(
      id: j['id'] as String,
      name: j['name'] as String,
      tier: j['tier'] as String? ?? kTierCentral,
      // 알 수 없는 분류는 '기타'로 fallback (리뷰 반영).
      category: (cat != null && kClubCategories.contains(cat)) ? cat : '기타',
      colleges: (j['colleges'] as List? ?? const []).cast<String>(),
      activity: j['activity'] as String? ?? '',
      registration: j['registration'] as String?,
    );
  }

  /// 가입 자격 뱃지에 표시할 라벨 목록.
  /// central → ['중앙'], dorm → ['기숙사'], college → 단과대 이름들.
  List<String> get eligibilityLabels {
    switch (tier) {
      case kTierDorm:
        return const ['기숙사'];
      case kTierCollege:
        if (colleges.isEmpty) return const ['단과대'];
        return colleges.map(collegeNameFromCode).toList();
      case kTierCentral:
      default:
        return const ['중앙'];
    }
  }
}

/// 단과대 코드 → 한글 이름. 매칭 실패 시 코드 그대로 반환.
String collegeNameFromCode(String code) {
  for (final c in snuColleges) {
    if (c.code == code) return c.name;
  }
  return code;
}
