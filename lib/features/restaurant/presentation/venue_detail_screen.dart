import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../domain/venue.dart';
import '../../map/data/map_repository.dart';
import '../../map/presentation/widgets/route_panel.dart';

class VenueDetailScreen extends StatelessWidget {
  final Venue venue;
  const VenueDetailScreen({super.key, required this.venue});

  @override
  Widget build(BuildContext context) {
    final isOpen = venue.isOpenAt(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Text(venue.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isOpen
                  ? Colors.green.withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              isOpen ? '영업중' : '준비중',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isOpen ? Colors.green[700] : Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 위치 + 전화
          _InfoCard(venue: venue),
          const SizedBox(height: 12),
          // 운영시간
          _HoursCard(hours: venue.hours),
          const SizedBox(height: 12),
          // 메뉴 (SNUCO)
          if (venue.type == VenueType.snuco) ...[
            _SnucoMenuCard(venue: venue),
            const SizedBox(height: 12),
          ],
          // Instagram (강여사집밥 등)
          if (venue.type == VenueType.instagram) ...[
            _InstagramCard(venue: venue),
            const SizedBox(height: 12),
          ],
          // 길찾기 버튼
          FilledButton.icon(
            onPressed: () => _openDirections(context),
            icon: const Icon(Icons.directions),
            label: const Text('길찾기'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _openDirections(BuildContext context) {
    final dest = PlaceResult(
      name: venue.name,
      address: venue.address,
      lat: venue.lat,
      lng: venue.lng,
      category: '',
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => RouteOverlayPanel(
        dest: dest,
        onClose: () => Navigator.pop(ctx),
        onRouteLoaded: (result, mode) {}, // 지도 없는 맥락: 경로 정보만 표시
        onOriginChanged: (_) {},
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final Venue venue;
  const _InfoCard({required this.venue});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _Row(
              icon: Icons.location_on_outlined,
              label: '위치',
              value: '${venue.building}\n${venue.address}',
            ),
            if (venue.phone != null) ...[
              const Divider(height: 16),
              GestureDetector(
                onTap: () => _launchTel(context, venue.phone!),
                child: _Row(
                  icon: Icons.phone_outlined,
                  label: '전화',
                  value: venue.phone!,
                  valueColor: Colors.blue,
                ),
              ),
            ],
            if (venue.tags.isNotEmpty) ...[
              const Divider(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.label_outline, size: 18, color: Colors.grey[500]),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: venue.tags.map((t) => Chip(
                        label: Text(t, style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      )).toList(),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _launchTel(BuildContext context, String phone) async {
    try {
      final uri = Uri.parse('tel:$phone');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('앱을 열 수 없어요')));
      }
    } catch (e) {
      debugPrint('[venue] 전화 연결 실패: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('앱을 열 수 없어요')));
      }
    }
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  const _Row({required this.icon, required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey[500]),
        const SizedBox(width: 10),
        SizedBox(
          width: 40,
          child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 13, color: valueColor),
          ),
        ),
      ],
    );
  }
}

class _HoursCard extends StatelessWidget {
  final VenueHours hours;
  const _HoursCard({required this.hours});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('운영시간',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 10),
            _DayRow(label: '평일', day: hours.weekday),
            const SizedBox(height: 6),
            _DayRow(label: '토요일', day: hours.saturday),
            const SizedBox(height: 6),
            _DayRow(label: '일요일', day: hours.sunday),
          ],
        ),
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  final String label;
  final DayHours day;
  const _DayRow({required this.label, required this.day});

  @override
  Widget build(BuildContext context) {
    final text = day.closed || day.ranges.isEmpty
        ? '휴무'
        : day.ranges.map((r) => '${r.open}–${r.close}').join(', ');
    final isClosed = day.closed || day.ranges.isEmpty;
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        ),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: isClosed ? Colors.grey : null,
            fontWeight: isClosed ? FontWeight.normal : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _SnucoMenuCard extends StatelessWidget {
  final Venue venue;
  const _SnucoMenuCard({required this.venue});

  @override
  Widget build(BuildContext context) {
    final hasMenu = venue.snucoBreakfast != null ||
        venue.snucoLunch != null ||
        venue.snucoDinner != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('오늘의 메뉴',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 10),
            if (!hasMenu)
              const Text('오늘 메뉴 정보가 없습니다',
                  style: TextStyle(color: Colors.grey))
            else ...[
              if (venue.snucoBreakfast?.isNotEmpty == true)
                _MealSection(label: '조식', menu: venue.snucoBreakfast!),
              if (venue.snucoLunch?.isNotEmpty == true)
                _MealSection(label: '중식', menu: venue.snucoLunch!),
              if (venue.snucoDinner?.isNotEmpty == true)
                _MealSection(label: '석식', menu: venue.snucoDinner!),
            ],
          ],
        ),
      ),
    );
  }
}

class _MealSection extends StatelessWidget {
  final String label;
  final String menu;
  const _MealSection({required this.label, required this.menu});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1565C0),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(menu, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _InstagramCard extends StatelessWidget {
  final Venue venue;
  const _InstagramCard({required this.venue});

  @override
  Widget build(BuildContext context) {
    final posts = venue.instagramPosts;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.photo_camera_outlined, size: 18),
                const SizedBox(width: 6),
                const Text('최근 메뉴',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const Spacer(),
                if (venue.instagramHandle != null)
                  TextButton(
                    onPressed: () => _openInstagram(context),
                    child: Text(venue.instagramHandle!,
                        style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (posts == null || posts.isEmpty)
              const Text('인스타그램 연동 대기 중',
                  style: TextStyle(color: Colors.grey))
            else
              ...posts.take(3).map((p) => _IgPost(post: p)),
          ],
        ),
      ),
    );
  }

  Future<void> _openInstagram(BuildContext context) async {
    try {
      final uri = Uri.parse(
          'https://instagram.com/${venue.instagramHandle!.replaceAll('@', '')}');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('앱을 열 수 없어요')));
      }
    } catch (e) {
      debugPrint('[venue] 인스타그램 열기 실패: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('앱을 열 수 없어요')));
      }
    }
  }
}

class _IgPost extends StatelessWidget {
  final Map<String, dynamic> post;
  const _IgPost({required this.post});

  @override
  Widget build(BuildContext context) {
    final caption = (post['caption'] as String? ?? '').split('\n').first;
    final raw = post['date'] as String? ?? '';
    final date = raw.length >= 10 ? raw.substring(0, 10) : raw;
    return GestureDetector(
      onTap: () => _openPost(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            if (post['imageUrl'] != null && (post['imageUrl'] as String).isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  post['imageUrl'] as String,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(width: 52, height: 52),
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(date,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  // 스크래핑된 게시물 URL은 신뢰할 수 없으므로 scheme 검증 후 열기
  Future<void> _openPost(BuildContext context) async {
    final url = post['url'] as String?;
    if (url == null) return;
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        debugPrint('[venue] 차단된 게시물 scheme: ${uri.scheme}');
        return;
      }
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('앱을 열 수 없어요')));
      }
    } catch (e) {
      debugPrint('[venue] 게시물 열기 실패: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('앱을 열 수 없어요')));
      }
    }
  }
}
