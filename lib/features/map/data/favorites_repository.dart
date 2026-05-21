import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/favorite_place.dart';

typedef FavState = ({FavoritePlace? home, List<FavoritePlace> custom});

class FavoritesNotifier extends AsyncNotifier<FavState> {
  static const _homeKey = 'fav_home';
  static const _customKey = 'fav_custom';

  @override
  Future<FavState> build() async {
    final prefs = await SharedPreferences.getInstance();
    final home = FavoritePlace.tryDecode(prefs.getString(_homeKey));
    final customRaw = prefs.getString(_customKey);
    final custom = customRaw != null
        ? (jsonDecode(customRaw) as List)
            .map((e) => FavoritePlace.fromJson(e as Map<String, dynamic>))
            .toList()
        : <FavoritePlace>[];
    return (home: home, custom: custom);
  }

  Future<void> setHome(FavoritePlace place) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_homeKey, jsonEncode(place.toJson()));
    ref.invalidateSelf();
    await future;
  }

  Future<void> clearHome() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_homeKey);
    ref.invalidateSelf();
    await future;
  }

  Future<void> addCustom(FavoritePlace place) async {
    final prefs = await SharedPreferences.getInstance();
    final current = state.valueOrNull?.custom ?? [];
    final updated = [...current, place];
    await prefs.setString(_customKey, jsonEncode(updated.map((e) => e.toJson()).toList()));
    ref.invalidateSelf();
    await future;
  }

  Future<void> removeCustom(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final current = state.valueOrNull?.custom ?? [];
    final updated = current.where((e) => e.name != name).toList();
    await prefs.setString(_customKey, jsonEncode(updated.map((e) => e.toJson()).toList()));
    ref.invalidateSelf();
    await future;
  }

  Future<void> updateCustom(String oldName, FavoritePlace newPlace) async {
    final prefs = await SharedPreferences.getInstance();
    final current = state.valueOrNull?.custom ?? [];
    final updated = current.map((e) => e.name == oldName ? newPlace : e).toList();
    await prefs.setString(_customKey, jsonEncode(updated.map((e) => e.toJson()).toList()));
    ref.invalidateSelf();
    await future;
  }
}

final favoritesProvider =
    AsyncNotifierProvider<FavoritesNotifier, FavState>(FavoritesNotifier.new);
