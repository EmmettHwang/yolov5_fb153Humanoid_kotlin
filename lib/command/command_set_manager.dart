import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/action_button_config.dart';
import '../bluetooth/bluetooth_manager.dart';
import '../services/yolo_detector_service.dart';
import '../services/audio_service.dart';

/// 버튼 명령어 셋 관리자 (SharedPreferences 저장)
class CommandSetManager extends ChangeNotifier {
  static const String _keyPrefix = 'button_config_';
  static const int _buttonCount = 15;

  List<ActionButtonConfig> _configs = [];
  List<ActionButtonConfig> get configs => List.unmodifiable(_configs);
  List<ActionButtonConfig> get buttons => _configs;

  ActionButtonConfig getConfig(int buttonId) {
    if (buttonId < 1 || buttonId > _buttonCount) {
      return ActionButtonConfig.defaults().first;
    }
    return _configs.firstWhere(
      (c) => c.id == buttonId,
      orElse: () {
        final defs = ActionButtonConfig.defaults();
        return defs.firstWhere(
          (c) => c.id == buttonId,
          orElse: () => ActionButtonConfig(
            id: buttonId,
            label: '버튼$buttonId',
            motionIndex: buttonId,
            color: 0xFF37474F,
          ),
        );
      },
    );
  }

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
            loaded.add(_defaultForIndex(i));
          }
        } else {
          loaded.add(_defaultForIndex(i));
        }
      }

      _configs = loaded;
      notifyListeners();
    } catch (e) {
      _configs = List.generate(_buttonCount, (i) => _defaultForIndex(i + 1));
      notifyListeners();
    }
  }

  ActionButtonConfig _defaultForIndex(int i) {
    final defs = ActionButtonConfig.defaults();
    return defs.firstWhere(
      (c) => c.id == i,
      orElse: () => ActionButtonConfig(
        id: i,
        label: '버튼$i',
        motionIndex: i,
        color: 0xFF37474F,
      ),
    );
  }

  Future<void> saveConfig(ActionButtonConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_keyPrefix${config.id}', jsonEncode(config.toJson()));

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

  Future<void> resetToDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (int i = 1; i <= _buttonCount; i++) {
        await prefs.remove('$_keyPrefix$i');
      }
      _configs = List.generate(_buttonCount, (i) => _defaultForIndex(i + 1));
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('초기화 오류: $e');
    }
  }

  /// 명령어 시퀀스 실행
  /// - 모션 패킷 전송
  /// - 오디오(TTS/MP3)가 있으면 AudioService 재생 →
  ///   LedSpeechAnimator 가 attach() 돼 있으면 자동으로 18번 머리 LED 반짝임
  Future<void> executeCommandSet(
    ActionButtonConfig config,
    BluetoothManager btManager, {
    YoloDetectorService? yoloService,
  }) async {
    if (!btManager.isConnected) return;

    yoloService?.pauseInference();

    try {
      // 모션 실행
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

      // 오디오 재생 (비동기 — LED 애니메이션은 AudioService 콜백으로 자동 트리거)
      if (config.hasAudio) {
        AudioService().playForButton(
          mp3FilePath: config.mp3FilePath,
          ttsText: config.ttsText,
        );
      }
    } finally {
      yoloService?.resumeInference();
    }
  }
}
