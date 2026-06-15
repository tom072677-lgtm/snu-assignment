import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../domain/opportunity.dart';

abstract class OpportunityRepository {
  Future<List<Opportunity>> fetchAll();
}

typedef AssetLoader = Future<String> Function(String path);

/// Plan A 구현체: asset fixture에서 로드.
/// Plan B에서 ServerOpportunityRepository(dio)로 교체(provider 한 줄 변경).
class FixtureOpportunityRepository implements OpportunityRepository {
  final AssetLoader loadAsset;
  final String assetPath;

  FixtureOpportunityRepository({
    AssetLoader? loadAsset,
    this.assetPath = 'assets/data/opportunities_sample.json',
  }) : loadAsset = loadAsset ?? rootBundle.loadString;

  @override
  Future<List<Opportunity>> fetchAll() async {
    final raw = await loadAsset(assetPath);
    final List data = jsonDecode(raw) as List;
    return data
        .map((e) => Opportunity.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
