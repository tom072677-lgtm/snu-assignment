import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/notification_service.dart';

/// 24시간 이내 마감 과제가 있을 때 상단에 고정 표시되는 폭탄 카운트다운 배너.
/// 닫기 버튼 없음 — 학생이 과제를 까먹지 않도록 항상 표시.
/// 내부 1분 타이머와 동기화해 시스템 알림도 함께 갱신.
class BombCountdownBanner extends ConsumerStatefulWidget {
  /// 24시간 이내 마감 과제 목록 (etlId 포함). 비어있으면 배너 숨김.
  final List<({String etlId, String title, String courseName, Duration remaining})> urgentAssignments;

  const BombCountdownBanner({super.key, required this.urgentAssignments});

  @override
  ConsumerState<BombCountdownBanner> createState() => _BombCountdownBannerState();
}

class _BombCountdownBannerState extends ConsumerState<BombCountdownBanner>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  Timer? _timer;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // 가장 촉박한 과제 기준 실시간 남은 시간 (1분마다 갱신)
  Duration _mostUrgentRemaining = Duration.zero;
  String _mostUrgentTitle = '';
  String _mostUrgentCourse = '';

  // 이전 urgent 과제 ID 집합 (새로 추가된 과제 감지용)
  Set<String> _prevEtlIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _update();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _update());
  }

  @override
  void didUpdateWidget(BombCountdownBanner old) {
    super.didUpdateWidget(old);
    _update();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _update();
    // 앱이 백그라운드로 전환되는 순간 → 알림 재발송으로 heads-up 팝업 트리거
    // (Android는 포그라운드 앱의 알림에 heads-up을 표시하지 않으므로)
    if (state == AppLifecycleState.paused) _triggerHeadsUpOnBackground();
  }

  /// 앱이 백그라운드로 전환될 때: 기존 알림 취소 후 재발송 → Android가 신규 알림으로
  /// 인식해 상단에 heads-up 팝업 표시.
  /// 600ms 딜레이: 홈 전환 애니메이션 완료 후 DISABLE_HEADS_UP이 해제되면 발송
  Future<void> _triggerHeadsUpOnBackground() async {
    final assignments = widget.urgentAssignments;
    if (assignments.isEmpty) return;

    // 전환 애니메이션이 끝나고 DISABLE_HEADS_UP 플래그가 해제될 때까지 대기
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    // 가장 임박한 과제는 FGS 폭탄 알림이 담당하므로 제외 (중복 알림 방지)
    final sorted = [...assignments]
      ..sort((a, b) => a.remaining.compareTo(b.remaining));
    final mostUrgentId = sorted.isEmpty ? null : sorted.first.etlId;

    final notifService = ref.read(notificationServiceProvider);
    for (final a in assignments) {
      if (a.etlId == mostUrgentId) continue; // FGS가 담당
      if (a.remaining.inSeconds <= 0) continue;
      // 취소 후 재발송 → Android/Samsung이 신규 알림으로 인식 → heads-up 팝업
      await NotificationService.cancelOngoingNotification(a.etlId);
      if (!mounted) return;
      await notifService.showOngoingNotification(
        etlId: a.etlId,
        title: a.title,
        courseName: a.courseName,
        remaining: a.remaining,
        headsUp: true,
      );
    }
  }

  void _update() {
    if (!mounted) return;
    final assignments = widget.urgentAssignments;

    // 시스템 알림 동기화 (새 과제 → heads-up 팝업, 만료 과제 → 알림 취소)
    final notifService = ref.read(notificationServiceProvider);
    notifService.syncUrgentNotifications(
      assignments: assignments,
      previousEtlIds: _prevEtlIds,
    ).ignore();
    _prevEtlIds = assignments.map((a) => a.etlId).toSet();

    if (assignments.isEmpty) return;

    // 남은 시간이 가장 짧은 과제 선택
    final mostUrgent = assignments.reduce(
      (a, b) => a.remaining < b.remaining ? a : b,
    );

    setState(() {
      _mostUrgentRemaining = mostUrgent.remaining;
      _mostUrgentTitle = mostUrgent.title;
      _mostUrgentCourse = mostUrgent.courseName;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseCtrl.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urgentAssignments.isEmpty) return const SizedBox.shrink();

    const totalSeconds = 24 * 3600;
    final remainingSeconds = _mostUrgentRemaining.inSeconds.clamp(0, totalSeconds);
    // progress: 0.0 = 24시간 남음(왼쪽), 1.0 = 0시간(오른쪽)
    final progress = 1.0 - (remainingSeconds / totalSeconds);
    final isVeryUrgent = _mostUrgentRemaining.inHours < 1;

    final remainingText = _formatRemaining(_mostUrgentRemaining);
    final count = widget.urgentAssignments.length;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isVeryUrgent
              ? [const Color(0xFFB71C1C), const Color(0xFFD32F2F)]
              : [const Color(0xFFE65100), const Color(0xFFF57C00)],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 상단 행: 폭탄 + 과제 정보
              Row(
                children: [
                  ScaleTransition(
                    scale: _pulseAnim,
                    child: const Text('💣', style: TextStyle(fontSize: 22)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _mostUrgentCourse.isNotEmpty
                              ? _mostUrgentCourse
                              : _mostUrgentTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_mostUrgentCourse.isNotEmpty)
                          Text(
                            _mostUrgentTitle,
                            style: const TextStyle(
                              color: Color(0xCCFFFFFF),
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        remainingText,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: isVeryUrgent ? 0.5 : 0,
                        ),
                      ),
                      if (count > 1)
                        Text(
                          '외 ${count - 1}개',
                          style: const TextStyle(
                            color: Color(0xCCFFFFFF),
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 진행 바 + 폭탄 이모지 위치
              SizedBox(
                height: 22,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 배경 바
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    // 채워진 바 (시간이 지날수록 채워짐)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: LayoutBuilder(
                        builder: (ctx, constraints) {
                          // LayoutBuilder가 부모 Positioned.fill의 크기를 못 볼 수 있으므로
                          // FractionallySizedBox 대신 AnimatedContainer 사용
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: progress,
                            child: Container(
                              color: isVeryUrgent
                                  ? Colors.red[900]
                                  : Colors.orange[900],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // 💣 폭탄 이모지: progress 위치에 표시
                    Positioned.fill(
                      child: LayoutBuilder(builder: (ctx, constraints) {
                        final maxOffset = constraints.maxWidth - 20.0;
                        final offset = (progress * maxOffset).clamp(0.0, maxOffset);
                        return Stack(
                          children: [
                            Positioned(
                              left: offset,
                              top: 0,
                              bottom: 0,
                              child: const Center(
                                child: Text('💣', style: TextStyle(fontSize: 14)),
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              // 좌우 레이블
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('24h', style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 10)),
                  Text('0h', style: TextStyle(color: Color(0xAAFFFFFF), fontSize: 10)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatRemaining(Duration d) {
    if (d.inSeconds <= 0) return '마감!';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '$h시간 $m분 후';
    if (m > 0) return '$m분 후';
    return '${d.inSeconds}초 후';
  }
}
