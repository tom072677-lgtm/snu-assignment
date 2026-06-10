import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/shuttle_repository.dart';
import '../domain/shuttle_models.dart';

// ── providers ──────────────────────────────────────────────────────────────

final _routesProvider = FutureProvider<List<ShuttleRoute>>((ref) {
  return ref.watch(shuttleRepositoryProvider).fetchRoutes();
});

// ── screen ─────────────────────────────────────────────────────────────────

class ShuttleScreen extends ConsumerStatefulWidget {
  const ShuttleScreen({super.key});

  @override
  ConsumerState<ShuttleScreen> createState() => _ShuttleScreenState();
}

class _ShuttleScreenState extends ConsumerState<ShuttleScreen> {
  ShuttleRoute? _selectedRoute;
  ShuttleStation? _selectedStation;
  ShuttleArrival? _arrival;
  String? _arrivalError;
  bool _loadingArrival = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _selectRoute(ShuttleRoute route) {
    _timer?.cancel();
    setState(() {
      _selectedRoute = route;
      _selectedStation = null;
      _arrival = null;
    });
  }

  void _selectStation(ShuttleStation station) {
    _timer?.cancel();
    setState(() {
      _selectedStation = station;
      _arrival = null;
    });
    _fetchArrival();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _fetchArrival());
  }

  Future<void> _fetchArrival() async {
    final route = _selectedRoute;
    final station = _selectedStation;
    if (route == null || station == null) return;
    setState(() {
      _loadingArrival = true;
      _arrivalError = null;
    });
    try {
      final result = await ref
          .read(shuttleRepositoryProvider)
          .fetchArrival(route.id, station.code);
      if (mounted) setState(() { _arrival = result; _loadingArrival = false; });
    } catch (e) {
      debugPrint('[shuttle] arrival fetch failed: $e');
      if (mounted) {
        setState(() {
          _loadingArrival = false;
          _arrivalError = '도착 정보를 불러오지 못했어요';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('셔틀버스'),
        actions: [
          if (_selectedStation != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _fetchArrival,
            ),
        ],
      ),
      body: Column(
        children: [
          if (_selectedRoute != null)
            _Breadcrumb(
              route: _selectedRoute!,
              station: _selectedStation,
              onRouteReset: () => _selectRoute(_selectedRoute!),
              onReset: () {
                _timer?.cancel();
                setState(() {
                  _selectedRoute = null;
                  _selectedStation = null;
                  _arrival = null;
                });
              },
            ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_selectedRoute == null) return _RouteList(onSelected: _selectRoute);
    if (_selectedStation == null) {
      return _StationList(
        route: _selectedRoute!,
        onSelected: _selectStation,
      );
    }
    return _ArrivalView(
      arrival: _arrival,
      loading: _loadingArrival,
      error: _arrivalError,
      stationName: _selectedStation!.name,
      routeName: _selectedRoute!.name,
    );
  }
}

// ── 노선 목록 ───────────────────────────────────────────────────────────────

class _RouteList extends ConsumerStatefulWidget {
  const _RouteList({required this.onSelected});
  final void Function(ShuttleRoute) onSelected;

  @override
  ConsumerState<_RouteList> createState() => _RouteListState();
}

class _RouteListState extends ConsumerState<_RouteList> {
  bool _showSlowHint = false;
  Timer? _slowHintTimer;

  @override
  void initState() {
    super.initState();
    // 5초 후에도 로딩 중이면 "서버 기동 중" 힌트 표시
    _slowHintTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showSlowHint = true);
    });
  }

  @override
  void dispose() {
    _slowHintTimer?.cancel();
    super.dispose();
  }

  String _errorMessage(Object e) {
    if (e is DioException) {
      return switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout =>
          '서버 응답 시간 초과\n(서버가 기동 중일 수 있어요)',
        DioExceptionType.connectionError =>
          '네트워크 연결을 확인해주세요',
        _ => e.message ?? e.toString(),
      };
    }
    return e.toString();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_routesProvider);
    return async.when(
      loading: () => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (_showSlowHint) ...[
              const SizedBox(height: 16),
              Text(
                '서버 기동 중... (최대 90초 소요)',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                '노선 정보를 불러올 수 없습니다',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                _errorMessage(e),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  setState(() => _showSlowHint = false);
                  _slowHintTimer?.cancel();
                  _slowHintTimer = Timer(const Duration(seconds: 5), () {
                    if (mounted) setState(() => _showSlowHint = true);
                  });
                  ref.invalidate(_routesProvider);
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      ),
      data: (routes) {
        final grouped = <String, List<ShuttleRoute>>{};
        for (final r in routes) {
          grouped.putIfAbsent(r.type, () => []).add(r);
        }
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            for (final type in ['교내', '통학', '야간', '심야'])
              if (grouped.containsKey(type)) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 6),
                  child: Text(
                    _typeLabel(type),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: _typeColor(type),
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                for (final route in grouped[type]!)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _typeColor(type).withValues(alpha: 0.15),
                        child: Icon(Icons.directions_bus, color: _typeColor(type), size: 20),
                      ),
                      title: Text(route.name),
                      subtitle: Text('정류장 ${route.stations.length}개'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => widget.onSelected(route),
                    ),
                  ),
              ],
          ],
        );
      },
    );
  }

  String _typeLabel(String type) => switch (type) {
        '교내' => '🔄 교내순환',
        '통학' => '🚌 통학셔틀',
        '야간' => '🌙 야간셔틀',
        '심야' => '🌃 심야셔틀',
        _ => type,
      };

  Color _typeColor(String type) => switch (type) {
        '교내' => Colors.blue,
        '통학' => Colors.green,
        '야간' => Colors.indigo,
        '심야' => Colors.deepPurple,
        _ => Colors.grey,
      };
}

