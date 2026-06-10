import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/dio_client.dart';
import '../domain/library_models.dart';

class LibraryRepository {
  Future<LibrarySeats> fetchSeats() async {
    final response = await DioClient.instance.get('/api/library/seats');
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      final head = data.toString();
      debugPrint('[library] unexpected response: '
          '${head.length > 200 ? head.substring(0, 200) : head}');
      throw Exception('도서관 좌석 응답 형식이 올바르지 않습니다');
    }
    return LibrarySeats.fromJson(data);
  }
}

final libraryRepositoryProvider = Provider((_) => LibraryRepository());

// AutoDispose so it re-fetches when navigated to
final librarySeatsProvider =
    FutureProvider.autoDispose<LibrarySeats>((ref) async {
  return ref.read(libraryRepositoryProvider).fetchSeats();
});
