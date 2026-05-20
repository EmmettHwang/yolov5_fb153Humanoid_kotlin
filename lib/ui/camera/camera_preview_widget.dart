import 'package:flutter/material.dart';

/// 카메라 프리뷰 + YOLO 인식 오버레이 (시뮬레이션)
/// 실제 기기에서는 camera 패키지로 교체
class CameraPreviewWidget extends StatefulWidget {
  final List<DetectionResult> detections;
  final bool isDetecting;

  const CameraPreviewWidget({
    super.key,
    this.detections = const [],
    this.isDetecting = false,
  });

  @override
  State<CameraPreviewWidget> createState() => _CameraPreviewWidgetState();
}

class _CameraPreviewWidgetState extends State<CameraPreviewWidget>
    with TickerProviderStateMixin {
  late AnimationController _scanLineCtrl;
  late Animation<double> _scanLineAnim;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _scanLineCtrl = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
    _scanLineAnim = Tween<double>(begin: 0.0, end: 1.0).animate(_scanLineCtrl);

    _pulseCtrl = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scanLineCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 카메라 배경 (실기기에서는 실제 카메라 프리뷰)
        _buildCameraBackground(),

        // 코너 프레임
        _buildCornerFrame(),

        // 스캔 라인 애니메이션
        AnimatedBuilder(
          animation: _scanLineAnim,
          builder: (context, _) => _buildScanLine(),
        ),

        // YOLO 인식 결과 바운딩 박스
        ...widget.detections.map((det) => _buildDetectionBox(det)),

        // 상단 오버레이 (카메라 상태)
        Positioned(
          top: 8,
          left: 8,
          right: 8,
          child: _buildTopOverlay(),
        ),

        // 하단 오버레이 (추론 상태)
        if (widget.isDetecting)
          Positioned(
            bottom: 8,
            right: 8,
            child: _buildDetectionStatus(),
          ),
      ],
    );
  }

  Widget _buildCameraBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.2,
          colors: [
            const Color(0xFF0A1628),
            const Color(0xFF050C14),
          ],
        ),
      ),
      child: Center(
        child: AnimatedBuilder(
          animation: _pulseAnim,
          builder: (context, _) => Opacity(
            opacity: _pulseAnim.value * 0.3,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.camera_alt_outlined,
                  size: 48,
                  color: Colors.cyan.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  'CAMERA FEED',
                  style: TextStyle(
                    color: Colors.cyan.withValues(alpha: 0.5),
                    fontSize: 12,
                    letterSpacing: 3,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'YOLOv5 · TFLite',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 10,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCornerFrame() {
    return Positioned.fill(
      child: CustomPaint(
        painter: _CornerFramePainter(),
      ),
    );
  }

  Widget _buildScanLine() {
    return Positioned(
      top: MediaQuery.sizeOf(context).height * _scanLineAnim.value * 0.4,
      left: 0,
      right: 0,
      child: Container(
        height: 2,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.transparent,
              Colors.cyan.withValues(alpha: 0.6),
              Colors.cyanAccent,
              Colors.cyan.withValues(alpha: 0.6),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetectionBox(DetectionResult det) {
    return Positioned(
      left: det.rect.left,
      top: det.rect.top,
      width: det.rect.width,
      height: det.rect.height,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.greenAccent, width: 2),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            color: Colors.greenAccent,
            child: Text(
              '${det.label} ${(det.confidence * 100).toInt()}%',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopOverlay() {
    return Row(
      children: [
        _buildTag('640×480', Icons.videocam),
        const SizedBox(width: 6),
        _buildTag('YOLOv5s', Icons.visibility),
        const Spacer(),
        _buildTag('10-15 FPS', Icons.speed),
      ],
    );
  }

  Widget _buildTag(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.cyan.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: Colors.cyan),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectionStatus() {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, _) => Opacity(
        opacity: _pulseAnim.value,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '인식 중',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CornerFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.7)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    const len = 20.0;

    // 좌상단
    canvas.drawLine(const Offset(8, 8), const Offset(8 + len, 8), paint);
    canvas.drawLine(const Offset(8, 8), const Offset(8, 8 + len), paint);

    // 우상단
    canvas.drawLine(
        Offset(size.width - 8, 8), Offset(size.width - 8 - len, 8), paint);
    canvas.drawLine(
        Offset(size.width - 8, 8), Offset(size.width - 8, 8 + len), paint);

    // 좌하단
    canvas.drawLine(
        Offset(8, size.height - 8), Offset(8 + len, size.height - 8), paint);
    canvas.drawLine(
        Offset(8, size.height - 8), Offset(8, size.height - 8 - len), paint);

    // 우하단
    canvas.drawLine(Offset(size.width - 8, size.height - 8),
        Offset(size.width - 8 - len, size.height - 8), paint);
    canvas.drawLine(Offset(size.width - 8, size.height - 8),
        Offset(size.width - 8, size.height - 8 - len), paint);
  }

  @override
  bool shouldRepaint(_) => false;
}

/// 인식 결과 데이터
class DetectionResult {
  final String label;
  final double confidence;
  final Rect rect;

  const DetectionResult({
    required this.label,
    required this.confidence,
    required this.rect,
  });
}
