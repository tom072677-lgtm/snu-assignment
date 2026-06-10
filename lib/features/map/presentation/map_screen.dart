import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' show Position, Geolocator;
import 'package:sensors_plus/sensors_plus.dart';
import '../data/map_repository.dart';
import '../../../features/partner/data/partner_repository.dart';
import '../../../features/partner/domain/partner_restaurant.dart';
import '../../../features/restaurant/data/venue_repository.dart';
import '../../../features/restaurant/domain/venue.dart';
import '../../../features/restaurant/presentation/venue_detail_screen.dart';
import '../../../shared/providers/settings_provider.dart';
import 'route_search_screen.dart';
import 'widgets/route_panel.dart'
    show RouteOverlayPanel, resolveCurrentPosition, LocationFailure;

// SNU 관악캠퍼스 중심 좌표
const _snuCenter = NLatLng(37.4607, 126.9526);

enum _SheetMode { none, placeDetail, routePanel, venueDetail, partnerDetail }
enum _MarkerMode { none, venue, partner }

/// 드래그 가능한 바텀시트 (NaverMap Stack 내에서 동작).
/// minHeight ↔ maxHeight 사이를 수직 드래그로 조절.
class _DraggableMapSheet extends StatefulWidget {
  final double minHeight;
  final double maxHeight;
  final Widget Function(ScrollController) builder;
  const _DraggableMapSheet({
    required this.minHeight,
    required this.maxHeight,
    required this.builder,
  });

  @override
  State<_DraggableMapSheet> createState() => _DraggableMapSheetState();
}

