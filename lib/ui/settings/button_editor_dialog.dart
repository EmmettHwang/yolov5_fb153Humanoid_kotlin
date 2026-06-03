import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/action_button_config.dart';
import '../../models/motion_table.dart';
import '../../command/command_set_manager.dart';
import '../../services/audio_service.dart';

/// 버튼 편집 다이얼로그
class ButtonEditorDialog extends StatefulWidget {
  final ActionButtonConfig config;

  const ButtonEditorDialog({super.key, required this.config});

  @override
  State<ButtonEditorDialog> createState() => _ButtonEditorDialogState();
}

class _ButtonEditorDialogState extends State<ButtonEditorDialog> {
  late TextEditingController _labelCtrl;
  late TextEditingController _mp3Ctrl;
  late TextEditingController _ttsCtrl;
  late int _motionIndex;
  late int _color;
  late List<CommandStep> _sequence;

  // 오디오 모드: 'none' | 'mp3' | 'tts'
  late String _audioMode;

  static const List<int> _presetColors = [
    0xFF6200EE, // 보라
    0xFF03DAC6, // 청록
    0xFFFF5722, // 주황
    0xFF2196F3, // 파랑
    0xFF4CAF50, // 초록
    0xFFFF9800, // 오렌지
    0xFF9C27B0, // 자주
    0xFF00BCD4, // 시안
    0xFFF44336, // 빨강
    0xFF607D8B, // 회색
  ];

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.config.label);
    _mp3Ctrl   = TextEditingController(text: widget.config.mp3FilePath ?? '');
    _ttsCtrl   = TextEditingController(text: widget.config.ttsText ?? '');
    _motionIndex = widget.config.motionIndex;
    _color = widget.config.color;
    _sequence = List.from(widget.config.commandSequence);
    if (_sequence.isEmpty) {
      _sequence.add(CommandStep(motionIndex: _motionIndex, holdDurationMs: 3000));
    }

    // 초기 모드 설정
    if (widget.config.mp3FilePath != null && widget.config.mp3FilePath!.isNotEmpty) {
      _audioMode = 'mp3';
    } else if (widget.config.ttsText != null && widget.config.ttsText!.isNotEmpty) {
      _audioMode = 'tts';
    } else {
      _audioMode = 'none';
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _mp3Ctrl.dispose();
    _ttsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0D1F2D),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.cyan.withValues(alpha: 0.4)),
      ),
      child: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 헤더 ──
              Row(
                children: [
                  const Icon(Icons.edit, color: Colors.cyanAccent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '버튼 ${widget.config.id} 설정',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const Divider(color: Colors.white24),
              const SizedBox(height: 8),

              // ── 버튼 이름 ──
              _buildLabel('버튼 이름'),
              TextField(
                controller: _labelCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('인사, 댄스, 복귀...'),
              ),
              const SizedBox(height: 16),

              // ── 기본 모션 번호 (스피너 + 모션 이름) ──
              _buildLabel('기본 모션 번호'),
              _MotionSpinner(
                value: _motionIndex,
                onChanged: (v) => setState(() => _motionIndex = v),
              ),
              const SizedBox(height: 16),

              // ── 색상 선택 ──
              _buildLabel('버튼 색상'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _presetColors.map((c) {
                  final isSelected = c == _color;
                  return GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: Colors.white, width: 2.5)
                            : null,
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: Color(c).withValues(alpha: 0.6),
                                  blurRadius: 6,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // ══════════════════════════════════════════════════════════════
              // ── 오디오 설정 섹션 ──
              // ══════════════════════════════════════════════════════════════
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.cyan.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 섹션 헤더
                    const Row(
                      children: [
                        Icon(Icons.volume_up,
                            color: Colors.cyanAccent, size: 16),
                        SizedBox(width: 6),
                        Text(
                          '버튼 실행 시 소리',
                          style: TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 모드 선택 (SegmentedButton)
                    Row(
                      children: [
                        _AudioModeChip(
                          label: '없음',
                          icon: Icons.music_off,
                          selected: _audioMode == 'none',
                          onTap: () => setState(() => _audioMode = 'none'),
                        ),
                        const SizedBox(width: 6),
                        _AudioModeChip(
                          label: 'MP3 파일',
                          icon: Icons.audio_file,
                          selected: _audioMode == 'mp3',
                          onTap: () => setState(() => _audioMode = 'mp3'),
                        ),
                        const SizedBox(width: 6),
                        _AudioModeChip(
                          label: 'TTS 음성',
                          icon: Icons.record_voice_over,
                          selected: _audioMode == 'tts',
                          onTap: () => setState(() => _audioMode = 'tts'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // MP3 모드
                    if (_audioMode == 'mp3') ...[
                      _buildLabel('MP3 파일'),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _mp3Ctrl,
                              readOnly: true,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                              decoration: _inputDecoration('파일을 선택하세요')
                                  .copyWith(
                                helperText: '📁 아이콘을 눌러 파일 탐색기 열기',
                                helperStyle: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.35),
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _pickMp3File,
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.cyan.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: Colors.cyan.withValues(alpha: 0.4)),
                              ),
                              child: const Icon(Icons.folder_open,
                                  color: Colors.cyanAccent, size: 22),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // 테스트 재생 버튼
                      _buildTestButton(
                        label: '🎵 미리 듣기',
                        onTap: () async {
                          final path = _mp3Ctrl.text.trim();
                          if (path.isEmpty) return;
                          await AudioService().playForButton(mp3FilePath: path);
                        },
                      ),
                    ],

                    // TTS 모드
                    if (_audioMode == 'tts') ...[
                      _buildLabel('읽을 텍스트'),
                      TextField(
                        controller: _ttsCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: _inputDecoration(
                          '한국어 또는 영어 텍스트를 입력하세요\n예) 안녕하세요!  또는  Hello Robot!',
                        ).copyWith(
                          helperText: '한글/영어 자동 감지 · 버튼 실행 시 TTS 발화',
                          helperStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 10,
                          ),
                        ),
                        maxLines: 3,
                        minLines: 2,
                      ),
                      const SizedBox(height: 8),
                      // TTS 테스트
                      _buildTestButton(
                        label: '🔊 미리 듣기',
                        onTap: () async {
                          final text = _ttsCtrl.text.trim();
                          if (text.isEmpty) return;
                          await AudioService().speak(text);
                        },
                      ),
                    ],

                    // 없음 안내
                    if (_audioMode == 'none')
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          '소리 없이 동작만 실행합니다.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.35),
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── 명령어 시퀀스 ──
              Row(
                children: [
                  _buildLabel('명령어 시퀀스'),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('추가', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.cyanAccent,
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: _addStep,
                  ),
                ],
              ),
              ..._sequence.asMap().entries.map((e) => _buildStepRow(e.key, e.value)),

              const SizedBox(height: 20),

              // ── 저장/취소 ──
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white54,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyanAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _save,
                      child: const Text(
                        '저장',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 테스트 재생 버튼 ──────────────────────────────────────────────────────
  Widget _buildTestButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.cyan.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.cyan.withValues(alpha: 0.5)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.7),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.cyanAccent),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  Widget _buildStepRow(int index, CommandStep step) {
    final motionLabel = MotionTable.labelFor(step.motionIndex);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.cyan.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  motionLabel,
                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${step.holdDurationMs}ms · ×${step.repeatCount}',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5), fontSize: 10),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
            onPressed: () => setState(() => _sequence.removeAt(index)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  void _addStep() {
    setState(() {
      _sequence.add(CommandStep(
        motionIndex: _motionIndex,
        holdDurationMs: 1000,
      ));
    });
  }

  Future<void> _pickMp3File() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'ogg', 'aac', 'm4a'],
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        setState(() => _mp3Ctrl.text = result.files.single.path!);
      }
    } catch (e) {
      debugPrint('[ButtonEditor] 파일 선택 오류: $e');
    }
  }

  void _save() {
    // 오디오 모드에 따라 저장
    final mp3Path = (_audioMode == 'mp3') ? _mp3Ctrl.text.trim() : null;
    final ttsText = (_audioMode == 'tts') ? _ttsCtrl.text.trim() : null;

    final updated = widget.config.copyWith(
      label: _labelCtrl.text.trim().isEmpty
          ? widget.config.label
          : _labelCtrl.text.trim(),
      motionIndex: _motionIndex,
      color: _color,
      commandSequence: _sequence,
      mp3FilePath: mp3Path,
      clearMp3: (_audioMode != 'mp3'),
      ttsText: ttsText,
      clearTts: (_audioMode != 'tts'),
    );
    context.read<CommandSetManager>().saveConfig(updated);
    Navigator.pop(context);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 오디오 모드 선택 칩
// ─────────────────────────────────────────────────────────────────────────────
class _AudioModeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _AudioModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? Colors.cyanAccent.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? Colors.cyanAccent.withValues(alpha: 0.8)
                  : Colors.white.withValues(alpha: 0.15),
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.cyanAccent : Colors.white38,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.cyanAccent : Colors.white38,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 모션 번호 스피너 위젯
// [−10] [−] [  번호  ] [+] [+10]  +  모션 이름 표시
// ─────────────────────────────────────────────────────────────────────────────
class _MotionSpinner extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _MotionSpinner({required this.value, required this.onChanged});

  @override
  State<_MotionSpinner> createState() => _MotionSpinnerState();
}

class _MotionSpinnerState extends State<_MotionSpinner> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '${widget.value}');
  }

  @override
  void didUpdateWidget(_MotionSpinner old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _ctrl.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _change(int delta) {
    final next = (widget.value + delta).clamp(0, 255);
    widget.onChanged(next);
  }

  void _onTextSubmit(String text) {
    final parsed = int.tryParse(text.trim());
    if (parsed != null) {
      widget.onChanged(parsed.clamp(0, 255));
    } else {
      _ctrl.text = '${widget.value}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = MotionTable.byIndex(widget.value);
    final modeName = info != null ? '[${info.mode}]' : '[Custom]';
    final motionName = info != null ? info.name : '—';
    final motionDesc = info != null ? info.desc : '사용자 정의';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyan.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          // ── 조작 행: [−10] [−] [번호 크게] [+] [+10] ──
          Row(
            children: [
              _SpinBtn(label: '−10', onTap: () => _change(-10), fontSize: 10),
              const SizedBox(width: 4),
              _SpinBtn(label: '−', onTap: () => _change(-1)),
              const SizedBox(width: 8),
              // 중앙: 모션 번호 크게 + 직접 입력
              Expanded(
                child: Container(
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.cyanAccent.withValues(alpha: 0.6),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.cyanAccent.withValues(alpha: 0.15),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _ctrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      letterSpacing: 2,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      _MaxValueFormatter(255),
                    ],
                    onSubmitted: _onTextSubmit,
                    onEditingComplete: () => _onTextSubmit(_ctrl.text),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SpinBtn(label: '+', onTap: () => _change(1)),
              const SizedBox(width: 4),
              _SpinBtn(label: '+10', onTap: () => _change(10), fontSize: 10),
            ],
          ),
          const SizedBox(height: 10),
          // ── 모션 이름 + 설명 (번호 아래) ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.cyan.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.cyan.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    modeName,
                    style: TextStyle(
                      color: Colors.cyanAccent.withValues(alpha: 0.9),
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$motionName  —  $motionDesc',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpinBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final double fontSize;
  const _SpinBtn({required this.label, required this.onTap, this.fontSize = 16});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.cyan.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.cyan.withValues(alpha: 0.4)),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.cyanAccent,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

class _MaxValueFormatter extends TextInputFormatter {
  final int maxVal;
  _MaxValueFormatter(this.maxVal);

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue old, TextEditingValue next) {
    if (next.text.isEmpty) return next;
    final v = int.tryParse(next.text);
    if (v == null) return old;
    if (v > maxVal) {
      return TextEditingValue(
        text: '$maxVal',
        selection: TextSelection.collapsed(offset: '$maxVal'.length),
      );
    }
    return next;
  }
}
