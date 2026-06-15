import 'opportunity.dart';

enum ScrapStatus { interested, preparing, applied }

ScrapStatus scrapStatusFrom(String s) => ScrapStatus.values
    .firstWhere((e) => e.name == s, orElse: () => ScrapStatus.interested);

class ScrapEntry {
  final String id;
  final String title;
  final DateTime? deadline;
  final ScrapStatus status;

  const ScrapEntry({
    required this.id,
    required this.title,
    required this.deadline,
    required this.status,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'deadline': deadline?.toIso8601String(),
        'status': status.name,
      };

  factory ScrapEntry.fromJson(Map<String, dynamic> j) => ScrapEntry(
        id: j['id'] as String,
        title: j['title'] as String,
        deadline:
            j['deadline'] == null ? null : DateTime.parse(j['deadline'] as String),
        status: scrapStatusFrom(j['status'] as String? ?? 'interested'),
      );

  ScrapEntry copyWith({ScrapStatus? status}) => ScrapEntry(
        id: id,
        title: title,
        deadline: deadline,
        status: status ?? this.status,
      );
}

ScrapEntry scrapEntryOf(Opportunity o) => ScrapEntry(
      id: o.id,
      title: o.title,
      deadline: o.deadline,
      status: ScrapStatus.interested,
    );