class _DraggableMapSheetState extends State<_DraggableMapSheet> {
  late double _height;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _height = widget.minHeight;
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: GestureDetector(
        onVerticalDragUpdate: (d) {
          setState(() {
            _height = (_height - d.delta.dy)
                .clamp(widget.minHeight, widget.maxHeight);
          });
        },
        onVerticalDragEnd: (_) {
          // 절반 이상 올리면 최대, 절반 이하면 최소로 스냅
          final mid = (widget.minHeight + widget.maxHeight) / 2;
          setState(() {
            _height = _height > mid ? widget.maxHeight : widget.minHeight;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: _height,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(color: Color(0x1F000000), blurRadius: 20, offset: Offset(0, -3)),
            ],
          ),
          child: Column(
            children: [
              // 드래그 핸들
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(child: widget.builder(_scrollCtrl)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 색상/치수 상수 ─────────────────────────────────────────────────
class _MC {
  _MC._();
  static const primary    = Color(0xFF1A73E8);
  static const textMain   = Color(0xFF191919);
  static const textSub    = Color(0xFF767676);
  static const textHint   = Color(0xFFAAAAAA);
}

Color _routeColor(RouteMode mode) => switch (mode) {
      RouteMode.transit => const Color(0xFF1565C0),
      RouteMode.car     => const Color(0xFFE53935),
      RouteMode.bike    => const Color(0xFF2E7D32),
      RouteMode.walk    => Colors.blue,
    };

// ── 카테고리별 마커 아이콘 ─────────────────────────────────────────
NOverlayImage _markerIcon(VenueCategory cat) => switch (cat) {
      VenueCategory.restaurant  => const NOverlayImage.fromAssetImage('assets/marker_restaurant.png'),
      VenueCategory.cafe        => const NOverlayImage.fromAssetImage('assets/marker_cafe.png'),
      VenueCategory.convenience => const NOverlayImage.fromAssetImage('assets/marker_convenience.png'),
    };

const _markerSize = Size(28, 28);

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with SingleTickerProviderStateMixin {
  NaverMapController? _mapCtrl;
  StreamSubscription<MagnetometerEvent>? _compassSub;
  double _heading = 0;
  bool _compassMode = false;
  Position? _initialPosition;

  // 시트 상태
  _SheetMode _sheetMode = _SheetMode.none;
  PlaceResult? _selectedPlace;
  PlaceResult? _routeDest;
  PlaceResult? _routeOrigin;

  // 식당/카페/편의점 마커
  VenueCategory? _venueFilter;
  Venue? _selectedVenue;
  PartnerRestaurant? _selectedPartner;
  _MarkerMode _markerMode = _MarkerMode.none;
  int _markerGeneration = 0; // rapid-switching stale prevention

  @override
  void dispose() {
    _compassSub?.cancel();
    super.dispose();
  }

  // ── 위치 ────────────────────────────────────────────────────────

  Future<void> _initLocation() async {
    _mapCtrl?.setLocationTrackingMode(NLocationTrackingMode.noFollow);
    final (pos, fail) = await resolveCurrentPosition();
    // 초기 시도는 조용히 (사유만 로그)
    if (pos == null) {
      debugPrint('[MapScreen._initLocation] 위치 실패: $fail');
      return;
    }
    _initialPosition = pos;
    _mapCtrl?.updateCamera(NCameraUpdate.withParams(
      target: NLatLng(pos.latitude, pos.longitude),
    ));
  }

  Future<void> _goToMyLocation() async {
    final (resolved, fail) = await resolveCurrentPosition();
    final pos = resolved ?? _initialPosition;
    if (pos == null) {
      debugPrint('[MapScreen._goToMyLocation] 위치 실패: $fail');
      if (!mounted) return;
      if (fail == LocationFailure.serviceDisabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('위치 서비스(GPS)를 켜주세요')),
        );
      } else if (fail == LocationFailure.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('위치 권한이 차단되어 있습니다'),
            action: SnackBarAction(
              label: '설정 열기',
              onPressed: () => Geolocator.openAppSettings(),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('위치 권한을 확인해 주세요')),
        );
      }
      return;
    }
    _initialPosition = pos;
    _mapCtrl?.updateCamera(NCameraUpdate.withParams(
      target: NLatLng(pos.latitude, pos.longitude),
      zoom: 16,
    ));
  }

  // ── 나침반 ────────────────────────────────────────────────────────

  void _startCompass() {
    // 자기장 이벤트는 초당 수십~수백 회 → 1도 미만 변화는 무시해 rebuild 폭주 방지
    _compassSub = magnetometerEventStream(
            samplingPeriod: SensorInterval.uiInterval)
        .listen((event) {
      final heading = math.atan2(event.y, event.x) * (180 / math.pi);
      if ((heading - _heading).abs() < 1) return;
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

  // ── 마커 관리 ─────────────────────────────────────────────────────

  Future<void> _clearVenueMarkers() async {
    final ctrl = _mapCtrl;
    if (ctrl == null) return;
    await ctrl.clearOverlays(type: NOverlayType.marker);
  }

  Future<void> _applyVenueMarkers(List<Venue> allVenues) async {
    final ctrl = _mapCtrl;
    if (ctrl == null) return;

    final gen = ++_markerGeneration;
    await ctrl.clearOverlays(type: NOverlayType.marker);

    final filter = _venueFilter;
    if (filter == null) return;

    var filtered = allVenues.where((v) => v.category == filter).toList();
    // 성능: 500개로 제한
    if (filtered.length > 500) {
      filtered = filtered.take(500).toList();
    }

    if (gen != _markerGeneration) return;

    final icon = _markerIcon(filter);
    final markers = filtered.map<NAddableOverlay>((venue) {
      final m = NMarker(
        id: 'venue_${venue.id}',
        position: NLatLng(venue.lat, venue.lng),
        icon: icon,
        size: _markerSize,
        caption: NOverlayCaption(text: venue.name, textSize: 10),
      );
      m.setOnTapListener((_) => _showVenueDetail(venue));
      return m;
    }).toSet();

    if (gen != _markerGeneration) return;

    await ctrl.addOverlayAll(markers);
  }

  VenueCategory _venueIconCategory(String category) => switch (category) {
    '카페' => VenueCategory.cafe,
    '편의점' => VenueCategory.convenience,
    _ => VenueCategory.restaurant,
  };

  Future<void> _applyPartnerMarkers(List<PartnerRestaurant> restaurants) async {
    final ctrl = _mapCtrl;
    if (ctrl == null) return;
    final gen = ++_markerGeneration;
    await ctrl.clearOverlays(type: NOverlayType.marker);
    if (gen != _markerGeneration) return;
    final markers = restaurants.map<NAddableOverlay>((r) {
      final m = NMarker(
        id: 'partner_${r.id}',
        position: NLatLng(r.lat!, r.lng!),
        icon: _markerIcon(_venueIconCategory(r.category)),
        size: const Size(32, 32),
        caption: NOverlayCaption(
          text: r.name,
          textSize: 10,
          color: const Color(0xFFE65100),
        ),
      );
      m.setOnTapListener((_) {
        if (mounted) _showPartnerDetail(r);
      });
      return m;
    }).toSet();
    if (gen != _markerGeneration) return;
    await ctrl.addOverlayAll(markers);
  }

  void _onPartnerChipTapped() {
    if (_sheetMode == _SheetMode.routePanel || _sheetMode == _SheetMode.placeDetail) {
      if (_sheetMode == _SheetMode.routePanel) _closeRoutePanel();
      if (_sheetMode == _SheetMode.placeDetail) _closePlaceDetail();
      return;
    }
    if (_sheetMode == _SheetMode.venueDetail) {
      setState(() { _sheetMode = _SheetMode.none; _selectedVenue = null; });
    }
    if (_sheetMode == _SheetMode.partnerDetail) {
      setState(() { _sheetMode = _SheetMode.none; _selectedPartner = null; });
    }
    final turning = _markerMode != _MarkerMode.partner;
    setState(() {
      _markerMode = turning ? _MarkerMode.partner : _MarkerMode.none;
      _venueFilter = null;
    });
    if (turning) {
      final partners = ref.read(partnerMapProvider).valueOrNull ?? [];
      _applyPartnerMarkers(partners);
    } else {
      _clearVenueMarkers();
    }
  }

  void _showPartnerDetail(PartnerRestaurant r) {
    setState(() {
      _sheetMode = _SheetMode.partnerDetail;
      _selectedPartner = r;
      _selectedVenue = null;
      _selectedPlace = null;
    });
    _mapCtrl?.updateCamera(NCameraUpdate.withParams(
      target: NLatLng(r.lat!, r.lng!),
      zoom: 16,
    ));
  }

  void _closePartnerDetail() {
    setState(() {
      _sheetMode = _SheetMode.none;
      _selectedPartner = null;
    });
  }

  PlaceResult? _partnerToPlaceResult(PartnerRestaurant? r) {
    if (r == null) return null;
    return PlaceResult(name: r.name, address: r.address, lat: r.lat!, lng: r.lng!, category: r.category);
  }

  void _restoreMarkers() {
    if (_markerMode == _MarkerMode.partner) {
      final partners = ref.read(partnerMapProvider).valueOrNull ?? [];
      _applyPartnerMarkers(partners);
    } else if (_markerMode == _MarkerMode.venue && _venueFilter != null) {
      final venues = ref.read(venuesProvider).valueOrNull ?? [];
      _applyVenueMarkers(venues);
    }
  }

  void _onVenueFilterTapped(VenueCategory cat, List<Venue> venues) {
    if (_sheetMode == _SheetMode.routePanel ||
        _sheetMode == _SheetMode.placeDetail) {
      if (_sheetMode == _SheetMode.routePanel) _closeRoutePanel();
      if (_sheetMode == _SheetMode.placeDetail) _closePlaceDetail();
      return;
    }
    if (_sheetMode == _SheetMode.venueDetail) {
      setState(() { _sheetMode = _SheetMode.none; _selectedVenue = null; });
    }
    if (_sheetMode == _SheetMode.partnerDetail) {
      setState(() { _sheetMode = _SheetMode.none; _selectedPartner = null; });
    }
    final newFilter = _venueFilter == cat ? null : cat;
    setState(() {
      _venueFilter = newFilter;
      _markerMode = newFilter != null ? _MarkerMode.venue : _MarkerMode.none;
    });
    if (newFilter != null) {
      _mapCtrl?.updateCamera(NCameraUpdate.withParams(target: _snuCenter, zoom: 15));
    }
    _applyVenueMarkers(venues);
  }

  // ── 상태 전환 ─────────────────────────────────────────────────────

  Future<void> _showPlaceDetail(PlaceResult place) async {
    if (_sheetMode == _SheetMode.routePanel) {
      await _mapCtrl?.clearOverlays();
    }
    // 마커 모두 지우고 poi_marker만
    await _clearVenueMarkers();
    if (!mounted) return; // await 사이 화면 이탈 시 setState-after-dispose 방지
    setState(() {
      _sheetMode = _SheetMode.placeDetail;
      _selectedPlace = place;
      _selectedVenue = null;
      _routeDest = null;
      _routeOrigin = null;
    });
    await _mapCtrl?.addOverlay(NMarker(
      id: 'poi_marker',
      position: NLatLng(place.lat, place.lng),
    ));
    _mapCtrl?.updateCamera(NCameraUpdate.withParams(
      target: NLatLng(place.lat, place.lng),
      zoom: 15,
    ));
  }

  void _showVenueDetail(Venue venue) {
    setState(() {
      _sheetMode = _SheetMode.venueDetail;
      _selectedVenue = venue;
      _selectedPlace = null;
    });
    _mapCtrl?.updateCamera(NCameraUpdate.withParams(
      target: NLatLng(venue.lat, venue.lng),
      zoom: 16,
    ));
  }

  void _openAsDest() {
    final place = _selectedPlace ?? _venueToPlaceResult(_selectedVenue) ?? _partnerToPlaceResult(_selectedPartner);
    if (place == null) return;
    _clearVenueMarkers();
    _mapCtrl?.clearOverlays();
    setState(() {
      _sheetMode = _SheetMode.routePanel;
      _routeDest = place;
      _routeOrigin = null;
      _selectedPlace = null;
      _selectedVenue = null;
    });
  }

  Future<void> _openAsOrigin() async {
    final origin = _selectedPlace ?? _venueToPlaceResult(_selectedVenue) ?? _partnerToPlaceResult(_selectedPartner);
    if (origin == null) return;
    final dest = await Navigator.push<PlaceResult>(
      context,
      MaterialPageRoute(builder: (_) => const RouteSearchScreen()),
    );
    if (dest == null || !mounted) return;
    _clearVenueMarkers();
    await _mapCtrl?.clearOverlays();
    setState(() {
      _sheetMode = _SheetMode.routePanel;
      _routeDest = dest;
      _routeOrigin = origin;
      _selectedPlace = null;
      _selectedVenue = null;
    });
  }

  void _closePlaceDetail() {
    _mapCtrl?.clearOverlays();
    setState(() {
      _sheetMode = _SheetMode.none;
      _selectedPlace = null;
    });
    _restoreMarkers();
  }

  void _closeVenueDetail() {
    // 마커는 그대로, 시트만 닫기
    setState(() {
      _sheetMode = _SheetMode.none;
      _selectedVenue = null;
    });
  }

  void _closeRoutePanel() {
    _mapCtrl?.clearOverlays();
    setState(() {
      _sheetMode = _SheetMode.none;
      _routeDest = null;
      _routeOrigin = null;
    });
    _restoreMarkers();
  }

  PlaceResult? _venueToPlaceResult(Venue? v) {
    if (v == null) return null;
    return PlaceResult(
      name: v.name,
      address: v.address,
      lat: v.lat,
      lng: v.lng,
      category: v.category.name,
    );
  }

  // ── 지도 오버레이 ──────────────────────────────────────────────────

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
    await ctrl.updateCamera(NCameraUpdate.fitBounds(
      bounds,
      padding: const EdgeInsets.fromLTRB(40, 100, 40, 114),
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
    final venuesAsync = ref.watch(venuesProvider);
    final venues = venuesAsync.valueOrNull ?? [];

    ref.listen<AsyncValue<List<Venue>>>(venuesProvider, (_, next) {
      if (next.hasValue && _markerMode == _MarkerMode.venue) {
        _applyVenueMarkers(next.value!);
      }
    });
    ref.listen<AsyncValue<List<PartnerRestaurant>>>(partnerMapProvider, (_, next) {
      if (next.hasValue && _markerMode == _MarkerMode.partner) {
        _applyPartnerMarkers(next.value!);
      }
    });

    final topPadding = MediaQuery.of(context).padding.top;
    final showSearchBar = _sheetMode == _SheetMode.none ||
        _sheetMode == _SheetMode.venueDetail ||
        _sheetMode == _SheetMode.partnerDetail;
    final showButtons = _sheetMode != _SheetMode.routePanel;
    final showFilterChips = _sheetMode == _SheetMode.none ||
        _sheetMode == _SheetMode.venueDetail ||
        _sheetMode == _SheetMode.partnerDetail;
    final bottomOffset = switch (_sheetMode) {
      _SheetMode.routePanel    => MediaQuery.of(context).size.height * 0.5 + 16,
      _SheetMode.placeDetail   => 200.0,
      _SheetMode.venueDetail   => 240.0,
      _SheetMode.partnerDetail => 260.0,
      _SheetMode.none          => 100.0,
    };

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
              if (_sheetMode == _SheetMode.venueDetail) _closeVenueDetail();
              if (_sheetMode == _SheetMode.partnerDetail) _closePartnerDetail();
            },
          ),

          // 2. 검색 바 + 카테고리 필터 칩
          if (showSearchBar)
            Positioned(
              top: topPadding + 10,
              left: 12,
              right: 12,
              child: Column(
                children: [
                  _buildSearchBar(),
                  if (showFilterChips) ...[
                    const SizedBox(height: 8),
                    _buildCategoryChips(venues),
                  ],
                ],
              ),
            ),

          // 3. 우하단 버튼 그룹
          if (showButtons)
            Positioned(
              bottom: bottomOffset,
              right: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MapControlButton(
                    tooltip: '나침반',
                    active: _compassMode,
                    onPressed: _toggleCompass,
                    child: Transform.rotate(
                      angle: _heading * (math.pi / 180),
                      child: Icon(
                        Icons.explore,
                        size: 22,
                        color: _compassMode ? _MC.primary : _MC.textSub,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _MapControlButton(
                    tooltip: '내 위치',
                    active: false,
                    onPressed: _goToMyLocation,
                    child: const Icon(
                      Icons.near_me,
                      size: 22,
                      color: _MC.primary,
                    ),
                  ),
                ],
              ),
            ),

          // 4. POI 상세 시트 (드래그 가능)
          if (_sheetMode == _SheetMode.placeDetail && _selectedPlace != null)
            _DraggableMapSheet(
              minHeight: 230,
              maxHeight: 360,
              builder: (scroll) => _buildPlaceDetailContent(_selectedPlace!, scroll),
            ),

          // 5. Venue 상세 시트 (드래그 가능)
          if (_sheetMode == _SheetMode.venueDetail && _selectedVenue != null)
            _DraggableMapSheet(
              minHeight: 260,
              maxHeight: 420,
              builder: (scroll) => _buildVenueDetailContent(_selectedVenue!, scroll),
            ),

          // 5b. 제휴 식당 상세 시트
          if (_sheetMode == _SheetMode.partnerDetail && _selectedPartner != null)
            _DraggableMapSheet(
              minHeight: 260,
              maxHeight: 420,
              builder: (scroll) => _buildPartnerDetailContent(_selectedPartner!, scroll),
            ),

          // 6. 경로 패널
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

  // ── 검색 바 ───────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      elevation: 0,
      child: InkWell(
        onTap: () => _openSearch(),
        borderRadius: BorderRadius.circular(28),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x28000000),
                blurRadius: 16,
                spreadRadius: 0,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 18),
              const Icon(Icons.search, color: _MC.primary, size: 22),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '장소, 버스, 지하철, 주소 검색',
                  style: TextStyle(fontSize: 15, color: _MC.textHint),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(width: 1, height: 20, color: const Color(0xFFE0E0E0)),
              IconButton(
                icon: const Icon(Icons.mic_none, color: _MC.textSub, size: 22),
                tooltip: '음성 검색',
                onPressed: () => _openSearch(voiceMode: true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 카테고리 필터 칩 ─────────────────────────────────────────────

  Widget _buildCategoryChips(List<Venue> venues) {
    const chips = [
      (cat: VenueCategory.restaurant,  label: '음식점',  icon: Icons.restaurant),
      (cat: VenueCategory.cafe,        label: '카페',    icon: Icons.local_cafe),
      (cat: VenueCategory.convenience, label: '편의점',  icon: Icons.store),
    ];
    final partnerSelected = _markerMode == _MarkerMode.partner;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ...chips.map((c) {
            final selected = _venueFilter == c.cat;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => _onVenueFilterTapped(c.cat, venues),
                child: _FilterChip(
                  label: c.label,
                  icon: c.icon,
                  selected: selected,
                ),
              ),
            );
          }),
          GestureDetector(
            onTap: _onPartnerChipTapped,
            child: _FilterChip(
              label: '제휴 할인',
              icon: Icons.local_offer_outlined,
              selected: partnerSelected,
              selectedColor: const Color(0xFFE65100),
            ),
          ),
        ],
      ),
    );
  }

  // ── 제휴 식당 상세 콘텐츠 ─────────────────────────────────────────

  Widget _buildPartnerDetailContent(PartnerRestaurant r, ScrollController scroll) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(r.name,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _MC.textMain)),
            ),
            GestureDetector(
              onTap: _closePartnerDetail,
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.close, size: 20, color: _MC.textSub),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [
          _Chip(label: r.category, color: const Color(0xFFE65100)),
        ]),
        if (r.address.isNotEmpty) ...[
          const SizedBox(height: 8),
          _AddressRow(address: r.address),
        ],
        if (r.phone != null) ...[
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.phone_outlined, size: 14, color: _MC.textHint),
            const SizedBox(width: 4),
            Text(r.phone!, style: const TextStyle(fontSize: 13, color: _MC.textSub)),
          ]),
        ],
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFFE082)),
          ),
          child: Row(children: [
            const Text('🎁', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(r.benefit,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF5D4037))),
            ),
          ]),
        ),
        if (r.couponCode?.isNotEmpty == true) ...[
          const SizedBox(height: 8),
          _MapCouponRow(code: r.couponCode!),
        ],
        const Divider(height: 28, color: Color(0xFFF0F0F0)),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ActionButton(
              icon: Icons.my_location,
              label: '출발',
              onTap: _openAsOrigin,
            ),
            _ActionButton(
              icon: Icons.directions,
              label: '길찾기',
              onTap: _openAsDest,
            ),
          ],
        ),
        SizedBox(height: 16 + bottomInset),
      ],
    );
  }

  // ── POI 상세 콘텐츠 (DraggableMapSheet 내부) ─────────────────────

  Widget _buildPlaceDetailContent(PlaceResult place, ScrollController scroll) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      children: [
        // 제목 + 닫기
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(place.name,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700, color: _MC.textMain)),
            ),
            GestureDetector(
              onTap: _closePlaceDetail,
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.close, size: 20, color: _MC.textSub),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (place.category.isNotEmpty) _Chip(label: place.category),
        if (place.address.isNotEmpty) ...[
          const SizedBox(height: 8),
          _AddressRow(address: place.address),
        ],
        const Divider(height: 28, color: Color(0xFFF0F0F0)),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ActionButton(
              icon: Icons.my_location,
              label: '출발',
              onTap: _openAsOrigin,
            ),
            _ActionButton(
              icon: Icons.location_on,
              label: '도착',
              onTap: _openAsDest,
            ),
          ],
        ),
        SizedBox(height: 16 + bottomInset),
      ],
    );
  }

  // ── Venue 상세 콘텐츠 (DraggableMapSheet 내부) ───────────────────

  Widget _buildVenueDetailContent(Venue venue, ScrollController scroll) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final now = DateTime.now();
    final isOpen = venue.isOpenAt(now);
    final hoursText = venue.todayHoursText(now);
    final isFav = ref.watch(favVenuesProvider).contains(venue.id);

    String catLabel;
    Color catColor;
    switch (venue.category) {
      case VenueCategory.restaurant:
        catLabel = '음식점'; catColor = Colors.orange[700]!;
      case VenueCategory.cafe:
        catLabel = '카페'; catColor = _MC.primary;
      case VenueCategory.convenience:
        catLabel = '편의점'; catColor = Colors.green[700]!;
    }

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      children: [
        // 이름 + 영업중 배지 + 닫기
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(venue.name,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700, color: _MC.textMain)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isOpen
                    ? Colors.green.withValues(alpha: 0.12)
                    : Colors.grey.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isOpen ? '영업중' : '준비중',
                style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600,
                  color: isOpen ? Colors.green[700] : Colors.grey[600],
                ),
              ),
            ),
            const SizedBox(width: 6),
            // 즐겨찾기 버튼
            GestureDetector(
              onTap: () => ref.read(favVenuesProvider.notifier).toggle(venue.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  isFav ? Icons.favorite : Icons.favorite_border,
                  color: isFav ? Colors.red : _MC.textSub,
                  size: 22,
                ),
              ),
            ),
            GestureDetector(
              onTap: _closeVenueDetail,
              child: const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.close, size: 20, color: _MC.textSub),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 카테고리 + 지역 + 가격
        Wrap(
          spacing: 6,
          children: [
            _Chip(label: catLabel, color: catColor),
            _Chip(label: venue.area),
            if (venue.priceLevel != null)
              _Chip(label: '₩' * venue.priceLevel!, color: Colors.green[700]!),
          ],
        ),
        const SizedBox(height: 8),
        if (venue.address.isNotEmpty) _AddressRow(address: venue.address),
        if (hoursText != null) ...[
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.access_time_outlined, size: 14, color: _MC.textHint),
            const SizedBox(width: 4),
            Text(hoursText, style: const TextStyle(fontSize: 13, color: _MC.textSub)),
          ]),
        ],
        if (venue.phone != null) ...[
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.phone_outlined, size: 14, color: _MC.textHint),
            const SizedBox(width: 4),
            Text(venue.phone!, style: const TextStyle(fontSize: 13, color: _MC.textSub)),
          ]),
        ],
        const Divider(height: 28, color: Color(0xFFF0F0F0)),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ActionButton(
              icon: Icons.my_location,
              label: '출발',
              onTap: _openAsOrigin,
            ),
            _ActionButton(
              icon: Icons.directions,
              label: '길찾기',
              onTap: _openAsDest,
            ),
            _ActionButton(
              icon: Icons.article_outlined,
              label: '상세보기',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => VenueDetailScreen(venue: venue)),
              ),
              color: _MC.textSub,
            ),
          ],
        ),
        SizedBox(height: 16 + bottomInset),
      ],
    );
  }
}

