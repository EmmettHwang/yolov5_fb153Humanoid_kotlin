import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 로봇 이름 관리 서비스
class RobotNameService extends ChangeNotifier {
  static final RobotNameService _instance = RobotNameService._internal();
  factory RobotNameService() => _instance;
  RobotNameService._internal();

  static const _prefKey = 'robot_name';
  static const String defaultName = 'ROBO';

  String _name = defaultName;
  String get name => _name;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _name = prefs.getString(_prefKey) ?? defaultName;
    notifyListeners();
  }

  Future<void> setName(String name) async {
    final trimmed = name.trim().isEmpty ? defaultName : name.trim();
    _name = trimmed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, trimmed);
    notifyListeners();
  }
}
