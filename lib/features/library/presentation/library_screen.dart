import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../data/library_repository.dart';
import '../domain/library_models.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  // 60초마다 자동 갱신 (포그라운드에서만 동작)
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      ref.invalidate(librarySeatsProvider);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 백그라운드에선 불필요한 스크랩 요청 중단, 복귀 시 즉시 갱신 후 재개
    if (state == AppLifecycleState.paused) {
      _timer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      ref.invalidate(librarySeatsProvider);
      _startTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(librarySeatsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('도서관 좌석'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(librarySeatsProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) {
          debugPrint('[library] seats load error: $e');
          return _ErrorView(
            onRetry: () => ref.invalidate(librarySeatsProvider),
          );
        },
        data: (data) => data.rooms.isEmpty
            ? _EmptyView(
                updatedAt: data.updatedAt,
                onRetry: () => ref.invalidate(librarySeatsProvider),
              )
            : _RoomList(data: data),
      ),
    );
  }
}

class _RoomList extends StatelessWidget {
  final LibrarySeats data;
  const _RoomList({required this.data});

  @override
  Widget build(BuildContext context) {
    final updatedAt = data.updatedAt;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (updatedAt != null) ...[
          Text(
            '${DateFormat('HH:mm').format(updatedAt.toLocal())} 기준',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 8),
        ],
        ...data.rooms.map((r) => _SeatCard(room: r)),
      ],
    );
  }
}

class _SeatCard extends StatelessWidget {
  final ReadingRoom room;
  const _SeatCard({required this.room});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = room.isAvailable
        ? (room.isCrowded ? Colors.orange : colorScheme.primary)
        : Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(room.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    room.isAvailable
                        ? '${room.available}석 가능'
                        : '자리 없음',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: color),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 좌석 게이지
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: room.occupancyRate,
                minHeight: 6,
                backgroundColor: Colors.grey.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${room.total - room.available} / ${room.total}석 사용 중',
              style:
                  TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final DateTime? updatedAt;
  final VoidCallback onRetry;
  const _EmptyView({this.updatedAt, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chair_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text('좌석 정보를 불러오지 못했습니다'),
          const SizedBox(height: 8),
          const Text(
            '도서관 시스템이 점검 중일 수 있어요',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('네트워크 오류'),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}
