import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'widgets/route_panel.dart';

// SNU 관악캠퍼스 중심 좌표
const _snuCenter = NLatLng(37.4607, 126.9526);

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

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

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
        perm == LocationPermission.deniedForever) return;

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      _initialPosition = pos;
      // 지도가 이미 준비된 경우 즉시 이동
      _mapCtrl?.updateCamera(NCameraUpdate.withParams(
        target: NLatLng(pos.latitude, pos.longitude),
      ));
    } catch (_) {}
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
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
              controller.setLocationTrackingMode(NLocationTrackingMode.noFollow);
              // 위치를 이미 받은 경우 즉시 이동, 아니면 _initLocation 완료 시 이동
              if (_initialPosition != null) {
                controller.updateCamera(NCameraUpdate.withParams(
                  target: NLatLng(
                    _initialPosition!.latitude,
                    _initialPosition!.longitude,
                  ),
                ));
              }
            },
          ),
          // 나침반 버튼
          Positioned(
            bottom: 100,
            right: 12,
            child: FloatingActionButton.small(
              heroTag: 'compass',
              backgroundColor: _compassMode ? Colors.blue : Colors.white,
              foregroundColor: _compassMode ? Colors.white : Colors.black87,
              onPressed: _toggleCompass,
              child: Transform.rotate(
                angle: _heading * (math.pi / 180),
                child: const Icon(Icons.navigation),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'route',
        icon: const Icon(Icons.directions),
        label: const Text('길찾기'),
        onPressed: () => _showRoutePanel(context),
      ),
    );
  }

  void _showRoutePanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => RoutePanel(mapCtrl: _mapCtrl),
    );
  }
}
