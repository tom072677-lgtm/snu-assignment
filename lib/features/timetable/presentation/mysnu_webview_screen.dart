import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../domain/timetable_models.dart';

/// mySNU(mo.snu.ac.kr) 로그인 후 시간표 자동 추출 WebView.
///
/// 로그인 감지 → 시간표 후보 URL 순차 직접 이동 → AJAX 인터셉터로 데이터 캡처
/// → Navigator.pop(context, List<ClassSession>)
class MySNUWebViewScreen extends StatefulWidget {
  const MySNUWebViewScreen({super.key});

  @override
  State<MySNUWebViewScreen> createState() => _MySNUWebViewScreenState();
}

class _MySNUWebViewScreenState extends State<MySNUWebViewScreen> {
  late final WebViewController _ctrl;
  bool _loading    = true;
  bool _loggedIn   = false;
  bool _captured   = false;
  bool _gaveUp     = false;
  Timer? _giveUpTimer;
  String _statusMsg = '';

  static const _startUrl = 'https://my.snu.ac.kr/login.jsp';

  /// 모든 페이지에 주입하는 XHR + fetch 인터셉터.
  /// JSON 응답 중 과목명 필드가 있는 것을 수업 데이터로 판단해 Sharap으로 전송.
  static const _interceptorJs = r'''
(function() {
  if (window.__sharapOk) return;
  window.__sharapOk = true;

  function tryExtract(text, url) {
    let j;
    try { j = JSON.parse(text); } catch(e) { return null; }
    const list = j && (j.list || j.data || j.result || j.lctList ||
                       j.courseList || j.subjectList ||
                       (Array.isArray(j) ? j : null));
    if (!list || list.length === 0) return null;
    const first = list[0];
    const hasName = first.sbjtNm || first.sbjcNm || first.courseNm || first.lctNm ||
                    first.className || first.subjectName || first.name;
    if (!hasName) return null;
    return list.map(item => ({
      sbjtNm:    item.sbjtNm    || item.sbjcNm    || item.courseNm  ||
                 item.lctNm    || item.className  || item.subjectName|| item.name || '',
      timTblInfo:item.timTblInfo|| item.timeInfo  || item.classTime || item.lctTm ||
                 item.timetable || '',
      roomNm:    item.roomNm   || item.clsRm     || item.room      ||
                 item.classroom|| item.lctRm     || '',
      dayCd:     item.dayCd   || item.day        || item.weekday   || '',
      bgHour:    String(item.bgHour  || item.startHour || item.sHour || ''),
      bgMin:     item.bgMin   || item.startMin   || item.sMin     || 0,
      edHour:    String(item.edHour  || item.endHour   || item.eHour || ''),
      edMin:     item.edMin   || item.endMin     || item.eMin     || 0,
    }));
  }

  function report(url, status, slim) {
    try { window.Sharap.postMessage(JSON.stringify({ t: 'intercept', url, status, slim })); }
    catch(e) {}
  }

  // fetch 인터셉터
  const origFetch = window.fetch.bind(window);
  window.fetch = async function(...args) {
    const resp = await origFetch(...args);
    try {
      const url = typeof args[0] === 'string' ? args[0] :
                  (args[0] instanceof Request ? args[0].url : '');
      resp.clone().text().then(text => {
        if (text.length < 10) return;
        const slim = tryExtract(text, url);
        if (slim) report(url, resp.status, slim);
      }).catch(() => {});
    } catch(e) {}
    return resp;
  };

  // XHR 인터셉터
  const OrigXHR = window.XMLHttpRequest;
  function PatchedXHR() {
    const xhr = new OrigXHR();
    let _url = '';
    const origOpen = xhr.open.bind(xhr);
    xhr.open = function(m, url) { _url = String(url); return origOpen.apply(this, arguments); };
    xhr.addEventListener('load', function() {
      try {
        if (!xhr.responseText || xhr.responseText.length < 10) return;
        const slim = tryExtract(xhr.responseText, _url);
        if (slim) report(_url, xhr.status, slim);
      } catch(e) {}
    });
    return xhr;
  }
  PatchedXHR.prototype = OrigXHR.prototype;
  window.XMLHttpRequest = PatchedXHR;
})();
''';

