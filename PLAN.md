# Plan: Venue Markers on Map Screen

## Goal
Show all venues (restaurant/cafe/convenience) on the existing Naver Map screen
as category-filtered markers. Tapping a marker shows a venue detail bottom sheet.

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
