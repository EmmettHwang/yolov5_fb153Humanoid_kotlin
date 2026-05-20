import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/yolo_detector_service.dart';

// ─────────────────────────────────────────────────────────────────
// DetectionResult 모델
// ─────────────────────────────────────────────────────────────────
class DetectionResult {
  final String label;
  final double confidence;
  final Rect rect;
  final int classIndex;

  const DetectionResult({
    required this.label,
    required this.confidence,
    required this.rect,
    this.classIndex = 0,
  });
}

// ─────────────────────────────────────────────────────────────────
// CameraPreviewWidget — 실제 카메라 + TFLite YOLOv5/MobileNet SSD
// ─────────────────────────────────────────────────────────────────
class CameraPreviewWidget extends StatefulWidget {
  /// 외부에서 주입하는 감지 결과 (YoloDetectorService에서 직접 받을 때 사용)
  final List<DetectionResult> detections;
  final bool isDetecting;
  final bool isYoloActive;
  final VoidCallback? onYoloToggle;

  /// YOLO 서비스 (null이면 위젯 내부에서 직접 관리)
  final YoloDetectorService? yoloService;

  const CameraPreviewWidget({
    super.key,
    this.detections = const [],
    this.isDetecting = false,
    this.isYoloActive = false,
    this.onYoloToggle,
    this.yoloService,
  });

  @override
  State<CameraPreviewWidget> createState() => _CameraPreviewWidgetState();
}

