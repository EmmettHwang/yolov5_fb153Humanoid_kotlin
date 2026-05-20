import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'bluetooth/bluetooth_manager.dart';
import 'command/command_set_manager.dart';
import 'ui/control/control_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 세로 방향 고정
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // 상태바 스타일 설정
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
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF0D1F2D),
      ),
    );
  }
}

/// 스플래시 화면
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

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    _scaleAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.7, curve: Curves.elasticOut),
      ),
    );

    _ctrl.forward();

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const ControlScreen(),
            transitionsBuilder: (_, anim, __, child) => FadeTransition(
              opacity: anim,
              child: child,
            ),
            transitionDuration: const Duration(milliseconds: 600),
          ),
        );
      }
    });
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
                    width: 100,
                    height: 100,
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
                      size: 52,
                      color: Colors.cyanAccent,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 앱 이름
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
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // 로딩 인디케이터
                  SizedBox(
                    width: 180,
                    child: Column(
                      children: [
                        LinearProgressIndicator(
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.cyanAccent,
                          ),
                          value: _fadeAnim.value,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Bluetooth SPP · YOLOv5 · 15-byte Packet',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: 9,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
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
