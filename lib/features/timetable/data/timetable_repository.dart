import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/dio_client.dart';
import '../../../shared/providers/settings_provider.dart';
import '../domain/timetable_models.dart';

class TimetableRepository {
  Future<TimetableData> fetch({
    required String icalUrl,
    String? canvasToken,
  }) async {
    final response = await DioClient.instance.post(
      '/api/timetable',
      data: {
        'icalUrl': icalUrl,
        if (canvasToken != null && canvasToken.isNotEmpty)
          'canvasToken': canvasToken,
      },
    );
    final data = response.data as Map<String, dynamic>;
    final errors = data['errors'] as Map<String, dynamic>?;
    final sessionError = errors?['sessions'] as String?;
    if (sessionError != null) throw Exception(sessionError);
    return TimetableData.fromJson(data);
  }
}

final timetableRepositoryProvider =
    Provider((_) => TimetableRepository());

final timetableProvider = FutureProvider.autoDispose<TimetableData>((ref) async {
  final icalUrl = ref.watch(icalUrlProvider);
  final canvasToken = ref.watch(canvasTokenProvider);

  if (icalUrl == null || icalUrl.isEmpty) {
    return const TimetableData(courses: [], sessions: []);
  }

  return ref.read(timetableRepositoryProvider).fetch(
        icalUrl: icalUrl,
        canvasToken: canvasToken,
      );
});