// ── 작은 칩 ──────────────────────────────────────────────────────
class _Chip extends StatelessWidget {
  final String label;
  final Color? color;
  const _Chip({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF1A73E8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12, color: c, fontWeight: FontWeight.w500)),
    );
  }
}

// ── 주소 행 ───────────────────────────────────────────────────────
class _AddressRow extends StatelessWidget {
  final String address;
  const _AddressRow({required this.address});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.place_outlined, size: 14, color: Color(0xFFAAAAAA)),
        const SizedBox(width: 4),
        Expanded(
          child: Text(address,
              style:
                  const TextStyle(fontSize: 13, color: Color(0xFF767676))),
        ),
      ],
    );
  }
}

// ── 필터 칩 (검색바 아래) ────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color? selectedColor;
  const _FilterChip({required this.label, required this.icon, required this.selected, this.selectedColor});

  @override
  Widget build(BuildContext context) {
    final color = selectedColor ?? const Color(0xFF1A73E8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? color : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? color : const Color(0xFFDDDDDD),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: selected
                ? color.withValues(alpha: 0.25)
                : const Color(0x14000000),
            blurRadius: selected ? 8 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: selected ? Colors.white : const Color(0xFF555555)),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: selected ? Colors.white : const Color(0xFF333333))),
        ],
      ),
    );
  }
}

// ── Naver 스타일 액션 버튼 (아이콘 원 + 라벨) ─────────────────────
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _ActionButton({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF1A73E8);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: c, size: 24),
          ),
          const SizedBox(height: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: c, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── 제휴 쿠폰 코드 행 ────────────────────────────────────────────
class _MapCouponRow extends StatelessWidget {
  final String code;
  const _MapCouponRow({required this.code});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: code));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('쿠폰코드가 복사됐어요'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF81C784)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.confirmation_num_outlined, size: 13, color: Color(0xFF388E3C)),
            const SizedBox(width: 5),
            Text('코드: $code', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF388E3C))),
            const SizedBox(width: 8),
            const Icon(Icons.copy, size: 12, color: Color(0xFF388E3C)),
          ],
        ),
      ),
    );
  }
}

// ── 지도 컨트롤 버튼 ─────────────────────────────────────────────
class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.tooltip,
    required this.active,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final bool active;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        shape: const CircleBorder(),
        color: Colors.white,
        elevation: 4,
        shadowColor: const Color(0x1F000000),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
