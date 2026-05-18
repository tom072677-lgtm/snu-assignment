import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/dio_client.dart';
import '../domain/restaurant.dart';

final restaurantProvider =
    FutureProvider.autoDispose<List<Restaurant>>((ref) async {
  final response = await DioClient.instance.get('/api/restaurant/snuco');
  final data = response.data as Map<String, dynamic>;
  final list = (data['restaurants'] as List)
      .map((e) => Restaurant.fromJson(e as Map<String, dynamic>))
      .toList();
  return list;
});
