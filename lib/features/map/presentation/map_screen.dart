import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:sensors_plus/sensors_plus.dart';
import '../data/map_repository.dart';
import '../../../features/restaurant/data/venue_repository.dart';
import '../../../features/restaurant/domain/venue.dart';
import '../../../features/restaurant/presentation/venue_detail_screen.dart';
import '../../../shared/providers/settings_provider.dart';
import 'route_search_screen.dart';
import 'widgets/route_panel.dart' show RouteOverlayPanel, resolveCurrentPosition;

// SNU 관악캠퍼스 중심 좌표
const _snuCenter = NLatLng(37.4607, 126.9526);

enum _SheetMode { none, placeDetail, routePanel, venueDetail }

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
  static const chipBg     = Color(0xFFF0F4FF);
  static const shadow     = Color(0x1F000000);
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
  int _markerGeneration = 0; // rapid-switching stale prevention

  @override
  void dispose() {
    _compassSub?.cancel();
    super.dispose();
  }

  // ── 위치 ────────────────────────────────────────────────────────

  Future<void> _initLocation() async {
    _mapCtrl?.setLocationTrackingMode(NLocationTrackingMode.noFollow);
    final pos = await resolveCurrentPosition();
    if (pos == null) return;
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

  // ── 나침반 ────────────────────────────────────────────────────────

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

  void _onVenueFilterTapped(VenueCategory cat, List<Venue> venues) {
    // 경로 패널이나 장소 상세가 열려 있으면 먼저 닫기
    if (_sheetMode == _SheetMode.routePanel ||
        _sheetMode == _SheetMode.placeDetail) {
      if (_sheetMode == _SheetMode.routePanel) _closeRoutePanel();
      if (_sheetMode == _SheetMode.placeDetail) _closePlaceDetail();
      return; // 닫고 나서 다음 탭에서 필터 적용
    }
    if (_sheetMode == _SheetMode.venueDetail) {
      setState(() { _sheetMode = _SheetMode.none; _selectedVenue = null; });
    }
    final newFilter = _venueFilter == cat ? null : cat;
    setState(() => _venueFilter = newFilter);
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
    final place = _selectedPlace ?? _venueToPlaceResult(_selectedVenue);
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
    final origin = _selectedPlace ?? _venueToPlaceResult(_selectedVenue);
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
    // 마커 복원
    final venues = ref.read(venuesProvider).valueOrNull ?? [];
    _applyVenueMarkers(venues);
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
    // 마커 복원
    final venues = ref.read(venuesProvider).valueOrNull ?? [];
    _applyVenueMarkers(venues);
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

    // venues가 로드 완료되면 선택된 필터가 있을 경우 마커 자동 적용
    ref.listen<AsyncValue<List<Venue>>>(venuesProvider, (_, next) {
      if (next.hasValue && _venueFilter != null) {
        _applyVenueMarkers(next.value!);
      }
    });

    final topPadding = MediaQuery.of(context).padding.top;
    final showSearchBar = _sheetMode == _SheetMode.none ||
        _sheetMode == _SheetMode.venueDetail;
    final showButtons = _sheetMode != _SheetMode.routePanel;
    final showFilterChips = _sheetMode == _SheetMode.none ||
        _sheetMode == _SheetMode.venueDetail;
    final bottomOffset = switch (_sheetMode) {
      _SheetMode.routePanel   => MediaQuery.of(context).size.height * 0.5 + 16,
      _SheetMode.placeDetail  => 200.0,
      _SheetMode.venueDetail  => 240.0,
      _SheetMode.none         => 100.0,
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
      borderRadius: BorderRadius.circular(12),
      elevation: 0,
      child: InkWell(
        onTap: () => _openSearch(),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: _MC.shadow,
                blurRadius: 12,
                spreadRadius: 1,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              const Icon(Icons.search, color: _MC.primary, size: 22),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '장소, 버스, 지하철, 주소 검색',
                  style: TextStyle(fontSize: 15, color: _MC.textHint),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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
    return Row(
      children: chips.map((c) {
        final selected = _venueFilter == c.cat;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => _onVenueFilterTapped(c.cat, venues),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? _MC.primary : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: _MC.shadow,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(c.icon,
                      size: 14,
                      color: selected ? Colors.white : _MC.textSub),
                  const SizedBox(width: 4),
                  Text(
                    c.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : _MC.textMain,
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
        const SizedBox(height: 16),
        _RouteButtons(onOrigin: _openAsOrigin, onDest: _openAsDest),
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
        const SizedBox(height: 16),
        // 버튼 행
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _openAsOrigin,
                icon: const Icon(Icons.my_location, size: 16),
                label: const Text('출발'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _MC.primary, side: const BorderSide(color: _MC.primary),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 44,
              child: FilledButton.icon(
                onPressed: _openAsDest,
                icon: const Icon(Icons.location_on, size: 16),
                label: const Text('길찾기'),
                style: FilledButton.styleFrom(backgroundColor: _MC.primary),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 44,
              child: OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => VenueDetailScreen(venue: venue)),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _MC.textMain, side: BorderSide(color: Colors.grey[300]!),
                ),
                child: const Text('상세보기'),
              ),
            ),
          ),
        ]),
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

// ── 출발/도착 버튼 ─────────────────────────────────────────────────
class _RouteButtons extends StatelessWidget {
  final VoidCallback onOrigin;
  final VoidCallback onDest;
  const _RouteButtons({required this.onOrigin, required this.onDest});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: onOrigin,
              icon: const Icon(Icons.my_location, size: 16),
              label: const Text('출발'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1A73E8),
                side: const BorderSide(color: Color(0xFF1A73E8)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: onDest,
              icon: const Icon(Icons.location_on, size: 16),
              label: const Text('도착'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1A73E8),
              ),
            ),
          ),
        ),
      ],
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
