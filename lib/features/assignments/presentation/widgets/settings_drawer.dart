import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/analytics.dart';
import '../../../../core/constants.dart';
import '../../../../core/widget_service.dart';
import '../../../../shared/providers/notification_service.dart';
import '../../../../shared/providers/settings_provider.dart';

class SettingsDrawer extends ConsumerStatefulWidget {
  const SettingsDrawer({super.key});

  @override
  ConsumerState<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends ConsumerState<SettingsDrawer> {
  late TextEditingController _icalCtrl;
  late TextEditingController _tokenCtrl;
  int _versionTapCount = 0; // 버전 5번 탭 → 개발자 메뉴 표시
  bool _devMenuVisible = false;

  @override
  void initState() {
    super.initState();
    _icalCtrl = TextEditingController(text: ref.read(icalUrlProvider) ?? '');
    _tokenCtrl =
        TextEditingController(text: ref.read(canvasTokenProvider) ?? '');
  }

  @override
  void dispose() {
    _icalCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final assignmentDays = ref.watch(assignmentDaysProvider);
    final hasIcal = ref.watch(icalUrlProvider) != null;
    final isConnected = hasIcal; // 토큰은 선택 사항 — URL만 있으면 연동됨

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (_, scroll) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          children: [
            // 핸들
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  const Text('설정',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  if (!isConnected) ...[
                    // ─── 미연동: URL + 토큰 같이 입력 ───
                    const Text('📋 eTL 캘린더 URL 가져오는 방법',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    const Text(
                      '1. eTL 로그인 → 상단 캘린더 클릭\n'
                      '2. 좌측 하단 "캘린더 내보내기" 클릭\n'
                      '3. "모든 과목" + "최근 및 다음 60일" 선택\n'
                      '4. "캘린더 URL 가져오기" 클릭 → URL 복사',
                      style: TextStyle(fontSize: 13, height: 1.6),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _icalCtrl,
                      decoration: const InputDecoration(
                        labelText: 'eTL 캘린더 URL',
                        hintText: 'webcal://myetl.snu.ac.kr/feeds/...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('🔑 eTL API 토큰 가져오는 방법',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    const Text(
                      '1. eTL 로그인 → 우측 상단 프로필 클릭\n'
                      '2. 설정 → 하단 "승인된 통합" 섹션\n'
                      '3. "+ 새 액세스 토큰" → 목적 입력 후 생성\n'
                      '4. 토큰 복사 (다시 볼 수 없으니 주의)',
                      style: TextStyle(fontSize: 13, height: 1.6),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _tokenCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'eTL API 토큰',
                        hintText: '토큰 입력...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: _saveAll,
                      child: const Text('저장 & 과제 가져오기'),
                    ),
                  ] else ...[
                    // ─── 연동됨 ───
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green, size: 18),
                          SizedBox(width: 8),
                          Text('eTL 연동됨', style: TextStyle(color: Colors.green)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () {
                        ref.read(icalUrlProvider.notifier).set(null);
                        ref.read(canvasTokenProvider.notifier).set(null);
                        _icalCtrl.clear();
                        _tokenCtrl.clear();
                        // 서버 구독 해제 (push 중단)
                        ref.read(notificationServiceProvider).unsubscribeEtl();
                        // 홈 위젯 미연동 상태로 초기화
                        WidgetService.clearWidget();
                      },
                      child: const Text('연동 해제'),
                    ),
                  ],

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),

                  // ─── 테마 설정 ─────────────────────────────────────────────
                  const Text('화면 테마',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 10),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto, size: 18),
                        label: Text('자동'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode, size: 18),
                        label: Text('라이트'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode, size: 18),
                        label: Text('다크'),
                      ),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (Set<ThemeMode> s) {
                      final mode = s.first;
                      ref.read(themeModeProvider.notifier).set(mode);
                      Analytics.themeModeChanged(switch (mode) {
                        ThemeMode.system => 'system',
                        ThemeMode.light => 'light',
                        ThemeMode.dark => 'dark',
                      });
                    },
                  ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),

                  // ─── 과제 조회 기간 ──────────────────────────────────────
                  const Text('과제 조회 기간',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(
                    '앞으로 며칠 내 마감 과제를 가져올지 설정합니다.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 7, label: Text('7일')),
                      ButtonSegment(value: 14, label: Text('14일')),
                      ButtonSegment(value: 30, label: Text('30일')),
                    ],
                    selected: {assignmentDays},
                    onSelectionChanged: (Set<int> s) {
                      ref.read(assignmentDaysProvider.notifier).set(s.first);
                      Analytics.assignmentDaysChanged(s.first);
                    },
                  ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 16),

                  // ─── 알림 설정 ────────────────────────────────────────────
                  const Text('알림 설정',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(
                    '교수님이 새 과제나 공지사항을 올리면 push 알림을 받아요.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  // 새 과제 토글
                  Consumer(builder: (ctx, ref, _) {
                    final enabled = ref.watch(newAssignmentNotifProvider);
                    return SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('새 과제 등록 알림',
                          style: TextStyle(fontSize: 13)),
                      subtitle: Text(
                        enabled ? '새 과제 등록 시 push 알림' : '꺼짐',
                        style: TextStyle(
                            fontSize: 11,
                            color: enabled ? Colors.blue : Colors.grey[400]),
                      ),
                      value: enabled,
                      onChanged: (v) async {
                        ref.read(newAssignmentNotifProvider.notifier).set(v);
                        if (!v) {
                          // 공지사항 알림이 ON이면 서버 구독은 유지해야 함
                          final announcementOn = ref.read(newAnnouncementNotifProvider);
                          if (!announcementOn) {
                            ref.read(notificationServiceProvider).unsubscribeEtl();
                          }
                        } else {
                          final icalUrl = ref.read(icalUrlProvider);
                          final apiToken = ref.read(canvasTokenProvider);
                          if (icalUrl != null && icalUrl.isNotEmpty) {
                            final ok = await ref.read(notificationServiceProvider).subscribeEtl(
                              icalUrl: icalUrl,
                              canvasToken: apiToken,
                            );
                            if (!ok && ctx.mounted) {
                              ref.read(newAssignmentNotifProvider.notifier).set(false);
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('서버 연결 실패. 잠시 후 다시 시도해 주세요.')),
                              );
                            }
                          }
                        }
                      },
                    );
                  }),
                  // 공지사항 토글
                  Consumer(builder: (ctx, ref, _) {
                    final enabled = ref.watch(newAnnouncementNotifProvider);
                    return SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('공지사항 알림',
                          style: TextStyle(fontSize: 13)),
                      subtitle: Text(
                        enabled ? '교수님 공지사항 push 알림' : '꺼짐',
                        style: TextStyle(
                            fontSize: 11,
                            color: enabled ? Colors.blue : Colors.grey[400]),
                      ),
                      value: enabled,
                      onChanged: (v) async {
                        ref.read(newAnnouncementNotifProvider.notifier).set(v);
                        if (!v) {
                          // 과제 알림도 OFF면 서버 구독 해제
                          final assignmentOn = ref.read(newAssignmentNotifProvider);
                          if (!assignmentOn) {
                            ref.read(notificationServiceProvider).unsubscribeEtl();
                          }
                        } else {
                          // 공지 알림 켜면 서버 구독 보장
                          final icalUrl = ref.read(icalUrlProvider);
                          final apiToken = ref.read(canvasTokenProvider);
                          if (icalUrl != null && icalUrl.isNotEmpty) {
                            final ok = await ref.read(notificationServiceProvider).subscribeEtl(
                              icalUrl: icalUrl,
                              canvasToken: apiToken,
                            );
                            if (!ok && ctx.mounted) {
                              ref.read(newAnnouncementNotifProvider.notifier).set(false);
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('서버 연결 실패. 잠시 후 다시 시도해 주세요.')),
                              );
                            }
                          }
                        }
                      },
                    );
                  }),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),

                  // ─── 버전 (5번 탭하면 개발자 메뉴 등장) ─────────────────
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _versionTapCount++;
                        if (_versionTapCount >= 5) {
                          _devMenuVisible = true;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('개발자 메뉴가 활성화되었습니다'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        }
                      });
                    },
                    child: Center(
                      child: Text(
                        '샤랍 $appVersion',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[400],
                        ),
                      ),
                    ),
                  ),

                  // ─── 개발자 메뉴 ──────────────────────────────────────────
                  if (_devMenuVisible) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.code, size: 14, color: Colors.orange),
                              SizedBox(width: 6),
                              Text(
                                '개발자 옵션',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Consumer(builder: (context, ref, _) {
                            final isDevMode = ref.watch(devModeProvider);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            '개발자 모드',
                                            style: TextStyle(fontSize: 13),
                                          ),
                                          Text(
                                            isDevMode
                                                ? '내 데이터 수집 중단됨 (Analytics OFF)'
                                                : '내 데이터가 Analytics에 포함됨',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDevMode
                                                  ? Colors.orange
                                                  : Colors.grey[500],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Switch(
                                      value: isDevMode,
                                      activeColor: Colors.orange,
                                      onChanged: (_) async {
                                        ref
                                            .read(devModeProvider.notifier)
                                            .toggle();
                                        await Analytics.setDevMode(!isDevMode);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(!isDevMode
                                                  ? '개발자 모드 ON: 내 데이터는 Analytics에서 제외됩니다'
                                                  : '개발자 모드 OFF: Analytics 정상 수집'),
                                              duration:
                                                  const Duration(seconds: 2),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ],
                                ),
                                if (isDevMode) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '💡 내 이벤트만 보려면:\n'
                                    'adb shell setprop debug.firebase.analytics.app com.tom07.sharap\n'
                                    '→ Firebase Console > Analytics > DebugView',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[500],
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveAll() {
    final url = _icalCtrl.text.trim();
    if (url.isEmpty) return; // URL은 필수, Canvas 토큰은 선택
    ref.read(icalUrlProvider.notifier).set(url);
    final token = _tokenCtrl.text.trim();
    if (token.isNotEmpty) {
      ref.read(canvasTokenProvider.notifier).set(token);
    }
    Analytics.etlConnected(hasCanvasToken: token.isNotEmpty);
    Navigator.pop(context);
  }
}
