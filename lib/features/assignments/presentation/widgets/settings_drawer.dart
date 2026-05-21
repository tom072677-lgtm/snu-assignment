import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/providers/settings_provider.dart';

class SettingsDrawer extends ConsumerStatefulWidget {
  const SettingsDrawer({super.key});

  @override
  ConsumerState<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends ConsumerState<SettingsDrawer> {
  late TextEditingController _icalCtrl;
  late TextEditingController _tokenCtrl;

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
    final isDark = ref.watch(darkModeProvider);
    final hasIcal = ref.watch(icalUrlProvider) != null;
    final hasToken = ref.watch(canvasTokenProvider) != null;
    final isConnected = hasIcal && hasToken;

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
                      },
                      child: const Text('연동 해제'),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text('다크 모드',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Switch(
                        value: isDark,
                        onChanged: (_) =>
                            ref.read(darkModeProvider.notifier).toggle(),
                      ),
                    ],
                  ),
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
    final token = _tokenCtrl.text.trim();
    if (url.isEmpty || token.isEmpty) return;
    ref.read(icalUrlProvider.notifier).set(url);
    ref.read(canvasTokenProvider.notifier).set(token);
    Navigator.pop(context);
  }
}
