/// 단과대·학과 제휴 식당 데이터 모델.
library;

class PartnerRestaurant {
  final String id;
  final String name;
  final String address;
  final String category;       // '음식점' | '카페' | '편의점' | '기타'
  final String benefit;        // 예: '학생증 제시 시 10% 할인'
  final double? lat;
  final double? lng;
  final String? phone;
  final String? imageUrl;
  final List<String> colleges;     // 해당 단과대 코드 목록 (빈 목록 = 전체)
  final List<String> departments;  // 해당 학과 코드 목록 (빈 목록 = 단과대 전체)
  final DateTime? updatedAt;
  final DateTime? expiresAt;       // 혜택 만료일 (null = 상시)
  final String? couponCode;        // 앱 쿠폰코드 (null = 없음)

  const PartnerRestaurant({
    required this.id,
    required this.name,
    required this.address,
    required this.category,
    required this.benefit,
    this.lat,
    this.lng,
    this.phone,
    this.imageUrl,
    this.colleges = const [],
    this.departments = const [],
    this.updatedAt,
    this.expiresAt,
    this.couponCode,
  });

  /// 만료 여부 — 만료일 당일 자정(다음날 00:00)까지 유효.
  bool get isExpired {
    if (expiresAt == null) return false;
    final endOfDay = DateTime(
        expiresAt!.year, expiresAt!.month, expiresAt!.day + 1);
    return DateTime.now().isAfter(endOfDay);
  }

  /// D-day 계산 (만료일까지 남은 일수, 이미 만료면 음수).
  int? get daysUntilExpiry {
    if (expiresAt == null) return null;
    final today = DateTime.now();
    final endOfDay = DateTime(
        expiresAt!.year, expiresAt!.month, expiresAt!.day + 1);
    final diff = endOfDay.difference(today);
    return (diff.inMicroseconds / Duration.microsecondsPerDay).floor();
  }

  factory PartnerRestaurant.fromJson(Map<String, dynamic> j) =>
      PartnerRestaurant(
        id: j['id'] as String,
        name: j['name'] as String,
        address: j['address'] as String? ?? '',
        category: j['category'] as String? ?? '기타',
        benefit: j['benefit'] as String? ?? '',
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        phone: j['phone'] as String?,
        imageUrl: j['imageUrl'] as String?,
        colleges: (j['colleges'] as List? ?? []).cast<String>(),
        departments: (j['departments'] as List? ?? []).cast<String>(),
        updatedAt: j['updatedAt'] != null
            ? DateTime.tryParse(j['updatedAt'] as String)
            : null,
        expiresAt: j['expiresAt'] != null
            ? DateTime.tryParse(j['expiresAt'] as String)
            : null,
        couponCode: j['couponCode'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'address': address,
        'category': category,
        'benefit': benefit,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (phone != null) 'phone': phone,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'colleges': colleges,
        'departments': departments,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
        if (couponCode != null) 'couponCode': couponCode,
      };

  /// 사용자의 단과대/학과 코드에 해당하는 제휴 식당인지 확인.
  bool matchesUser({required String? collegeCode, required String? deptCode}) {
    // colleges 또는 departments 중 하나라도 매칭되면 표시
    if (colleges.isEmpty && departments.isEmpty) return true; // 전체 공개
    if (collegeCode != null && colleges.contains(collegeCode)) return true;
    if (deptCode != null && departments.contains(deptCode)) return true;
    return false;
  }
}
