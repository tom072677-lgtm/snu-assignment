import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:sensors_plus/sensors_plus.dart';
import '../data/map_repository.dart';
import 'route_search_screen.dart';
import 'widgets/route_panel.dart' show RouteOverlayPanel, resolveCurrentPosition;

// SNU 관악캠퍼스 중심 좌표
const _snuCenter = NLatLng(37.4607, 126.9526);

enum _SheetMode { none, placeDetail, routePanel }

Color _routeColor(RouteMode mode) => switch (mode) {
      RouteMode.transit => const Color(0xFF1565C0),
      RouteMode.car => const Color(0xFFE53935),
      RouteMode.bike => const Color(0xFF2E7D32),
      RouteMode.walk => Colors.blue,
    };

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  NaverMapController? _mapCtrl;
  StreamSubscription<MagnetometerEvent>? _compassSub;
  double _heading = 0;
  bool _compassMode = false;
  Position? _initialPosition;

  // 시트 상태 기계
  _SheetMode _sheetMode = _SheetMode.none;
  PlaceResult? _selectedPlace; // POI 상세 보기 대상
  PlaceResult? _routeDest;
  PlaceResult? _routeOrigin; // null = 현재위치

  @override
  void dispose() {
    _compassSub?.cancel();
    super.dispose();
  }

  // ── 위치 ──────────────────────────────────────────────────────

  Future<void> _initLocation() async {
    _mapCtrl?.setLocationTrackingMode(NLocationTrackingMode.noFollow);
    final pos = await resolveCurrentPosition();
    if (pos == null) {
      debugPrint('[위치] 취득 실패 (권한 거부 또는 서비스 꺼짐)');
      return;
    }
    _initialPosition = pos;
    _mapCtrl?.updateCamera(NCameraUpdate.withParams(
      target: NLatLng(pos.latitude, pos.longitude),
    ));
  }

  Future<void> _goToMyLocation() async {
    final pos = await resolveCurrentPosition() ?? _initialPosition;
    if (pos == null) return;
    _initialPosition = pos;
    _mapCtrl?.updateCamera(NCameraUpdate.withParams(
      target: NLatLng(pos.latitude, pos.longitude),
      zoom: 16,
    ));
  }

  // ── 나침반 ──────────────────────────────────────────────────────

  void _startCompass() {
    _compassSub = magnetometerEventStream().listen((event) {
      final heading = math.atan2(event.y, event.x) * (180 / math.pi);
      setState(() => _heading = heading);
      if (_compassMode) {
        _mapCtrl?.updateCamera(NCameraUpdate.withParams(bearing: heading));
      }
    });
  }

  void _stopCompass() {
    _compassSub?.cancel();
    _compassSub = null;
  }

  void _toggleCompass() {
    setState(() => _compassMode = !_compassMode);
    if (_compassMode) {
      _startCompass();
    } else {
      _stopCompass();
      _mapCtrl?.updateCamera(NCameraUpdate.withParams(bearing: 0));
    }
  }

  // ── 상태 전환 ──────────────────────────────────────────────────

  /// 장소 선택 → POI 상세 시트
  Future<void> _showPlaceDetail(PlaceResult place) async {
    // 기존 경로 패널 닫기
    if (_sheetMode == _SheetMode.routePanel) {
      await _mapCtrl?.clearOverlays();
    }
    setState(() {
      _sheetMode = _SheetMode.placeDetail;
      _selectedPlace = place;
      _routeDest = null;
      _routeOrigin = null;
    });
    // 지도에 POI 마커 + 카메라 이동
    await _mapCtrl?.clearOverlays();
    await _mapCtrl?.addOverlay(NMarker(
      id: 'poi_marker',
      position: NLatLng(place.lat, place.lng),
    ));
    _mapCtrl?.updateCamera(NCameraUpdate.withParams(
      target: NLatLng(place.lat, place.lng),
      zoom: 15,
    ));
  }

  /// POI 상세 → "도착"으로 경로 패널 오픈
  void _openAsDest() {
    final place = _selectedPlace;
    if (place == null) return;
    _mapCtrl?.clearOverlays();
    setState(() {
      _sheetMode = _SheetMode.routePanel;
      _routeDest = place;
      _routeOrigin = null;
      _selectedPlace = null;
    });
  }

  /// POI 상세 → "출발"로 설정 후 목적지 검색
  Future<void> _openAsOrigin() async {
    final origin = _selectedPlace;
    if (origin == null) return;
    final dest = await Navigator.push<PlaceResult>(
      context,
      MaterialPageRoute(builder: (_) => const RouteSearchScreen()),
    );
    if (dest == null || !mounted) return;
    await _mapCtrl?.clearOverlays();
    setState(() {
      _sheetMode = _SheetMode.routePanel;
      _routeDest = dest;
      _routeOrigin = origin;
      _selectedPlace = null;
    });
  }

  /// POI 상세 닫기
  void _closePlaceDetail() {
    _mapCtrl?.clearOverlays();
    setState(() {
      _sheetMode = _SheetMode.none;
      _selectedPlace = null;
    });
  }

  /// 경로 패널 닫기
  void _closeRoutePanel() {
    _mapCtrl?.clearOverlays();
    setState(() {
      _sheetMode = _SheetMode.none;
      _routeDest = null;
      _routeOrigin = null;
    });
  }

  // ── 지도 오버레이 ───────────────────────────────────────────────

  Future<void> _onRouteLoaded(RouteResult? result, RouteMode mode) async {
    final ctrl = _mapCtrl;
    if (ctrl == null) return;
    if (result == null || result.path.length < 2) {
      await ctrl.clearOverlays();
      return;
    }
    await ctrl.clearOverlays();
    final coords = result.path.map((p) => NLatLng(p.$1, p.$2)).toList();
    await ctrl.addOverlay(NArrowheadPathOverlay(
      id: 'route_main',
      coords: coords,
      color: _routeColor(mode),
      width: 6,
      outlineWidth: 1,
      outlineColor: Colors.white,
      headSizeRatio: 4,
    ));
    await ctrl.addOverlay(NMarker(
      id: 'dest_marker',
      position: NLatLng(result.path.last.$1, result.path.last.$2),
    ));
    final lats = result.path.map((p) => p.$1);
    final lngs = result.path.map((p) => p.$2);
    final bounds = NLatLngBounds(
      southWest: NLatLng(lats.reduce(math.min), lngs.reduce(math.min)),
      northEast: NLatLng(lats.reduce(math.max), lngs.reduce(math.max)),
    );
    if (!mounted) return;
    final panelHeight = MediaQuery.of(context).size.height * 0.5;
    await ctrl.updateCamera(NCameraUpdate.fitBounds(
      bounds,
      padding: EdgeInsets.fromLTRB(40, 100, 40, panelHeight + 20),
    ));
  }

  // ── 검색 ────────────────────────────────────────────────────────

  Future<void> _openSearch({bool voiceMode = false}) async {
    final place = await Navigator.push<PlaceResult>(
      context,
      MaterialPageRoute(
        builder: (_) => RouteSearchScreen(autoStartMic: voiceMode),
      ),
    );
    if (place == null || !mounted) return;
    await _showPlaceDetail(place);
  }

  // ── UI ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final showSearchBar = _sheetMode == _SheetMode.none;
    final showButtons = _sheetMode != _SheetMode.routePanel;
    final bottomOffset = _sheetMode == _SheetMode.routePanel
        ? MediaQuery.of(context).size.height * 0.5 + 16
        : _sheetMode == _SheetMode.placeDetail
            ? 200.0
            : 100.0;

    return Scaffold(
      body: Stack(
        children: [
          // 1. 지도
          NaverMap(
            options: const NaverMapViewOptions(
              initialCameraPosition: NCameraPosition(
                target: _snuCenter,
                zoom: 15,
              ),
              consumeSymbolTapEvents: false,
            ),
            onMapReady: (controller) {
              _mapCtrl = controller;
              _initLocation();
            },
            onMapTapped: (point, latLng) {
              if (_sheetMode == _SheetMode.placeDetail) _closePlaceDetail();
              if (_sheetMode == _SheetMode.routePanel) _closeRoutePanel();
            },
          ),

          // 2. 검색 바
          if (showSearchBar)
            Positioned(
              top: topPadding + 12,
              left: 16,
              right: 16,
              child: _buildSearchBar(),
            ),

          // 3. 우하단 버튼 그룹
          if (showButtons)
            Positioned(
              bottom: bottomOffset,
              right: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'compass',
                    backgroundColor:
                        _compassMode ? Colors.blue : Colors.white,
                    foregroundColor:
                        _compassMode ? Colors.white : Colors.black87,
                    onPressed: _toggleCompass,
                    child: Transform.rotate(
                      angle: _heading * (math.pi / 180),
                      child: const Icon(Icons.navigation),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'my_location',
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.blue,
                    onPressed: _goToMyLocation,
                    child: const Icon(Icons.my_location),
                  ),
                ],
              ),
            ),

          // 4. POI 상세 시트
          if (_sheetMode == _SheetMode.placeDetail && _selectedPlace != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildPlaceDetailSheet(_selectedPlace!),
            ),

          // 5. 경로 패널
          if (_sheetMode == _SheetMode.routePanel && _routeDest != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: RouteOverlayPanel(
                dest: _routeDest!,
                origin: _routeOrigin,
                initialPosition: _initialPosition,
                onClose: _closeRoutePanel,
                onRouteLoaded: _onRouteLoaded,
                onOriginChanged: (p) => setState(() => _routeOrigin = p),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return GestureDetector(
      onTap: () => _openSearch(),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            const Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.search, color: Colors.grey, size: 20),
                    SizedBox(width: 10),
                    Text(
                      '어디 가세요?',
                      style: TextStyle(fontSize: 15, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            Container(width: 1, height: 24, color: Colors.grey[300]),
            SizedBox(
              width: 52,
              child: IconButton(
                icon: const Icon(Icons.mic_none, color: Colors.grey),
                onPressed: () => _openSearch(voiceMode: true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceDetailSheet(PlaceResult place) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, -2)),
        ],
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 드래그 핸들
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    if (place.category.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(place.category,
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[600])),
                    ],
                    if (place.address.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(place.address,
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[500])),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _closePlaceDetail,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openAsOrigin,
                  icon: const Icon(Icons.my_location, size: 16),
                  label: const Text('출발'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue,
                    side: const BorderSide(color: Colors.blue),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _openAsDest,
                  icon: const Icon(Icons.location_on, size: 16),
                  label: const Text('도착'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