class _CameraPreviewWidgetState extends State<CameraPreviewWidget>
    with TickerProviderStateMixin {
  // ── 카메라 ──────────────────────────────────────
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _cameraInitialized = false;
  bool _cameraPermissionDenied = false;
  String? _cameraError;

  // ── YOLO 서비스 (내부 관리용) ──────────────────────
  YoloDetectorService? _internalYoloService;
  YoloDetectorService get _yoloSvc =>
      widget.yoloService ?? (_internalYoloService ??= YoloDetectorService());

  List<DetectionResult> _liveDetections = [];
  bool _isProcessingFrame = false;

  // ── 애니메이션 ──────────────────────────────────
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // ── 상태 ────────────────────────────────────────
  bool _isYoloPrev = false;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initCamera();

    // YOLO 서비스 변경 리스닝
    _yoloSvc.addListener(_onYoloServiceChanged);
  }

  void _initAnimations() {
    _glowCtrl = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );

    _pulseCtrl = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  /// 카메라 초기화 (권한 → 카메라 목록 → CameraController)
  Future<void> _initCamera() async {
    // 카메라 권한 요청
    final status = await Permission.camera.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      if (mounted) {
        setState(() => _cameraPermissionDenied = true);
      }
      return;
    }

    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        if (mounted) setState(() => _cameraError = '사용 가능한 카메라 없음');
        return;
      }

      // 후면 카메라 선택
      CameraDescription selectedCamera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _cameraController = CameraController(
        selectedCamera,
        ResolutionPreset.medium, // 640×480 정도
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() => _cameraInitialized = true);
      }

      // YOLO가 이미 활성화된 경우 스트림 시작
      if (widget.isYoloActive) {
        await _startImageStream();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cameraError = '카메라 초기화 실패: $e');
      }
      debugPrint('[Camera] 초기화 오류: $e');
    }
  }

  /// 이미지 스트림 시작 (YOLO 추론용)
  Future<void> _startImageStream() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (_cameraController!.value.isStreamingImages) return;

    // YOLO 서비스 초기화
    if (_yoloSvc.modelState == YoloModelState.idle) {
      _yoloSvc.initialize();
    }

    await _cameraController!.startImageStream(_onCameraFrame);
    debugPrint('[Camera] 이미지 스트림 시작');
  }

  /// 이미지 스트림 중지
  Future<void> _stopImageStream() async {
    if (_cameraController == null) return;
    if (!_cameraController!.value.isStreamingImages) return;

    try {
      await _cameraController!.stopImageStream();
      if (mounted) setState(() => _liveDetections = []);
      debugPrint('[Camera] 이미지 스트림 중지');
    } catch (e) {
      debugPrint('[Camera] 스트림 중지 오류: $e');
    }
  }

  /// 카메라 프레임 콜백
  void _onCameraFrame(CameraImage image) {
    if (_isProcessingFrame) return;
    if (_yoloSvc.modelState != YoloModelState.ready) return;

    _isProcessingFrame = true;
    final previewSize = _getPreviewSize();

    _yoloSvc.processFrame(image, previewSize).then((_) {
      _isProcessingFrame = false;
    }).catchError((e) {
      _isProcessingFrame = false;
    });
  }

  /// 현재 위젯 크기를 추론 결과 좌표계로 사용
  Size _getPreviewSize() {
    final box = context.findRenderObject() as RenderBox?;
    if (box != null) return box.size;
    return const Size(360, 240); // fallback
  }

  void _onYoloServiceChanged() {
    if (!mounted) return;
    setState(() {
      _liveDetections = _yoloSvc.results;
    });
  }

  @override
  void didUpdateWidget(CameraPreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // YOLO 활성화 상태 변경 감지
    if (widget.isYoloActive != _isYoloPrev) {
      _isYoloPrev = widget.isYoloActive;
      if (widget.isYoloActive) {
        _startImageStream();
      } else {
        _stopImageStream();
      }
    }
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    _pulseCtrl.dispose();
    _yoloSvc.removeListener(_onYoloServiceChanged);
    _internalYoloService?.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ① 카메라 프리뷰 (또는 에러/로딩 화면)
        _buildCameraLayer(),

        // ② YOLO 활성화 테두리 글로우
        if (widget.isYoloActive) _buildActiveGlow(),

        // ③ 코너 프레임
        _buildCornerFrame(),

        // ④ 모델 로딩 프로그레스바
        if (widget.isYoloActive &&
            _yoloSvc.modelState == YoloModelState.loading)
          _buildLoadingOverlay(),

        // ⑤ 바운딩 박스 오버레이 (YOLO 활성화 + 모델 준비 완료)
        if (widget.isYoloActive &&
            _yoloSvc.modelState == YoloModelState.ready)
          ..._buildDetectionBoxes(),

        // ⑥ 상단 정보 오버레이
        Positioned(
          top: 8,
          left: 8,
          right: 8,
          child: _buildTopOverlay(),
        ),

        // ⑦ 추론 시간 표시
        if (widget.isYoloActive && _yoloSvc.modelState == YoloModelState.ready)
          Positioned(
            bottom: 44,
            right: 8,
            child: _buildInferenceTag(),
          ),

        // ⑧ YOLO 토글 버튼 (중앙 하단)
        Positioned(
          bottom: 12,
          left: 0,
          right: 0,
          child: Center(child: _buildYoloToggleButton()),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 카메라 레이어
  // ─────────────────────────────────────────────────────────────

  Widget _buildCameraLayer() {
    // 권한 거부
    if (_cameraPermissionDenied) {
      return _buildPlaceholder(
        icon: Icons.no_photography,
        title: '카메라 권한 필요',
        subtitle: '설정 > 앱 > Robo Commander\n카메라 권한을 허용해 주세요',
        showSettingsButton: true,
      );
    }

    // 오류
    if (_cameraError != null) {
      return _buildPlaceholder(
        icon: Icons.error_outline,
        title: '카메라 오류',
        subtitle: _cameraError!,
        color: Colors.redAccent,
      );
    }

    // 초기화 중
    if (!_cameraInitialized || _cameraController == null) {
      return _buildPlaceholder(
        icon: Icons.videocam,
        title: '카메라 초기화 중...',
        showSpinner: true,
      );
    }

    // 실제 카메라 프리뷰
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _cameraController!.value.previewSize?.height ?? 640,
            height: _cameraController!.value.previewSize?.width ?? 480,
            child: CameraPreview(_cameraController!),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder({
    required IconData icon,
    required String title,
    String? subtitle,
    Color color = Colors.cyanAccent,
    bool showSpinner = false,
    bool showSettingsButton = false,
  }) {
    return Container(
      color: const Color(0xFF050C14),
      child: Center(
        child: AnimatedBuilder(
          animation: _pulseAnim,
          builder: (context, _) => Opacity(
            opacity: showSpinner ? 1.0 : _pulseAnim.value,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (showSpinner) ...[
                  CircularProgressIndicator(
                    color: color,
                    strokeWidth: 2,
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  Icon(icon, size: 44, color: color.withValues(alpha: 0.7)),
                  const SizedBox(height: 8),
                ],
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 10,
                      height: 1.5,
                    ),
                  ),
                ],
                if (showSettingsButton) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: openAppSettings,
                    icon: const Icon(Icons.settings, size: 14),
                    label: const Text('설정 열기', style: TextStyle(fontSize: 11)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.cyanAccent,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // YOLO 로딩 오버레이
  // ─────────────────────────────────────────────────────────────

  Widget _buildLoadingOverlay() {
    final progress = _yoloSvc.loadingProgress;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 로봇 아이콘 + 펄스 애니메이션
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (ctx, _) => Transform.scale(
                  scale: 0.9 + _pulseAnim.value * 0.2,
                  child: const Icon(
                    Icons.smart_toy,
                    size: 40,
                    color: Colors.greenAccent,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'AI 모델 로딩 중...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'EfficientDet-Lite0 COCO (80 클래스)',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 10,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 16),
              // 프로그레스 바
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.greenAccent),
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 바운딩 박스
  // ─────────────────────────────────────────────────────────────

  List<Widget> _buildDetectionBoxes() {
    final detections = widget.isYoloActive && widget.detections.isNotEmpty
        ? widget.detections
        : _liveDetections;

    if (detections.isEmpty) return [];

    // CustomPaint로 모든 박스를 한번에 렌더링
    return [
      Positioned.fill(
        child: CustomPaint(
          painter: _DetectionPainter(detections: detections),
        ),
      ),
    ];
  }

  // ─────────────────────────────────────────────────────────────
  // 기타 오버레이
  // ─────────────────────────────────────────────────────────────

  Widget _buildActiveGlow() {
    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (context, _) => Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: Colors.greenAccent.withValues(alpha: _glowAnim.value * 0.7),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.greenAccent.withValues(alpha: _glowAnim.value * 0.2),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
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
              : Colors.cyanAccent.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildTopOverlay() {
    String statusLabel;
    Color statusColor;
    IconData statusIcon;

    switch (_yoloSvc.modelState) {
      case YoloModelState.idle:
        statusLabel = widget.isYoloActive ? '모델 준비 중' : '대기';
        statusColor = Colors.white38;
        statusIcon = Icons.flash_off;
      case YoloModelState.loading:
        statusLabel = '로딩 중 ${(_yoloSvc.loadingProgress * 100).toInt()}%';
        statusColor = Colors.amber;
        statusIcon = Icons.downloading;
      case YoloModelState.ready:
        final count = _liveDetections.length;
        statusLabel = widget.isYoloActive
            ? (count > 0 ? '인식 $count개' : '감지 중')
            : '준비 완료';
        statusColor = widget.isYoloActive ? Colors.greenAccent : Colors.white38;
        statusIcon = widget.isYoloActive ? Icons.flash_on : Icons.flash_off;
      case YoloModelState.error:
        statusLabel = '모델 오류';
        statusColor = Colors.redAccent;
        statusIcon = Icons.error_outline;
    }

    return Row(
      children: [
        _buildTag(
          _cameraInitialized ? '카메라 ON' : '카메라',
          Icons.videocam,
          color: _cameraInitialized ? Colors.cyanAccent : Colors.white38,
        ),
        const SizedBox(width: 6),
        _buildTag('EfficientDet-Lite0', Icons.model_training),
        const Spacer(),
        _buildTag(statusLabel, statusIcon, color: statusColor),
      ],
    );
  }

  Widget _buildTag(String label, IconData icon, {Color? color}) {
    final c = color ?? Colors.cyan;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
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

  Widget _buildInferenceTag() {
    final ms = _yoloSvc.inferenceMs;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Colors.greenAccent.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        '${ms}ms',
        style: const TextStyle(
          color: Colors.greenAccent,
          fontSize: 9,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  /// YOLO 토글 버튼
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
              : Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isActive
                ? Colors.greenAccent.withValues(alpha: 0.8)
                : Colors.white.withValues(alpha: 0.3),
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
}

// ─────────────────────────────────────────────────────────────────
// CustomPainter: 바운딩 박스 + 레이블
// ─────────────────────────────────────────────────────────────────
class _DetectionPainter extends CustomPainter {
  final List<DetectionResult> detections;

  const _DetectionPainter({required this.detections});

  // 클래스별 색상 팔레트
  static const List<Color> _classColors = [
    Colors.greenAccent,
    Colors.cyanAccent,
    Colors.orangeAccent,
    Colors.pinkAccent,
    Colors.yellowAccent,
    Colors.lightBlueAccent,
    Colors.tealAccent,
    Colors.purpleAccent,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final det in detections) {
      final color = _classColors[det.classIndex % _classColors.length];

      // 바운딩 박스
      final boxPaint = Paint()
        ..color = color
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      canvas.drawRect(det.rect, boxPaint);

      // 레이블 배경
      final label = '${det.label} ${(det.confidence * 100).toInt()}%';
      final tp = TextPainter(
        text: TextSpan(
          text: ' $label ',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelH = tp.height + 2;
      final labelTop = det.rect.top - labelH;
      final bgRect = Rect.fromLTWH(
        det.rect.left,
        labelTop.clamp(0.0, size.height - labelH),
        tp.width,
        labelH,
      );

      canvas.drawRect(bgRect, Paint()..color = color);
      tp.paint(
        canvas,
        Offset(bgRect.left, bgRect.top + 1),
      );
    }
  }

  @override
  bool shouldRepaint(_DetectionPainter old) =>
      old.detections != detections;
}

// ─────────────────────────────────────────────────────────────────
// CustomPainter: 코너 프레임
// ─────────────────────────────────────────────────────────────────
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
