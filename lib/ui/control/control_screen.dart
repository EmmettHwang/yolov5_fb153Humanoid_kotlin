import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../bluetooth/bluetooth_manager.dart';
import '../../bluetooth/motion_repeater.dart';
import '../../command/command_set_manager.dart';
import '../../models/action_button_config.dart';
import '../../models/yolo_action_config.dart';
import '../../services/audio_service.dart';
import '../../services/robot_name_service.dart';
import '../../services/yolo_detector_service.dart';
import '../camera/camera_preview_widget.dart';
import '../camera/custom_vision_screen.dart';
import '../settings/settings_screen.dart';
import '../settings/vision_settings_screen.dart';
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
  final Map<JoystickDirection, int> _joystickMotionMap = {
    ...JoystickOutput.defaultMotionMap,
  };

  // YOLO 서비스
  late YoloDetectorService _yoloService;
  bool _isYoloActive = false;
  String _detectedObject = '-';

  // YOLO 동작 실행 쿨다운 (너무 자주 실행 방지, 3초)
  DateTime? _lastYoloActionTime;
  static const _yoloCooldown = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    final btManager = context.read<BluetoothManager>();
    _motionRepeater = MotionRepeater(btManager);
    context.read<CommandSetManager>().load();

    _yoloService = YoloDetectorService();
    _yoloService.addListener(_onYoloResultsChanged);
  }

  @override
  void dispose() {
    _motionRepeater.dispose();
    _yoloService.removeListener(_onYoloResultsChanged);
    _yoloService.dispose();
    super.dispose();
  }

  /// YOLO 추론 결과 변경 콜백
  void _onYoloResultsChanged() {
    if (!mounted) return;
    final results = _yoloService.results;
    setState(() {
      if (results.isNotEmpty) {
        final best = results.reduce(
          (a, b) => a.confidence > b.confidence ? a : b,
        );
        _detectedObject = best.label;
        // YOLO 동작 트리거
        _triggerYoloAction(best.label);
      } else {
        _detectedObject = '-';
      }
    });
  }

  /// YOLO 인식 라벨에 매칭되는 동작 실행 (쿨다운 적용)
  void _triggerYoloAction(String label) {
    final now = DateTime.now();
    if (_lastYoloActionTime != null &&
        now.difference(_lastYoloActionTime!) < _yoloCooldown) {
      return;
    }

    final yoloManager = context.read<YoloActionManager>();
    final matched = yoloManager.matchLabel(label);
    if (matched == null) { return; }

    _lastYoloActionTime = now;

    // 오디오 재생
    if (matched.hasAudio) {
      AudioService().playForButton(
        mp3FilePath: matched.mp3FilePath,
        ttsText: matched.ttsText,
      );
    }

    // 모션 실행 (BT 연결 시)
    final btManager = context.read<BluetoothManager>();
    final cmdManager = context.read<CommandSetManager>();
    if (btManager.isConnected && matched.motionIndex > 0) {
      // YoloActionConfig → ActionButtonConfig 래핑
      final fakeConfig = ActionButtonConfig(
        id: 0,
        label: matched.label,
        motionIndex: matched.motionIndex,
        color: 0xFF00BCD4,
        commandSequence: matched.commandSequence,
        mp3FilePath: matched.mp3FilePath,
        ttsText: matched.ttsText,
      );
      cmdManager.executeCommandSet(fakeConfig, btManager,
          yoloService: _yoloService);
    }
  }

  void _onJoystickMove(JoystickOutput output) {
    if (!context.read<BluetoothManager>().isConnected) return;
    if (output.direction == _lastDirection) return;
    _lastDirection = output.direction;

    if (output.direction == JoystickDirection.stop || output.power < 0.15) {
      _motionRepeater.stop(returnMotion: 1);
    } else {
      final dir = output.direction;
      // 전진: 2→3→4 시퀀스, 후진: 9→10→11 시퀀스
      if (dir == JoystickDirection.forward) {
        _motionRepeater.startSequence([2, 3, 4]);
      } else if (dir == JoystickDirection.backward) {
        _motionRepeater.startSequence([9, 10, 11]);
      } else {
        final motionIndex = _joystickMotionMap[dir] ?? 1;
        _motionRepeater.start(motionIndex, intervalMs: 50);
      }
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
    cmdManager.executeCommandSet(config, btManager, yoloService: _yoloService);
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

  void _openBluetoothScan() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const BluetoothScanScreen(isFirstLaunch: false),
      ),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _openVisionSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const VisionSettingsScreen()),
    );
  }

  void _openCustomVision() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CustomVisionScreen()),
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
            // ─── 상단 헤더 ───
            _buildHeader(btManager),

            // ─── 카메라 프리뷰 (46%) ───
            SizedBox(
              height: size.height * 0.46,
              child: CameraPreviewWidget(
                isYoloActive: _isYoloActive,
                yoloService: _yoloService,
                onYoloToggle: () {
                  setState(() {
                    _isYoloActive = !_isYoloActive;
                    if (!_isYoloActive) _detectedObject = '-';
                  });
                },
              ),
            ),

            // ─── 상태바 ───
            _buildStatusBar(btManager),

            // ─── 조이스틱 + 액션 버튼 패널 (Expanded) ───
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

                  // 액션 버튼 (우측) — 버튼패널 + 음성버튼
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: ActionButtonPanel(
                            onButtonPressed: _onActionButton,
                          ),
                        ),
                        // ─── 음성 명령 버튼 (버튼 패널 아래) ───
                        _buildVoiceRow(),
                      ],
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

  /// 음성 명령 버튼 행 (버튼 패널 아래 배치)
  Widget _buildVoiceRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1628),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          VoiceCommandButton(),
        ],
      ),
    );
  }

  Widget _buildHeader(BluetoothManager btManager) {
    // 로봇 이름 동적으로 읽기
    final robotName = context.watch<RobotNameService>().name;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1F2D),
        border: Border(
          bottom: BorderSide(color: Colors.cyan.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          // 로봇 아이콘 + 이름
          const Icon(Icons.smart_toy, color: Colors.cyanAccent, size: 20),
          const SizedBox(width: 6),
          Text(
            robotName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(width: 4),

          // BT 연결 버튼
          GestureDetector(
            onTap: _openBluetoothScan,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: btManager.isConnected
                    ? Colors.greenAccent.withValues(alpha: 0.12)
                    : Colors.redAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: btManager.isConnected
                      ? Colors.greenAccent.withValues(alpha: 0.7)
                      : Colors.redAccent.withValues(alpha: 0.7),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    btManager.isConnected
                        ? Icons.bluetooth_connected
                        : Icons.bluetooth_disabled,
                    size: 13,
                    color: btManager.isConnected
                        ? Colors.greenAccent
                        : Colors.redAccent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    btManager.isConnected
                        ? (btManager.connectedDevice?.macSuffix ?? 'BT')
                        : 'BT 연결',
                    style: TextStyle(
                      color: btManager.isConnected
                          ? Colors.greenAccent
                          : Colors.redAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // 패킷 카운터
          if (btManager.isConnected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'TX:${btManager.packetsSent}',
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
            ),

          // 직접 학습 버튼
          IconButton(
            icon: const Icon(Icons.auto_awesome,
                color: Colors.purpleAccent, size: 20),
            tooltip: '직접 학습 (Teachable Machine)',
            onPressed: _openCustomVision,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 4),

          // 비전 설정 버튼
          IconButton(
            icon: const Icon(Icons.remove_red_eye,
                color: Colors.cyanAccent, size: 20),
            tooltip: '비전 설정',
            onPressed: _openVisionSettings,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 4),

          // 설정 버튼
          IconButton(
            icon:
                const Icon(Icons.settings, color: Colors.white54, size: 20),
            tooltip: '설정',
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
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFF0A1628),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isConnected ? Colors.greenAccent : Colors.white24,
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
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              isConnected ? deviceName : '블루투스 미연결 — 헤더 BT 버튼으로 연결',
              style: TextStyle(
                color: isConnected ? Colors.greenAccent : Colors.white30,
                fontSize: 10,
                fontWeight: isConnected ? FontWeight.w600 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isConnected) ...[
            const SizedBox(width: 8),
            _StatusChip(
              icon: Icons.timer_outlined,
              label: '${btManager.latencyMs}ms',
              color: Colors.cyanAccent,
            ),
          ],
          const Spacer(),
          // 객체인식 토글 칩
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
                  ? (_yoloService.modelState == YoloModelState.loading
                      ? 'AI 로딩 ${(_yoloService.loadingProgress * 100).toInt()}%'
                      : _detectedObject == '-'
                          ? '객체인식 ON'
                          : '인식: $_detectedObject')
                  : '객체인식 OFF',
              color: _isYoloActive
                  ? (_yoloService.modelState == YoloModelState.loading
                      ? Colors.amber
                      : Colors.greenAccent)
                  : Colors.white30,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJoystickPanel(BluetoothManager btManager) {
    return Column(
      children: [
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
        Expanded(
          child: Center(
            child: JoystickView(
              size: 160,
              onJoystickMove: _onJoystickMove,
              onJoystickRelease: _onJoystickRelease,
            ),
          ),
        ),
        _buildDirectionInfo(),
      ],
    );
  }

  Widget _buildDirectionInfo() {
    if (_lastDirection == JoystickDirection.stop) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          '전진: 2→3→4  후진: 9→10→11',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.25),
            fontSize: 9,
          ),
        ),
      );
    }

    final isForward = _lastDirection == JoystickDirection.forward;
    final isBackward = _lastDirection == JoystickDirection.backward;
    String label;
    if (isForward) {
      label =
          '전진 시퀀스 M${_motionRepeater.currentMotion} 전송 중';
    } else if (isBackward) {
      label =
          '후진 시퀀스 M${_motionRepeater.currentMotion} 전송 중';
    } else {
      final motionIndex = _joystickMotionMap[_lastDirection] ?? 1;
      label = '모션 $motionIndex 전송 중';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label,
        style: const TextStyle(color: Colors.greenAccent, fontSize: 9),
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
