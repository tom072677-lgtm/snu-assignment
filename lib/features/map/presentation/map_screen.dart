import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../data/map_repository.dart';
import 'route_search_screen.dart';
import 'widgets/route_panel.dart';

// SNU 관악캠퍼스 중심 좌표
const _snuCenter = NLatLng(37.4607, 126.9526);

// 모드별 경로 색상
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

  // 경로 패널 상태
  PlaceResult? _routeDest;
  PlaceResult? _routeOrigin; // null = 현재위치

  @override
  void dispose() {
    _compassSub?.cancel();
    super.dispose();
  }

  Future<void> _initLocation() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }

    _mapCtrl?.setLocationTrackingMode(NLocationTrackingMode.noFollow);

    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && _initialPosition == null) {
        _initialPosition = last;
        _mapCtrl?.updateCamera(NCameraUpdate.withParams(
          target: NLatLng(last.latitude, last.longitude),
        ));
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _initialPosition = pos;
      _mapCtrl?.updateCamera(NCameraUpdate.withParams(
        target: NLatLng(pos.latitude, pos.longitude),
      ));
    } catch (e) {
      debugPrint('[위치] 오류: $e');
    }
  }

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

  Future<void> _goToMyLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      _mapCtrl?.updateCamera(NCameraUpdate.withParams(
        target: NLatLng(pos.latitude, pos.longitude),
        zoom: 16,
      ));
    } catch (_) {
      if (_initialPosition != null) {
        _mapCtrl?.updateCamera(NCameraUpdate.withParams(
          target: NLatLng(_initialPosition!.latitude, _initialPosition!.longitude),
          zoom: 16,
        ));
      }
    }
  }

  // ── 경로 패널 콜백 ──────────────────────────────────────────

  void _onDestSelected(PlaceResult dest) {
    setState(() => _routeDest = dest);
  }

  void _onRoutePanelClose() {
    _clearRouteOnMap();
    setState(() { _routeDest = null; _routeOrigin = null; });
  }

  void _clearRouteOnMap() {
    _mapCtrl?.clearOverlays();
  }

  Future<void> _onRouteLoaded(RouteResult? result, RouteMode mode) async {
    final ctrl = _mapCtrl;
    if (ctrl == null) return;

    // result == null → 오버레이만 클리어
    if (result == null || result.path.length < 2) {
      await ctrl.clearOverlays();
      return;
    }

    // 기존 경로 제거
    await ctrl.clearOverlays();

    final coords = result.path.map((p) => NLatLng(p.$1, p.$2)).toList();

    // 경로선 (방향 화살표 포함)
    await ctrl.addOverlay(NArrowheadPathOverlay(
      id: 'route_main',
      coords: coords,
      color: _routeColor(mode),
      width: 6,
      outlineWidth: 1,
      outlineColor: Colors.white,
      headSizeRatio: 4,
    ));

    // 도착지 마커
    await ctrl.addOverlay(NMarker(
      id: 'dest_marker',
      position: NLatLng(result.path.last.$1, result.path.last.$2),
    ));

    // 카메라를 경로 전체에 맞춤 (패널 높이만큼 하단 여백)
    final lats = result.path.map((p) => p.$1);
    final lngs = result.path.map((p) => p.$2);
    final bounds = NLatLngBounds(
      southWest: NLatLng(lats.reduce(math.min), lngs.reduce(math.min)),
      northEast: NLatLng(lats.reduce(math.max), lngs.reduce(math.max)),
    );

    if (!mounted) return;
    final panelHeight = MediaQuery.of(context).size.height * 0.5;
    await ctrl.updateCamera(
      NCameraUpdate.fitBounds(
        bounds,
        padding: EdgeInsets.fromLTRB(40, 100, 40, panelHeight + 20),
      ),
    );
  }

  // ── UI ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final panelOpen = _routeDest != null;

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
              if (_routeDest != null) _onRoutePanelClose();
            },
          ),

          // 2. 검색 바 (경로 패널이 열리면 숨김)
          if (!panelOpen)
            Positioned(
              top: topPadding + 12,
              left: 16,
              right: 16,
              child: _buildSearchBar(),
            ),

          // 3. 우하단 버튼 그룹 (나침반 + 현재위치)
          Positioned(
            bottom: panelOpen
                ? MediaQuery.of(context).size.height * 0.5 + 16
                : 100,
            right: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'compass',
                  backgroundColor: _compassMode ? Colors.blue : Colors.white,
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

          // 4. 경로 패널 오버레이
          if (panelOpen)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: RouteOverlayPanel(
                dest: _routeDest!,
                origin: _routeOrigin,
                onClose: _onRoutePanelClose,
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
      onTap: () => _openRouteSearch(context),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // 길찾기 텍스트
            const Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.directions, color: Colors.blue, size: 20),
                    SizedBox(width: 10),
                    Text(
                      '길찾기',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
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
                onPressed: () => _startVoiceSearch(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRouteSearch(BuildContext context,
      {String initialQuery = ''}) async {
    final dest = await Navigator.push<PlaceResult>(
      context,
      MaterialPageRoute(
          builder: (_) =>
              RouteSearchScreen(initialQuery: initialQuery)),
    );
    if (dest == null || !context.mounted) return;
    _onDestSelected(dest);
  }

  Future<void> _startVoiceSearch(BuildContext context) async {
    final dest = await Navigator.push<PlaceResult>(
      context,
      MaterialPageRoute(
        builder: (_) => const RouteSearchScreen(autoStartMic: true),
      ),
    );
    if (dest == null || !context.mounted) return;
    _onDestSelected(dest);
  }
}
