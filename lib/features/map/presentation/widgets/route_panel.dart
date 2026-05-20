import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../data/map_repository.dart';

class RouteOverlayPanel extends ConsumerStatefulWidget {
  final PlaceResult dest;
  final VoidCallback onClose;
  final void Function(RouteResult result, RouteMode mode) onRouteLoaded;

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
  RouteMode _mode = RouteMode.walk;
  RouteResult? _result;
  bool _loading = false;
  String? _error;
  int _fetchVersion = 0;
  Position? _cachedPosition;

  @override
  void initState() {
    super.initState();
    _fetchRoute();
  }

  Future<void> _fetchRoute() async {
    final myVersion = ++_fetchVersion;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      _cachedPosition ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      if (myVersion != _fetchVersion || !mounted) return;

      final pos = _cachedPosition!;
      final result = await ref.read(mapRepositoryProvider).getRoute(
            mode: _mode,
            olat: pos.latitude,
            olng: pos.longitude,
            dlat: widget.dest.lat,
            dlng: widget.dest.lng,
          );

      if (myVersion != _fetchVersion || !mounted) return;

      setState(() {
        _result = result;
        _loading = false;
      });
      widget.onRouteLoaded(result, _mode);
    } catch (e) {
      if (myVersion != _fetchVersion || !mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _changeMode(RouteMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    _fetchRoute();
  }

  // ── Helpers ──────────────────────────────────────────────────

  String _modeLabel(RouteMode mode) => switch (mode) {
        RouteMode.walk => '도보',
        RouteMode.bike => '자전거',
        RouteMode.transit => '대중교통',
        RouteMode.car => '자동차',
      };

  String _modeEmoji(RouteMode mode) => switch (mode) {
        RouteMode.walk => '🚶',
        RouteMode.bike => '🚲',
        RouteMode.transit => '🚇',
        RouteMode.car => '🚗',
      };

  Color _modeColor(RouteMode mode) => switch (mode) {
        RouteMode.transit => const Color(0xFF1565C0),
        RouteMode.car => const Color(0xFFE53935),
        RouteMode.bike => const Color(0xFF2E7D32),
        RouteMode.walk => Colors.blue,
      };

  String _formatDuration(double seconds) {
    final m = (seconds / 60).round();
    if (m < 60) return '$m분';
    return '${m ~/ 60}시간 ${m % 60}분';
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  String _formatFare(int won) {
    if (won <= 0) return '';
    final s = won.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return '$s원';
  }

  Color _parseLegColor(String hexColor) {
    try {
      final hex = hexColor.startsWith('#') ? hexColor.substring(1) : hexColor;
      if (hex.length != 6) return Colors.blue;
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.blue;
    }
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    // Panel content height (excluding SafeArea bottom)
    final contentHeight = screenHeight * 0.5;

    return Container(
      height: contentHeight + bottomInset,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 12,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header: back + dest name + close
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: widget.onClose,
                  tooltip: '닫기',
                ),
                Expanded(
                  child: Text(
                    widget.dest.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          // Mode tabs
          _buildModeTabs(),
          const Divider(height: 1),
          // Scrollable result area
          Expanded(
            child: _buildContent(),
          ),
          SizedBox(height: bottomInset),
        ],
      ),
    );
  }

  Widget _buildModeTabs() {
    return Row(
      children: RouteMode.values.map((mode) {
        final isSelected = mode == _mode;
        return Expanded(
          child: GestureDetector(
            onTap: () => _changeMode(mode),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSelected ? Colors.blue : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_modeEmoji(mode),
                      style: const TextStyle(fontSize: 18)),
                  const SizedBox(height: 2),
                  Text(
                    _modeLabel(mode),
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected ? Colors.blue : Colors.grey,
                      fontWeight: isSelected
                          ? FontWeight.w600
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

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 32),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextButton(
                  onPressed: _fetchRoute, child: const Text('다시 시도')),
            ],
          ),
        ),
      );
    }
    if (_result == null) return const SizedBox.shrink();

    final result = _result!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Duration + Distance
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
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
          // Fare (transit only)
          if (_mode == RouteMode.transit && result.fare > 0) ...[
            const SizedBox(height: 4),
            Text(
              '요금 ${_formatFare(result.fare)}',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
          // Transit segment bar + legs
          if (_mode == RouteMode.transit && result.legs.isNotEmpty) ...[
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
        // Colored bar
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
                return Expanded(flex: flex, child: Container(color: color));
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Station names
        _buildStationNames(legs),
        const SizedBox(height: 10),
        // Leg chips row
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
              ]
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
          const Text('🚶', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 2),
          Text(
            _formatDuration(leg.durationSeconds.toDouble()),
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      );
    }
    final color = _parseLegColor(leg.color);
    final icon = leg.type == 'subway' ? '🚇' : '🚌';
    final label =
        leg.name.isEmpty ? _formatDuration(leg.durationSeconds.toDouble()) : leg.name;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        '$icon $label',
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w600),
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
                child:
                    Icon(Icons.arrow_forward, size: 12, color: Colors.grey),
              ),
            Text(
              stations[i],
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }
}
