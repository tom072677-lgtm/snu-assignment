/// 서울대학교 단과대학 및 학과/학부 정적 목록.
/// 학과 코드는 제휴 식당 API 요청 시 사용한다.
library;

class SnuCollege {
  final String code;  // 예: 'engineering'
  final String name;  // 예: '공과대학'
  final List<SnuDepartment> departments;
  const SnuCollege({required this.code, required this.name, required this.departments});
}

class SnuDepartment {
  final String code;  // 예: 'cse'
  final String name;  // 예: '컴퓨터공학부'
  const SnuDepartment({required this.code, required this.name});
}

const List<SnuCollege> snuColleges = [
  SnuCollege(code: 'liberal_arts', name: '인문대학', departments: [
    SnuDepartment(code: 'korean_language', name: '국어국문학과'),
    SnuDepartment(code: 'chinese_language', name: '중어중문학과'),
    SnuDepartment(code: 'english_language', name: '영어영문학과'),
    SnuDepartment(code: 'french_language', name: '불어불문학과'),
    SnuDepartment(code: 'german_language', name: '독어독문학과'),
    SnuDepartment(code: 'russian_language', name: '노어노문학과'),
    SnuDepartment(code: 'spanish_language', name: '서어서문학과'),
    SnuDepartment(code: 'linguistics', name: '언어학과'),
    SnuDepartment(code: 'korean_history', name: '국사학과'),
    SnuDepartment(code: 'eastern_history', name: '동양사학과'),
    SnuDepartment(code: 'western_history', name: '서양사학과'),
    SnuDepartment(code: 'archaeology', name: '고고미술사학과'),
    SnuDepartment(code: 'philosophy', name: '철학과'),
    SnuDepartment(code: 'religion', name: '종교학과'),
    SnuDepartment(code: 'aesthetics', name: '미학과'),
  ]),
  SnuCollege(code: 'social_sciences', name: '사회과학대학', departments: [
    SnuDepartment(code: 'political_science', name: '정치외교학부'),
    SnuDepartment(code: 'economics', name: '경제학부'),
    SnuDepartment(code: 'sociology', name: '사회학과'),
    SnuDepartment(code: 'anthropology', name: '인류학과'),
    SnuDepartment(code: 'psychology', name: '심리학과'),
    SnuDepartment(code: 'geography', name: '지리학과'),
    SnuDepartment(code: 'social_welfare', name: '사회복지학과'),
    SnuDepartment(code: 'communication', name: '언론정보학과'),
  ]),
  SnuCollege(code: 'natural_sciences', name: '자연과학대학', departments: [
    SnuDepartment(code: 'mathematics', name: '수리과학부'),
    SnuDepartment(code: 'statistics', name: '통계학과'),
    SnuDepartment(code: 'physics', name: '물리천문학부'),
    SnuDepartment(code: 'chemistry', name: '화학부'),
    SnuDepartment(code: 'life_sciences', name: '생명과학부'),
    SnuDepartment(code: 'earth_sciences', name: '지구환경과학부'),
  ]),
  SnuCollege(code: 'nursing', name: '간호대학', departments: [
    SnuDepartment(code: 'nursing', name: '간호학과'),
  ]),
  SnuCollege(code: 'engineering', name: '공과대학', departments: [
    SnuDepartment(code: 'cse', name: '컴퓨터공학부'),
    SnuDepartment(code: 'electrical', name: '전기·정보공학부'),
    SnuDepartment(code: 'mechanical', name: '기계공학부'),
    SnuDepartment(code: 'aerospace', name: '항공우주공학과'),
    SnuDepartment(code: 'material_science', name: '재료공학부'),
    SnuDepartment(code: 'chemical_engineering', name: '화학생물공학부'),
    SnuDepartment(code: 'nuclear', name: '에너지시스템공학부'),
    SnuDepartment(code: 'civil', name: '건설환경공학부'),
    SnuDepartment(code: 'architecture', name: '건축학과'),
    SnuDepartment(code: 'industrial', name: '산업공학과'),
    SnuDepartment(code: 'systems_biomedical', name: '시스템생명공학부'),
    SnuDepartment(code: 'interdisciplinary_engineering', name: '학제전공'),
  ]),
  SnuCollege(code: 'agriculture', name: '농업생명과학대학', departments: [
    SnuDepartment(code: 'food_agriculture', name: '식물생산과학부'),
    SnuDepartment(code: 'forest_science', name: '산림과학부'),
    SnuDepartment(code: 'landscape', name: '조경·지역시스템공학부'),
    SnuDepartment(code: 'biosystems', name: '바이오시스템·소재학부'),
    SnuDepartment(code: 'food_animal', name: '농경제사회학부'),
    SnuDepartment(code: 'food_nutrition', name: '식품·동물생명공학부'),
  ]),
  SnuCollege(code: 'business', name: '경영대학', departments: [
    SnuDepartment(code: 'business_admin', name: '경영학과'),
  ]),
  SnuCollege(code: 'education', name: '사범대학', departments: [
    SnuDepartment(code: 'edu_admin', name: '교육학과'),
    SnuDepartment(code: 'korean_edu', name: '국어교육과'),
    SnuDepartment(code: 'english_edu', name: '영어교육과'),
    SnuDepartment(code: 'french_edu', name: '불어교육과'),
    SnuDepartment(code: 'german_edu', name: '독어교육과'),
    SnuDepartment(code: 'social_edu', name: '사회교육과'),
    SnuDepartment(code: 'history_edu', name: '역사교육과'),
    SnuDepartment(code: 'geography_edu', name: '지리교육과'),
    SnuDepartment(code: 'ethics_edu', name: '윤리교육과'),
    SnuDepartment(code: 'math_edu', name: '수학교육과'),
    SnuDepartment(code: 'physics_edu', name: '물리교육과'),
    SnuDepartment(code: 'chemistry_edu', name: '화학교육과'),
    SnuDepartment(code: 'biology_edu', name: '생물교육과'),
    SnuDepartment(code: 'earth_edu', name: '지구과학교육과'),
    SnuDepartment(code: 'physical_edu', name: '체육교육과'),
  ]),
  SnuCollege(code: 'fine_arts', name: '미술대학', departments: [
    SnuDepartment(code: 'painting', name: '회화과'),
    SnuDepartment(code: 'sculpture', name: '조소과'),
    SnuDepartment(code: 'crafts', name: '공예과'),
    SnuDepartment(code: 'design', name: '디자인학부'),
    SnuDepartment(code: 'visual_design', name: '시각디자인과'),
    SnuDepartment(code: 'industrial_design', name: '산업디자인과'),
  ]),
  SnuCollege(code: 'music', name: '음악대학', departments: [
    SnuDepartment(code: 'composition', name: '작곡과'),
    SnuDepartment(code: 'piano', name: '피아노과'),
    SnuDepartment(code: 'voice', name: '성악과'),
    SnuDepartment(code: 'orchestral', name: '관현악과'),
    SnuDepartment(code: 'korean_music', name: '국악과'),
  ]),
  SnuCollege(code: 'law', name: '법과대학', departments: [
    SnuDepartment(code: 'law', name: '법학부'),
  ]),
  SnuCollege(code: 'veterinary', name: '수의과대학', departments: [
    SnuDepartment(code: 'veterinary', name: '수의학과'),
  ]),
  SnuCollege(code: 'medicine', name: '의과대학', departments: [
    SnuDepartment(code: 'medicine', name: '의학과'),
  ]),
  SnuCollege(code: 'dentistry', name: '치의학대학원', departments: [
    SnuDepartment(code: 'dentistry', name: '치의학과'),
  ]),
  SnuCollege(code: 'pharmacy', name: '약학대학', departments: [
    SnuDepartment(code: 'pharmacy', name: '약학과'),
  ]),
  SnuCollege(code: 'home_economics', name: '생활과학대학', departments: [
    SnuDepartment(code: 'consumer_child', name: '소비자아동학부'),
    SnuDepartment(code: 'food_nutrition_he', name: '식품영양학과'),
    SnuDepartment(code: 'textiles', name: '의류학과'),
  ]),
  SnuCollege(code: 'humanities', name: '자유전공학부', departments: [
    SnuDepartment(code: 'liberal', name: '자유전공학부'),
  ]),
];
