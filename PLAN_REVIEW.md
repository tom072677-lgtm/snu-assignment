I’ll validate the plan against the actual map and venue code so the feedback is grounded in this repo, not just the text of the plan.
`rg` is not installed in this PowerShell environment, so I’m using direct file reads and PowerShell search instead. One immediate thing I see: the file is already mojibake-encoded in comments/labels, so the plan’s broken Korean text is not just cosmetic if new UI copy is added.
The repo already has `assets/marker_restaurant.png` and `assets/marker_cafe.png`, but I don’t see a convenience marker asset in that first asset scan. I’m checking the map plugin API surface next because the plan depends on marker removal and colored icon creation.
**Overall verdict: needs revision**
System.Management.Automation.RemoteException
**1. Problems or risks in the plan**
- `MapScreen` is currently a plain `StatefulWidget`, so `ref.watch(venuesProvider)` will not compile unless the screen is converted to `ConsumerStatefulWidget` / `ConsumerState` or wrapped in a `Consumer`.
- Existing map code calls `clearOverlays()` in several flows: place detail, route panel, route load, close handlers. That will accidentally remove venue markers and make `_venueMarkerIds` stale unless overlay ownership is redesigned.
- Applying markers only when the chip is tapped misses the async case: if `venuesProvider` is still loading, the filter can be selected but markers never appear after data arrives. Use `ref.listen` or another explicit post-load apply path; avoid async map mutations directly inside `build()`.
- Tracking marker IDs alone is incomplete. `deleteOverlay` needs `NOverlayInfo(type: NOverlayType.marker, id: id)`, and IDs should be prefixed, e.g. `venue_${venue.id}`, to avoid collisions with `poi_marker` / `dest_marker`.
- The performance note is internally inconsistent: it says skip if category total > 500, but then says restaurant ~800 should cap at nearest 500. Pick one behavior. Capping nearest 500 is better than skipping all restaurants.
- `venue.todayHoursText` is a method requiring `DateTime`, not a property: use `venue.todayHoursText(DateTime.now())`.
- `NOverlayImage.fromWidget` is heavier and async; for 500 markers this is risky. The repo already has `assets/marker_restaurant.png` and `assets/marker_cafe.png`, but no convenience marker asset listed in `pubspec.yaml`.
System.Management.Automation.RemoteException
**2. Missing edge cases**
- Map controller not ready when venues load or chip is tapped.
- Provider loading/error/empty states, including retry after failure.
- Rapid chip switching while async marker add/remove is still running. Add a generation token or cancel stale updates.
- Closing route panel: should the selected venue filter markers be restored or remain cleared?
- Search/POI selection while venue markers are visible: should venue markers stay, hide, or clear?
- `onMapTapped` currently closes only `placeDetail` and `routePanel`; it must handle `venueDetail`.
- `bottomOffset` and visible control placement need a `venueDetail` case so buttons do not overlap the new sheet.
- If nearest-500 sorting is used, define the camera center source and fallback before the map is ready.
System.Management.Automation.RemoteException
**3. Simpler alternatives**
- Use existing asset markers where available and default tinted `NMarker` for convenience, instead of `fromWidget`.
- Use `addOverlayAll(Set<NAddableOverlay>)` for marker batches instead of awaiting hundreds of `addOverlay` calls.
- Add small helpers only inside `MapScreen`: `_venueToPlaceResult`, `_clearVenueMarkers`, `_showVenueRoute`. No shared abstraction needed yet.
- Consider `NClusterableMarker` later, but for this change a simple capped marker set is enough.
System.Management.Automation.RemoteException
**4. Recommended revision**
Revise the plan to explicitly cover Riverpod integration, async marker lifecycle, overlay clearing interactions, and route/search behavior. After those are defined, the implementation is reasonable.
SUCCESS: The process with PID 37452 (child process of PID 33832) has been terminated.
SUCCESS: The process with PID 33832 (child process of PID 24368) has been terminated.