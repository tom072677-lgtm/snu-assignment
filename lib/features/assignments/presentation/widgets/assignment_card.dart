import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../shared/providers/settings_provider.dart';
import '../../domain/assignment.dart';
import '../assignment_detail_screen.dart';

class AssignmentCard extends ConsumerStatefulWidget {
  final Assignment assignment;
  final bool isCompleted;

  const AssignmentCard({
    super.key,
    required this.assignment,
    this.isCompleted = false,
  });

  @override
  ConsumerState<AssignmentCard> createState() => _AssignmentCardState();
}

class _AssignmentCardState extends ConsumerState<AssignmentCard> {
  bool _memoExpanded = false;
  late TextEditingController _memoCtrl;

  @override
  void initState() {
    super.initState();
    final memo = ref.read(memosProvider)[widget.assignment.etlId] ?? '';
    _memoCtrl = TextEditingController(text: memo);
  }

  @override
  void dispose() {
    _memoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.assignment;
    final memos = ref.watch(memosProvider);
    final memo = memos[a.etlId] ?? '';
    final remaining = a.remaining;
    final colorScheme = Theme.of(context).colorScheme;

    final badgeColor = a.isOverdue
        ? Colors.grey
        : a.isUrgent
            ? Colors.red
            : colorScheme.primary;

    final badgeText = a.isOverdue
        ? '마감'
        : remaining.inDays > 0
            ? 'D-${remaining.inDays}'
            : '오늘';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onCardTap(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badgeText,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      a.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        decoration: widget.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        color: widget.isCompleted ? Colors.grey : null,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                a.courseName,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 2),
              Text(
                _formatDue(a.dueDate, a.dateOnly),
                style: TextStyle(
                  fontSize: 12,
                  color: a.isUrgent && !a.isOverdue ? Colors.red : Colors.grey[600],
                ),
              ),
              // 하단: 메모 토글 + 완료 버튼
              const SizedBox(height: 8),
              Row(
                children: [
                  // 메모 토글 아이콘
                  InkWell(
                    onTap: () => setState(() => _memoExpanded = !_memoExpanded),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _memoExpanded
                                ? Icons.edit_note
                                : Icons.note_alt_outlined,
                            size: 16,
                            color: memo.isNotEmpty
                                ? Colors.blue
                                : Colors.grey[400],
                          ),
                          if (memo.isNotEmpty && !_memoExpanded) ...[
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                memo,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                    fontStyle: FontStyle.italic),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  widget.isCompleted
                      ? OutlinedButton(
                          onPressed: () => ref
                              .read(completedTasksProvider.notifier)
                              .undo(a.etlId),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('되돌리기',
                              style: TextStyle(fontSize: 13)),
                        )
                      : FilledButton(
                          onPressed: () => ref
                              .read(completedTasksProvider.notifier)
                              .complete(a.etlId),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child:
                              const Text('완료', style: TextStyle(fontSize: 13)),
                        ),
                ],
              ),
              // 메모 입력 필드 (펼쳐진 경우)
              if (_memoExpanded) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _memoCtrl,
                  decoration: const InputDecoration(
                    hintText: '메모 입력...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 3,
                  onChanged: (v) {
                    if (v.isEmpty) {
                      ref.read(memosProvider.notifier).remove(a.etlId);
                    } else {
                      ref.read(memosProvider.notifier).set(a.etlId, v);
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDue(DateTime due, bool dateOnly) {
    if (dateOnly) {
      return DateFormat('M월 d일 (E) 마감', 'ko').format(due);
    }
    return DateFormat('M월 d일 (E) HH:mm 마감', 'ko').format(due);
  }

  void _onCardTap(BuildContext context) {
    final a = widget.assignment;
    // Canvas ID가 있으면 상세 화면으로, 없으면 eTL URL 직접 열기
    if (a.hasDetail || a.url.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AssignmentDetailScreen(assignment: a),
        ),
      );
    } else {
      setState(() => _memoExpanded = !_memoExpanded);
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
