import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../data/favorites_repository.dart';
import '../data/map_repository.dart';
import '../domain/favorite_place.dart';
import 'widgets/place_search_sheet.dart';

const _kRecentKey = 'recent_searches';
const _kMaxRecent = 10;

/// 네이버 지도 스타일 목적지 검색 화면
/// pop() 시 PlaceResult 반환
class RouteSearchScreen extends ConsumerStatefulWidget {
  final String initialQuery;
  final bool autoStartMic;
  const RouteSearchScreen({
    super.key,
    this.initialQuery = '',
    this.autoStartMic = false,
  });

  @override
  ConsumerState<RouteSearchScreen> createState() => _RouteSearchScreenState();
}

class _RouteSearchScreenState extends ConsumerState<RouteSearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _stt = SpeechToText();

  List<PlaceResult> _suggestions = [];
  List<PlaceResult> _recents = [];
  bool _loading = false;
  bool _sttReady = false;
  bool _listening = false;

  Timer? _debounce;
  String _activeQuery = '';

  @override
  void initState() {
    super.initState();
    _loadRecents();
    if (widget.initialQuery.isNotEmpty) {
      _ctrl.text = widget.initialQuery;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _focus.requestFocus();
      await _initStt();
      if (widget.initialQuery.isNotEmpty) {
        _search(widget.initialQuery);
      } else if (widget.autoStartMic) {
        _toggleListening();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _stt.stop();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ── 최근 검색 ──────────────────────────────────

  Future<void> _loadRecents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_kRecentKey) ?? [];
      final list = <PlaceResult>[];
      for (final s in raw) {
        try {
          final m = jsonDecode(s) as Map<String, dynamic>;
          list.add(PlaceResult(
            name: m['name'] as String,
            address: m['address'] as String? ?? '',
            lat: (m['lat'] as num).toDouble(),
            lng: (m['lng'] as num).toDouble(),
            category: m['category'] as String? ?? '',
          ));
        } catch (e) {
          debugPrint('[Recent] 항목 파싱 실패: $e');
        }
      }
      if (mounted) setState(() => _recents = list);
    } catch (e) {
      debugPrint('[Recent] _loadRecents 실패: $e');
    }
  }

  Future<void> _saveRecent(PlaceResult p) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entry = jsonEncode({
        'name': p.name,
        'address': p.address,
        'lat': p.lat,
        'lng': p.lng,
        'category': p.category,
      });
      final raw = prefs.getStringList(_kRecentKey) ?? [];
      // 같은 위치(lat+lng) 중복 제거 후 맨 앞에 추가
      raw.removeWhere((s) {
        try {
          final m = jsonDecode(s) as Map<String, dynamic>;
          return (m['lat'] as num).toDouble() == p.lat &&
              (m['lng'] as num).toDouble() == p.lng;
        } catch (_) {
          return false;
        }
      });
      raw.insert(0, entry);
      await prefs.setStringList(_kRecentKey, raw.take(_kMaxRecent).toList());
      debugPrint('[Recent] 저장 완료: ${p.name}');
    } catch (e) {
      debugPrint('[Recent] _saveRecent 실패: $e');
    }
  }

  Future<void> _removeRecent(int index) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_kRecentKey) ?? [];
      if (index < raw.length) {
        raw.removeAt(index);
        await prefs.setStringList(_kRecentKey, raw);
        await _loadRecents();
      }
    } catch (_) {}
  }

  Future<void> _clearAllRecents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kRecentKey);
      if (mounted) setState(() => _recents = []);
    } catch (_) {}
  }

  // ── 검색 ───────────────────────────────────────

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _loading = false;
        _activeQuery = '';
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    final trimmed = q.trim();
    if (trimmed.isEmpty) return;
    _activeQuery = trimmed;
    try {
      const snuLat = 37.4607;
      const snuLng = 126.9526;
      final results =
          await ref.read(mapRepositoryProvider).searchPlace(trimmed, snuLat, snuLng);
      // stale response 방지: 이미 다른 쿼리로 넘어갔으면 무시
      if (!mounted || _activeQuery != trimmed) return;
      setState(() => _suggestions = results.take(8).toList());
    } catch (e) {
      debugPrint('[route_search] search error: $e');
      if (!mounted || _activeQuery != trimmed) return;
      setState(() => _suggestions = []);
    } finally {
      if (mounted && _activeQuery == trimmed) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _selectPlace(PlaceResult p) async {
    await _saveRecent(p);
    if (mounted) Navigator.pop(context, p);
  }

  // ── STT ────────────────────────────────────────

  Future<void> _initStt() async {
    final available = await _stt.initialize(
      onError: (e) {
        debugPrint('[STT] 에러: ${e.errorMsg} permanent=${e.permanent}');
        if (mounted) {
          setState(() => _listening = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('음성 인식 오류: ${e.errorMsg}')),
          );
        }
      },
    );
    debugPrint('[STT] initialize: $available');
    if (mounted) setState(() => _sttReady = available);
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      return;
    }
    if (!_sttReady) {
      // 권한 거부와 엔진 부재를 구분해 안내한다.
      final status = await Permission.microphone.status;
      if (!mounted) return;
      if (status.isPermanentlyDenied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('마이크 권한이 차단되어 있어요'),
            action: SnackBarAction(label: '설정 열기', onPressed: openAppSettings),
          ),
        );
        return;
      }
      if (status.isDenied) {
        // 재요청 후 허용되면 STT 재초기화 (이후 다시 마이크 버튼을 누르면 동작)
        final result = await Permission.microphone.request();
        if (result.isGranted) {
          await _initStt();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('마이크 권한이 허용됐어요. 다시 눌러 주세요')),
            );
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('음성 검색을 하려면 마이크 권한이 필요해요')),
          );
        }
        return;
      }
      // 권한은 있으나 음성 엔진을 쓸 수 없는 기기
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이 기기에서는 음성 인식을 사용할 수 없어요')),
      );
      return;
    }
    _focus.unfocus();
    setState(() => _listening = true);

    final locales = await _stt.locales();
    final koLocale = locales
        .where((l) => l.localeId.startsWith('ko'))
        .map((l) => l.localeId)
        .firstOrNull;
    debugPrint('[STT] 선택된 locale: $koLocale');

    final started = await _stt.listen(
      localeId: koLocale,
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      onResult: (result) {
        debugPrint('[STT] 인식: "${result.recognizedWords}" final=${result.finalResult}');
        final words = result.recognizedWords;
        if (words.isNotEmpty) {
          _ctrl.text = words;
          _ctrl.selection =
              TextSelection.fromPosition(TextPosition(offset: words.length));
        }
        if (result.finalResult) {
          setState(() => _listening = false);
          if (words.isNotEmpty) _search(words);
        }
      },
    );

    debugPrint('[STT] listen 시작됨: $started');
    if (!started && mounted) {
      setState(() => _listening = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('음성 인식을 시작할 수 없습니다')),
      );
    }
  }

  // ── 즐겨찾기 행 ────────────────────────────────

  Widget _buildFavoritesRow(BuildContext context) {
    final favAsync = ref.watch(favoritesProvider);
    final fav = favAsync.valueOrNull;
    final home = fav?.home;
    final custom = fav?.custom ?? [];
    final isHomeSet = home != null;

    void selectFav(FavoritePlace p) {
      Navigator.pop(
          context,
          PlaceResult(
            name: p.name,
            address: '',
            lat: p.lat,
            lng: p.lng,
            category: '',
          ));
    }

    void openSetHome() {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => PlaceSearchSheet(
          title: '집 위치 설정',
          fixedName: '집',
          onSave: (p) => ref.read(favoritesProvider.notifier).setHome(p),
        ),
      );
    }

    Widget chip(
        {Widget? icon,
        required String label,
        bool filled = false,
        bool isAdd = false}) {
      final Color bg = isAdd
          ? Colors.blue.withValues(alpha: 0.08)
          : filled
              ? Colors.blue
              : Colors.grey[100]!;
      final Color border = isAdd
          ? Colors.blue.withValues(alpha: 0.4)
          : filled
              ? Colors.blue
              : Colors.grey[400]!;
      final Color text = isAdd
          ? Colors.blue
          : filled
              ? Colors.white
              : Colors.grey[700]!;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[icon, const SizedBox(width: 4)],
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: text,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 48,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => isHomeSet ? selectFav(home) : openSetHome(),
                    onLongPress: isHomeSet
                        ? () => showModalBottomSheet(
                              context: context,
                              builder: (_) => SafeArea(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ListTile(
                                      leading: const Icon(
                                          Icons.edit_location_alt),
                                      title: const Text('집 위치 재설정'),
                                      onTap: () {
                                        Navigator.pop(context);
                                        openSetHome();
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.red),
                                      title: const Text('집 삭제',
                                          style:
                                              TextStyle(color: Colors.red)),
                                      onTap: () {
                                        Navigator.pop(context);
                                        ref
                                            .read(
                                                favoritesProvider.notifier)
                                            .clearHome();
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            )
                        : null,
                    child: chip(
                      icon: Icon(Icons.home,
                          size: 14,
                          color: isHomeSet
                              ? Colors.white
                              : Colors.grey[600]),
                      label: '집',
                      filled: isHomeSet,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ...custom.map((p) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => selectFav(p),
                          child: chip(label: p.name),
                        ),
                      )),
                  GestureDetector(
                    onTap: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => PlaceSearchSheet(
                        title: '장소 추가',
                        fixedName: null,
                        existingNames: custom.map((e) => e.name).toSet(),
                        onSave: (p) =>
                            ref.read(favoritesProvider.notifier).addCustom(p),
                      ),
                    ),
                    child: chip(
                      icon: const Icon(Icons.add,
                          size: 14, color: Colors.blue),
                      label: '추가',
                      isAdd: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }

  // ── 최근 검색 목록 ──────────────────────────────

  Widget _buildRecentsSection() {
    if (_recents.isEmpty) {
      return const Expanded(
        child: Center(
          child: Text(
            '검색어를 입력하거나 마이크를 눌러보세요',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return Expanded(
      child: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('최근 검색',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87)),
                GestureDetector(
                  onTap: _clearAllRecents,
                  child: const Text('전체삭제',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: _recents.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 56),
              itemBuilder: (_, i) {
                final p = _recents[i];
                return ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFF5F5F5),
                    child: Icon(Icons.history,
                        color: Colors.grey, size: 18),
                  ),
                  title: Text(p.name,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: p.address.isNotEmpty
                      ? Text(
                          p.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        )
                      : null,
                  trailing: IconButton(
                    icon: const Icon(Icons.close,
                        size: 16, color: Colors.grey),
                    onPressed: () => _removeRecent(i),
                  ),
                  onTap: () => _selectPlace(p),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── 검색 결과 목록 ──────────────────────────────

  Widget _buildSuggestions() {
    return Expanded(
      child: ListView.separated(
        itemCount: _suggestions.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 56),
        itemBuilder: (_, i) {
          final p = _suggestions[i];
          return ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFEEF2FF),
              child: Icon(Icons.location_on,
                  color: Color(0xFF3D5AFE), size: 18),
            ),
            title: Text(p.name,
                style:
                    const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text(
              p.address,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            onTap: () => _selectPlace(p),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showResults = _suggestions.isNotEmpty;
    // 검색어가 있는데 결과가 0건이면 '검색 결과 없음' 표시 (최근 검색 대신)
    final showNoResults =
        !_loading && _suggestions.isEmpty && _activeQuery.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: TextField(
          controller: _ctrl,
          focusNode: _focus,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: '장소, 주소 검색',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
          onSubmitted: _search,
        ),
        actions: [
          if (_ctrl.text.isNotEmpty && !_listening)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _ctrl.clear();
                _debounce?.cancel();
                setState(() {
                  _suggestions = [];
                  _loading = false;
                  _activeQuery = '';
                });
                _focus.requestFocus();
              },
            ),
          IconButton(
            icon: _listening
                ? const Icon(Icons.mic, color: Colors.red)
                : const Icon(Icons.mic_none),
            tooltip: _listening ? '듣는 중 (탭해서 중지)' : '음성 검색',
            onPressed: _toggleListening,
          ),
        ],
      ),
      body: _listening
          ? _ListeningView(stt: _stt)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFavoritesRow(context),
                if (_loading)
                  const LinearProgressIndicator(minHeight: 2)
                else
                  const SizedBox(height: 2),
                if (showResults)
                  _buildSuggestions()
                else if (showNoResults)
                  const Expanded(
                    child: Center(
                      child: Text(
                        '검색 결과가 없습니다',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  _buildRecentsSection(),
              ],
            ),
    );
  }
}

/// 음성 인식 중 표시 화면
class _ListeningView extends StatelessWidget {
  final SpeechToText stt;
  const _ListeningView({required this.stt});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mic, color: Colors.red, size: 40),
          ),
          const SizedBox(height: 24),
          const Text(
            '듣고 있어요...',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          const Text(
            '목적지를 말해보세요',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
