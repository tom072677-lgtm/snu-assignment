import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/dio_client.dart';
import '../../../shared/widgets/error_view.dart';

// 학교 소식 provider
final newsProvider = FutureProvider.autoDispose<_NewsData>((ref) async {
  final response = await DioClient.instance.get('/api/events');
  final data = response.data as Map<String, dynamic>;
  return _NewsData(
    schedule: (data['schedule'] as List)
        .map((e) => _ScheduleItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    notices: (data['notices'] as List)
        .map((e) => _NoticeItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
});

class _NewsData {
  final List<_ScheduleItem> schedule;
  final List<_NoticeItem> notices;
  _NewsData({required this.schedule, required this.notices});
}

class _ScheduleItem {
  final String title;
  final String date;
  final String? endDate;
  factory _ScheduleItem.fromJson(Map<String, dynamic> j) => _ScheduleItem._(
        j['title'] as String,
        j['date'] as String,
        j['endDate'] as String?,
      );
  _ScheduleItem._(this.title, this.date, this.endDate);
}

class _NoticeItem {
  final String title;
  final String? url;
  final String? date;
  final String? category;
  factory _NoticeItem.fromJson(Map<String, dynamic> j) => _NoticeItem._(
        j['title'] as String,
        j['url'] as String?,
        j['date'] as String?,
        j['category'] as String?,
      );
  _NoticeItem._(this.title, this.url, this.date, this.category);
}

class NewsSection extends ConsumerStatefulWidget {
  const NewsSection({super.key});

  @override
  ConsumerState<NewsSection> createState() => _NewsSectionState();
}

class _NewsSectionState extends ConsumerState<NewsSection>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final newsAsync = ref.watch(newsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _collapsed = !_collapsed),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Text('학교 소식',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                Icon(_collapsed ? Icons.expand_more : Icons.expand_less),
              ],
            ),
          ),
        ),
        if (!_collapsed) ...[
          TabBar(
            controller: _tabCtrl,
            tabs: const [
              Tab(text: '학사일정'),
              Tab(text: '공지사항'),
            ],
          ),
          SizedBox(
            height: 300,
            child: newsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(
                message: e.toString(),
                onRetry: () => ref.invalidate(newsProvider),
              ),
              data: (news) => TabBarView(
                controller: _tabCtrl,
                children: [
                  _ScheduleList(items: news.schedule),
                  _NoticeList(items: news.notices),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ScheduleList extends StatelessWidget {
  final List<_ScheduleItem> items;
  const _ScheduleList({required this.items});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        final dateStr = item.endDate != null
            ? '${item.date} ~ ${item.endDate}'
            : item.date;
        return ListTile(
          dense: true,
          title: Text(item.title),
          trailing: Text(dateStr,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        );
      },
    );
  }
}

class _NoticeList extends StatelessWidget {
  final List<_NoticeItem> items;
  const _NoticeList({required this.items});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        final date = item.date != null
            ? DateFormat('M/d').format(DateTime.parse(item.date!))
            : '';
        return ListTile(
          dense: true,
          title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('${item.category ?? ''} $date'.trim()),
          trailing: item.url != null
              ? const Icon(Icons.open_in_new, size: 16)
              : null,
          onTap: item.url != null
              ? () async {
                  final uri = Uri.tryParse(item.url!);
                  if (uri != null && await canLaunchUrl(uri)) {
                    await launchUrl(uri,
                        mode: LaunchMode.externalApplication);
                  }
                }
              : null,
        );
      },
    );
  }
}
