import 'package:shared_preferences/shared_preferences.dart';
import '../domain/user_prefs.dart';

/// 개인화 설정(관심분야·지역) 영속 저장.
class OppPrefsStore {
  static const _kInterests = 'opp_interests_v1';
  static const _kRegion = 'opp_region_v1';

  Future<OppUserPrefs> load() async {
    final p = await SharedPreferences.getInstance();
    return OppUserPrefs(
      interests: (p.getStringList(_kInterests) ?? const []).toSet(),
      region: p.getString(_kRegion),
    );
  }

  Future<void> save(OppUserPrefs prefs) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kInterests, prefs.interests.toList());
    if (prefs.region == null) {
      await p.remove(_kRegion);
    } else {
      await p.setString(_kRegion, prefs.region!);
    }
  }
}
