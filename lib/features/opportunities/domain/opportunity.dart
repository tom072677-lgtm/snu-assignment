enum OppCategory { contest, activity, scholarship, education, intern }

OppCategory categoryFromString(String s) {
  switch (s) {
    case 'contest':
      return OppCategory.contest;
    case 'activity':
      return OppCategory.activity;
    case 'scholarship':
      return OppCategory.scholarship;
    case 'education':
      return OppCategory.education;
    case 'intern':
      return OppCategory.intern;
    default:
      return OppCategory.contest; // 안전한 폴백
  }
}

String categoryLabel(OppCategory c) {
  switch (c) {
    case OppCategory.contest:
      return '공모전';
    case OppCategory.activity:
      return '대외활동';
    case OppCategory.scholarship:
      return '장학금';
    case OppCategory.education:
      return '교육';
    case OppCategory.intern:
      return '인턴';
  }
}

class Opportunity {
  final String id;
  final OppCategory category;
  final String title;
  final String organization;
  final String url;
  final String source;
  final DateTime? deadline;
  final DateTime? startDate;
  final String? region;
  final List<String> tags;
  final String? summary;
  final Map<String, String> extra;

  const Opportunity({
    required this.id,
    required this.category,
    required this.title,
    required this.organization,
    required this.url,
    required this.source,
    this.deadline,
    this.startDate,
    this.region,
    this.tags = const [],
    this.summary,
    this.extra = const {},
  });

  static DateTime? _date(dynamic v) =>
      (v == null || v == '') ? null : DateTime.tryParse(v as String);

  factory Opportunity.fromJson(Map<String, dynamic> j) => Opportunity(
        id: j['id'] as String,
        category: categoryFromString(j['category'] as String? ?? ''),
        title: j['title'] as String,
        organization: j['organization'] as String? ?? '',
        url: j['url'] as String? ?? '',
        source: j['source'] as String? ?? '',
        deadline: _date(j['deadline']),
        startDate: _date(j['startDate']),
        region: j['region'] as String?,
        tags: (j['tags'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        summary: j['summary'] as String?,
        extra: (j['extra'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
            const {},
      );
}
