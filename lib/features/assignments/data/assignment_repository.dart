import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/dio_client.dart';
import '../../../shared/providers/settings_provider.dart';
import '../domain/assignment.dart';

class AssignmentRepository {
  final Dio _dio;
  final String? icalUrl;
  final String? apiToken;

  AssignmentRepository({
    required Dio dio,
    required this.icalUrl,
    required this.apiToken,
  }) : _dio = dio;

  Future<List<Assignment>> fetchAssignments() async {
    if (icalUrl == null || icalUrl!.isEmpty) return [];

    final response = await _dio.post(
      '/api/sync-ical',
      data: {
        'icalUrl': icalUrl,
        if (apiToken != null && apiToken!.isNotEmpty) 'apiToken': apiToken,
      },
    );

    final list = (response.data as List)
        .map((e) => Assignment.fromJson(e as Map<String, dynamic>))
        .toList();
    return list;
  }
}

final assignmentRepositoryProvider = Provider<AssignmentRepository>((ref) {
  return AssignmentRepository(
    dio: DioClient.instance,
    icalUrl: ref.watch(icalUrlProvider),
    apiToken: ref.watch(canvasTokenProvider),
  );
});

final assignmentsProvider =
    FutureProvider.autoDispose<List<Assignment>>((ref) async {
  final repo = ref.watch(assignmentRepositoryProvider);
  return repo.fetchAssignments();
});
