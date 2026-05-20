import 'package:flutter/material.dart';

/// 카메라 프리뷰 + YOLO 인식 오버레이 (시뮬레이션)
/// 실제 기기에서는 camera 패키지로 교체
class CameraPreviewWidget extends StatefulWidget {
  final List<DetectionResult> detections;
  final bool isDetecting;
  final bool isYoloActive;
  final VoidCallback? onYoloToggle;

  const CameraPreviewWidget({
    super.key,
    this.detections = const [],
    this.isDetecting = false,
    this.isYoloActive = false,
    this.onYoloToggle,
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
  late AnimationController _activateCtrl;
  late Animation<double> _activateAnim;

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

    // YOLO 활성화 시 글로우 애니메이션
    _activateCtrl = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
    _activateAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _activateCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scanLineCtrl.dispose();
    _pulseCtrl.dispose();
    _activateCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 카메라 배경 (실기기에서는 실제 카메라 프리뷰)
        _buildCameraBackground(),

        // YOLO 활성화 시 테두리 글로우 효과
        if (widget.isYoloActive)
          AnimatedBuilder(
            animation: _activateAnim,
            builder: (context, _) => Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.greenAccent
                        .withValues(alpha: _activateAnim.value * 0.8),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.greenAccent
                          .withValues(alpha: _activateAnim.value * 0.3),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),

        // 코너 프레임
        _buildCornerFrame(),

        // 스캔 라인 애니메이션 (YOLO 활성화 시만 표시)
        if (widget.isYoloActive)
          AnimatedBuilder(
            animation: _scanLineAnim,
            builder: (context, _) => _buildScanLine(),
          ),

        // YOLO 인식 결과 바운딩 박스
        if (widget.isYoloActive)
          ...widget.detections.map((det) => _buildDetectionBox(det)),

        // 상단 오버레이 (카메라 상태)
        Positioned(
          top: 8,
          left: 8,
          right: 8,
          child: _buildTopOverlay(),
        ),

        // 하단 오버레이 (추론 상태)
        if (widget.isDetecting && widget.isYoloActive)
          Positioned(
            bottom: 8,
            right: 8,
            child: _buildDetectionStatus(),
          ),

        // ── YOLO 토글 버튼 (중앙 하단) ──────────────────
        Positioned(
          bottom: 12,
          left: 0,
          right: 0,
          child: Center(child: _buildYoloToggleButton()),
        ),
      ],
    );
  }

  /// YOLO 활성화/비활성화 토글 버튼
  Widget _buildYoloToggleButton() {
    final isActive = widget.isYoloActive;

    return GestureDetector(
      onTap: widget.onYoloToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.greenAccent.withValues(alpha: 0.15)
              : Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isActive
                ? Colors.greenAccent.withValues(alpha: 0.8)
                : Colors.white.withValues(alpha: 0.25),
            width: isActive ? 1.5 : 1.0,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.greenAccent.withValues(alpha: 0.3),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isActive ? Icons.visibility : Icons.visibility_off,
                key: ValueKey(isActive),
                size: 16,
                color: isActive ? Colors.greenAccent : Colors.white54,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              isActive ? 'YOLO ON' : 'YOLO OFF',
              style: TextStyle(
                color: isActive ? Colors.greenAccent : Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 8),
            // 상태 인디케이터 점
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? Colors.greenAccent : Colors.white24,
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: Colors.greenAccent.withValues(alpha: 0.8),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.2,
          colors: [
            widget.isYoloActive
                ? const Color(0xFF0A1E14)
                : const Color(0xFF0A1628),
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
                  widget.isYoloActive
                      ? Icons.videocam
                      : Icons.camera_alt_outlined,
                  size: 48,
                  color: widget.isYoloActive
                      ? Colors.greenAccent.withValues(alpha: 0.5)
                      : Colors.cyan.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.isYoloActive ? 'YOLO ACTIVE' : 'CAMERA FEED',
                  style: TextStyle(
                    color: widget.isYoloActive
                        ? Colors.greenAccent.withValues(alpha: 0.5)
                        : Colors.cyan.withValues(alpha: 0.5),
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
        painter: _CornerFramePainter(
          color: widget.isYoloActive
              ? Colors.greenAccent.withValues(alpha: 0.7)
              : Colors.cyanAccent.withValues(alpha: 0.7),
        ),
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
              Colors.greenAccent.withValues(alpha: 0.6),
              Colors.greenAccent,
              Colors.greenAccent.withValues(alpha: 0.6),
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
        _buildTag(
          widget.isYoloActive ? '인식 활성' : '대기 중',
          widget.isYoloActive ? Icons.flash_on : Icons.flash_off,
          color: widget.isYoloActive ? Colors.greenAccent : Colors.white38,
        ),
      ],
    );
  }

  Widget _buildTag(String label, IconData icon, {Color? color}) {
    final c = color ?? Colors.cyan;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: c),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: c,
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
  final Color color;
  const _CornerFramePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
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
  bool shouldRepaint(_CornerFramePainter old) => old.color != color;
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
