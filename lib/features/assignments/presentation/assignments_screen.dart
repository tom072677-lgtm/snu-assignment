import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/settings_provider.dart';
import '../../../shared/widgets/error_view.dart';
import '../data/assignment_repository.dart';
import 'widgets/assignment_card.dart';
import 'widgets/bomb_countdown_banner.dart';
import 'widgets/settings_drawer.dart';

class AssignmentsScreen extends ConsumerWidget {
  const AssignmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icalUrl = ref.watch(icalUrlProvider);
    final assignmentsAsync = ref.watch(assignmentsProvider);
    final completed = ref.watch(completedTasksProvider);

    // 24시간 이내 미완료·미만료 과제 → 폭탄 배너 대상
    final urgentAssignments = assignmentsAsync.valueOrNull
            ?.where((a) =>
                !completed.contains(a.etlId) &&
                !a.isOverdue &&
                a.remaining.inHours < 24)
            .map((a) => (
                  etlId: a.etlId,
                  title: a.title,
                  courseName: a.courseName,
                  remaining: a.remaining,
                ))
            .toList() ??
        [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('샤랍', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _openSettings(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          // 폭탄 카운트다운 배너 (24h 이내 과제 있을 때만)
          BombCountdownBanner(urgentAssignments: urgentAssignments),
          // 본문
          Expanded(
            child: icalUrl == null
                ? _buildNoEtl(context, ref)
                : assignmentsAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => ErrorView(
                      message: e.toString(),
                      onRetry: () => ref.invalidate(assignmentsProvider),
                    ),
                    data: (assignments) {
                      final active = assignments
                          .where((a) => !completed.contains(a.etlId))
                          .toList();
                      final done = assignments
                          .where((a) => completed.contains(a.etlId))
                          .toList();

                      if (active.isEmpty && done.isEmpty) {
                        return _buildEmpty();
                      }

                      return RefreshIndicator(
                        onRefresh: () =>
                            ref.read(assignmentsProvider.notifier).refresh(),
                        child: ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            if (active.isNotEmpty) ...[
                              const _SectionHeader(title: '과제 목록'),
                              ...active.map((a) => AssignmentCard(assignment: a)),
                            ],
                            if (done.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              const _SectionHeader(title: '최근 완료한 과제'),
                              ...done.map(
                                  (a) => AssignmentCard(assignment: a, isCompleted: true)),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoEtl(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.school_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('eTL 캘린더 URL을 등록해주세요',
              style: TextStyle(fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => _openSettings(context, ref),
            child: const Text('설정 열기'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
          SizedBox(height: 12),
          Text('7일 내 마감 과제가 없습니다 🎉',
              style: TextStyle(fontSize: 16, color: Colors.grey)),
        ],
      ),
    );
  }

  void _openSettings(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const SettingsDrawer(),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: Colors.grey[600], fontWeight: FontWeight.bold),
      ),
    );
  }
}
