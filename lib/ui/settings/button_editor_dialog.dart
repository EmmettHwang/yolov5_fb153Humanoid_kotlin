import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/action_button_config.dart';
import '../../command/command_set_manager.dart';

/// 버튼 편집 다이얼로그
class ButtonEditorDialog extends StatefulWidget {
  final ActionButtonConfig config;

  const ButtonEditorDialog({super.key, required this.config});

  @override
  State<ButtonEditorDialog> createState() => _ButtonEditorDialogState();
}

class _ButtonEditorDialogState extends State<ButtonEditorDialog> {
  late TextEditingController _labelCtrl;
  late int _motionIndex;
  late int _color;
  late List<CommandStep> _sequence;

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
    _motionIndex = widget.config.motionIndex;
    _color = widget.config.color;
    _sequence = List.from(widget.config.commandSequence);
    if (_sequence.isEmpty) {
      _sequence.add(CommandStep(motionIndex: _motionIndex, holdDurationMs: 3000));
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
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
              // 헤더
              Row(
                children: [
                  Icon(Icons.edit, color: Colors.cyanAccent, size: 20),
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

              // 버튼 이름
              _buildLabel('버튼 이름'),
              TextField(
                controller: _labelCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: _inputDecoration('인사, 댄스, 복귀...'),
              ),
              const SizedBox(height: 16),

              // 기본 모션 번호
              _buildLabel('기본 모션 번호: $_motionIndex'),
              Slider(
                value: _motionIndex.toDouble(),
                min: 0,
                max: 255,
                divisions: 255,
                label: _motionIndex.toString(),
                activeColor: Colors.cyanAccent,
                inactiveColor: Colors.white24,
                onChanged: (v) => setState(() => _motionIndex = v.toInt()),
              ),

              const SizedBox(height: 16),

              // 색상 선택
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

              const SizedBox(height: 16),

              // 명령어 시퀀스
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

              // 저장/취소 버튼
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
                style:
                    const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '모션 ${step.motionIndex} · ${step.holdDurationMs}ms · ×${step.repeatCount}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
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

  void _save() {
    final updated = widget.config.copyWith(
      label: _labelCtrl.text.trim().isEmpty ? widget.config.label : _labelCtrl.text.trim(),
      motionIndex: _motionIndex,
      color: _color,
      commandSequence: _sequence,
    );
    context.read<CommandSetManager>().saveConfig(updated);
    Navigator.pop(context);
  }
}
