import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../shared/providers/settings_provider.dart';
import '../data/assignment_repository.dart';
import '../domain/assignment.dart';
import '../domain/assignment_detail.dart';

class AssignmentDetailScreen extends ConsumerStatefulWidget {
  final Assignment assignment;

  const AssignmentDetailScreen({super.key, required this.assignment});

  @override
  ConsumerState<AssignmentDetailScreen> createState() =>
      _AssignmentDetailScreenState();
}

class _AssignmentDetailScreenState
    extends ConsumerState<AssignmentDetailScreen> {
  AssignmentDetail? _detail;
  String? _fetchError;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final a = widget.assignment;
    final apiToken = ref.read(canvasTokenProvider);

    // 토큰 없거나 courseId 없으면 기본 정보만 표시 (fetch 생략)
    if (!a.hasDetail || apiToken == null || apiToken.isEmpty) return;

    setState(() => _loading = true);
    try {
      final detail = await ref.read(assignmentsProvider.notifier).fetchDetail(
            courseId: a.courseId!,
            assignmentId: a.assignmentId!,
            apiToken: apiToken,
          );
      if (mounted) setState(() { _detail = detail; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _fetchError = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.assignment;
    final apiToken = ref.read(canvasTokenProvider);
    final hasToken = apiToken != null && apiToken.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          a.courseName.isNotEmpty ? a.courseName : '과제 상세',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          if (a.url.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.open_in_browser),
              tooltip: 'eTL에서 열기',
              onPressed: () => _openUrl(a.url),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 헤더 카드 (항상 표시) ──
            _buildHeader(a),

            const SizedBox(height: 16),

            // ── Canvas 상세 섹션 ──
            if (!hasToken) ...[
              _buildInfoBanner(
                icon: Icons.info_outline,
                color: Colors.blue,
                message: 'Canvas API 토큰을 설정하면\n교수님의 설명과 첨부파일을 볼 수 있습니다.',
              ),
            ] else if (!a.hasDetail) ...[
              _buildInfoBanner(
                icon: Icons.info_outline,
                color: Colors.orange,
                message: '목록을 새로 고침하면 상세 정보를 불러올 수 있습니다.\n(아래 당겨서 새로 고침)',
              ),
            ] else if (_loading) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
            ] else if (_fetchError != null) ...[
              _buildInfoBanner(
                icon: Icons.error_outline,
                color: Colors.red,
                message: '불러오기 실패: $_fetchError',
              ),
            ] else if (_detail != null) ...[
              _buildDetailContent(_detail!),
            ],

            const SizedBox(height: 24),
            // eTL 열기 버튼 (항상 표시)
            if (a.url.isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openUrl(a.url),
                  icon: const Icon(Icons.open_in_browser, size: 16),
                  label: const Text('eTL에서 열기'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Assignment a) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상태 배지
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: a.isOverdue
                        ? Colors.grey
                        : a.isUrgent
                            ? Colors.red
                            : colorScheme.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    a.isOverdue
                        ? '마감'
                        : a.remaining.inDays > 0
                            ? 'D-${a.remaining.inDays}'
                            : '오늘',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 과제명
            Text(
              a.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            // 과목명
            if (a.courseName.isNotEmpty)
              Text(a.courseName,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(height: 4),
            // 마감일
            Row(
              children: [
                Icon(
                  a.isOverdue ? Icons.check_circle_outline : Icons.schedule,
                  size: 14,
                  color: a.isUrgent
                      ? Colors.red
                      : a.isOverdue
                          ? Colors.grey
                          : Colors.blue,
                ),
                const SizedBox(width: 4),
                Text(
                  _formatDue(a.dueDate, a.dateOnly),
                  style: TextStyle(
                    fontSize: 13,
                    color: a.isUrgent && !a.isOverdue
                        ? Colors.red
                        : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBanner({
    required IconData icon,
    required Color color,
    required String message,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailContent(AssignmentDetail detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 제출 방식
        if (detail.submissionTypes.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            children: detail.submissionTypes
                .map((t) => Chip(
                      label: Text(_submissionTypeLabel(t),
                          style: const TextStyle(fontSize: 11)),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
        ],

        // 설명
        const Text('과제 설명',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (detail.descriptionText.isEmpty)
          Text('설명이 없습니다.',
              style: TextStyle(color: Colors.grey[500], fontSize: 14))
        else
          SelectableText(
            detail.descriptionText,
            style: const TextStyle(fontSize: 14, height: 1.6),
          ),

        // 첨부파일
        if (detail.attachments.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('첨부파일 (${detail.attachments.length})',
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...detail.attachments.map(
            (f) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.attach_file, color: Colors.blue),
              title: Text(f.name,
                  style: const TextStyle(fontSize: 14),
                  overflow: TextOverflow.ellipsis),
              trailing:
                  const Icon(Icons.download, size: 18, color: Colors.grey),
              onTap: () => _openUrl(f.url),
            ),
          ),
        ],
      ],
    );
  }

  String _formatDue(DateTime due, bool dateOnly) {
    if (dateOnly) return DateFormat('M월 d일 (E) 마감', 'ko').format(due);
    return DateFormat('M월 d일 (E) HH:mm 마감', 'ko').format(due);
  }

  String _submissionTypeLabel(String type) => switch (type) {
        'online_upload' => '파일 제출',
        'online_text_entry' => '텍스트 제출',
        'online_url' => 'URL 제출',
        'none' => '제출 없음',
        'not_graded' => '미채점',
        _ => type,
      };

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('링크를 열 수 없습니다')),
        );
      }
    }
  }
}
