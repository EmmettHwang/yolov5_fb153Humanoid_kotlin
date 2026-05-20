import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/action_button_config.dart';
import '../../bluetooth/bluetooth_manager.dart' as bt;
import '../../command/command_set_manager.dart';
import '../../services/audio_service.dart';
import '../settings/button_editor_dialog.dart';
import 'package:provider/provider.dart';

/// 3x3 액션 버튼 패널
class ActionButtonPanel extends StatelessWidget {
  final void Function(ActionButtonConfig config)? onButtonPressed;

  const ActionButtonPanel({
    super.key,
    this.onButtonPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cmdManager = context.watch<CommandSetManager>();
    final btManager = context.watch<bt.BluetoothManager>();

    return Column(
      children: [
        // 패널 헤더
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              const Icon(Icons.gamepad, color: Colors.cyanAccent, size: 16),
              const SizedBox(width: 4),
              Text(
                'ACTION',
                style: TextStyle(
                  color: Colors.cyanAccent.withValues(alpha: 0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              Text(
                '길게 눌러 편집',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
        // 3x3 그리드
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 1.0,
            ),
            itemCount: 9,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (context, index) {
              final config = cmdManager.getConfig(index + 1);
              return _ActionButton(
                config: config,
                isConnected: btManager.isConnected,
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  if (config.hasAudio) {
                    AudioService().playForButton(
                      mp3FilePath: config.mp3FilePath,
                      ttsText: config.ttsText,
                    );
                  }
                  onButtonPressed?.call(config);
                },
                onLongPress: () {
                  HapticFeedback.heavyImpact();
                  _openEditor(context, config);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _openEditor(BuildContext context, ActionButtonConfig config) {
    showDialog(
      context: context,
      builder: (_) => ButtonEditorDialog(config: config),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final ActionButtonConfig config;
  final bool isConnected;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;

  const _ActionButton({
    required this.config,
    required this.isConnected,
    this.onPressed,
    this.onLongPress,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _onTapDown(_) {
    _animCtrl.forward();
  }

  void _onTapUp(_) {
    _animCtrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final btnColor = Color(widget.config.color);
    final isActive = widget.isConnected;

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: () => _animCtrl.reverse(),
      onTap: isActive ? widget.onPressed : null,
      onLongPress: widget.onLongPress,  // 햅틱은 ActionButtonPanel에서 처리
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnim.value,
          child: child,
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isActive
                  ? [
                      btnColor.withValues(alpha: 0.9),
                      btnColor.withValues(alpha: 0.6),
                    ]
                  : [
                      Colors.grey.shade800,
                      Colors.grey.shade900,
                    ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isActive
                  ? btnColor.withValues(alpha: 0.7)
                  : Colors.grey.shade700,
              width: 1.5,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: btnColor.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 모션 번호 뱃지 (모션 번호 표시)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${widget.config.motionIndex}',
                  style: TextStyle(
                    color: Colors.cyanAccent.withValues(alpha: 0.85),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // 버튼 이름
              Text(
                widget.config.label,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.grey.shade600,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              // 오디오 힌트 + 버튼 번호
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.config.audioHint.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: Text(
                        widget.config.audioHint,
                        style: const TextStyle(fontSize: 9),
                      ),
                    ),
                  Text(
                    '${widget.config.id}',
                    style: TextStyle(
                      color: isActive
                          ? Colors.white.withValues(alpha: 0.5)
                          : Colors.grey.shade700,
                      fontSize: 8,
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
}
