import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/analytics.dart';
import '../../data/map_repository.dart';
import '../route_search_screen.dart';

// ── 색상/치수 상수 ────────────────────────────────────────────────
class _C {
  _C._();
  static const primary     = Color(0xFF1A73E8);
  static const primaryBg   = Color(0xFFF0F6FF);
  static const textMain    = Color(0xFF191919);
  static const textSub     = Color(0xFF767676);
  static const textHint    = Color(0xFFAAAAAA);
  static const border      = Color(0xFFE8E8E8);
  static const panelBg     = Color(0xFFF5F5F5);
  static const walkColor   = Color(0xFFDDDDDD);
  static const shadow      = Color(0x1F000000);
  static const cardRadius  = 14.0;
  static const panelRadius = 20.0;
}

/// 위치 권한 체크 + 현재위치 취득 헬퍼.
/// 1) 권한 확인/요청 → 거부 시 null 반환
/// 2) 서비스 꺼짐 시 null 반환
/// 3) 캐시 위치가 5분 이내면 바로 반환, 오래됐으면 getCurrentPosition(20s) 대기
Future<Position?> resolveCurrentPosition() async {
  try {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) { return null; }

    final last = await Geolocator.getLastKnownPosition();
    if (last != null) {
      final age = DateTime.now().difference(last.timestamp);
      if (age.inMinutes < 5) return last; // 5분 이내 캐시는 신뢰
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
  } catch (_) {
    return null;
  }
}

// 네이버지도와 동일한 탭 순서
const _modeOrder = [
  RouteMode.transit,
  RouteMode.walk,
  RouteMode.bike,
  RouteMode.car,
];

class _ModeState {
  final bool loading;
  final List<RouteResult> routes;
  final String? error;
  const _ModeState({this.loading = false, this.routes = const [], this.error});
}

class RouteOverlayPanel extends ConsumerStatefulWidget {
  final PlaceResult dest;
  final PlaceResult? origin;
  final Position? initialPosition;
  final VoidCallback onClose;
  final void Function(RouteResult? result, RouteMode mode) onRouteLoaded;
  final void Function(PlaceResult?) onOriginChanged;

  const RouteOverlayPanel({
    super.key,
    required this.dest,
    this.origin,
    this.initialPosition,
    required this.onClose,
    required this.onRouteLoaded,
    required this.onOriginChanged,
  });

  @override
  ConsumerState<RouteOverlayPanel> createState() => _RouteOverlayPanelState();
}

