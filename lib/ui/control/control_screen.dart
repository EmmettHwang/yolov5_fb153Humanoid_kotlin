import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../bluetooth/bluetooth_manager.dart';
import '../../bluetooth/motion_repeater.dart';
import '../../command/command_set_manager.dart';
import '../../models/action_button_config.dart';
import '../camera/camera_preview_widget.dart';
import '../settings/settings_screen.dart';
import '../bluetooth/bluetooth_scan_screen.dart';
import 'joystick_view.dart';
import 'action_button_panel.dart';
import 'voice_command_button.dart';

/// 메인 제어 화면
class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen>
    with TickerProviderStateMixin {
  late MotionRepeater _motionRepeater;
  JoystickDirection _lastDirection = JoystickDirection.stop;

  // 조이스틱 방향 → 모션 번호 매핑 (기본값)
  Map<JoystickDirection, int> _joystickMotionMap = {
    ...JoystickOutput.defaultMotionMap,
  };

  // 인식 결과 (시뮬레이션)
  List<DetectionResult> _detections = [];
  bool _isDetecting = false;

  // YOLO 활성화 상태
  bool _isYoloActive = false;

  // 현재 인식 중인 객체
  String _detectedObject = '-';

  @override
  void initState() {
    super.initState();
    final btManager = context.read<BluetoothManager>();
    _motionRepeater = MotionRepeater(btManager);
    context.read<CommandSetManager>().load();
  }

  @override
  void dispose() {
    _motionRepeater.dispose();
    super.dispose();
  }

  void _onJoystickMove(JoystickOutput output) {
    if (!context.read<BluetoothManager>().isConnected) return;

    if (output.direction == _lastDirection) return;
    _lastDirection = output.direction;

    if (output.direction == JoystickDirection.stop || output.power < 0.15) {
      _motionRepeater.stop(returnMotion: 1);
    } else {
      final motionIndex = _joystickMotionMap[output.direction] ?? 1;
      _motionRepeater.start(motionIndex, intervalMs: 50);
    }
  }

  void _onJoystickRelease() {
    _motionRepeater.stop(returnMotion: 1);
    _lastDirection = JoystickDirection.stop;
  }

  void _onActionButton(ActionButtonConfig config) {
    final btManager = context.read<BluetoothManager>();
    final cmdManager = context.read<CommandSetManager>();
    if (!btManager.isConnected) {
      _showConnectSnackBar();
      return;
    }
    cmdManager.executeCommandSet(config, btManager);
  }

  void _showConnectSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.bluetooth_disabled, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('먼저 fb153 로봇에 연결하세요'),
          ],
        ),
        backgroundColor: Colors.redAccent,
        action: SnackBarAction(
          label: '연결',
          textColor: Colors.white,
          onPressed: () => _openBluetoothScan(),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Bluetooth 스캔 화면 직접 열기
  void _openBluetoothScan() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const BluetoothScanScreen(isFirstLaunch: false),
      ),
    );
  }

  /// 설정 화면 열기 (버튼 편집 등)
  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final btManager = context.watch<BluetoothManager>();
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: const Color(0xFF060E18),
      body: SafeArea(
        child: Column(
          children: [
            // ─── 상단 헤더 (앱바) ───
            _buildHeader(btManager),

            // ─── 카메라 프리뷰 (55%) ───
            SizedBox(
              height: size.height * 0.46,
              child: CameraPreviewWidget(
                detections: _detections,
                isDetecting: _isDetecting,
                isYoloActive: _isYoloActive,
                onYoloToggle: () {
                  setState(() {
                    _isYoloActive = !_isYoloActive;
                    if (_isYoloActive) {
                      _detectedObject = '-';
                    }
                  });
                },
              ),
            ),

            // ─── 상태바 (5%) ───
            _buildStatusBar(btManager),

            // ─── 조이스틱 + 액션 버튼 (하단 40%) ───
            Expanded(
              child: Row(
                children: [
                  // 조이스틱 (좌측)
                  Expanded(
                    child: _buildJoystickPanel(btManager),
                  ),

                  // 구분선
                  Container(
                    width: 1,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),

                  // 액션 버튼 (우측)
                  Expanded(
                    child: ActionButtonPanel(
                      onButtonPressed: _onActionButton,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BluetoothManager btManager) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1F2D),
        border: Border(
          bottom: BorderSide(
            color: Colors.cyan.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          // 로봇 아이콘 + 앱 이름
          const Icon(Icons.smart_toy, color: Colors.cyanAccent, size: 20),
          const SizedBox(width: 8),
          const Text(
            'ROBO COMMANDER',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),

          // 패킷 카운터
          if (btManager.isConnected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'TX: ${btManager.packetsSent}',
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),

          // 음성 명령 버튼
          const SizedBox(
            width: 60,
            child: VoiceCommandButton(),
          ),
          const SizedBox(width: 8),

          // 설정 버튼
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white54, size: 20),
            onPressed: _openSettings,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(BluetoothManager btManager) {
    final isConnected = btManager.isConnected;
    final deviceName = btManager.connectedDevice?.name ?? '-';

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFF0A1628),
      child: Row(
        children: [
          // 연결 상태
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: isConnected ? Colors.greenAccent : Colors.redAccent,
              shape: BoxShape.circle,
              boxShadow: isConnected
                  ? [
                      BoxShadow(
                        color: Colors.greenAccent.withValues(alpha: 0.6),
                        blurRadius: 4,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isConnected ? deviceName : '연결 안됨',
            style: TextStyle(
              color: isConnected ? Colors.greenAccent : Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),

          if (isConnected) ...[
            const SizedBox(width: 12),
            _StatusChip(
              icon: Icons.timer_outlined,
              label: '${btManager.latencyMs}ms',
              color: Colors.cyanAccent,
            ),
          ],

          const Spacer(),

          // YOLO 인식 상태 (탭으로 토글)
          GestureDetector(
            onTap: () {
              setState(() {
                _isYoloActive = !_isYoloActive;
                if (!_isYoloActive) _detectedObject = '-';
              });
            },
            child: _StatusChip(
              icon: _isYoloActive ? Icons.visibility : Icons.visibility_off,
              label: _isYoloActive
                  ? (_detectedObject == '-' ? 'YOLO ON' : '인식: $_detectedObject')
                  : 'YOLO OFF',
              color: _isYoloActive ? Colors.greenAccent : Colors.white38,
            ),
          ),

          const SizedBox(width: 8),

          // 연결 버튼 (미연결 시)
          if (!isConnected)
            GestureDetector(
              onTap: _openBluetoothScan,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.cyanAccent, width: 1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '연결',
                  style: TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildJoystickPanel(BluetoothManager btManager) {
    return Column(
      children: [
        // 조이스틱 헤더
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              const Icon(Icons.gamepad, color: Colors.cyanAccent, size: 16),
              const SizedBox(width: 4),
              Text(
                'JOYSTICK',
                style: TextStyle(
                  color: Colors.cyanAccent.withValues(alpha: 0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              // 현재 방향 표시
              if (_lastDirection != JoystickDirection.stop)
                Text(
                  _getDirectionLabel(_lastDirection),
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ),

        // 조이스틱
        Expanded(
          child: Center(
            child: JoystickView(
              size: 160,
              onJoystickMove: _onJoystickMove,
              onJoystickRelease: _onJoystickRelease,
            ),
          ),
        ),

        // 방향 모션 번호 표시 (하단)
        _buildDirectionInfo(),
      ],
    );
  }

  Widget _buildDirectionInfo() {
    if (_lastDirection == JoystickDirection.stop) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          '50ms 간격 패킷 전송',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.25),
            fontSize: 9,
          ),
        ),
      );
    }
    final motionIndex = _joystickMotionMap[_lastDirection] ?? 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '모션 $motionIndex 전송 중',
        style: const TextStyle(
          color: Colors.greenAccent,
          fontSize: 9,
        ),
      ),
    );
  }

  String _getDirectionLabel(JoystickDirection dir) {
    final output = JoystickOutput(direction: dir, power: 1.0);
    return output.directionLabel;
  }
}

/// 상태 칩 위젯
class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
