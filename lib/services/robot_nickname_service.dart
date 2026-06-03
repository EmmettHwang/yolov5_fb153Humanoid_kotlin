import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── 아바타 종류 ───────────────────────────────────────────────────
enum RobotAvatarType { icon, photo }

const kAvatarIcons = [
  'smart_toy',               // 0 로봇 (기본)
  'android',                 // 1 안드로이드
  'precision_manufacturing', // 2 공장 로봇
  'adb',                     // 3 디버그 봇
  'memory',                  // 4 AI 칩
  'self_improvement',        // 5 명상 봇
];

/// MAC 주소 → 로봇 프로필 (별명 + 아바타 + 색상 + 사진) 관리
class RobotNicknameService extends ChangeNotifier {
  static final RobotNicknameService _instance = RobotNicknameService._internal();
  factory RobotNicknameService() => _instance;
  RobotNicknameService._internal();

  static const _prefKey = 'robot_profiles_v2';

  // MAC → 프로필 맵
  Map<String, _RobotProfile> _profiles = {};

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefKey);
      if (json != null) {
        final map = jsonDecode(json) as Map<String, dynamic>;
        _profiles = map.map((k, v) =>
            MapEntry(k, _RobotProfile.fromJson(v as Map<String, dynamic>)));
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('[Profile] 로드 오류: $e');
    }
  }

  // ── 조회 ────────────────────────────────────────────────────
  _RobotProfile? _profile(String mac) => _profiles[mac.toUpperCase()];

  String? getNickname(String mac) => _profile(mac)?.nickname;

  String displayName(String mac, String defaultName) {
    final nick = getNickname(mac);
    return (nick != null && nick.trim().isNotEmpty) ? nick : defaultName;
  }

  bool hasNickname(String mac) {
    final nick = _profile(mac)?.nickname;
    return nick != null && nick.trim().isNotEmpty;
  }

  int getAvatarIconIndex(String mac) => _profile(mac)?.iconIndex ?? 0;
  int getAvatarColor(String mac) => _profile(mac)?.colorValue ?? 0xFF00BCD4;
  String? getPhotoPath(String mac) => _profile(mac)?.photoPath;
  RobotAvatarType getAvatarType(String mac) =>
      _profile(mac)?.avatarType ?? RobotAvatarType.icon;

  // ── 저장 ────────────────────────────────────────────────────
  Future<void> setProfile(
    String mac, {
    String? nickname,
    int? iconIndex,
    int? colorValue,
    String? photoPath,
    RobotAvatarType? avatarType,
  }) async {
    final key = mac.toUpperCase();
    final existing = _profiles[key] ?? const _RobotProfile();
    _profiles[key] = existing.copyWith(
      nickname: nickname,
      iconIndex: iconIndex,
      colorValue: colorValue,
      photoPath: photoPath,
      avatarType: avatarType,
    );
    notifyListeners();
    await _persist();
  }

  Future<void> setNickname(String mac, String nickname) =>
      setProfile(mac, nickname: nickname);

  Future<void> removeNickname(String mac) async {
    final key = mac.toUpperCase();
    if (_profiles.containsKey(key)) {
      _profiles[key] = _profiles[key]!.copyWith(nickname: '');
      notifyListeners();
      await _persist();
    }
  }

  Future<void> removeProfile(String mac) async {
    _profiles.remove(mac.toUpperCase());
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefKey,
          jsonEncode(_profiles.map((k, v) => MapEntry(k, v.toJson()))));
    } catch (e) {
      if (kDebugMode) debugPrint('[Profile] 저장 오류: $e');
    }
  }
}

// ── 내부 프로필 모델 ─────────────────────────────────────────────
class _RobotProfile {
  final String nickname;
  final int iconIndex;    // kAvatarIcons 인덱스
  final int colorValue;   // Color.value (ARGB int)
  final String? photoPath; // 로컬 파일 경로
  final RobotAvatarType avatarType;

  const _RobotProfile({
    this.nickname = '',
    this.iconIndex = 0,
    this.colorValue = 0xFF00BCD4,
    this.photoPath,
    this.avatarType = RobotAvatarType.icon,
  });

  _RobotProfile copyWith({
    String? nickname,
    int? iconIndex,
    int? colorValue,
    String? photoPath,
    RobotAvatarType? avatarType,
  }) =>
      _RobotProfile(
        nickname: nickname ?? this.nickname,
        iconIndex: iconIndex ?? this.iconIndex,
        colorValue: colorValue ?? this.colorValue,
        photoPath: photoPath ?? this.photoPath,
        avatarType: avatarType ?? this.avatarType,
      );

  Map<String, dynamic> toJson() => {
        'nickname': nickname,
        'iconIndex': iconIndex,
        'colorValue': colorValue,
        if (photoPath != null) 'photoPath': photoPath,
        'avatarType': avatarType.name,
      };

  factory _RobotProfile.fromJson(Map<String, dynamic> j) => _RobotProfile(
        nickname: j['nickname'] as String? ?? '',
        iconIndex: j['iconIndex'] as int? ?? 0,
        colorValue: j['colorValue'] as int? ?? 0xFF00BCD4,
        photoPath: j['photoPath'] as String?,
        avatarType: RobotAvatarType.values.firstWhere(
          (e) => e.name == (j['avatarType'] as String? ?? 'icon'),
          orElse: () => RobotAvatarType.icon,
        ),
      );
}

// ── 아바타 위젯 (공통 사용) ─────────────────────────────────────
class RobotAvatarWidget extends StatelessWidget {
  final String mac;
  final RobotNicknameService service;
  final double size;

  const RobotAvatarWidget({
    super.key,
    required this.mac,
    required this.service,
    this.size = 50,
  });

  static IconData iconDataFromName(String name) {
    switch (name) {
      case 'android':
        return Icons.android;
      case 'precision_manufacturing':
        return Icons.precision_manufacturing;
      case 'adb':
        return Icons.adb;
      case 'memory':
        return Icons.memory;
      case 'self_improvement':
        return Icons.self_improvement;
      default:
        return Icons.smart_toy;
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarType = service.getAvatarType(mac);
    final colorValue = service.getAvatarColor(mac);
    final color = Color(colorValue);
    final photoPath = service.getPhotoPath(mac);
    final iconIdx = service.getAvatarIconIndex(mac);

    if (avatarType == RobotAvatarType.photo &&
        photoPath != null &&
        File(photoPath).existsSync()) {
      return CircleAvatar(
        radius: size / 2,
        backgroundImage: FileImage(File(photoPath)),
        backgroundColor: color.withValues(alpha: 0.2),
      );
    }

    final iconName =
        iconIdx < kAvatarIcons.length ? kAvatarIcons[iconIdx] : kAvatarIcons[0];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Icon(iconDataFromName(iconName), color: color, size: size * 0.48),
    );
  }
}
