import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../data/map_repository.dart';
import '../route_search_screen.dart';

// 네이버지도와 동일한 탭 순서
const _modeOrder = [
  RouteMode.transit,
  RouteMode.walk,
  RouteMode.bike,
  RouteMode.car,
];

class _ModeState {
  final bool loading;
  final List<RouteResult> routes; // 비어 있으면 미로드 상태
  final String? error;
  const _ModeState({this.loading = false, this.routes = const [], this.error});
}

class RouteOverlayPanel extends ConsumerStatefulWidget {
  final PlaceResult dest;
  final PlaceResult? origin; // null = 현재위치
  final VoidCallback onClose;
  // result == null → 지도 오버레이 클리어 신호
  final void Function(RouteResult? result, RouteMode mode) onRouteLoaded;
  final void Function(PlaceResult?) onOriginChanged;

  const RouteOverlayPanel({
    super.key,
    required this.dest,
    this.origin,
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

  // 버스 실시간 도착 정보
  String? _arrivalMsg;
  bool _arrivalLoading = false;
  int _arrivalReqId = 0;

  // 드래그/스냅 상태
  late final AnimationController _anim;
  double _panelHeight = 0;
  double _dragOffset = 0; // 현재 드래그 중인 추가 오프셋
  static const double _peekHeight = 90.0; // 최소 표시 높이 (탭 바 높이)

  @override
  void initState() {
    super.initState();
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
    _anim.dispose();
    super.dispose();
  }

  Future<void> _fetchAll() async {
    double olat, olng;
    if (widget.origin != null) {
      olat = widget.origin!.lat;
      olng = widget.origin!.lng;
    } else {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
        olat = pos.latitude;
        olng = pos.longitude;
      } catch (_) {
        if (!mounted) return;
        const errState = _ModeState(error: '위치를 가져올 수 없습니다');
        setState(() {
          _states = {for (final m in RouteMode.values) m: errState};
        });
        widget.onRouteLoaded(null, _mode);
        return;
      }
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
    setState(() { _selectedTransitIndex = index; _arrivalMsg = null; });
    widget.onRouteLoaded(routes[index], RouteMode.transit);
    _fetchArrival(routes);
  }

  Future<void> _fetchArrival(List<RouteResult> routes) async {
    if (routes.isEmpty) return;
    final route = routes[_selectedTransitIndex.clamp(0, routes.length - 1)];

    // 경로 순서대로 첫 번째 버스 또는 지하철 leg 선택
    RouteLeg? transitLeg;
    for (final leg in route.legs) {
      if (leg.type == 'bus' || leg.type == 'subway') { transitLeg = leg; break; }
    }
    // 버스: stId+busRouteId 필요 / 지하철: startStation 필요
    final bool canFetch = transitLeg != null && (
      (transitLeg.type == 'bus' && transitLeg.stId != null && transitLeg.busRouteId != null) ||
      (transitLeg.type == 'subway' && transitLeg.startStation != null && transitLeg.name.isNotEmpty)
    );
    if (!canFetch) {
      setState(() { _arrivalMsg = null; _arrivalLoading = false; });
      return;
    }

    final reqId = ++_arrivalReqId;
    setState(() { _arrivalLoading = true; _arrivalMsg = null; });

    final msg = await ref.read(mapRepositoryProvider).getTransitArrival(
      legType: transitLeg.type,
      routeName: transitLeg.name,
      startStation: transitLeg.startStation,
      subwayCode: transitLeg.subwayCode,
      stId: transitLeg.stId,
      busRouteId: transitLeg.busRouteId,
    );

    if (!mounted || reqId != _arrivalReqId) return;
    setState(() { _arrivalMsg = msg; _arrivalLoading = false; });
  }

  // ── Helpers ─────────────────────────────────────────────────

  String _modeLabel(RouteMode mode) => switch (mode) {
        RouteMode.walk => '도보',
        RouteMode.bike => '자전거',
        RouteMode.transit => '대중교통',
        RouteMode.car => '자동차',
      };

  IconData _modeIcon(RouteMode mode) => switch (mode) {
        RouteMode.walk => Icons.directions_walk,
        RouteMode.bike => Icons.directions_bike,
        RouteMode.transit => Icons.directions_transit,
        RouteMode.car => Icons.directions_car,
      };

  Color _modeColor(RouteMode mode) => switch (mode) {
        RouteMode.transit => const Color(0xFF1565C0),
        RouteMode.car => const Color(0xFFE53935),
        RouteMode.bike => const Color(0xFF2E7D32),
        RouteMode.walk => const Color(0xFF0288D1),
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

  Color _parseLegColor(String hexColor) {
    try {
      final hex =
          hexColor.startsWith('#') ? hexColor.substring(1) : hexColor;
      if (hex.length != 6) return Colors.blue;
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.blue;
    }
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    _panelHeight = screenHeight * 0.5 + bottomInset;
    final collapsedOffset = _panelHeight - _peekHeight;

    final panel = Container(
      height: _panelHeight,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, -2)),
        ],
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _buildModeTabs(),
          const Divider(height: 1),
          _buildHeader(),
          const Divider(height: 1),
          Expanded(child: _buildContent()),
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
        final currentOffset =
            _anim.value * collapsedOffset + _dragOffset;

        if (velocity > 300 || currentOffset > collapsedOffset * 0.5) {
          // 접기
          _anim.value = (currentOffset / collapsedOffset).clamp(0.0, 1.0);
          _anim.animateTo(1.0, curve: Curves.easeOut);
          setState(() { _dragOffset = 0; });
        } else {
          // 펼치기
          _anim.value = (currentOffset / collapsedOffset).clamp(0.0, 1.0);
          _anim.animateTo(0.0, curve: Curves.easeOut);
          setState(() { _dragOffset = 0; });
        }
      },
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          final offset = (_anim.value * collapsedOffset + _dragOffset)
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

  Widget _buildModeTabs() {
    return Row(
      children: _modeOrder.map((mode) {
        final isSelected = mode == _mode;
        final state = _states[mode]!;
        final activeColor = _modeColor(mode);
        final color = isSelected ? activeColor : Colors.grey[600]!;

        final String timeText;
        if (state.loading) {
          timeText = '···';
        } else if (state.routes.isNotEmpty) {
          timeText = _formatDuration(state.routes.first.durationSeconds);
        } else {
          timeText = '-';
        }

        return Expanded(
          child: GestureDetector(
            onTap: () => _selectMode(mode),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSelected ? activeColor : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_modeIcon(mode), color: color, size: 20),
                  const SizedBox(height: 2),
                  Text(_modeLabel(mode),
                      style: TextStyle(fontSize: 10, color: color)),
                  const SizedBox(height: 2),
                  Text(
                    timeText,
                    style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildHeader() {
    final originLabel = widget.origin?.name ?? '현재 위치';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: _changeOrigin,
                  child: Row(children: [
                    Icon(Icons.my_location, size: 14,
                        color: widget.origin != null ? Colors.green : Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        originLabel,
                        style: TextStyle(
                          fontSize: 13,
                          color: widget.origin != null ? Colors.black87 : Colors.grey,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.edit, size: 12, color: Colors.grey),
                  ]),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.location_on, size: 14, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.dest.name,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.close), onPressed: widget.onClose),
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
    widget.onOriginChanged(result); // null이면 현재위치로 리셋
    // 출발지 바뀌면 경로 다시 조회
    setState(() {
      _states = {for (final m in RouteMode.values) m: const _ModeState(loading: true)};
      _arrivalMsg = null;
    });
    _fetchAll();
  }

  Widget _buildContent() {
    final state = _states[_mode]!;
    if (state.loading) return const Center(child: CircularProgressIndicator());
    if (state.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 32),
              const SizedBox(height: 8),
              Text(state.error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                  textAlign: TextAlign.center),
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

  // ── 대중교통: 카드 목록 ─────────────────────────────────────

  Widget _buildTransitRoutes(List<RouteResult> routes) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: routes.length,
      itemBuilder: (_, i) => _buildTransitCard(routes[i], i),
    );
  }

  Widget _buildTransitCard(RouteResult result, int index) {
    final isSelected = index == _selectedTransitIndex;
    final transfers = _transferCount(result.legs);
    final cardColor = _modeColor(RouteMode.transit);

    return GestureDetector(
      onTap: () => _selectTransitRoute(index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? cardColor.withValues(alpha: 0.04)
              : Colors.white,
          border: Border.all(
            color: isSelected ? cardColor : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단: 도착시각 / 소요시간 / 거리 / 요금
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '도착 ${_arrivalTime(result.durationSeconds)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(width: 10),
                Text(
                  _formatDuration(result.durationSeconds),
                  style: TextStyle(
                    fontSize: isSelected ? 22 : 18,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? cardColor : Colors.black87,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDistance(result.distanceMeters),
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
                const Spacer(),
                if (result.fare > 0)
                  Text(
                    _formatFare(result.fare),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
            // 환승 횟수
            if (result.legs.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                transfers == 0 ? '직행' : '환승 $transfers회',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              const SizedBox(height: 8),
              // 구간 바
              _buildMiniBar(result.legs, height: isSelected ? 10 : 7),
              // 선택된 카드만 상세 정보 표시
              if (isSelected) ...[
                const SizedBox(height: 8),
                _buildStationNames(result.legs),
                const SizedBox(height: 8),
                _buildLegChipRow(result.legs),
                if (_arrivalLoading) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    SizedBox(
                      width: 12, height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: cardColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('버스 도착 정보 조회 중...',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  ]),
                ] else if (_arrivalMsg != null) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(Icons.directions_bus, size: 13, color: cardColor),
                    const SizedBox(width: 4),
                    Text(_arrivalMsg!,
                        style: TextStyle(
                            fontSize: 12,
                            color: cardColor,
                            fontWeight: FontWeight.w600)),
                  ]),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMiniBar(List<RouteLeg> legs, {double height = 8}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: height,
        child: Row(
          children: legs.map((leg) {
            final flex = max(1, leg.durationSeconds);
            final color = leg.type == 'walk'
                ? Colors.grey[300]!
                : _parseLegColor(leg.color);
            return Expanded(flex: flex, child: Container(color: color));
          }).toList(),
        ),
      ),
    );
  }

  // ── 도보/자전거/자동차: 단일 결과 ───────────────────────────

  IconData _turnIcon(int turnType) {
    switch (turnType) {
      case 12: return Icons.turn_left;
      case 13: return Icons.turn_right;
      case 14: return Icons.u_turn_left;
      case 16: return Icons.turn_slight_left;
      case 17: return Icons.turn_slight_right;
      case 11: case 0: default: return Icons.straight;
    }
  }

  Widget _buildSingleResult(RouteResult result) {
    final color = _modeColor(_mode);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '도착 ${_arrivalTime(result.durationSeconds)}',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
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
                style: TextStyle(fontSize: 16, color: Colors.grey[500]),
              ),
            ],
          ),
          if (result.steps.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...result.steps.map((step) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_turnIcon(step.turnType), size: 18, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      step.description,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  if (step.distanceMeters > 0)
                    Text(
                      _formatDistance(step.distanceMeters.toDouble()),
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }

  // ── 공통 위젯 ────────────────────────────────────────────────

  Widget _buildStationNames(List<RouteLeg> legs) {
    final stations = <String>[];
    bool firstTransit = true;
    for (final leg in legs) {
      if (leg.type == 'walk') continue;
      if (firstTransit && leg.startStation != null) {
        stations.add(leg.startStation!);
        firstTransit = false;
      } else {
        firstTransit = false;
      }
      if (leg.endStation != null) stations.add(leg.endStation!);
    }
    if (stations.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < stations.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child: Icon(Icons.arrow_forward, size: 12, color: Colors.grey),
              ),
            Text(stations[i],
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ],
      ),
    );
  }

  Widget _buildLegChipRow(List<RouteLeg> legs) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < legs.length; i++) ...[
            _buildLegChip(legs[i]),
            if (i < legs.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child:
                    Icon(Icons.chevron_right, size: 14, color: Colors.grey),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildLegChip(RouteLeg leg) {
    if (leg.type == 'walk') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_walk, size: 14, color: Colors.grey[500]),
          const SizedBox(width: 2),
          Text(_formatDuration(leg.durationSeconds.toDouble()),
              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ],
      );
    }
    final color = _parseLegColor(leg.color);
    final icon =
        leg.type == 'subway' ? Icons.directions_subway : Icons.directions_bus;
    final label = leg.name.isEmpty
        ? _formatDuration(leg.durationSeconds.toDouble())
        : leg.name;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
