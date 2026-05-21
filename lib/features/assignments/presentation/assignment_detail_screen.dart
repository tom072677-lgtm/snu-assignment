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
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final a = widget.assignment;
    final apiToken = ref.read(canvasTokenProvider);

    if (!a.hasDetail || apiToken == null || apiToken.isEmpty) {
      setState(() {
        _loading = false;
        _error = apiToken == null || apiToken.isEmpty
            ? 'Canvas API 토큰이 설정되지 않았습니다.\n설정에서 토큰을 입력해주세요.'
            : '과제 ID를 찾을 수 없습니다.';
      });
      return;
    }

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
          _error = '불러오기 실패: ${e.toString().replaceAll('Exception: ', '')}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.assignment;
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError(a)
              : _buildContent(a, _detail!),
    );
  }

  Widget _buildError(Assignment a) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.red),
            ),
            const SizedBox(height: 20),
            if (a.url.isNotEmpty)
              FilledButton.icon(
                onPressed: () => _openUrl(a.url),
                icon: const Icon(Icons.open_in_browser),
                label: const Text('eTL에서 열기'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(Assignment a, AssignmentDetail detail) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 헤더 카드 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  if (a.courseName.isNotEmpty)
                    Text(a.courseName,
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey[600])),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        a.isOverdue ? Icons.check_circle : Icons.schedule,
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
                  if (detail.submissionTypes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: detail.submissionTypes
                          .map((t) => Chip(
                                label: Text(
                                  _submissionTypeLabel(t),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── 설명 ──
          _sectionHeader('과제 설명'),
          const SizedBox(height: 8),
          if (detail.descriptionText.isEmpty)
            Text('설명이 없습니다.',
                style: TextStyle(color: Colors.grey[500], fontSize: 14))
          else
            SelectableText(
              detail.descriptionText,
              style: const TextStyle(fontSize: 14, height: 1.6),
            ),

          // ── 첨부파일 ──
          if (detail.attachments.isNotEmpty) ...[
            const SizedBox(height: 24),
            _sectionHeader('첨부파일 (${detail.attachments.length})'),
            const SizedBox(height: 8),
            ...detail.attachments.map(
              (f) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.attach_file, color: Colors.blue),
                title: Text(
                  f.name,
                  style: const TextStyle(fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.download, size: 18,
                    color: Colors.grey),
                onTap: () => _openUrl(f.url),
              ),
            ),
          ],

          const SizedBox(height: 24),
          // eTL 열기 버튼
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
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
