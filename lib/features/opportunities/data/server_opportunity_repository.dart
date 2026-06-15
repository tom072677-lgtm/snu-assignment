import '../../../core/dio_client.dart';
import '../domain/opportunity.dart';
import 'opportunity_repository.dart';

/// 서버(/api/opportunities)에서 집계된 기회 목록을 가져온다.
/// 응답 형태: { source, count, items: [ {Opportunity json}, ... ] }
class ServerOpportunityRepository implements OpportunityRepository {
  @override
  Future<List<Opportunity>> fetchAll() async {
    final res = await DioClient.instance.get('/api/opportunities');
    final data = res.data;
    final list = (data is Map && data['items'] is List)
        ? data['items'] as List
        : const [];
    return list
        .map((e) => Opportunity.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}
