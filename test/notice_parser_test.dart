import 'package:flutter_test/flutter_test.dart';
import 'package:sharap/features/notices/data/notice_repository.dart';
import 'package:sharap/features/notices/domain/department_notice_source.dart';
import 'package:sharap/features/notices/domain/extra_program.dart';
import 'package:sharap/features/notices/domain/notice.dart';

void main() {
  // ── parseFeedDate ──────────────────────────────────────────────────────────

  group('NoticeRepository.parseFeedDate', () {
    test('parses RFC822 with weekday and timezone', () {
      expect(
        NoticeRepository.parseFeedDate('Fri, 29 May 2026 13:51:50 +0000'),
        DateTime(2026, 5, 29, 13, 51, 50),
      );
    });

    test('parses RFC822 without weekday', () {
      expect(
        NoticeRepository.parseFeedDate('29 May 2026 09:00:00 +0900'),
        DateTime(2026, 5, 29, 9, 0, 0),
      );
    });

    test('parses ISO8601 date-only (dc:date)', () {
      final d = NoticeRepository.parseFeedDate('2026-05-29');
      expect(d, isNotNull);
      expect(d!.year, 2026);
      expect(d.month, 5);
      expect(d.day, 29);
    });

    test('returns null for empty/null/garbage', () {
      expect(NoticeRepository.parseFeedDate(null), isNull);
      expect(NoticeRepository.parseFeedDate(''), isNull);
      expect(NoticeRepository.parseFeedDate('신청중'), isNull);
    });
  });

  // ── parseFeed (RSS/Atom) ─────────────────────────────────────────────────────

  group('NoticeRepository.parseFeed', () {
    test('parses RSS items, dedupes, extracts category, skips empty title', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/"><channel>
  <item><title>[장학] 첫 공지</title><link>https://x.snu.ac.kr/123/</link><pubDate>Fri, 29 May 2026 13:51:50 +0000</pubDate></item>
  <item><title>중복(스킴·슬래시 다름)</title><link>http://x.snu.ac.kr/123</link><pubDate>Thu, 28 May 2026 10:00:00 +0000</pubDate></item>
  <item><title>   </title><link>https://x.snu.ac.kr/999/</link></item>
  <item><title>날짜없음</title><link>https://x.snu.ac.kr/888/</link></item>
</channel></rss>''';
      final list = NoticeRepository.parseFeed(xml, deptCode: 'test');
      // 중복 link 제거 + 빈 제목 스킵 → 2건
      expect(list, hasLength(2));
      // 날짜 있는 항목이 먼저
      expect(list.first.title, '[장학] 첫 공지');
      expect(list.first.category, '장학');
      expect(list.first.date, isNotNull);
      expect(list.first.id, startsWith('dept_test_'));
      // 날짜 없는 항목은 뒤로
      expect(list.last.title, '날짜없음');
      expect(list.last.date, isNull);
    });

    test('parses Atom feed with link href', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry><title>Atom 공지</title><link href="https://a.snu.ac.kr/1"/><updated>2026-05-29T10:00:00Z</updated></entry>
</feed>''';
      final list = NoticeRepository.parseFeed(xml, deptCode: 'test');
      expect(list, hasLength(1));
      expect(list.first.title, 'Atom 공지');
      expect(list.first.url, 'https://a.snu.ac.kr/1');
      expect(list.first.date, isNotNull);
    });

    test('returns empty list for valid feed with no items', () {
      const xml = '<?xml version="1.0"?><rss version="2.0"><channel></channel></rss>';
      expect(NoticeRepository.parseFeed(xml, deptCode: 'test'), isEmpty);
    });

    test('throws on malformed XML', () {
      expect(
        () => NoticeRepository.parseFeed('<not xml', deptCode: 'test'),
        throwsA(anything),
      );
    });

    test('respects item limit', () {
      final buf = StringBuffer('<?xml version="1.0"?><rss version="2.0"><channel>');
      for (var i = 0; i < 10; i++) {
        buf.write('<item><title>n$i</title><link>https://x.snu.ac.kr/$i</link></item>');
      }
      buf.write('</channel></rss>');
      final list =
          NoticeRepository.parseFeed(buf.toString(), deptCode: 'test', limit: 3);
      expect(list, hasLength(3));
    });
  });

  // ── noticeSourceFor ──────────────────────────────────────────────────────────

  group('noticeSourceFor', () {
    test('returns RSS source for a registered department', () {
      final s = noticeSourceFor('physical_edu');
      expect(s, isNotNull);
      expect(s!.rssFeedUrl, isNotNull);
      expect(s.homepageUrl, isNotEmpty);
    });

    test('returns null for unregistered department', () {
      expect(noticeSourceFor('economics'), isNull);
    });

    test('returns null for null deptCode', () {
      expect(noticeSourceFor(null), isNull);
    });
  });

  // ── parseHtmlDate ──────────────────────────────────────────────────────────

  group('NoticeRepository.parseHtmlDate', () {
    test('parses standard dot-separated date with trailing dot', () {
      expect(
        NoticeRepository.parseHtmlDate('2026.06.01.'),
        DateTime(2026, 6, 1),
      );
    });

    test('parses date without trailing dot', () {
      expect(
        NoticeRepository.parseHtmlDate('2026.12.31'),
        DateTime(2026, 12, 31),
      );
    });

    test('ignores time portion after a space', () {
      expect(
        NoticeRepository.parseHtmlDate('2026.06.15. 09:00'),
        DateTime(2026, 6, 15),
      );
    });

    test('returns null for empty string', () {
      expect(NoticeRepository.parseHtmlDate(''), isNull);
    });

    test('returns null for unparseable string', () {
      expect(NoticeRepository.parseHtmlDate('신청중'), isNull);
    });
  });

  // ── parseDateRange ─────────────────────────────────────────────────────────

  group('NoticeRepository.parseDateRange', () {
    test('parses a valid range separated by ~', () {
      final range = NoticeRepository.parseDateRange('2026.06.01.~2026.06.14.');
      expect(range, isNotNull);
      expect(range!.$1, DateTime(2026, 6, 1));
      expect(range.$2, DateTime(2026, 6, 14));
    });

    test('returns null for null input', () {
      expect(NoticeRepository.parseDateRange(null), isNull);
    });

    test('returns null for empty string', () {
      expect(NoticeRepository.parseDateRange(''), isNull);
    });

    test('returns null when ~ separator is missing', () {
      expect(NoticeRepository.parseDateRange('2026.06.01.'), isNull);
    });

    test('returns null when one date part is invalid', () {
      expect(
        NoticeRepository.parseDateRange('2026.06.01.~없음'),
        isNull,
      );
    });
  });

  // ── parseExtraHtml ─────────────────────────────────────────────────────────

  group('NoticeRepository.parseExtraHtml', () {
    test('returns empty list for empty HTML', () {
      expect(NoticeRepository.parseExtraHtml(''), isEmpty);
    });

    test('returns empty list when no lica_wrap items found', () {
      const html = '<html><body><div class="other">내용</div></body></html>';
      expect(NoticeRepository.parseExtraHtml(html), isEmpty);
    });

    test('parses a single program item correctly', () {
      const html = '''
<html><body>
<div class="lica_wrap">
  <ul>
    <li>
      <div class="lica_gp">
        <a class="tit">리더십 프로그램</a>
        <span data-params='{"pgmSeq":"12345"}'></span>
        <span class="btn01"><span>모집중</span></span>
        <ul class="major_type">
          <li>학생처</li>
          <li>리더십</li>
        </ul>
        <dl class="apl_date"><dd>2026.06.01.~2026.06.14.</dd></dl>
        <dl class="edu_date"><dd>2026.06.20.~2026.06.25.</dd></dl>
        <dl class="class_cd"><dd>온라인</dd></dl>
        <span class="dday">D-5</span>
      </div>
    </li>
  </ul>
</div>
</body></html>
''';
      final programs = NoticeRepository.parseExtraHtml(html);
      expect(programs, hasLength(1));

      final p = programs.first;
      expect(p.name, '리더십 프로그램');
      expect(p.seq, '12345');
      expect(p.status, '모집중');
      expect(p.organizer, '학생처');
      expect(p.category, '리더십');
      expect(p.aplFrom, DateTime(2026, 6, 1));
      expect(p.aplTo, DateTime(2026, 6, 14));
      expect(p.eduFrom, DateTime(2026, 6, 20));
      expect(p.eduTo, DateTime(2026, 6, 25));
      expect(p.mode, '온라인');
      expect(p.dday, 5);
      // 자격 필드 기본값 (HTML에 없으면 빈값)
      expect(p.targetOrg, '');
      expect(p.targetStatus, isEmpty);
    });

    test('parses targetOrg and single targetStatus', () {
      const html = '''
<div class="lica_wrap"><ul><li>
  <div class="lica_gp">
    <a class="tit">단과대 한정 프로그램</a>
    <dl class="apl_date"><dd>2026.06.01.~2026.06.14.</dd></dl>
    <dl class="org_name"><dt>신청대상</dt><dd>농업생명과학대학</dd></dl>
    <dl class="user_cd"><dt>신청신분</dt><dd><div class="cdDiv">학사</div></dd></dl>
  </div>
</li></ul></div>
''';
      final programs = NoticeRepository.parseExtraHtml(html);
      expect(programs, hasLength(1));
      expect(programs.first.targetOrg, '농업생명과학대학');
      expect(programs.first.targetStatus, ['학사']);
    });

    test('parses multiple targetStatus (cdDiv) values', () {
      const html = '''
<div class="lica_wrap"><ul><li>
  <div class="lica_gp">
    <a class="tit">전체 학적 프로그램</a>
    <dl class="apl_date"><dd>2026.06.01.~2026.06.14.</dd></dl>
    <dl class="org_name"><dt>신청대상</dt><dd>서울대학교</dd></dl>
    <dl class="user_cd"><dt>신청신분</dt><dd>
      <div class="cdDiv">학사</div>
      <div class="cdDiv">석사</div>
      <div class="cdDiv">박사</div>
    </dd></dl>
  </div>
</li></ul></div>
''';
      final programs = NoticeRepository.parseExtraHtml(html);
      expect(programs, hasLength(1));
      expect(programs.first.targetOrg, '서울대학교');
      expect(programs.first.targetStatus, ['학사', '석사', '박사']);
    });

    test('skips items without lica_gp container', () {
      const html = '''
<div class="lica_wrap">
  <ul>
    <li><a class="tit">제목없음</a></li>
  </ul>
</div>
''';
      expect(NoticeRepository.parseExtraHtml(html), isEmpty);
    });

    test('skips items with empty title', () {
      const html = '''
<div class="lica_wrap">
  <ul>
    <li>
      <div class="lica_gp">
        <a class="tit">   </a>
      </div>
    </li>
  </ul>
</div>
''';
      expect(NoticeRepository.parseExtraHtml(html), isEmpty);
    });

    test('falls back to organizer as category when only one major_type item', () {
      const html = '''
<div class="lica_wrap">
  <ul>
    <li>
      <div class="lica_gp">
        <a class="tit">단일 카테고리 프로그램</a>
        <ul class="major_type"><li>학생처</li></ul>
        <dl class="apl_date"><dd>2026.06.01.~2026.06.10.</dd></dl>
      </div>
    </li>
  </ul>
</div>
''';
      final programs = NoticeRepository.parseExtraHtml(html);
      expect(programs, hasLength(1));
      expect(programs.first.organizer, '학생처');
      expect(programs.first.category, '학생처');
    });
  });

  // ── shouldShowProgram ──────────────────────────────────────────────────────

  group('shouldShowProgram', () {
    ExtraProgram makeProgram({
      required String status,
      DateTime? aplFrom,
      DateTime? aplTo,
    }) =>
        ExtraProgram(
          seq: '1',
          name: '테스트',
          category: '기타',
          status: status,
          aplFrom: aplFrom,
          aplTo: aplTo,
        );

    final today = DateTime(2026, 6, 1);

    test('excludes programs with status "마감"', () {
      final p = makeProgram(
        status: '마감',
        aplFrom: today,
        aplTo: today.add(const Duration(days: 7)),
      );
      expect(shouldShowProgram(p, today), isFalse);
    });

    test('excludes programs with null aplFrom', () {
      final p = makeProgram(status: '모집중', aplFrom: null, aplTo: today);
      expect(shouldShowProgram(p, today), isFalse);
    });

    test('includes program currently open for application', () {
      final p = makeProgram(
        status: '모집중',
        aplFrom: today.subtract(const Duration(days: 2)),
        aplTo: today.add(const Duration(days: 5)),
      );
      expect(shouldShowProgram(p, today), isTrue);
    });

    test('includes program starting within 5 days', () {
      final p = makeProgram(
        status: '모집대기',
        aplFrom: today.add(const Duration(days: 5)),
        aplTo: today.add(const Duration(days: 10)),
      );
      expect(shouldShowProgram(p, today), isTrue);
    });

    test('excludes program starting 6 or more days later', () {
      final p = makeProgram(
        status: '모집대기',
        aplFrom: today.add(const Duration(days: 6)),
        aplTo: today.add(const Duration(days: 12)),
      );
      expect(shouldShowProgram(p, today), isFalse);
    });

    test('excludes already closed program (aplTo in the past)', () {
      final p = makeProgram(
        status: '마감임박',
        aplFrom: today.subtract(const Duration(days: 10)),
        aplTo: today.subtract(const Duration(days: 1)),
      );
      expect(shouldShowProgram(p, today), isFalse);
    });
  });

  // ── NoticeRepository.extractDeadline ─────────────────────────────────────

  group('NoticeRepository.extractDeadline', () {
    final now = DateTime(2026, 6, 1);

    test('extracts ~YYYY.MM.DD', () {
      expect(
        NoticeRepository.extractDeadline('신청기간 (~2026.06.14.)', now),
        DateTime(2026, 6, 14),
      );
    });

    test('extracts ~MM.DD (no year, uses now.year)', () {
      expect(
        NoticeRepository.extractDeadline('프로그램 신청 (~6.20)', now),
        DateTime(2026, 6, 20),
      );
    });

    test('extracts end date from range MM.DD~MM.DD', () {
      // "~6.14" is matched as the end of the range
      expect(
        NoticeRepository.extractDeadline('신청기간: 5.20~6.14', now),
        DateTime(2026, 6, 14),
      );
    });

    test('extracts MM월 DD일까지', () {
      expect(
        NoticeRepository.extractDeadline('6월 30일까지 신청 가능', now),
        DateTime(2026, 6, 30),
      );
    });

    test('extracts MM.DD까지', () {
      expect(
        NoticeRepository.extractDeadline('마감: 6.25까지', now),
        DateTime(2026, 6, 25),
      );
    });

    test('returns null for title with no date pattern', () {
      expect(
        NoticeRepository.extractDeadline('2026학년도 교육과정 안내', now),
        isNull,
      );
    });

    test('returns null for invalid month/day', () {
      expect(
        NoticeRepository.extractDeadline('신청 (~13.40)', now),
        isNull,
      );
    });
  });

  // ── shouldShowSportsNotice ────────────────────────────────────────────────

  group('shouldShowSportsNotice', () {
    final now = DateTime(2026, 6, 1);

    Notice makeNotice({required String title, DateTime? date}) => Notice(
          id: 'test',
          title: title,
          url: 'https://example.com',
          source: NoticeSource.sports,
          date: date,
        );

    test('hides notice with past deadline in title', () {
      final n = makeNotice(title: '행사 신청 (~5.31)');
      expect(shouldShowSportsNotice(n, now), isFalse);
    });

    test('shows notice with future deadline in title', () {
      final n = makeNotice(title: '행사 신청 (~6.30)');
      expect(shouldShowSportsNotice(n, now), isTrue);
    });

    test('shows notice with deadline exactly today', () {
      final n = makeNotice(title: '오늘 마감 (~6.1)');
      expect(shouldShowSportsNotice(n, now), isTrue);
    });

    test('hides old notice without date pattern (> 90 days)', () {
      final n = makeNotice(
        title: '일반 안내문',
        date: DateTime(2026, 1, 1), // 151 days ago
      );
      expect(shouldShowSportsNotice(n, now), isFalse);
    });

    test('shows recent notice without date pattern (<= 90 days)', () {
      final n = makeNotice(
        title: '일반 안내문',
        date: DateTime(2026, 4, 1), // 61 days ago
      );
      expect(shouldShowSportsNotice(n, now), isTrue);
    });

    test('shows notice with no date info at all', () {
      final n = makeNotice(title: '날짜 없는 공지');
      expect(shouldShowSportsNotice(n, now), isTrue);
    });

    test('deadline in title takes priority over posting date', () {
      // Posted recently but deadline passed
      final n = makeNotice(
        title: '마감된 신청 (~5.15)',
        date: DateTime(2026, 5, 20),
      );
      expect(shouldShowSportsNotice(n, now), isFalse);
    });
  });

  // ── ExtraProgram.matchesStatus ────────────────────────────────────────────

  group('ExtraProgram.matchesStatus', () {
    ExtraProgram make(List<String> targetStatus) => ExtraProgram(
          seq: '1',
          name: 'test',
          category: '기타',
          status: '모집중',
          targetStatus: targetStatus,
        );

    test('empty targetStatus matches anyone (제한없음)', () {
      expect(make([]).matchesStatus(null), isTrue);
      expect(make([]).matchesStatus('학사'), isTrue);
      expect(make([]).matchesStatus('박사'), isTrue);
    });

    test('null userStatus is not filtered out', () {
      expect(make(['학사', '석사']).matchesStatus(null), isTrue);
    });

    test('empty userStatus is not filtered out', () {
      expect(make(['학사']).matchesStatus(''), isTrue);
    });

    test('matching status returns true', () {
      expect(make(['학사', '석사']).matchesStatus('학사'), isTrue);
      expect(make(['학사', '석사']).matchesStatus('석사'), isTrue);
    });

    test('non-matching status returns false', () {
      expect(make(['학사', '석사']).matchesStatus('박사'), isFalse);
    });

    test('single targetStatus matched exactly', () {
      expect(make(['박사']).matchesStatus('박사'), isTrue);
      expect(make(['박사']).matchesStatus('학사'), isFalse);
    });
  });

  // ── ExtraProgram.matchesCollege ────────────────────────────────────────────

  group('ExtraProgram.matchesCollege', () {
    ExtraProgram make(String targetOrg) => ExtraProgram(
          seq: '1',
          name: 'test',
          category: '기타',
          status: '모집중',
          targetOrg: targetOrg,
        );

    test('empty targetOrg matches everyone', () {
      expect(make('').matchesCollege(null), isTrue);
      expect(make('').matchesCollege('공과대학'), isTrue);
    });

    test('"서울대학교" matches everyone', () {
      expect(make('서울대학교').matchesCollege(null), isTrue);
      expect(make('서울대학교').matchesCollege('농업생명과학대학'), isTrue);
    });

    test('"서울대학교" variant with extra text still matches everyone', () {
      expect(make('서울대학교 전체').matchesCollege(null), isTrue);
      expect(make('서울대학교(전체)').matchesCollege('공과대학'), isTrue);
    });

    test('specific college does NOT match when collegeName is null', () {
      expect(make('농업생명과학대학').matchesCollege(null), isFalse);
    });

    test('specific college does NOT match when collegeName is empty', () {
      expect(make('농업생명과학대학').matchesCollege(''), isFalse);
    });

    test('specific college matches correct college name', () {
      expect(make('농업생명과학대학').matchesCollege('농업생명과학대학'), isTrue);
    });

    test('specific college does NOT match different college', () {
      expect(make('농업생명과학대학').matchesCollege('공과대학'), isFalse);
    });

    test('whitespace in targetOrg is normalized before matching', () {
      expect(make('농업생명과학대학').matchesCollege('농업생명과학대학'), isTrue);
    });
  });
}
