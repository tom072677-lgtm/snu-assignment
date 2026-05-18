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
                  // eTL URL
                  const Text('📋 eTL 캘린더 URL 가져오는 방법',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text(
                    '1. eTL 로그인 → 상단 캘린더 클릭\n'
                    '2. 좌측 하단 "캘린더 내보내기" 클릭\n'
                    '3. "모든 과목" + "최근 및 다음 60일" 선택\n'
                    '4. "캘린더 URL 가져오기" 클릭 → URL 복사\n'
                    '5. 아래에 붙여넣기',
                    style: TextStyle(fontSize: 13, height: 1.6),
                  ),
                  const SizedBox(height: 14),
                  if (!hasIcal) ...[
                    TextField(
                      controller: _icalCtrl,
                      decoration: const InputDecoration(
                        labelText: 'eTL 캘린더 URL',
                        hintText: 'webcal://myetl.snu.ac.kr/feeds/...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: _saveIcal,
                      child: const Text('저장 & 과제 가져오기'),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
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
                      onPressed: () =>
                          ref.read(icalUrlProvider.notifier).set(null),
                      child: const Text('연동 해제'),
                    ),
                    const SizedBox(height: 14),
                    const Divider(),
                    const SizedBox(height: 10),
                    const Text('제출한 과제 자동 제외 (선택)',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    const Text(
                      'eTL → 우측 상단 프로필 → 설정 → 스크롤 하단 "승인된 통합" → 새 액세스 토큰',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _tokenCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'eTL API 토큰',
                        hintText: '토큰 입력...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => ref
                          .read(canvasTokenProvider.notifier)
                          .set(_tokenCtrl.text.isEmpty ? null : _tokenCtrl.text),
                      child: const Text('토큰 저장'),
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

  void _saveIcal() {
    final url = _icalCtrl.text.trim();
    if (url.isEmpty) return;
    ref.read(icalUrlProvider.notifier).set(url);
    Navigator.pop(context);
  }
}
