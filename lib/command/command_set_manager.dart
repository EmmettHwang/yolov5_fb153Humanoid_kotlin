import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/action_button_config.dart';
import '../bluetooth/bluetooth_manager.dart';
import '../services/yolo_detector_service.dart';

/// 버튼 명령어 셋 관리자 (SharedPreferences 저장)
class CommandSetManager extends ChangeNotifier {
  static const String _keyPrefix = 'button_config_';
  static const int _buttonCount = 9;

  List<ActionButtonConfig> _configs = [];
  List<ActionButtonConfig> get configs => List.unmodifiable(_configs);
  // STT 매칭용 alias
  List<ActionButtonConfig> get buttons => _configs;

  ActionButtonConfig getConfig(int buttonId) {
    return _configs.firstWhere(
      (c) => c.id == buttonId,
      orElse: () => ActionButtonConfig.defaults()
          .firstWhere((c) => c.id == buttonId),
    );
  }

  /// SharedPreferences에서 설정 불러오기
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loaded = <ActionButtonConfig>[];

      for (int i = 1; i <= _buttonCount; i++) {
        final jsonStr = prefs.getString('$_keyPrefix$i');
        if (jsonStr != null) {
          try {
            final json = jsonDecode(jsonStr) as Map<String, dynamic>;
            loaded.add(ActionButtonConfig.fromJson(json));
          } catch (e) {
            // 손상된 데이터는 기본값 사용
            loaded.add(ActionButtonConfig.defaults()[i - 1]);
          }
        } else {
          loaded.add(ActionButtonConfig.defaults()[i - 1]);
        }
      }

      _configs = loaded;
      notifyListeners();
    } catch (e) {
      _configs = ActionButtonConfig.defaults();
      notifyListeners();
    }
  }

  /// 버튼 설정 저장
  Future<void> saveConfig(ActionButtonConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(config.toJson());
      await prefs.setString('$_keyPrefix${config.id}', jsonStr);

      final idx = _configs.indexWhere((c) => c.id == config.id);
      if (idx >= 0) {
        _configs[idx] = config;
      } else {
        _configs.add(config);
        _configs.sort((a, b) => a.id.compareTo(b.id));
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('설정 저장 오류: $e');
    }
  }

  /// 기본값으로 초기화
  Future<void> resetToDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (int i = 1; i <= _buttonCount; i++) {
        await prefs.remove('$_keyPrefix$i');
      }
      _configs = ActionButtonConfig.defaults();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('초기화 오류: $e');
    }
  }

  /// 명령어 시퀀스 실행
  /// [yoloService] 가 있으면 전송 중 TFLite 추론 일시정지 → 완료 후 재개
  Future<void> executeCommandSet(
    ActionButtonConfig config,
    BluetoothManager btManager, {
    YoloDetectorService? yoloService,
  }) async {
    if (!btManager.isConnected) return;

    // 추론 일시정지 (딜레이 제거)
    yoloService?.pauseInference();

    try {
      if (config.commandSequence.isEmpty) {
        await btManager.sendMotion(config.motionIndex);
      } else {
        for (final step in config.commandSequence) {
          for (int r = 0; r < step.repeatCount; r++) {
            await btManager.sendMotion(step.motionIndex);
            await Future.delayed(Duration(milliseconds: step.holdDurationMs));
          }
        }
      }
    } finally {
      // 추론 재개 (예외 시에도 반드시 재개)
      yoloService?.resumeInference();
    }
  }
}
