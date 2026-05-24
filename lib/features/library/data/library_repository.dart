import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/dio_client.dart';
import '../domain/library_models.dart';

class LibraryRepository {
  Future<LibrarySeats> fetchSeats() async {
    final response = await DioClient.instance.get('/api/library/seats');
    return LibrarySeats.fromJson(response.data as Map<String, dynamic>);
  }
}

final libraryRepositoryProvider = Provider((_) => LibraryRepository());

// AutoDispose so it re-fetches when navigated to
final librarySeatsProvider =
    FutureProvider.autoDispose<LibrarySeats>((ref) async {
  return ref.read(libraryRepositoryProvider).fetchSeats();
});
