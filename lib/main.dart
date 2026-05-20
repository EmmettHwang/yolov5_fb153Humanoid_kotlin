import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'bluetooth/bluetooth_manager.dart';
import 'command/command_set_manager.dart';
import 'ui/bluetooth/bluetooth_scan_screen.dart';
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
      colorScheme: ColorScheme.dark(
        primary: Colors.cyanAccent,
        secondary: Colors.cyan,
        surface: const Color(0xFF0D1F2D),
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
/// 초기화 → 자동 재연결 시도 → 결과에 따라 화면 분기
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

  String _statusText = '초기화 중...';

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.6, curve: Curves.easeOut)),
    );
    _scaleAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.7, curve: Curves.elasticOut)),
    );
    _ctrl.forward();
    _initialize();
  }

  Future<void> _initialize() async {
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;
    final btManager = context.read<BluetoothManager>();

    // 1. BluetoothManager 초기화 (마지막 기기 복원)
    await btManager.init();

    // 2. Bluetooth 활성화 확인
    final btEnabled = await btManager.isBluetoothEnabled();
    if (!btEnabled) {
      _goToBluetoothScan(); // BT 꺼져 있으면 스캔 화면으로
      return;
    }

    // 3. 마지막 연결 기기가 있으면 자동 재연결 시도
    if (btManager.lastMac != null) {
      if (mounted) setState(() => _statusText = '마지막 로봇에 재연결 중...');

      final reconnected = await btManager.tryAutoReconnect();

      if (reconnected && mounted) {
        // 자동 재연결 성공 → 바로 제어 화면
        _goToControl();
      } else if (mounted) {
        // 재연결 실패 → 스캔 화면
        _goToBluetoothScan();
      }
    } else {
      // 처음 실행 → 스캔 화면
      _goToBluetoothScan();
    }
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

  void _goToBluetoothScan() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) =>
            const BluetoothScanScreen(isFirstLaunch: true),
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
                  // 로봇 아이콘
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

                  // 상태 텍스트
                  Text(
                    _statusText,
                    style: TextStyle(
                      color: Colors.cyanAccent.withValues(alpha: 0.7),
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 로딩 바
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
