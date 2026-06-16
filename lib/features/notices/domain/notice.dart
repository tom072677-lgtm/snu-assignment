/// 공지/기회 항목 출처
/// - department: 학과 공지 (RSS 피드 또는 서버 HTML 게시판)
/// - sports: (레거시) 체육교육과 HTML 스크래퍼 — department로 대체됨
/// - extra: SNU 비교과 프로그램
enum NoticeSource { sports, extra, department }

/// 공지 또는 비교과 프로그램 항목
class Notice {
  const Notice({
    required this.id,
    required this.title,
    required this.url,
    required this.source,
    this.category,
    this.status,
    this.dDay,
    this.date,
    this.description,
    this.imageUrl,
    this.body,
  });

  final String id;
  final String title;
  final String url;            // 원본 페이지 URL
  final NoticeSource source;   // sports | extra
  final String? category;      // 체육교육과: 학생/학적 등
  final String? status;        // 비교과: 모집중/마감임박/마감
  final int? dDay;             // 비교과 D-day 숫자 (양수: 남은 일수)
  final DateTime? date;        // 체육교육과 게시일
  final String? description;   // 비교과 설명 텍스트
  final String? imageUrl;      // 비교과 썸네일 URL
  final String? body;          // 학과 공지 본문(RSS content:encoded → 정제 텍스트)

  bool get hasBody => body != null && body!.trim().isNotEmpty;

  bool get isExtra => source == NoticeSource.extra;
  bool get isSports => source == NoticeSource.sports;

  /// 비교과: 모집 중인 항목인지 (status가 null이면 모름 → true로 처리)
  bool get isActive {
    if (status == null) return true;
    return !status!.contains('마감') || status!.contains('마감임박');
  }
}
