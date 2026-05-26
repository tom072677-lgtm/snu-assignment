# 샤랍 개선 계획 v2

## 목표
1. 코덱스 리뷰 기반 취약점/개선사항 수정
2. 폭탄 카운트다운 UI (24시간 이내 과제 시 고정 배너)
3. 다크모드 제거 (라이트 전용)
4. 지도 탭 UX 개선 (네이버 지도 스타일)

---

## 1. 코드 취약점 / 개선사항

### A. 서버 (index.js)
- **sentKeys 영속성 없음**: 재시작 시 이미 발송한 알림 키를 잃어 중복 발송 가능. → MongoDB TTL 컬렉션으로 보완.
- **버스 디버그 엔드포인트 `/api/debug/bus-raw` 노출**: 프로덕션에서 API 키 일부 노출. → 삭제.
- **fcmTokenStore 메모리 기반**: 재시작 시 모든 토큰 유실 → MongoDB에서 이미 로드하므로 OK, sentKeys만 문제.

### B. Flutter (client)
- **`syncTasksForNotification` 미호출**: assignments_screen에서 과제 로드 시 서버 동기화 안 됨 → 24h/5h/1h FCM 알림 미작동의 근본 원인. → `assignmentsProvider` 데이터 로드 시 자동 동기화 추가.
- **다크모드 코드 잔재**: ThemeModeNotifier, darkTheme() → 제거.

---

## 2. 폭탄 카운트다운 UI

### 요구사항
- 24시간 이내 마감 과제가 있으면 assignments_screen 상단에 배너 표시
- 💣 이모지가 진행 바 위에서 이동 (24h=왼쪽, 0h=오른쪽)
- 절대 닫기 불가 (dismiss 없음)
- 여러 과제 중 가장 촉박한 것 기준
- 1분마다 업데이트

### 구현 구조
BombCountdownBanner (Stateful, Timer 1분)
  ├── 진행 바: 0.0(24h) → 1.0(0h), LinearProgressIndicator
  ├── 💣 이모지: Stack + Positioned으로 이동
  └── 과제 제목 + 남은 시간 텍스트

---

## 3. 다크모드 제거

- `app.dart`: darkTheme 파라미터 제거, ThemeMode.light 고정
- `core/theme.dart`: darkTheme() 함수 삭제
- `settings_provider.dart`: ThemeModeNotifier 및 themeModeProvider 제거
- `settings_drawer.dart`: 테마 토글 UI 제거

---

## 4. 지도 탭 UX 개선 (네이버지도 스타일)

### 개선 사항
1. DraggableScrollableSheet: placeDetail, venueDetail 시트를 드래그 가능으로 교체
2. 장소 상세 즐겨찾기 버튼: 하트 아이콘
3. 검색창 하단 바로가기: "집" 즐겨찾기 장소 빠른 접근 칩
4. 경로 진입 개선: 맵 탭 시 키보드 자동 해제
5. 버튼 정렬: 네이버지도 기준으로 우하단 컨트롤 정리

---

## 성공 기준

- [ ] 서버: /api/debug/bus-raw 삭제 후 404
- [ ] 앱: 다크모드 설정 없음
- [ ] 앱: 24h 이내 과제 → 폭탄 배너 표시, 닫기 불가
- [ ] 앱: 지도 바텀시트 드래그 가능
- [ ] 빌드/설치 성공

## Existing Architecture
- `MapScreen` in `lib/features/map/presentation/map_screen.dart`
- Uses `flutter_naver_map` (`NaverMap`, `NMarker`, `NLatLng`)
- `_SheetMode` enum controls sheet state (none / placeDetail / routePanel)
- `venuesProvider` in `lib/features/restaurant/data/venue_repository.dart`
  returns `AsyncValue<List<Venue>>`
- `Venue` model in `lib/features/restaurant/domain/venue.dart`
- `VenueDetailScreen` in `lib/features/restaurant/presentation/venue_detail_screen.dart`

## Changes Required

### 1. `_SheetMode` — add `venueDetail`
```dart
enum _SheetMode { none, placeDetail, routePanel, venueDetail }
```

### 2. State additions to `_MapScreenState`
```dart
VenueCategory? _venueFilter;   // null = no venue markers shown
Venue? _selectedVenue;
final _venueMarkerIds = <String>{};  // track added marker IDs for removal
```

### 3. Category filter chips row
Horizontal chip row shown ONLY when sheetMode == none.
Chips: 음식점 (Icons.restaurant), 카페 (Icons.local_cafe), 편의점 (Icons.store_mall_directory).
Tapping same chip again deselects → clears markers.

### 4. `_applyVenueFilter(VenueCategory? cat, List<Venue> venues)`
- Remove existing venue markers by ID
- If cat is null: done
- Filter venues by category, add NMarker per venue
- NMarker color: restaurant=orange, cafe=blue, convenience=green (via NOverlayImage)
- `marker.setOnTapListener((_) => _showVenueDetail(venue))`
- Max markers: if category total > 500, skip (show warning). In practice:
  convenience ~82 → ok, cafe ~270 → ok, restaurant ~800 → cap at 500 nearest to center

### 5. `_showVenueDetail(Venue venue)`
```dart
setState(() {
  _sheetMode = _SheetMode.venueDetail;
  _selectedVenue = venue;
  _selectedPlace = null;
});
// Pan map to venue
_mapCtrl?.updateCamera(NCameraUpdate.withParams(
  target: NLatLng(venue.lat, venue.lng), zoom: 16,
));
```

### 6. `_buildVenueDetailSheet(Venue venue)`
Reuse existing `_buildPlaceDetailSheet` style. Shows:
- Name + area badge (서울대입구/대학동/교내)
- Category chip (음식점/카페/편의점)
- Hours today (from venue.todayHoursText), open/closed badge
- Phone number
- Price level (₩/₩₩/₩₩₩)
- "길찾기" button → converts Venue to PlaceResult → opens route panel
- "상세보기" button → Navigator.push to VenueDetailScreen

### 7. `_closeVenueDetail()`
```dart
setState(() {
  _sheetMode = _SheetMode.none;
  _selectedVenue = null;
});
// Do NOT clear overlays — keep venue markers visible
```

### 8. Integrate with `build()` — consume venuesProvider
```dart
// At top of build():
final venuesAsync = ref.watch(venuesProvider);
final venues = venuesAsync.valueOrNull ?? [];
```
Pass venues to `_applyVenueFilter` when filter changes.

## Performance Notes
- restaurant: ~800 markers → cap at 500 sorted by distance from current camera center
- cafe: ~270 → all ok
- convenience: ~82 → all ok
- Use `NOverlayImage.fromWidget` for custom icon, or simpler `NOverlayImage.fromAssetImage`
  if custom PNG markers are available. Fall back to default colored NMarker if needed.
- Marker updates are async (addOverlay is async) — do them in a single batch

## Success Criteria
- Selecting 음식점 chip shows orange restaurant markers on the map
- Selecting 카페 chip clears restaurant markers, shows blue cafe markers
- Tapping a marker shows venue detail sheet with hours/phone/price
- "길찾기" button opens existing route panel with venue as destination
- "상세보기" opens VenueDetailScreen
- Deselecting chip clears markers
- No crash or freeze with 800 restaurant markers
