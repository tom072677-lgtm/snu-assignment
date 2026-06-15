import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/scrap_entry.dart';
import 'opportunities_providers.dart';

class MyScrapsPage extends ConsumerWidget {
  const MyScrapsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scraps = [...ref.watch(scrapsProvider)];
    scraps.sort((a, b) {
      if (a.deadline == null && b.deadline == null) return 0;
      if (a.deadline == null) return 1;
      if (b.deadline == null) return -1;
      return a.deadline!.compareTo(b.deadline!);
    });

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Scaffold(
      appBar: AppBar(title: const Text('내 스크랩')),
      body: scraps.isEmpty
          ? const Center(child: Text('스크랩한 기회가 없어요'))
          : ListView.builder(
              itemCount: scraps.length,
              itemBuilder: (_, i) {
                final e = scraps[i];
                final d = e.deadline?.difference(today).inDays;
                return ListTile(
                  title: Text(e.title),
                  subtitle: Text(d == null
                      ? '마감 미정'
                      : (d < 0 ? '마감됨' : (d == 0 ? 'D-day' : 'D-$d'))),
                  trailing: DropdownButton<ScrapStatus>(
                    value: e.status,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(
                          value: ScrapStatus.interested, child: Text('관심')),
                      DropdownMenuItem(
                          value: ScrapStatus.preparing, child: Text('준비중')),
                      DropdownMenuItem(
                          value: ScrapStatus.applied, child: Text('지원완료')),
                    ],
                    onChanged: (s) {
                      if (s != null) {
                        ref.read(scrapsProvider.notifier).setStatus(e.id, s);
                      }
                    },
                  ),
                );
              },
            ),
    );
  }
}