// ── 정류장 목록 ─────────────────────────────────────────────────────────────

class _StationList extends StatelessWidget {
  const _StationList({required this.route, required this.onSelected});
  final ShuttleRoute route;
  final void Function(ShuttleStation) onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: route.stations.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final s = route.stations[i];
        return ListTile(
          leading: Text(
            '${i + 1}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey),
          ),
          title: Text(s.name),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onSelected(s),
        );
      },
    );
  }
}

// ── 도착 정보 ───────────────────────────────────────────────────────────────

class _ArrivalView extends StatelessWidget {
  const _ArrivalView({
    required this.arrival,
    required this.loading,
    required this.error,
    required this.stationName,
    required this.routeName,
  });
  final ShuttleArrival? arrival;
  final bool loading;
  final String? error;
  final String stationName;
  final String routeName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(stationName,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    )),
            const SizedBox(height: 4),
            Text(routeName,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey)),
            const SizedBox(height: 32),
            if (loading && arrival == null)
              const CircularProgressIndicator()
            else if (arrival == null)
              Text(
                error ?? '도착 정보를 불러오지 못했어요',
                style: const TextStyle(color: Colors.grey),
              )
            else ...[
              _ArrivalChip(label: '첫번째 버스', value: arrival!.first),
              if (arrival!.second != null) ...[
                const SizedBox(height: 12),
                _ArrivalChip(label: '두번째 버스', value: arrival!.second!),
              ],
              if (arrival!.error != null) ...[
                const SizedBox(height: 16),
                Text('오류: ${arrival!.error}',
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
              const SizedBox(height: 24),
              Text('15초마다 자동 갱신',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ArrivalChip extends StatelessWidget {
  const _ArrivalChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final hasInfo = value != '운행정보없음' && value.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: hasInfo
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasInfo ? Colors.green.withValues(alpha: 0.4) : Colors.grey.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: hasInfo ? Colors.green[700] : Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 브레드크럼 ──────────────────────────────────────────────────────────────

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({
    required this.route,
    required this.station,
    required this.onRouteReset,
    required this.onReset,
  });
  final ShuttleRoute route;
  final ShuttleStation? station;
  final VoidCallback onRouteReset;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: onReset,
            child: const Text('셔틀버스',
                style: TextStyle(fontSize: 13, color: Colors.blue)),
          ),
          const Text(' › ', style: TextStyle(fontSize: 13, color: Colors.grey)),
          GestureDetector(
            onTap: station != null ? onRouteReset : null,
            child: Text(
              route.name,
              style: TextStyle(
                fontSize: 13,
                color: station != null ? Colors.blue : null,
              ),
            ),
          ),
          if (station != null) ...[
            const Text(' › ', style: TextStyle(fontSize: 13, color: Colors.grey)),
            Text(station!.name, style: const TextStyle(fontSize: 13)),
          ],
        ],
      ),
    );
  }
}
