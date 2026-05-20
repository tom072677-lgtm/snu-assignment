import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../data/map_repository.dart';

// 네이버지도와 동일한 탭 순서
const _modeOrder = [
  RouteMode.transit,
  RouteMode.walk,
  RouteMode.bike,
  RouteMode.car,
];

class _ModeState {
  final bool loading;
  final RouteResult? result;
  final String? error;
  const _ModeState({this.loading = false, this.result, this.error});
}

class RouteOverlayPanel extends ConsumerStatefulWidget {
  final PlaceResult dest;
  final VoidCallback onClose;
  // result == null → 지도 오버레이 클리어 신호
  final void Function(RouteResult? result, RouteMode mode) onRouteLoaded;

  const RouteOverlayPanel({
    super.key,
    required this.dest,
    required this.onClose,
    required this.onRouteLoaded,
  });

  @override
  ConsumerState<RouteOverlayPanel> createState() => _RouteOverlayPanelState();
}

class _RouteOverlayPanelState extends ConsumerState<RouteOverlayPanel> {
  RouteMode _mode = RouteMode.transit;
  late Map<RouteMode, _ModeState> _states;
  late final DateTime _requestedAt;

  @override
  void initState() {
    super.initState();
    _requestedAt = DateTime.now();
    _states = {
      for (final m in RouteMode.values) m: const _ModeState(loading: true)
    };
    _fetchAll();
  }

  Future<void> _fetchAll() async {
    Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      const errState = _ModeState(error: '위치를 가져올 수 없습니다');
      setState(() {
        _states = {for (final m in RouteMode.values) m: errState};
      });
      widget.onRouteLoaded(null, _mode);
      return;
    }

    if (!mounted) return;

    // 모든 모드 병렬 fetch — 각각 내부에서 에러 catch
    await Future.wait(
      RouteMode.values.map((m) => _fetchMode(m, pos)),
    );
  }

  Future<void> _fetchMode(RouteMode mode, Position pos) async {
    try {
      final result = await ref.read(mapRepositoryProvider).getRoute(
            mode: mode,
            olat: pos.latitude,
            olng: pos.longitude,
            dlat: widget.dest.lat,
            dlng: widget.dest.lng,
          );
      if (!mounted) return;
      setState(() => _states = {..._states, mode: _ModeState(result: result)});
      if (mode == _mode) widget.onRouteLoaded(result, mode);
    } catch (e) {
      if (!mounted) return;
      setState(() =>
          _states = {..._states, mode: _ModeState(error: e.toString())});
      if (mode == _mode) widget.onRouteLoaded(null, mode);
    }
  }

  void _selectMode(RouteMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    final state = _states[mode]!;
    widget.onRouteLoaded(state.result, mode);
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
    final arrival =
        _requestedAt.add(Duration(seconds: durationSeconds.round()));
    return '${arrival.hour.toString().padLeft(2, '0')}:'
        '${arrival.minute.toString().padLeft(2, '0')}';
  }

  String _formatFare(int won) {
    if (won <= 0) return '';
    return '${won.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}원';
  }

  int _transferCount(List<RouteLeg> legs) {
    final transitLegs = legs.where((l) => l.type != 'walk').length;
    return (transitLegs - 1).clamp(0, 99);
  }

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

    return Container(
      height: screenHeight * 0.5 + bottomInset,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
              color: Colors.black26, blurRadius: 12, offset: Offset(0, -2)),
        ],
      ),
      child: Column(
        children: [
          // 드래그 핸들
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // ① 모드 탭 (최상단 — 네이버지도 동일)
          _buildModeTabs(),
          const Divider(height: 1),
          // ② 출발 / 도착 헤더
          _buildHeader(),
          const Divider(height: 1),
          // ③ 경로 결과
          Expanded(child: _buildContent()),
          SizedBox(height: bottomInset),
        ],
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
        } else if (state.result != null) {
          timeText = _formatDuration(state.result!.durationSeconds);
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
                  Text(
                    _modeLabel(mode),
                    style: TextStyle(fontSize: 10, color: color),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeText,
                    style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.my_location, size: 14, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('현재 위치',
                      style:
                          TextStyle(fontSize: 13, color: Colors.grey)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.location_on,
                      size: 14, color: Colors.red),
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
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

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
                style:
                    const TextStyle(color: Colors.red, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final result = state.result!;
    final transfers = _transferCount(result.legs);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 도착 시각
          Text(
            '도착 ${_arrivalTime(result.durationSeconds)}',
            style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600]),
          ),
          const SizedBox(height: 4),
          // 소요시간 + 거리
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _formatDuration(result.durationSeconds),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: _modeColor(_mode),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _formatDistance(result.distanceMeters),
                style: TextStyle(fontSize: 16, color: Colors.grey[500]),
              ),
            ],
          ),
          // 대중교통: 요금 + 환승
          if (_mode == RouteMode.transit && result.legs.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                if (result.fare > 0) ...[
                  Text('요금 ${_formatFare(result.fare)}',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[600])),
                  const SizedBox(width: 12),
                ],
                if (transfers >= 0)
                  Text(
                    transfers == 0 ? '환승 없음' : '환승 $transfers회',
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey[600]),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSegmentBar(result.legs),
          ],
        ],
      ),
    );
  }

  Widget _buildSegmentBar(List<RouteLeg> legs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 컬러 구간 바
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: 10,
            child: Row(
              children: legs.map((leg) {
                final flex = max(1, leg.durationSeconds);
                final color = leg.type == 'walk'
                    ? Colors.grey[300]!
                    : _parseLegColor(leg.color);
                return Expanded(
                    flex: flex, child: Container(color: color));
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 역 이름 행
        _buildStationNames(legs),
        const SizedBox(height: 10),
        // 구간 칩 행
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (int i = 0; i < legs.length; i++) ...[
                _buildLegChip(legs[i]),
                if (i < legs.length - 1)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(Icons.chevron_right,
                        size: 14, color: Colors.grey),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegChip(RouteLeg leg) {
    if (leg.type == 'walk') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_walk, size: 14, color: Colors.grey[500]),
          const SizedBox(width: 2),
          Text(
            _formatDuration(leg.durationSeconds.toDouble()),
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
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
                child: Icon(Icons.arrow_forward,
                    size: 12, color: Colors.grey),
              ),
            Text(
              stations[i],
              style:
                  const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }
}