  @override
  void initState() {
    super.initState();
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('Sharap', onMessageReceived: _onMsg)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          setState(() => _loading = true);
          debugPrint('[mySNU] pageStarted: $url');
        },
        onPageFinished: _onPageDone,
        onWebResourceError: (e) =>
            debugPrint('[mySNU] resourceErr: ${e.description}'),
      ))
      ..loadRequest(Uri.parse(_startUrl));
  }

  @override
  void dispose() {
    _giveUpTimer?.cancel();
    super.dispose();
  }

  void _onPageDone(String url) {
    if (!mounted) return;
    setState(() => _loading = false);
    debugPrint('[mySNU] pageFinished: $url');

    if (_captured) return;

    // mo.snu.ac.kr 메인 진입 = 로그인 성공
    final isMoMain = url.contains('mo.snu.ac.kr') &&
        !url.contains('portalToSso') &&
        !url.contains('login') &&
        !url.contains('nsso.snu.ac.kr');

    if (isMoMain) {
      // 인터셉터 주입 (모든 페이지에서 AJAX 캡처)
      _ctrl.runJavaScript(_interceptorJs);

      if (!_loggedIn) {
        _loggedIn = true;
        setState(() => _statusMsg = '로그인 완료 — 수업 메뉴를 찾는 중...');
        // DOM에서 시간표 링크 자동 탐색 시도
        Future.delayed(const Duration(milliseconds: 800), _tryDomSearch);
        // 30초 안에 캡처 못 하면 무한 대기 방지를 위해 수동 안내 표시
        _giveUpTimer = Timer(const Duration(seconds: 30), () {
          if (!mounted || _captured) return;
          setState(() => _gaveUp = true);
        });
      }
    }
  }

  /// DOM에서 시간표 관련 링크를 찾아 클릭 시도.
  /// 실패 시 사용자에게 수동 안내만 표시하고 포털에 머뭄.
  Future<void> _tryDomSearch() async {
    if (_captured || !mounted) return;
    const js = r'''
(function() {
  var keywords = ['시간표', '수업', 'timetable', '학사일정', 'lct', 'schedule'];
  var links = Array.from(document.querySelectorAll('a'));
  var link = links.find(function(a) {
    var text = (a.textContent + a.href).toLowerCase();
    return keywords.some(function(k) { return text.includes(k); });
  });
  if (link) { link.click(); return 'clicked:' + link.href; }
  return 'notfound';
})();
''';
    try {
      final res = await _ctrl.runJavaScriptReturningResult(js);
      debugPrint('[mySNU] DOM 탐색 결과: $res');
      if (res.toString().startsWith('clicked:')) {
        setState(() => _statusMsg = '시간표 메뉴 클릭 — 데이터 수신 대기 중...');
      } else {
        setState(() =>
            _statusMsg = '수업 탭(≡ → 수업/시간표)을 직접 눌러 주세요.\n탭 이동 시 자동 캡처됩니다.');
      }
    } catch (_) {
      setState(() =>
          _statusMsg = '수업 탭(≡ → 수업/시간표)을 직접 눌러 주세요.\n탭 이동 시 자동 캡처됩니다.');
    }
  }

  void _onMsg(JavaScriptMessage msg) {
    if (!mounted || _captured) return;
    Map<String, dynamic> data;
    try {
      data = jsonDecode(msg.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    if (data['t'] != 'intercept') return;

    final url   = data['url']    as String? ?? '';
    final status = data['status'] as int?   ?? 0;
    final slim  = data['slim']   as List?   ?? [];

    // 개인정보 보호: URL/status/개수만 로그
    debugPrint('[mySNU] intercept $url → status=$status items=${slim.length}');
    if (slim.isEmpty) return;

    final sessions = _parseSlim(slim);
    if (sessions.isNotEmpty) {
      _captured = true;
      _giveUpTimer?.cancel();
      debugPrint('[mySNU] 성공! ${sessions.length}개 수업 추출');
      Navigator.pop(context, sessions);
    }
  }

  // ── 파싱 ──────────────────────────────────────────────────────────

  List<ClassSession> _parseSlim(List slim) {
    final sessions = <ClassSession>[];
    for (final raw in slim) {
      if (raw is! Map<String, dynamic>) continue;
      sessions.addAll(_itemToSessions(raw));
    }
    return sessions;
  }

  List<ClassSession> _itemToSessions(Map<String, dynamic> item) {
    final name     = (item['sbjtNm']     as String? ?? '').trim();
    if (name.isEmpty) return [];
    final location = (item['roomNm']     as String? ?? '').trim();
    final timeInfo = (item['timTblInfo'] as String? ?? '').trim();

    if (timeInfo.isNotEmpty) {
      debugPrint('[mySNU] item: name=$name time=$timeInfo loc=$location');
      final sessions = <ClassSession>[];
      for (final block in timeInfo.split(RegExp(r'[/|]'))) {
        final s = _parseTimeBlock(name, block.trim(), location);
        if (s != null) sessions.add(s);
      }
      return sessions;
    }

    final dayCdRaw = (item['dayCd'] as String? ?? '').trim();
    final bgHour   = (item['bgHour'] as String? ?? '').trim();
    final edHour   = (item['edHour'] as String? ?? '').trim();
    if (dayCdRaw.isNotEmpty && bgHour.isNotEmpty) {
      final dayEng = _dayCode(dayCdRaw);
      if (dayEng != null) {
        final sh = bgHour.padLeft(2, '0');
        final sm = (item['bgMin'] ?? 0).toString().padLeft(2, '0');
        final eh = edHour.padLeft(2, '0');
        final em = (item['edMin'] ?? 0).toString().padLeft(2, '0');
        return [ClassSession(
          uid: '${name}_${dayEng}_$sh$sm',
          summary: name,
          location: location,
          startTime: '$sh:$sm',
          endTime:   '$eh:$em',
          weekdays:  [dayEng],
        )];
      }
    }
    return [];
  }

  // ── 시간 문자열 파싱 ─────────────────────────────────────────────

  ClassSession? _parseTimeBlock(String name, String block, String location) {
    if (block.isEmpty) return null;

    // HH:mm 형식: "월 09:00-10:50", "화,목(13:30-15:00)"
    final hm = RegExp(
      r'([월화수목금토일,]+)\s*[\(\[]?\s*(\d{1,2}):(\d{2})\s*[-~]\s*(\d{1,2}):(\d{2})',
    ).firstMatch(block);
    if (hm != null) {
      final days = _parseKorDays(hm.group(1)!);
      if (days.isNotEmpty) {
        return ClassSession(
          uid:       '${name}_${block.hashCode}',
          summary:   name,
          location:  location,
          startTime: '${hm.group(2)!.padLeft(2,'0')}:${hm.group(3)}',
          endTime:   '${hm.group(4)!.padLeft(2,'0')}:${hm.group(5)}',
          weekdays:  days,
        );
      }
    }

    // 교시 형식: "월1-3", "월(1-3)", "월수(1-3)", "월,수(1-3)"
    // [+] 로 여러 요일 문자를 한 번에 캡처 → 월수목(1-3) 같은 다중 요일 처리
    final ps = RegExp(r'([월화수목금토일,]+)\(?(\d+)[-~](\d+)\)?').allMatches(block);
    if (ps.isNotEmpty) {
      final days = <String>[];
      String? st, et;
      for (final m in ps) {
        // 매치된 요일 문자들을 개별 처리
        for (final c in m.group(1)!.split('')) {
          final d = _korDayMap[c];
          if (d != null && !days.contains(d)) days.add(d);
        }
        if (st == null) {
          final sp = int.tryParse(m.group(2)!) ?? 1;
          final ep = int.tryParse(m.group(3)!) ?? sp;
          st = _periodToTime(sp);
          et = _periodToTime(ep, end: true);
        }
      }
      if (days.isNotEmpty && st != null) {
        return ClassSession(
          uid:       '${name}_${block.hashCode}',
          summary:   name,
          location:  location,
          startTime: st,
          endTime:   et!,
          weekdays:  days,
        );
      }
    }
    return null;
  }

  static const _korDayMap = {
    '월':'MO','화':'TU','수':'WE','목':'TH','금':'FR','토':'SA','일':'SU',
  };

  List<String> _parseKorDays(String str) => str
      .split(RegExp(r'[,\s]+'))
      .expand((s) => s.split(''))
      .map((c) => _korDayMap[c])
      .whereType<String>()
      .toSet()
      .toList();

  String? _dayCode(String code) => const {
    '1':'MO','2':'TU','3':'WE','4':'TH','5':'FR','6':'SA','7':'SU',
    '월':'MO','화':'TU','수':'WE','목':'TH','금':'FR','토':'SA','일':'SU',
    'MO':'MO','TU':'TU','WE':'WE','TH':'TH','FR':'FR','SA':'SA','SU':'SU',
  }[code];

  // SNU 교시 기준: 1교시 = 09:00-09:50, 2교시 = 10:00-10:50 ...
  // hour = 8 + period (period 1 → 09:00)
  String _periodToTime(int period, {bool end = false}) =>
      '${(8 + period).toString().padLeft(2,'0')}:${end ? '50' : '00'}';

  // ── UI ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('마이스누 로그인'),
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: Stack(children: [
        WebViewWidget(controller: _ctrl),
        // 자동 캡처 실패 시: 화면 하단에 눈에 띄는 안내 카드 + 뒤로 가기 버튼
        if (_gaveUp)
          Positioned(
            bottom: 12, left: 12, right: 12,
            child: Material(
              color: Colors.black.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '시간표를 자동으로 찾지 못했어요. 수업/시간표 탭을 직접 눌러보거나, '
                      '뒤로 가서 ICS 가져오기 또는 직접 추가를 이용해 주세요.',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => setState(() => _gaveUp = false),
                          child: const Text('닫기'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('뒤로 가기'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          )
        // 상태 메시지: 좌하단 소형 chip — 화면을 덮지 않음
        else if (_statusMsg.isNotEmpty)
          Positioned(
            bottom: 12, left: 12,
            child: Material(
              color: Colors.black.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  _statusMsg,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
