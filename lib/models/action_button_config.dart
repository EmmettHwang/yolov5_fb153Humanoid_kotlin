/// 액션 버튼 설정 데이터 모델
class ActionButtonConfig {
  final int id; // 버튼 번호 (1~9)
  final String label; // 버튼 표시 이름
  final int motionIndex; // 전송할 모션 번호 (0~255)
  final String? mp3FilePath; // MP3 파일 경로
  final String? mp3Url; // MP3 URL
  final int color; // 버튼 배경색 (ARGB)
  final List<CommandStep> commandSequence; // 연속 모션 시퀀스

  const ActionButtonConfig({
    required this.id,
    required this.label,
    required this.motionIndex,
    this.mp3FilePath,
    this.mp3Url,
    required this.color,
    this.commandSequence = const [],
  });

  ActionButtonConfig copyWith({
    String? label,
    int? motionIndex,
    String? mp3FilePath,
    String? mp3Url,
    int? color,
    List<CommandStep>? commandSequence,
  }) {
    return ActionButtonConfig(
      id: id,
      label: label ?? this.label,
      motionIndex: motionIndex ?? this.motionIndex,
      mp3FilePath: mp3FilePath ?? this.mp3FilePath,
      mp3Url: mp3Url ?? this.mp3Url,
      color: color ?? this.color,
      commandSequence: commandSequence ?? this.commandSequence,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'motionIndex': motionIndex,
        'mp3FilePath': mp3FilePath,
        'mp3Url': mp3Url,
        'color': color,
        'commandSequence': commandSequence.map((s) => s.toJson()).toList(),
      };

  factory ActionButtonConfig.fromJson(Map<String, dynamic> json) {
    return ActionButtonConfig(
      id: json['id'] as int,
      label: json['label'] as String,
      motionIndex: json['motionIndex'] as int,
      mp3FilePath: json['mp3FilePath'] as String?,
      mp3Url: json['mp3Url'] as String?,
      color: json['color'] as int,
      commandSequence: (json['commandSequence'] as List<dynamic>?)
              ?.map((s) => CommandStep.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// 기본 버튼 설정 (1~9)
  static List<ActionButtonConfig> defaults() {
    final defaults = [
      (id: 1, label: '인사', motion: 19, color: 0xFF6200EE),
      (id: 2, label: '손흔들기', motion: 18, color: 0xFF03DAC6),
      (id: 3, label: '커스텀1', motion: 20, color: 0xFFFF5722),
      (id: 4, label: '커스텀2', motion: 21, color: 0xFF2196F3),
      (id: 5, label: '커스텀3', motion: 22, color: 0xFF4CAF50),
      (id: 6, label: '커스텀4', motion: 23, color: 0xFFFF9800),
      (id: 7, label: '커스텀5', motion: 24, color: 0xFF9C27B0),
      (id: 8, label: '커스텀6', motion: 25, color: 0xFF00BCD4),
      (id: 9, label: '복귀', motion: 1, color: 0xFFF44336),
    ];

    return defaults
        .map((d) => ActionButtonConfig(
              id: d.id,
              label: d.label,
              motionIndex: d.motion,
              color: d.color,
              commandSequence: [
                CommandStep(
                  motionIndex: d.motion,
                  holdDurationMs: 3000,
                ),
              ],
            ))
        .toList();
  }
}

/// 명령어 단계
class CommandStep {
  final int motionIndex;
  final int holdDurationMs;
  final int repeatCount;

  const CommandStep({
    required this.motionIndex,
    required this.holdDurationMs,
    this.repeatCount = 1,
  });

  Map<String, dynamic> toJson() => {
        'motionIndex': motionIndex,
        'holdDurationMs': holdDurationMs,
        'repeatCount': repeatCount,
      };

  factory CommandStep.fromJson(Map<String, dynamic> json) {
    return CommandStep(
      motionIndex: json['motionIndex'] as int,
      holdDurationMs: json['holdDurationMs'] as int,
      repeatCount: json['repeatCount'] as int? ?? 1,
    );
  }
}
