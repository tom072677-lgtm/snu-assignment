import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../clubs/presentation/club_list_screen.dart';
import '../../notices/presentation/notices_screen.dart';
import '../../opportunities/presentation/opportunities_page.dart';
import '../../opportunities/presentation/my_scraps_page.dart';

/// 통합 '정보' 탭: 공지(내 학과 / SNU 비교과) + 동아리 + 혜택을 한 탭에 평면 배치.
/// 각 본문은 기존 화면을 재사용(공지=SportsTab/ExtraTab, 동아리·혜택=embedded).
class InfoScreen extends ConsumerWidget {
  const InfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title:
              const Text('정보', style: TextStyle(fontWeight: FontWeight.w700)),
          centerTitle: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.star),
              tooltip: '내 스크랩',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const MyScrapsPage())),
            ),
            IconButton(
              icon: const Icon(Icons.manage_accounts_outlined),
              tooltip: '내 정보 설정',
              onPressed: () => showNoticeProfileSheet(context),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: deptTabLabel(ref)),
              const Tab(text: 'SNU 비교과'),
              const Tab(text: '동아리'),
              const Tab(text: '혜택'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            SportsTab(),
            ExtraTab(),
            ClubListScreen(embedded: true),
            OpportunitiesPage(embedded: true),
          ],
        ),
      ),
    );
  }
}
