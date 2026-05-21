class AssignmentFile {
  final String name;
  final String url;

  const AssignmentFile({required this.name, required this.url});

  factory AssignmentFile.fromJson(Map<String, dynamic> json) => AssignmentFile(
        name: json['name'] as String? ?? '파일',
        url: json['url'] as String,
      );
}

class AssignmentDetail {
  final String name;
  final String descriptionText;
  final List<AssignmentFile> attachments;
  final List<String> submissionTypes;
  final List<String> allowedExtensions;

  const AssignmentDetail({
    required this.name,
    required this.descriptionText,
    required this.attachments,
    required this.submissionTypes,
    required this.allowedExtensions,
  });

  factory AssignmentDetail.fromJson(Map<String, dynamic> json) =>
      AssignmentDetail(
        name: json['name'] as String? ?? '',
        descriptionText: json['descriptionText'] as String? ?? '',
        attachments: (json['attachments'] as List? ?? [])
            .map((e) => AssignmentFile.fromJson(e as Map<String, dynamic>))
            .toList(),
        submissionTypes: (json['submissionTypes'] as List? ?? [])
            .map((e) => e as String)
            .toList(),
        allowedExtensions: (json['allowedExtensions'] as List? ?? [])
            .map((e) => e as String)
            .toList(),
      );
}
