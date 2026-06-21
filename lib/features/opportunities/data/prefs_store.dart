import 'package:shared_preferences/shared_preferences.dart';
import '../domain/user_prefs.dart';

/// 개인화 설정(관심분야) 영속 저장. (지역은 앱 내 세션 필터로 이동 — selectedRegionProvider)
class OppPrefsStore {
  static const _kInterests = 'opp_interests_v1';

  Future<OppUserPrefs> load() async {
    final p = await SharedPreferences.getInstance();
    return OppUserPrefs(
      interests: (p.getStringList(_kInterests) ?? const []).toSet(),
    );
  }

  Future<void> save(OppUserPrefs prefs) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kInterests, prefs.interests.toList());
  }
}
