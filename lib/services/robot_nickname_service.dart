import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MAC 주소 → 사용자 지정 로봇 별명 관리
/// 예) "AA:BB:CC:DD:EE:FF" → "내 로봇1"
class RobotNicknameService extends ChangeNotifier {
  static final RobotNicknameService _instance = RobotNicknameService._internal();
  factory RobotNicknameService() => _instance;
  RobotNicknameService._internal();

  static const _prefKey = 'robot_nicknames';

  // MAC → 별명 맵
  Map<String, String> _nicknames = {};

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefKey);
      if (json != null) {
        final map = jsonDecode(json) as Map<String, dynamic>;
        _nicknames = map.map((k, v) => MapEntry(k, v as String));
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('[Nickname] 로드 오류: $e');
    }
  }

  /// MAC 주소로 별명 조회 (없으면 null)
  String? getNickname(String mac) => _nicknames[mac.toUpperCase()];

  /// MAC 주소로 표시 이름 조회 (별명 있으면 별명, 없으면 기본 이름)
  String displayName(String mac, String defaultName) {
    final nick = getNickname(mac);
    return (nick != null && nick.trim().isNotEmpty) ? nick : defaultName;
  }

  /// 별명 설정
  Future<void> setNickname(String mac, String nickname) async {
    final key = mac.toUpperCase();
    if (nickname.trim().isEmpty) {
      _nicknames.remove(key);
    } else {
      _nicknames[key] = nickname.trim();
    }
    notifyListeners();
    await _persist();
  }

  /// 별명 삭제
  Future<void> removeNickname(String mac) async {
    _nicknames.remove(mac.toUpperCase());
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, jsonEncode(_nicknames));
    } catch (e) {
      if (kDebugMode) debugPrint('[Nickname] 저장 오류: $e');
    }
  }

  bool hasNickname(String mac) {
    final nick = _nicknames[mac.toUpperCase()];
    return nick != null && nick.trim().isNotEmpty;
  }
}
