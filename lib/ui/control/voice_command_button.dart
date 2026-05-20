import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/voice_command_service.dart';
import '../../command/command_set_manager.dart';
import '../../bluetooth/bluetooth_manager.dart';

/// 음성 명령 마이크 버튼
/// 탭 → 음성 인식 시작/중지
/// 인식 결과 → 버튼 이름 매칭 → 모션 실행
class VoiceCommandButton extends StatelessWidget {
  const VoiceCommandButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<VoiceCommandService>(
      builder: (context, voiceSvc, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 인식된 텍스트 / 상태 메시지
            _buildStatusLabel(voiceSvc),
            const SizedBox(height: 4),
            // 마이크 버튼
            _buildMicButton(context, voiceSvc),
          ],
        );
      },
    );
  }

  Widget _buildStatusLabel(VoiceCommandService voiceSvc) {
    String text = '';
    Color color = Colors.white38;

    switch (voiceSvc.state) {
      case VoiceState.idle:
        text = '음성 명령';
        color = Colors.white38;
      case VoiceState.listening:
        text = voiceSvc.recognizedText.isNotEmpty
            ? '"${voiceSvc.recognizedText}"'
            : '말씀하세요...';
        color = Colors.cyanAccent;
      case VoiceState.processing:
        text = '분석 중...';
        color = Colors.amber;
      case VoiceState.matched:
        text = '✓ ${voiceSvc.matchedLabel}';
        color = Colors.greenAccent;
      case VoiceState.noMatch:
        text = '인식 실패 — 다시 시도';
        color = Colors.redAccent;
      case VoiceState.error:
        text = voiceSvc.errorMessage.isNotEmpty
            ? voiceSvc.errorMessage
            : '오류 발생';
        color = Colors.redAccent;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Text(
        text,
        key: ValueKey(text),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontFamily: 'monospace',
        ),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildMicButton(BuildContext context, VoiceCommandService voiceSvc) {
    final isListening = voiceSvc.isListening;
    final isMatched = voiceSvc.state == VoiceState.matched;
    final isError = voiceSvc.state == VoiceState.error ||
        voiceSvc.state == VoiceState.noMatch;

    Color bgColor = const Color(0xFF0D1F2D);
    Color borderColor = Colors.white24;
    Color iconColor = Colors.white54;
    IconData icon = Icons.mic_none;

    if (isListening) {
      bgColor = Colors.cyanAccent.withValues(alpha: 0.15);
      borderColor = Colors.cyanAccent;
      iconColor = Colors.cyanAccent;
      icon = Icons.mic;
    } else if (isMatched) {
      bgColor = Colors.greenAccent.withValues(alpha: 0.15);
      borderColor = Colors.greenAccent;
      iconColor = Colors.greenAccent;
      icon = Icons.check;
    } else if (isError) {
      bgColor = Colors.redAccent.withValues(alpha: 0.1);
      borderColor = Colors.redAccent.withValues(alpha: 0.5);
      iconColor = Colors.redAccent;
      icon = Icons.mic_off;
    }

    return GestureDetector(
      onTap: () => _onTap(context, voiceSvc),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: isListening
              ? [
                  BoxShadow(
                    color: Colors.cyanAccent.withValues(alpha: 0.4),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ]
              : isMatched
                  ? [
                      BoxShadow(
                        color: Colors.greenAccent.withValues(alpha: 0.4),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
        ),
        child: Center(
          child: Icon(icon, size: 20, color: iconColor),
        ),
      ),
    );
  }

  void _onTap(BuildContext context, VoiceCommandService voiceSvc) {
    final cmdManager = context.read<CommandSetManager>();
    final btManager = context.read<BluetoothManager>();

    // 콜백 등록 (처음 탭 시)
    voiceSvc.onCommandMatched = (config) {
      if (!btManager.isConnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bluetooth 미연결 — 연결 후 사용하세요'),
            backgroundColor: Colors.redAccent,
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }
      // 매칭된 버튼의 명령 실행
      cmdManager.executeCommandSet(config, btManager);

      // 실행 알림
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.mic, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(
                '음성: "${config.label}" 실행',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
    };

    // 현재 버튼 설정 목록 가져오기
    final buttons = cmdManager.buttons;
    voiceSvc.startListening(buttons);
  }
}
