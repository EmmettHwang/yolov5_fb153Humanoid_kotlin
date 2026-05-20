import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'bluetooth/bluetooth_manager.dart';
import 'command/command_set_manager.dart';
import 'models/yolo_action_config.dart';
import 'services/audio_service.dart';
import 'services/robot_name_service.dart';
import 'services/voice_command_service.dart';
import 'ui/control/control_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const RoboCommanderApp());
}

class RoboCommanderApp extends StatelessWidget {
  const RoboCommanderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BluetoothManager()),
        ChangeNotifierProvider(create: (_) => CommandSetManager()),
        ChangeNotifierProvider(create: (_) => VoiceCommandService()),
        // 로봇 이름 서비스 (singleton)
        ChangeNotifierProvider<RobotNameService>(
          create: (_) => RobotNameService(),
        ),
        // YOLO 동작 설정 관리자 (singleton)
        ChangeNotifierProvider<YoloActionManager>(
          create: (_) => YoloActionManager(),
        ),
      ],
      child: MaterialApp(
        title: 'Robo Commander',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        home: const SplashScreen(),
      ),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: Colors.cyanAccent,
        secondary: Colors.cyan,
        surface: Color(0xFF0D1F2D),
      ),
      scaffoldBackgroundColor: const Color(0xFF060E18),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0D1F2D),
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.cyanAccent,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: Colors.cyanAccent,
        thumbColor: Colors.cyanAccent,
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF0D1F2D),
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xFF0D1F2D),
      ),
    );
  }
}

/// ─── 스플래시 화면 ───────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  String _statusText = '시작하는 중...';

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
          parent: _ctrl, curve: const Interval(0.0, 0.6, curve: Curves.easeOut)),
    );
    _scaleAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.0, 0.7, curve: Curves.elasticOut)),
    );
    _ctrl.forward();
    _initialize();
  }

  Future<void> _initialize() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    final btManager = context.read<BluetoothManager>();

    // 1. AudioService 미리 초기화
    await AudioService().initialize();

    // 2. RobotNameService 로드
    if (mounted) {
      await context.read<RobotNameService>().load();
    }

    // 3. YoloActionManager 로드
    if (mounted) {
      await context.read<YoloActionManager>().load();
    }

    // 4. BluetoothManager 초기화
    if (mounted) {
      await btManager.init();
    }

    // 5. 마지막 기기 자동 재연결 시도
    if (mounted && btManager.lastMac != null) {
      setState(() => _statusText = '마지막 로봇 재연결 시도 중...');
      btManager.tryAutoReconnect();
    }

    // 6. 메인 화면으로 이동
    _goToControl();

    // 7. TTS 인사말 (로봇 이름 포함)
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        final name = context.read<RobotNameService>().name;
        AudioService().speakGreeting(robotName: name);
      }
    });
  }

  void _goToControl() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const ControlScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060E18),
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) => Center(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: ScaleTransition(
              scale: _scaleAnim,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.cyan.withValues(alpha: 0.3),
                          Colors.cyan.withValues(alpha: 0.05),
                        ],
                      ),
                      border: Border.all(
                        color: Colors.cyanAccent.withValues(alpha: 0.6),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.smart_toy,
                      size: 56,
                      color: Colors.cyanAccent,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'ROBO COMMANDER',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'fb153 Humanoid Robot Controller',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 52),
                  Text(
                    _statusText,
                    style: TextStyle(
                      color: Colors.cyanAccent.withValues(alpha: 0.7),
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 160,
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.cyanAccent),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Bluetooth SPP · 15-byte Packet · YOLOv5',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.2),
                      fontSize: 9,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
