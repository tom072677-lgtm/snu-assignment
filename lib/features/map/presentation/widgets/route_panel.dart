import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../data/map_repository.dart';

class RoutePanel extends ConsumerStatefulWidget {
  final NaverMapController? mapCtrl;
  final String? initialDestName;
  final double? initialDestLat;
  final double? initialDestLng;

  const RoutePanel({
    super.key,
    required this.mapCtrl,
    this.initialDestName,
    this.initialDestLat,
    this.initialDestLng,
  });

  @override
  ConsumerState<RoutePanel> createState() => _RoutePanelState();
}

class _RoutePanelState extends ConsumerState<RoutePanel> {
  final _destCtrl = TextEditingController();
  List<PlaceResult> _suggestions = [];
  PlaceResult? _selectedDest;
  String _mode = 'walk';
  RouteResult? _routeResult;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialDestName != null) {
      _destCtrl.text = widget.initialDestName!;
      if (widget.initialDestLat != null && widget.initialDestLng != null) {
        _selectedDest = PlaceResult(
          name: widget.initialDestName!,
          address: '',
          lat: widget.initialDestLat!,
          lng: widget.initialDestLng!,
          category: '',
        );
      }
    }
  }

  @override
  void dispose() {
    _destCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    final repo = ref.read(mapRepositoryProvider);
    try {
      final results = await repo.searchPlace(q, null, null);
      setState(() => _suggestions = results.take(5).toList());
    } catch (_) {
      setState(() => _suggestions = []);
    }
  }

  Future<void> _getRoute() async {
    if (_selectedDest == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _routeResult = null;
    });

    try {
      Position pos = await Geolocator.getCurrentPosition();
      final repo = ref.read(mapRepositoryProvider);
      final profile = _mode == 'bike' ? 'cycling' : 'foot';
      final result = await repo.getOsrmRoute(
        profile: profile,
        olat: pos.latitude,
        olng: pos.longitude,
        dlat: _selectedDest!.lat,
        dlng: _selectedDest!.lng,
      );
      setState(() => _routeResult = result);

      // 지도에 경로 그리기
      if (widget.mapCtrl != null && result.path.isNotEmpty) {
        final polyline = NPolylineOverlay(
          id: 'route',
          coords: result.path
              .map((p) => NLatLng(p.$1, p.$2))
              .toList(),
          color: Colors.blue,
          width: 4,
        );
        await widget.mapCtrl!.addOverlay(polyline);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  String _formatDuration(double seconds) {
    final m = (seconds / 60).round();
    if (m < 60) return '$m분';
    return '${m ~/ 60}시간 ${m % 60}분';
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, scroll) => Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text('길찾기',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.my_location, color: Colors.blue, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                        child: Text('현재 위치',
                            style: TextStyle(color: Colors.grey))),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _destCtrl,
                        decoration: const InputDecoration(
                          hintText: '도착지 검색',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: _search,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 검색 제안
          if (_suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: _suggestions.map((p) {
                  return ListTile(
                    dense: true,
                    title: Text(p.name),
                    subtitle: Text(p.address,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      _destCtrl.text = p.name;
                      setState(() {
                        _selectedDest = p;
                        _suggestions = [];
                      });
                    },
                  );
                }).toList(),
              ),
            ),
          // 이동 수단 선택
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ModeBtn(icon: '🚶', label: '도보', value: 'walk', current: _mode,
                    onTap: () => setState(() => _mode = 'walk')),
                _ModeBtn(icon: '🚲', label: '자전거', value: 'bike', current: _mode,
                    onTap: () => setState(() => _mode = 'bike')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton(
              onPressed: _selectedDest == null ? null : _getRoute,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44)),
              child: const Text('길찾기'),
            ),
          ),
          const SizedBox(height: 8),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          if (_routeResult != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _formatDuration(_routeResult!.durationSeconds),
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    _formatDistance(_routeResult!.distanceMeters),
                    style: const TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ModeBtn extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  final String current;
  final VoidCallback onTap;

  const _ModeBtn({
    required this.icon,
    required this.label,
    required this.value,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == current;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: isSelected ? Colors.white : Colors.black87)),
          ],
        ),
      ),
    );
  }
}