class _RouteOverlayPanelState extends ConsumerState<RouteOverlayPanel>
    with SingleTickerProviderStateMixin {
  RouteMode _mode = RouteMode.transit;
  int _selectedTransitIndex = 0;
  late Map<RouteMode, _ModeState> _states;
  late final DateTime _requestedAt;
  PlaceResult? _currentOrigin;

  String? _arrivalMsg;
  bool _arrivalLoading = false;
  int _arrivalReqId = 0;
  Timer? _arrivalTimer;

  late final AnimationController _anim;
  double _panelHeight = 0;
  double _dragOffset = 0;
  static const double _peekHeight = 94.0; // 탭 바 높이 (아이콘 제거로 약간 줄어듦)

  @override
  void initState() {
    super.initState();
    _currentOrigin = widget.origin;
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _requestedAt = DateTime.now();
    _states = {
      for (final m in RouteMode.values) m: const _ModeState(loading: true)
    };
    _fetchAll();
  }

  @override
  void dispose() {
    _arrivalTimer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  Future<void> _fetchAll() async {
    double olat, olng;
    if (_currentOrigin != null) {
      olat = _currentOrigin!.lat;
      olng = _currentOrigin!.lng;
    } else {
      final pos = widget.initialPosition ?? await resolveCurrentPosition();
      if (!mounted) return;
      if (pos == null) {
        const errState = _ModeState(
          error: '위치를 가져올 수 없습니다.\n위치 권한과 GPS를 확인해주세요.',
        );
        setState(() {
          _states = {for (final m in RouteMode.values) m: errState};
        });
        widget.onRouteLoaded(null, _mode);
        return;
      }
      olat = pos.latitude;
      olng = pos.longitude;
    }

    if (!mounted) return;
    await Future.wait(RouteMode.values.map((m) => _fetchMode(m, olat, olng)));
  }

  Future<void> _fetchMode(RouteMode mode, double olat, double olng) async {
    try {
      final List<RouteResult> routes;
      if (mode == RouteMode.transit) {
        routes = await ref.read(mapRepositoryProvider).getTransitRoutes(
              olat: olat,
              olng: olng,
              dlat: widget.dest.lat,
              dlng: widget.dest.lng,
            );
      } else {
        final r = await ref.read(mapRepositoryProvider).getRoute(
              mode: mode,
              olat: olat,
              olng: olng,
              dlat: widget.dest.lat,
              dlng: widget.dest.lng,
            );
        routes = [r];
      }
      if (!mounted) return;
      setState(() => _states = {..._states, mode: _ModeState(routes: routes)});
      if (mode == _mode) {
        _notifyMap(mode, routes);
        if (mode == RouteMode.transit) _fetchArrival(routes);
      }
      if (mode == RouteMode.transit) {
        Analytics.routeSearched(destName: widget.dest.name, mode: 'transit');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() =>
          _states = {..._states, mode: _ModeState(error: e.toString())});
      if (mode == _mode) widget.onRouteLoaded(null, mode);
    }
  }

  void _notifyMap(RouteMode mode, List<RouteResult> routes) {
    if (routes.isEmpty) {
      widget.onRouteLoaded(null, mode);
      return;
    }
    final idx = mode == RouteMode.transit
        ? _selectedTransitIndex.clamp(0, routes.length - 1)
        : 0;
    widget.onRouteLoaded(routes[idx], mode);
  }

  void _selectMode(RouteMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    final state = _states[mode]!;
    _notifyMap(mode, state.routes);
  }

  void _selectTransitRoute(int index) {
    final routes = _states[RouteMode.transit]!.routes;
    if (index < 0 || index >= routes.length) return;
    setState(() {
      _selectedTransitIndex = index;
      _arrivalMsg = null;
    });
    widget.onRouteLoaded(routes[index], RouteMode.transit);
    _fetchArrival(routes);
  }

  Future<void> _fetchArrival(List<RouteResult> routes) async {
    if (routes.isEmpty) return;
    final route = routes[_selectedTransitIndex.clamp(0, routes.length - 1)];

    // 셔틀 구간 우선 (캠퍼스 출발 경로에 항상 존재, SNU 셔틀 API 이용 가능)
    // → 그 다음 지하철 구간 (sample 키로 실시간 데이터 제공됨)
    // → 마지막으로 버스 구간 (SEOUL_BUS_API_KEY 필요)
    final shuttleLegs = route.legs.where((l) =>
        l.type == 'shuttle' &&
        l.shuttleRouteId != null &&
        l.shuttleStationCode != null).toList();
    final subwayLegs = route.legs.where((l) =>
        l.type == 'subway' &&
        l.startStation != null &&
        l.name.isNotEmpty).toList();
    final busLegs = route.legs.where((l) =>
        l.type == 'bus' &&
        l.stId != null &&
        l.busRouteId != null).toList();
    final candidates = [...shuttleLegs, ...subwayLegs, ...busLegs];

    if (candidates.isEmpty) {
      setState(() { _arrivalMsg = null; _arrivalLoading = false; });
      return;
    }

    final reqId = ++_arrivalReqId;
    setState(() { _arrivalLoading = true; _arrivalMsg = null; });

    for (final leg in candidates) {
      final msg = await ref.read(mapRepositoryProvider).getTransitArrival(
        legType: leg.type,
        routeName: leg.name,
        startStation: leg.startStation,
        subwayCode: leg.subwayCode,
        stId: leg.stId,
        busRouteId: leg.busRouteId,
        ord: leg.ord,
        shuttleRouteId: leg.shuttleRouteId,
        shuttleStationCode: leg.shuttleStationCode,
      );
      if (!mounted || reqId != _arrivalReqId) return;
      if (msg != null) {
        setState(() { _arrivalMsg = msg; _arrivalLoading = false; });
        // 도착 정보가 있어도 30초 후 갱신 (실시간 유지)
        _scheduleArrivalRefresh(routes, seconds: 30);
        return;
      }
    }

    if (!mounted || reqId != _arrivalReqId) return;
    setState(() { _arrivalMsg = null; _arrivalLoading = false; });

    // 도착 정보가 없으면 60초 후 재시도
    _scheduleArrivalRefresh(routes, seconds: 60);
  }

  void _scheduleArrivalRefresh(List<RouteResult> routes, {int seconds = 60}) {
    _arrivalTimer?.cancel();
    _arrivalTimer = Timer(Duration(seconds: seconds), () {
      if (mounted) _fetchArrival(routes);
    });
  }

  // ── Helpers ─────────────────────────────────────────────────

  String _modeLabel(RouteMode mode) => switch (mode) {
        RouteMode.walk    => '도보',
        RouteMode.bike    => '자전거',
        RouteMode.transit => '대중교통',
        RouteMode.car     => '자동차',
      };

  Color _modeColor(RouteMode mode) => switch (mode) {
        RouteMode.transit => const Color(0xFF1565C0),
        RouteMode.car     => const Color(0xFFE53935),
        RouteMode.bike    => const Color(0xFF2E7D32),
        RouteMode.walk    => const Color(0xFF0288D1),
      };

  String _formatDuration(double seconds) {
    final m = max(1, (seconds / 60).round());
    if (m < 60) return '$m분';
    return '${m ~/ 60}시간 ${m % 60}분';
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  String _arrivalTime(double durationSeconds) {
    final t = _requestedAt.add(Duration(seconds: durationSeconds.round()));
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  String _formatFare(int won) {
    if (won <= 0) return '';
    return '${won.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}원';
  }

  int _transferCount(List<RouteLeg> legs) =>
      (legs.where((l) => l.type != 'walk').length - 1).clamp(0, 99);

  /// 비선택 카드에 한 줄로 표시할 주요 노선명 (버스번호, 지하철호선, 셔틀)
  String _mainRouteNames(List<RouteLeg> legs) {
    final names = legs
        .where((l) => l.type != 'walk' && l.name.isNotEmpty)
        .map((l) => l.name)
        .toList();
    return names.join(' · ');
  }

  Color _parseLegColor(String hexColor) {
    try {
      final hex = hexColor.startsWith('#') ? hexColor.substring(1) : hexColor;
      if (hex.length != 6) return Colors.blue;
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.blue;
    }
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final topPadding = mediaQuery.padding.top;
    final bottomInset = mediaQuery.padding.bottom;

    // 전체화면 패널 — 상태바 높이만큼 spacer로 안전하게 처리
    _panelHeight = screenHeight;
    final collapsedOffset = _panelHeight - _peekHeight;

    final panel = Container(
      height: _panelHeight,
      decoration: const BoxDecoration(
        color: _C.panelBg,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(_C.panelRadius)),
        boxShadow: [
          BoxShadow(color: _C.shadow, blurRadius: 20, offset: Offset(0, -3)),
        ],
      ),
      child: Column(
        children: [
          // 상태바 높이만큼 여백 (전체화면에서 status bar와 겹치지 않도록)
          SizedBox(height: topPadding),
          // 드래그 핸들
          Container(
            margin: const EdgeInsets.only(top: 6, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 탭 바 (흰 배경)
          Container(
            color: Colors.white,
            child: _buildModeTabs(),
          ),
          // 헤더 + 콘텐츠
          Expanded(
            child: Column(
              children: [
                const SizedBox(height: 8),
                // 출발-도착 헤더
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _buildHeader(),
                ),
                const SizedBox(height: 8),
                // 경로 콘텐츠
                Expanded(child: _buildContent()),
              ],
            ),
          ),
          SizedBox(height: bottomInset),
        ],
      ),
    );

    return GestureDetector(
      onVerticalDragUpdate: (d) {
        setState(() => _dragOffset += d.delta.dy);
      },
      onVerticalDragEnd: (d) {
        final velocity = d.primaryVelocity ?? 0;
        final currentOffset = _anim.value * collapsedOffset + _dragOffset;

        if (velocity > 300 || currentOffset > collapsedOffset * 0.5) {
          _anim.value = (currentOffset / collapsedOffset).clamp(0.0, 1.0);
          _anim.animateTo(1.0, curve: Curves.easeOut);
          setState(() => _dragOffset = 0);
        } else {
          _anim.value = (currentOffset / collapsedOffset).clamp(0.0, 1.0);
          _anim.animateTo(0.0, curve: Curves.easeOut);
          setState(() => _dragOffset = 0);
        }
      },
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          final offset =
              (_anim.value * collapsedOffset + _dragOffset)
                  .clamp(0.0, collapsedOffset + 40);
          return Transform.translate(
            offset: Offset(0, offset),
            child: child,
          );
        },
        child: panel,
      ),
    );
  }

  // ── 모드 탭 바 ────────────────────────────────────────────────

  Widget _buildModeTabs() {
    return Row(
      children: _modeOrder.map((mode) {
        final isSelected = mode == _mode;
        final state = _states[mode]!;
        final activeColor = _modeColor(mode);
        final color = isSelected ? activeColor : _C.textSub;

        final String timeText;
        if (state.loading) {
          timeText = '···';
        } else if (state.routes.isNotEmpty) {
          timeText = _formatDuration(state.routes.first.durationSeconds);
        } else {
          timeText = '-';
        }

        return Expanded(
          child: InkWell(
            onTap: () => _selectMode(mode),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSelected ? activeColor : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 소요시간 (가장 눈에 띄는 요소)
                  Text(
                    timeText,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // 모드 레이블
                  Text(
                    _modeLabel(mode),
                    style: TextStyle(fontSize: 11, color: color),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── 출발-도착 헤더 ────────────────────────────────────────────

  Widget _buildHeader() {
    final originLabel = _currentOrigin?.name ?? '현재 위치';
    final hasCustomOrigin = _currentOrigin != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: _C.shadow, blurRadius: 8, offset: Offset(0, 1)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 수직 트랙 (파란 원 → 선 → 빨간 핀)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: _C.primary,
                ),
              ),
              Container(
                width: 2,
                height: 18,
                color: Colors.grey[300],
              ),
              const Icon(Icons.location_on, size: 14, color: Colors.red),
            ],
          ),
          const SizedBox(width: 10),
          // 출발/도착 텍스트
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 출발 행
                GestureDetector(
                  onTap: _changeOrigin,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          originLabel,
                          style: TextStyle(
                            fontSize: 13,
                            color: hasCustomOrigin
                                ? _C.textMain
                                : _C.textSub,
                            overflow: TextOverflow.ellipsis,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit, size: 12, color: _C.textHint),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // 도착 행
                Text(
                  widget.dest.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _C.textMain,
                    overflow: TextOverflow.ellipsis,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // 닫기
          IconButton(
            icon: const Icon(Icons.close, color: _C.textSub, size: 20),
            tooltip: '닫기',
            onPressed: widget.onClose,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  Future<void> _changeOrigin() async {
    final result = await Navigator.push<PlaceResult>(
      context,
      MaterialPageRoute(builder: (_) => const RouteSearchScreen()),
    );
    if (!mounted) return;
    widget.onOriginChanged(result);
    setState(() {
      _currentOrigin = result;
      _states = {
        for (final m in RouteMode.values) m: const _ModeState(loading: true)
      };
      _arrivalMsg = null;
    });
    _fetchAll();
  }

  // ── 콘텐츠 ───────────────────────────────────────────────────

  Widget _buildContent() {
    final state = _states[_mode]!;
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 32),
              const SizedBox(height: 8),
              Text(
                state.error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    if (state.routes.isEmpty) return const SizedBox.shrink();

    if (_mode == RouteMode.transit) {
      return _buildTransitRoutes(state.routes);
    }
    return _buildSingleResult(state.routes.first);
  }

  // ── 대중교통 카드 목록 ────────────────────────────────────────

  Widget _buildTransitRoutes(List<RouteResult> routes) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      itemCount: routes.length,
      itemBuilder: (_, i) => _buildTransitCard(routes[i], i),
    );
  }

  Widget _buildTransitCard(RouteResult result, int index) {
    final isSelected = index == _selectedTransitIndex;
    final transfers = _transferCount(result.legs);

    return GestureDetector(
      onTap: () => _selectTransitRoute(index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSelected ? _C.primaryBg : Colors.white,
          borderRadius: BorderRadius.circular(_C.cardRadius),
          border: isSelected
              ? null
              : Border.all(color: _C.border),
          boxShadow: isSelected
              ? [
                  const BoxShadow(
                      color: _C.shadow, blurRadius: 6, offset: Offset(0, 2))
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_C.cardRadius),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 선택된 카드: 왼쪽 파란 세로 바
                if (isSelected)
                  Container(width: 4, color: _C.primary),
                // 카드 본문
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: _buildTransitCardBody(
                        result, isSelected, transfers),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransitCardBody(
      RouteResult result, bool isSelected, int transfers) {
    final timeColor = isSelected ? _C.primary : _C.textMain;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 뱃지 + 도착시각
        Row(
          children: [
            if (result.isFastest) ...[
              const _BadgeChip(label: '⚡ 빠름', color: _C.primary),
              const SizedBox(width: 6),
            ],
            if (result.isFree) ...[
              const _BadgeChip(
                  label: '🆓 무료', color: Color(0xFF2E7D32)),
              const SizedBox(width: 6),
            ],
            const Spacer(),
            Text(
              '도착 ${_arrivalTime(result.durationSeconds)}',
              style: const TextStyle(fontSize: 12, color: _C.textSub),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // 소요시간
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              _formatDuration(result.durationSeconds),
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: timeColor,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _formatDistance(result.distanceMeters),
              style: const TextStyle(fontSize: 13, color: _C.textSub),
            ),
            const Spacer(),
            if (result.fare > 0)
              Text(
                _formatFare(result.fare),
                style: const TextStyle(fontSize: 13, color: _C.textSub),
              ),
          ],
        ),
        // 환승 횟수 + 노선명 요약 (비선택 카드도 표시)
        if (result.legs.isNotEmpty) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                transfers == 0 ? '직행' : '환승 $transfers회',
                style: const TextStyle(fontSize: 12, color: _C.textHint),
              ),
              // 비선택 카드: 주요 노선 번호 요약
              if (!isSelected) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _mainRouteNames(result.legs),
                    style: const TextStyle(fontSize: 12, color: _C.textSub),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // 구간 바 (아이콘 + 소요시간 표시)
          _buildMiniBar(result.legs),
          // 선택 카드 상세
          if (isSelected) ...[
            const SizedBox(height: 10),
            _buildLegChipRow(result.legs),
            // 실시간 도착 정보 (경유 정류장 위에 표시)
            if (_arrivalLoading) ...[
              const SizedBox(height: 8),
              const Row(children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: _C.primary),
                ),
                SizedBox(width: 6),
                Text('도착 정보 조회 중...',
                    style: TextStyle(fontSize: 11, color: _C.textSub)),
              ]),
            ] else if (_arrivalMsg != null) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _C.primaryBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _C.primary.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.directions_transit,
                      size: 14, color: _C.primary),
                  const SizedBox(width: 6),
                  Text(
                    _arrivalMsg!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _C.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 8),
            _buildIntermediateStations(result.legs),
          ],
        ],
      ],
    );
  }

  // ── 라벨드 구간 바 (아이콘 + 소요시간 표시) ──────────────────

  Widget _buildMiniBar(List<RouteLeg> legs) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 28,
        child: Row(
          children: legs.map((leg) {
            final flex = max(1, leg.durationSeconds);
            final isWalk = leg.type == 'walk';
            final bgColor = isWalk ? _C.walkColor : _parseLegColor(leg.color);
            final textColor = isWalk ? _C.textSub : Colors.white;
            final icon = isWalk
                ? Icons.directions_walk
                : leg.type == 'subway'
                    ? Icons.directions_subway
                    : Icons.directions_bus;
            final dur = _formatDuration(leg.durationSeconds.toDouble());

            return Expanded(
              flex: flex,
              child: Container(
                color: bgColor,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 11, color: textColor),
                      const SizedBox(width: 2),
                      Text(
                        dur,
                        style: TextStyle(
                          fontSize: 10,
                          color: textColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── 도보/자전거/자동차 단일 결과 ─────────────────────────────

  IconData _turnIcon(int turnType) {
    switch (turnType) {
      case 12: return Icons.turn_left;
      case 13: return Icons.turn_right;
      case 14: return Icons.u_turn_left;
      case 16: return Icons.turn_slight_left;
      case 17: return Icons.turn_slight_right;
      case 11:
      case 0:
      default: return Icons.straight;
    }
  }

  Widget _buildSingleResult(RouteResult result) {
    final color = _modeColor(_mode);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_C.cardRadius),
          border: Border.all(color: _C.border),
          boxShadow: const [
            BoxShadow(color: _C.shadow, blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '도착 ${_arrivalTime(result.durationSeconds)}',
              style:
                  const TextStyle(fontSize: 13, color: _C.textSub),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  _formatDuration(result.durationSeconds),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _formatDistance(result.distanceMeters),
                  style: const TextStyle(fontSize: 16, color: _C.textSub),
                ),
              ],
            ),
            if (result.steps.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(height: 1, color: _C.border),
              const SizedBox(height: 8),
              ...result.steps.map((step) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(_turnIcon(step.turnType),
                            size: 18, color: color),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            step.description,
                            style: const TextStyle(
                                fontSize: 13, color: _C.textMain),
                          ),
                        ),
                        if (step.distanceMeters > 0)
                          Text(
                            _formatDistance(step.distanceMeters.toDouble()),
                            style: const TextStyle(
                                fontSize: 12, color: _C.textHint),
                          ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  // ── leg chip 행 ──────────────────────────────────────────────

  Widget _buildLegChipRow(List<RouteLeg> legs) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < legs.length; i++) ...[
            _buildLegChip(legs[i]),
            if (i < legs.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 3),
                child: Icon(Icons.chevron_right, size: 14, color: _C.textHint),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildLegChip(RouteLeg leg) {
    if (leg.type == 'walk') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.directions_walk,
                size: 13, color: _C.textSub),
            const SizedBox(width: 3),
            Text(
              _formatDuration(leg.durationSeconds.toDouble()),
              style: const TextStyle(fontSize: 12, color: _C.textSub),
            ),
          ],
        ),
      );
    }
    final color = _parseLegColor(leg.color);
    final icon = leg.type == 'subway'
        ? Icons.directions_subway
        : Icons.directions_bus;
    final label = leg.type == 'shuttle'
        ? '셔틀'
        : (leg.name.isEmpty
            ? _formatDuration(leg.durationSeconds.toDouble())
            : leg.name);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── 중간 정류장 ───────────────────────────────────────────────

  Widget _buildIntermediateStations(List<RouteLeg> legs) {
    final transitLegs =
        legs.where((l) => l.type != 'walk' && l.stations.isNotEmpty).toList();
    if (transitLegs.isEmpty) return const SizedBox.shrink();

    final items = <Widget>[];
    for (int li = 0; li < transitLegs.length; li++) {
      final leg = transitLegs[li];
      final color = _parseLegColor(leg.color);
      final count = leg.stations.length;

      items.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(
            leg.type == 'subway'
                ? Icons.directions_subway
                : Icons.directions_bus,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            leg.name.isEmpty ? leg.type : leg.name,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 4),
          Text(
            '$count 정거장',
            style: const TextStyle(fontSize: 11, color: _C.textHint),
          ),
        ]),
      ));

      for (int i = 0; i < count; i++) {
        final isFirst = i == 0;
        final isLast = i == count - 1;
        final dotColor =
            (isFirst || isLast) ? color : color.withValues(alpha: 0.45);

        items.add(IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 20,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isFirst)
                      Expanded(
                        child: Container(
                            width: 2,
                            color: color.withValues(alpha: 0.25)),
                      ),
                    Container(
                      width: 8,
                      height: 8,
                      decoration:
                          BoxDecoration(shape: BoxShape.circle, color: dotColor),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                            width: 2,
                            color: color.withValues(alpha: 0.25)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  leg.stations[i],
                  style: TextStyle(
                    fontSize: 12,
                    color: (isFirst || isLast)
                        ? _C.textMain
                        : _C.textSub,
                    fontWeight: (isFirst || isLast)
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ));
      }

      if (li < transitLegs.length - 1) items.add(const SizedBox(height: 10));
    }

    return SizedBox(
      height: 160,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: items,
        ),
      ),
    );
  }
}

// ── 뱃지 칩 ─────────────────────────────────────────────────────

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
