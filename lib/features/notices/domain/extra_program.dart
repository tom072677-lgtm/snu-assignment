class ExtraProgram {
  const ExtraProgram({
    required this.seq,
    required this.name,
    required this.category,
    required this.status,
    this.aplFrom,
    this.aplTo,
    this.eduFrom,
    this.eduTo,
    this.organizer,
    this.mode,
    this.dday,
  });

  final String seq;
  final String name;
  final String category;
  final String status;
  final DateTime? aplFrom;
  final DateTime? aplTo;
  final DateTime? eduFrom;
  final DateTime? eduTo;
  final String? organizer;
  final String? mode;
  final int? dday;

  String get detailUrl =>
      'https://extra.snu.ac.kr/ptfol/pgm/view.do?pgmSeq=$seq';

  static DateTime? _parseApiDate(String? s) {
    if (s == null || s.isEmpty) return null;
    // "2026.06.01" or "2026.06.01 00:00" → "2026-06-01"
    return DateTime.tryParse(s.replaceAll('.', '-').split(' ')[0]);
  }

  factory ExtraProgram.fromJson(Map<String, dynamic> j) => ExtraProgram(
        seq: j['pgmSeq']?.toString() ?? '',
        name: j['pgmNm'] as String? ?? '',
        category: j['planBigNm'] as String? ?? '기타',
        status: j['applyChk'] as String? ?? '',
        aplFrom: _parseApiDate(j['aplFrDd'] as String?),
        aplTo: _parseApiDate(j['aplToDd'] as String?),
        eduFrom: _parseApiDate(j['eduFrDd'] as String?),
        eduTo: _parseApiDate(j['eduToDd'] as String?),
        organizer: j['operOrgzNm'] as String?,
        mode: j['operClassNm'] as String?,
        dday: int.tryParse(j['dday']?.toString() ?? ''),
      );

  Map<String, dynamic> toJson() => {
        'seq': seq,
        'name': name,
        'category': category,
        'status': status,
        if (aplFrom != null) 'aplFrom': aplFrom!.toIso8601String(),
        if (aplTo != null) 'aplTo': aplTo!.toIso8601String(),
        if (eduFrom != null) 'eduFrom': eduFrom!.toIso8601String(),
        if (eduTo != null) 'eduTo': eduTo!.toIso8601String(),
        if (organizer != null) 'organizer': organizer,
        if (mode != null) 'mode': mode,
        if (dday != null) 'dday': dday,
      };

  static ExtraProgram fromCacheJson(Map<String, dynamic> j) => ExtraProgram(
        seq: j['seq'] as String,
        name: j['name'] as String,
        category: j['category'] as String,
        status: j['status'] as String,
        aplFrom: j['aplFrom'] != null
            ? DateTime.tryParse(j['aplFrom'] as String)
            : null,
        aplTo: j['aplTo'] != null
            ? DateTime.tryParse(j['aplTo'] as String)
            : null,
        eduFrom: j['eduFrom'] != null
            ? DateTime.tryParse(j['eduFrom'] as String)
            : null,
        eduTo: j['eduTo'] != null
            ? DateTime.tryParse(j['eduTo'] as String)
            : null,
        organizer: j['organizer'] as String?,
        mode: j['mode'] as String?,
        dday: j['dday'] as int?,
      );
}

/// 현재 신청 중이거나 5일 이내 시작 여부 (날짜 기준 순수 함수).
bool shouldShowProgram(ExtraProgram p, DateTime now) {
  if (p.aplFrom == null || p.aplTo == null) return false;
  final today = DateTime(now.year, now.month, now.day);
  final from =
      DateTime(p.aplFrom!.year, p.aplFrom!.month, p.aplFrom!.day);
  final to = DateTime(p.aplTo!.year, p.aplTo!.month, p.aplTo!.day);
  // 현재 신청중: from <= today <= to
  if (!today.isBefore(from) && !today.isAfter(to)) return true;
  // 5일 이내 시작: today < from && from - today <= 5일
  if (today.isBefore(from) && from.difference(today).inDays <= 5) return true;
  return false;
}
