import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'action_button_config.dart';

/// YOLO 인식 결과(라벨)에 연동된 동작 설정
class YoloActionConfig {
  final String label;       // COCO 라벨 (예: person, cat, car)
  final bool enabled;       // 활성화 여부
  final int motionIndex;    // 실행할 모션 번호
  final String? mp3FilePath;
  final String? ttsText;
  final List<CommandStep> commandSequence;

  const YoloActionConfig({
    required this.label,
    this.enabled = false,
    this.motionIndex = 1,
    this.mp3FilePath,
    this.ttsText,
    this.commandSequence = const [],
  });

  bool get hasAudio =>
      (mp3FilePath != null && mp3FilePath!.trim().isNotEmpty) ||
      (ttsText != null && ttsText!.trim().isNotEmpty);

  String get audioHint {
    if (mp3FilePath != null && mp3FilePath!.trim().isNotEmpty) return '🎵';
    if (ttsText != null && ttsText!.trim().isNotEmpty) return '🔊';
    return '';
  }

  YoloActionConfig copyWith({
    bool? enabled,
    int? motionIndex,
    String? mp3FilePath,
    bool clearMp3 = false,
    String? ttsText,
    bool clearTts = false,
    List<CommandStep>? commandSequence,
  }) {
    return YoloActionConfig(
      label: label,
      enabled: enabled ?? this.enabled,
      motionIndex: motionIndex ?? this.motionIndex,
      mp3FilePath: clearMp3 ? null : (mp3FilePath ?? this.mp3FilePath),
      ttsText: clearTts ? null : (ttsText ?? this.ttsText),
      commandSequence: commandSequence ?? this.commandSequence,
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'enabled': enabled,
        'motionIndex': motionIndex,
        'mp3FilePath': mp3FilePath,
        'ttsText': ttsText,
        'commandSequence': commandSequence.map((s) => s.toJson()).toList(),
      };

  factory YoloActionConfig.fromJson(Map<String, dynamic> json) {
    return YoloActionConfig(
      label: json['label'] as String,
      enabled: json['enabled'] as bool? ?? false,
      motionIndex: json['motionIndex'] as int? ?? 1,
      mp3FilePath: json['mp3FilePath'] as String?,
      ttsText: json['ttsText'] as String?,
      commandSequence: (json['commandSequence'] as List<dynamic>?)
              ?.map((s) => CommandStep.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// YOLO 동작 설정 관리자
class YoloActionManager extends ChangeNotifier {
  static final YoloActionManager _instance = YoloActionManager._internal();
  factory YoloActionManager() => _instance;
  YoloActionManager._internal();

  static const _prefKey = 'yolo_action_configs';

  // 기본 감지 대상 라벨 목록 (COCO 주요 클래스)
  static const List<String> defaultLabels = [
    'person', 'cat', 'dog', 'car', 'bicycle', 'motorcycle',
    'bus', 'truck', 'bird', 'bottle', 'chair', 'cell phone',
    'cup', 'book', 'ball',
  ];

  Map<String, YoloActionConfig> _configs = {};
  Map<String, YoloActionConfig> get configs => Map.unmodifiable(_configs);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefKey);
      if (jsonStr != null) {
        final list = jsonDecode(jsonStr) as List<dynamic>;
        _configs = {
          for (final item in list)
            (item['label'] as String):
                YoloActionConfig.fromJson(item as Map<String, dynamic>)
        };
      }
      // 기본 라벨 없는 것 초기화
      for (final label in defaultLabels) {
        _configs.putIfAbsent(label, () => YoloActionConfig(label: label));
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('[YoloAction] 로드 오류: $e');
      _initDefaults();
    }
  }

  void _initDefaults() {
    _configs = {
      for (final label in defaultLabels)
        label: YoloActionConfig(label: label)
    };
    notifyListeners();
  }

  Future<void> save(YoloActionConfig config) async {
    _configs[config.label] = config;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _configs.values.map((c) => c.toJson()).toList();
      await prefs.setString(_prefKey, jsonEncode(list));
    } catch (e) {
      if (kDebugMode) debugPrint('[YoloAction] 저장 오류: $e');
    }
  }

  YoloActionConfig getConfig(String label) =>
      _configs[label] ?? YoloActionConfig(label: label);

  /// 활성화된 설정만 반환
  List<YoloActionConfig> get enabledConfigs =>
      _configs.values.where((c) => c.enabled).toList();

  /// 라벨에 매칭되는 활성 설정 반환
  YoloActionConfig? matchLabel(String detectedLabel) {
    final lower = detectedLabel.toLowerCase();
    for (final cfg in enabledConfigs) {
      if (cfg.label.toLowerCase() == lower) return cfg;
    }
    return null;
  }
}
