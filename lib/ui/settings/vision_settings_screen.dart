import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/yolo_action_config.dart';
import '../../models/motion_table.dart';
import '../../services/audio_service.dart';

/// 비전(YOLO) 인식 결과별 동작 설정 화면
class VisionSettingsScreen extends StatefulWidget {
  const VisionSettingsScreen({super.key});

  @override
  State<VisionSettingsScreen> createState() => _VisionSettingsScreenState();
}

class _VisionSettingsScreenState extends State<VisionSettingsScreen> {
  @override
  void initState() {
    super.initState();
    // load()는 main.dart에서 이미 수행됨. 최신 설정 갱신만.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<YoloActionManager>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<YoloActionManager>();
    const labels = YoloActionManager.defaultLabels;

    return Scaffold(
      backgroundColor: const Color(0xFF060E18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1F2D),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(
          children: [
            Icon(Icons.visibility, color: Colors.cyanAccent, size: 20),
            SizedBox(width: 8),
            Text('비전 동작 설정',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
      ),
      body: Column(
        children: [
          // 안내 배너
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.cyan.withValues(alpha: 0.08),
            child: Text(
              'YOLO가 물체를 인식하면 자동으로 해당 모션·소리가 실행됩니다.\n'
              '토글로 활성화하고 길게 눌러 상세 설정하세요.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            ),
          ),
          // 라벨 목록
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: labels.length,
              itemBuilder: (context, index) {
                final label = labels[index];
                final cfg = manager.getConfig(label);
                return _YoloActionTile(
                  config: cfg,
                  onToggle: (val) {
                    manager.save(cfg.copyWith(enabled: val));
                  },
                  onEdit: () => _openEditor(context, cfg),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openEditor(BuildContext context, YoloActionConfig config) {
    showDialog(
      context: context,
      builder: (_) => _YoloActionEditorDialog(config: config),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 라벨 타일
// ─────────────────────────────────────────────────────────────────────────────
class _YoloActionTile extends StatelessWidget {
  final YoloActionConfig config;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;

  const _YoloActionTile({
    required this.config,
    required this.onToggle,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final motionLabel = MotionTable.labelFor(config.motionIndex);
    return GestureDetector(
      onLongPress: onEdit,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: config.enabled
              ? Colors.cyan.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: config.enabled
                ? Colors.cyanAccent.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            // 라벨 + 모션 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        config.label,
                        style: TextStyle(
                          color: config.enabled ? Colors.white : Colors.white54,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (config.audioHint.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(config.audioHint,
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ],
                  ),
                  if (config.enabled) ...[
                    const SizedBox(height: 2),
                    Text(
                      motionLabel,
                      style: TextStyle(
                        color: Colors.cyanAccent.withValues(alpha: 0.7),
                        fontSize: 10,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // 편집 버튼
            if (config.enabled)
              IconButton(
                icon: Icon(Icons.tune,
                    color: Colors.white.withValues(alpha: 0.5), size: 18),
                onPressed: onEdit,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            const SizedBox(width: 8),
            // 활성화 토글
            Switch(
              value: config.enabled,
              onChanged: onToggle,
              activeThumbColor: Colors.cyanAccent,
              inactiveTrackColor: Colors.white12,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// YOLO 동작 편집 다이얼로그
// ─────────────────────────────────────────────────────────────────────────────
class _YoloActionEditorDialog extends StatefulWidget {
  final YoloActionConfig config;
  const _YoloActionEditorDialog({required this.config});

  @override
  State<_YoloActionEditorDialog> createState() =>
      _YoloActionEditorDialogState();
}

class _YoloActionEditorDialogState extends State<_YoloActionEditorDialog> {
  late int _motionIndex;
  late TextEditingController _mp3Ctrl;
  late TextEditingController _ttsCtrl;
  late String _audioMode; // 'none' | 'mp3' | 'tts'

  @override
  void initState() {
    super.initState();
    _motionIndex = widget.config.motionIndex;
    _mp3Ctrl = TextEditingController(text: widget.config.mp3FilePath ?? '');
    _ttsCtrl = TextEditingController(text: widget.config.ttsText ?? '');
    if (widget.config.mp3FilePath != null &&
        widget.config.mp3FilePath!.isNotEmpty) {
      _audioMode = 'mp3';
    } else if (widget.config.ttsText != null &&
        widget.config.ttsText!.isNotEmpty) {
      _audioMode = 'tts';
    } else {
      _audioMode = 'none';
    }
  }

  @override
  void dispose() {
    _mp3Ctrl.dispose();
    _ttsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = MotionTable.byIndex(_motionIndex);
    final motionDesc =
        info != null ? '${info.name} · ${info.desc}' : '사용자 정의';

    return Dialog(
      backgroundColor: const Color(0xFF0D1F2D),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.cyan.withValues(alpha: 0.4)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Row(
              children: [
                const Icon(Icons.visibility, color: Colors.cyanAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '"${widget.config.label}" 인식 시 동작',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold),
                  ),
                ),
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

            // 모션 번호 스피너
            _buildLabel('모션 번호'),
            _buildMotionSpinner(),
            const SizedBox(height: 6),
            Text(
              motionDesc,
              style: TextStyle(
                  color: Colors.cyanAccent.withValues(alpha: 0.8),
                  fontSize: 11),
            ),
            const SizedBox(height: 16),

            // 오디오 설정
            _buildLabel('소리 설정'),
            Row(
              children: [
                _modeChip('없음', Icons.music_off, 'none'),
                const SizedBox(width: 6),
                _modeChip('MP3', Icons.audio_file, 'mp3'),
                const SizedBox(width: 6),
                _modeChip('TTS', Icons.record_voice_over, 'tts'),
              ],
            ),
            const SizedBox(height: 12),

            if (_audioMode == 'mp3') ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _mp3Ctrl,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: _inputDeco('MP3 파일 경로'),
                      readOnly: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _iconBtn(Icons.folder_open, _pickMp3),
                ],
              ),
              const SizedBox(height: 8),
              _testBtn('🎵 미리 듣기', () async {
                if (_mp3Ctrl.text.trim().isNotEmpty) {
                  await AudioService()
                      .playForButton(mp3FilePath: _mp3Ctrl.text.trim());
                }
              }),
            ],

            if (_audioMode == 'tts') ...[
              TextField(
                controller: _ttsCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: _inputDeco('한국어 또는 영어 텍스트'),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              _testBtn('🔊 미리 듣기', () async {
                if (_ttsCtrl.text.trim().isNotEmpty) {
                  await AudioService().speak(_ttsCtrl.text.trim());
                }
              }),
            ],

            if (_audioMode == 'none')
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '소리 없이 모션만 실행합니다.',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 11),
                ),
              ),

            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white54,
                      side: const BorderSide(color: Colors.white24),
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
                    ),
                    onPressed: _save,
                    child: const Text('저장',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      );

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.08),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide:
                BorderSide(color: Colors.white.withValues(alpha: 0.2))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide:
                BorderSide(color: Colors.white.withValues(alpha: 0.2))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.cyanAccent)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      );

  Widget _modeChip(String label, IconData icon, String mode) {
    final sel = _audioMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _audioMode = mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: sel
                ? Colors.cyanAccent.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: sel
                  ? Colors.cyanAccent.withValues(alpha: 0.8)
                  : Colors.white.withValues(alpha: 0.15),
              width: sel ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: sel ? Colors.cyanAccent : Colors.white38),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      color: sel ? Colors.cyanAccent : Colors.white38,
                      fontSize: 10,
                      fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.cyan.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.cyan.withValues(alpha: 0.4)),
        ),
        child: Icon(icon, color: Colors.cyanAccent, size: 20),
      ),
    );
  }

  Widget _testBtn(String label, VoidCallback onTap) {
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
          child: Text(label,
              style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  // 모션 번호 스피너 (간단 버전)
  Widget _buildMotionSpinner() {
    return Row(
      children: [
        _spinBtn('−10', () => _changeMotion(-10)),
        const SizedBox(width: 4),
        _spinBtn('−', () => _changeMotion(-1)),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(6),
              border:
                  Border.all(color: Colors.cyan.withValues(alpha: 0.4)),
            ),
            child: Center(
              child: Text(
                '$_motionIndex',
                style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _spinBtn('+', () => _changeMotion(1)),
        const SizedBox(width: 4),
        _spinBtn('+10', () => _changeMotion(10)),
      ],
    );
  }

  Widget _spinBtn(String label, VoidCallback onTap) {
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
          child: Text(label,
              style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  void _changeMotion(int delta) {
    setState(() => _motionIndex = (_motionIndex + delta).clamp(0, 255));
  }

  Future<void> _pickMp3() async {
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
      debugPrint('[VisionSettings] 파일 선택 오류: $e');
    }
  }

  void _save() {
    final mp3Path = (_audioMode == 'mp3') ? _mp3Ctrl.text.trim() : null;
    final ttsText = (_audioMode == 'tts') ? _ttsCtrl.text.trim() : null;
    final updated = widget.config.copyWith(
      motionIndex: _motionIndex,
      mp3FilePath: mp3Path,
      clearMp3: _audioMode != 'mp3',
      ttsText: ttsText,
      clearTts: _audioMode != 'tts',
    );
    context.read<YoloActionManager>().save(updated);
    Navigator.pop(context);
  }
}
