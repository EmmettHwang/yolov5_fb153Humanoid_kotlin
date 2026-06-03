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
// CameraPreviewWidget — 실제 카메라 + TFLite SSD MobileNet V1 COCO
// ─────────────────────────────────────────────────────────────────
class CameraPreviewWidget extends StatefulWidget {
  final bool isYoloActive;
  final VoidCallback? onYoloToggle;
  final YoloDetectorService? yoloService;

  const CameraPreviewWidget({
    super.key,
    this.isYoloActive = false,
    this.onYoloToggle,
    this.yoloService,
  });

  @override
  State<CameraPreviewWidget> createState() => _CameraPreviewWidgetState();
}

class _CameraPreviewWidgetState extends State<CameraPreviewWidget>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── 카메라 ───────────────────────────────────────────────────
  CameraController? _ctrl;
  bool _cameraReady     = false;
  bool _permDenied      = false;
  String? _cameraError;

  // ── 앱 라이프사이클 / 복귀 감지 ─────────────────────────────
  bool _reinitPending = false;

  // ── YOLO 서비스 ─────────────────────────────────────────────
  YoloDetectorService? _internalSvc;
  YoloDetectorService get _svc =>
      widget.yoloService ?? (_internalSvc ??= YoloDetectorService());

  List<DetectionResult> _detections = [];
  bool _streaming = false;

  // ── 애니메이션 ───────────────────────────────────────────────
  late AnimationController _glowCtrl;
  late Animation<double>   _glowAnim;
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  // ── isYoloActive 이전값 (didUpdateWidget용) ──────────────────
  bool _prevYolo = false;

  // ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _prevYolo = widget.isYoloActive;

    _glowCtrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 800))..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));

    _pulseCtrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _svc.addListener(_onSvcChanged);
    _initCamera();
  }

  // ─────────────────────────────────────────────────────────────
  // 앱 라이프사이클 감지 — resumed 시 카메라 재초기화
  // CustomVisionScreen 등 다른 화면에서 카메라 사용 후
  // 메인 화면으로 복귀할 때 카메라가 동작하지 않는 문제 해결
  // ─────────────────────────────────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;

    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        // 화면이 비활성화되면 카메라 스트림 중지 (리소스 해제)
        _pauseCamera();

      case AppLifecycleState.resumed:
        // 앱 복귀 시 카메라 재초기화
        if (_reinitPending || !_cameraReady || _ctrl == null ||
            !_ctrl!.value.isInitialized) {
          _reinitPending = false;
          _reinitCamera();
        }

      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 라우트 복귀 감지 — didChangeDependencies에서 RouteObserver 없이
  // Navigator.pop 후 복귀를 감지하기 위해 WidgetsBindingObserver 활용
  // ─────────────────────────────────────────────────────────────
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ModalRoute가 다시 현재 라우트가 되었을 때 카메라 재확인
    final route = ModalRoute.of(context);
    if (route != null && route.isCurrent) {
      // 카메라가 무효화된 경우 재초기화
      if (_cameraReady && (_ctrl == null || !_ctrl!.value.isInitialized)) {
        _reinitCamera();
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 카메라 일시 중지 (화면 비활성화 시)
  // ─────────────────────────────────────────────────────────────
  Future<void> _pauseCamera() async {
    if (_ctrl == null || !_ctrl!.value.isInitialized) return;
    try {
      if (_ctrl!.value.isStreamingImages) {
        await _ctrl!.stopImageStream();
        _streaming = false;
      }
    } catch (e) {
      debugPrint('[Cam] pauseCamera 오류: $e');
    }
    _reinitPending = true;
  }

  // ─────────────────────────────────────────────────────────────
  // 카메라 재초기화 — 기존 controller 해제 후 새로 생성
  // ─────────────────────────────────────────────────────────────
  Future<void> _reinitCamera() async {
    if (!mounted) return;
    debugPrint('[Cam] 카메라 재초기화 시작');

    // 기존 컨트롤러 정리
    final oldCtrl = _ctrl;
    _ctrl = null;
    _streaming = false;
    if (mounted) setState(() => _cameraReady = false);

    try {
      if (oldCtrl != null) {
        if (oldCtrl.value.isStreamingImages) {
          await oldCtrl.stopImageStream().catchError((_) {});
        }
        await oldCtrl.dispose().catchError((_) {});
      }
    } catch (_) {}

    // 잠깐 대기 후 재초기화 (Android에서 카메라 반환 시간 필요)
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) await _initCamera();
  }

  // ─────────────────────────────────────────────────────────────
  // 카메라 초기화
  // ─────────────────────────────────────────────────────────────
  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      if (mounted) setState(() => _permDenied = true);
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = '사용 가능한 카메라 없음');
        return;
      }

      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final ctrl = CameraController(
        cam,
        ResolutionPreset.medium, // 약 640×480
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await ctrl.initialize();

      if (!mounted) {
        await ctrl.dispose();
        return;
      }

      _ctrl = ctrl;
      setState(() {
        _cameraReady = true;
        _cameraError = null;
      });

      debugPrint('[Cam] 카메라 초기화 완료');

      // initState 때 이미 YOLO ON이면 바로 시작
      if (widget.isYoloActive) _startYolo();

    } catch (e) {
      if (mounted) setState(() => _cameraError = '카메라 오류: $e');
      debugPrint('[Cam] 초기화 오류: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // YOLO 시작 / 중지
  // ─────────────────────────────────────────────────────────────

  /// YOLO ON → 모델 로딩(필요시) + 스트림 시작
  Future<void> _startYolo() async {
    if (!_cameraReady || _ctrl == null) return;

    // 1) 모델이 아직 안 로딩됐으면 시작
    if (_svc.modelState == YoloModelState.idle) {
      await _svc.initialize(); // 로딩 완료까지 대기
    } else if (_svc.modelState == YoloModelState.loading) {
      // 이미 로딩 중이면 완료 신호를 리스너(_onSvcChanged)에서 받아 처리
      return;
    } else if (_svc.modelState == YoloModelState.error) {
      return;
    }

    // 2) 모델 ready → 스트림 시작
    await _startStream();
  }

  Future<void> _startStream() async {
    if (_ctrl == null || !_ctrl!.value.isInitialized) return;
    if (_streaming) return;
    if (_ctrl!.value.isStreamingImages) return;

    try {
      await _ctrl!.startImageStream(_onFrame);
      _streaming = true;
      debugPrint('[Cam] 이미지 스트림 시작');
    } catch (e) {
      debugPrint('[Cam] 스트림 시작 오류: $e');
    }
  }

  Future<void> _stopYolo() async {
    if (_ctrl == null) return;
    if (!_ctrl!.value.isStreamingImages) { _streaming = false; return; }
    try {
      await _ctrl!.stopImageStream();
      _streaming = false;
      _svc.clearResults();
      if (mounted) setState(() => _detections = []);
      debugPrint('[Cam] 이미지 스트림 중지');
    } catch (e) {
      debugPrint('[Cam] 스트림 중지 오류: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 카메라 프레임 콜백 — 프리뷰는 항상 60fps, 추론만 1fps 제한
  // ─────────────────────────────────────────────────────────────
  void _onFrame(CameraImage image) {
    if (_svc.modelState != YoloModelState.ready) return;
    if (!_svc.shouldProcessFrame()) return; // 1fps throttle

    final box = context.findRenderObject() as RenderBox?;
    final size = box?.size ?? const Size(360, 240);

    if (_svc.useCustomKnn && _svc.knnClasses.isNotEmpty) {
      // 커스텀 KNN 모드: 특징 추출 → KNN 추론
      _runKnnInference(image, size);
    } else {
      // 기본 YOLO SSD 모드
      _svc.processFrame(image, size);
    }
  }

  void _runKnnInference(CameraImage image, Size displaySize) {
    // shouldProcessFrame()이 이미 통과했으므로 바로 추론
    _svc.setRunning(true);
    final sw = Stopwatch()..start();
    try {
      // 메인 스레드에서 간단히 처리 (1fps라 부하 낮음)
      final knnInfer = _svc.knnInferFn;
      final featureFn = _svc.knnFeatureFn;
      if (knnInfer == null || featureFn == null) {
        _svc.setRunning(false);
        return;
      }
      final features = featureFn(image);
      final result = knnInfer(features);
      sw.stop();
      if (result != null) {
        final best = result.entries.reduce((a, b) => a.value > b.value ? a : b);
        _svc.injectKnnResult(best.key, best.value, displaySize);
      }
    } catch (e) {
      debugPrint('[Cam] KNN 추론 오류: $e');
    } finally {
      _svc.setRunning(false);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // YoloDetectorService 리스너
  // ─────────────────────────────────────────────────────────────
  void _onSvcChanged() {
    if (!mounted) return;

    // 모델 로딩 완료 → 스트림이 아직 안 시작됐으면 시작
    if (_svc.modelState == YoloModelState.ready &&
        widget.isYoloActive &&
        !_streaming) {
      _startStream();
    }

    setState(() => _detections = List.from(_svc.results));
  }

  // ─────────────────────────────────────────────────────────────
  @override
  void didUpdateWidget(CameraPreviewWidget old) {
    super.didUpdateWidget(old);
    if (widget.isYoloActive != _prevYolo) {
      _prevYolo = widget.isYoloActive;
      if (widget.isYoloActive) {
        _startYolo();
      } else {
        _stopYolo();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _glowCtrl.dispose();
    _pulseCtrl.dispose();
    _svc.removeListener(_onSvcChanged);
    _internalSvc?.dispose();
    // 스트림 먼저 중지 후 dispose
    if (_ctrl != null) {
      final ctrl = _ctrl!;
      _ctrl = null;
      if (ctrl.value.isStreamingImages) {
        ctrl.stopImageStream().then((_) => ctrl.dispose()).catchError((_) {
          ctrl.dispose().catchError((_) {});
        });
      } else {
        ctrl.dispose().catchError((_) {});
      }
    }
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ① 카메라 or 플레이스홀더
        _buildCameraLayer(),

        // ② YOLO ON 글로우 테두리
        if (widget.isYoloActive) _buildGlow(),

        // ③ 코너 프레임
        CustomPaint(painter: _CornerFramePainter(
          color: widget.isYoloActive
              ? Colors.greenAccent.withValues(alpha: 0.7)
              : Colors.cyanAccent.withValues(alpha: 0.5),
        )),

        // ④ 모델 로딩 프로그레스바
        if (widget.isYoloActive && _svc.modelState == YoloModelState.loading)
          _buildLoadingOverlay(),

        // ⑤ 바운딩 박스 (ready + 결과 있을 때)
        if (widget.isYoloActive &&
            _svc.modelState == YoloModelState.ready &&
            _detections.isNotEmpty)
          Positioned.fill(child: CustomPaint(
            painter: _DetectionPainter(detections: _detections),
          )),

        // ⑥ 상단 정보 태그
        Positioned(top: 8, left: 8, right: 8, child: _buildTopBar()),

        // ⑦ 추론 시간
        if (widget.isYoloActive && _svc.inferenceMs > 0)
          Positioned(bottom: 44, right: 8, child: _buildMsTag()),

        // ⑧ YOLO 토글 버튼
        Positioned(
          bottom: 12, left: 0, right: 0,
          child: Center(child: _buildToggleBtn()),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 카메라 레이어
  // ─────────────────────────────────────────────────────────────
  Widget _buildCameraLayer() {
    if (_permDenied) {
      return _placeholder(
        icon: Icons.no_photography,
        title: '카메라 권한 필요',
        sub: '설정 > 앱 > Robo Commander\n카메라 권한을 허용해 주세요',
        settingsBtn: true,
      );
    }
    if (_cameraError != null) {
      return _placeholder(icon: Icons.error_outline,
          title: '카메라 오류', sub: _cameraError!, color: Colors.redAccent);
    }
    if (!_cameraReady || _ctrl == null || !_ctrl!.value.isInitialized) {
      return _placeholder(icon: Icons.videocam,
          title: '카메라 초기화 중...', spinner: true);
    }

    // 실제 카메라 프리뷰
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width:  _ctrl!.value.previewSize?.height ?? 640,
            height: _ctrl!.value.previewSize?.width  ?? 480,
            child: CameraPreview(_ctrl!),
          ),
        ),
      ),
    );
  }

  Widget _placeholder({
    required IconData icon,
    required String title,
    String? sub,
    Color color = Colors.cyanAccent,
    bool spinner = false,
    bool settingsBtn = false,
  }) {
    return Container(
      color: const Color(0xFF050C14),
      child: Center(
        child: AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, __) => Opacity(
            opacity: spinner ? 1.0 : _pulseAnim.value,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (spinner)
                CircularProgressIndicator(color: color, strokeWidth: 2)
              else
                Icon(icon, size: 44, color: color.withValues(alpha: 0.7)),
              const SizedBox(height: 10),
              Text(title, style: TextStyle(
                  color: color, fontSize: 13,
                  fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              if (sub != null) ...[
                const SizedBox(height: 6),
                Text(sub, textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 10, height: 1.5)),
              ],
              if (settingsBtn) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: openAppSettings,
                  icon: const Icon(Icons.settings, size: 14),
                  label: const Text('설정 열기',
                      style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                      foregroundColor: Colors.cyanAccent),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 로딩 오버레이
  // ─────────────────────────────────────────────────────────────
  Widget _buildLoadingOverlay() {
    final p = _svc.loadingProgress;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.70),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, __) => Transform.scale(
                scale: 0.9 + _pulseAnim.value * 0.2,
                child: const Icon(Icons.smart_toy,
                    size: 40, color: Colors.greenAccent),
              ),
            ),
            const SizedBox(height: 14),
            const Text('AI 모델 로딩 중...',
                style: TextStyle(color: Colors.white,
                    fontSize: 14, fontWeight: FontWeight.bold,
                    letterSpacing: 1.5)),
            const SizedBox(height: 4),
            Text('SSD MobileNet V1  COCO 80 클래스',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 10)),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Column(children: [
                LinearProgressIndicator(
                  value: p,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.greenAccent),
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(3),
                ),
                const SizedBox(height: 6),
                Text('${(p * 100).toInt()}%',
                    style: const TextStyle(color: Colors.greenAccent,
                        fontSize: 11, fontFamily: 'monospace')),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 상단 정보 바
  // ─────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    // 상태 레이블
    String statusLabel;
    Color statusColor;
    IconData statusIcon;

    switch (_svc.modelState) {
      case YoloModelState.idle:
        statusLabel = widget.isYoloActive ? '모델 대기' : '대기';
        statusColor = Colors.white38;
        statusIcon  = Icons.flash_off;
      case YoloModelState.loading:
        statusLabel = '로딩 ${(_svc.loadingProgress * 100).toInt()}%';
        statusColor = Colors.amber;
        statusIcon  = Icons.downloading;
      case YoloModelState.ready:
        final n = _detections.length;
        statusLabel = widget.isYoloActive
            ? (n > 0 ? '인식 $n개' : '감지 중')
            : '준비 완료';
        statusColor = widget.isYoloActive ? Colors.greenAccent : Colors.white38;
        statusIcon  = widget.isYoloActive ? Icons.flash_on : Icons.flash_off;
      case YoloModelState.error:
        statusLabel = '모델 오류';
        statusColor = Colors.redAccent;
        statusIcon  = Icons.error_outline;
    }

    return Row(children: [
      _tag(_cameraReady ? '카메라 ON' : '카메라',
           Icons.videocam,
           color: _cameraReady ? Colors.cyanAccent : Colors.white38),
      const SizedBox(width: 6),
      _tag('SSD MobileNet V1', Icons.model_training),
      const Spacer(),
      _tag(statusLabel, statusIcon, color: statusColor),
    ]);
  }

  Widget _tag(String label, IconData icon, {Color? color}) {
    final c = color ?? Colors.cyan;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10, color: c),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(
            color: c, fontSize: 9, fontFamily: 'monospace')),
      ]),
    );
  }

  Widget _buildMsTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
      ),
      child: Text('${_svc.inferenceMs}ms',
          style: const TextStyle(color: Colors.greenAccent,
              fontSize: 9, fontFamily: 'monospace')),
    );
  }

  Widget _buildGlow() {
    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (_, __) => Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: Colors.greenAccent.withValues(alpha: _glowAnim.value * 0.7),
              width: 2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToggleBtn() {
    final on = widget.isYoloActive;
    return GestureDetector(
      onTap: widget.onYoloToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: on
              ? Colors.greenAccent.withValues(alpha: 0.15)
              : Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: on
                ? Colors.greenAccent.withValues(alpha: 0.85)
                : Colors.white.withValues(alpha: 0.3),
            width: on ? 1.5 : 1.0,
          ),
          boxShadow: on ? [BoxShadow(
            color: Colors.greenAccent.withValues(alpha: 0.3),
            blurRadius: 12, spreadRadius: 1,
          )] : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Icon(
              on ? Icons.visibility : Icons.visibility_off,
              key: ValueKey(on), size: 16,
              color: on ? Colors.greenAccent : Colors.white54,
            ),
          ),
          const SizedBox(width: 7),
          Text(on ? '객체인식 ON' : '객체인식 OFF',
              style: TextStyle(
                color: on ? Colors.greenAccent : Colors.white54,
                fontSize: 11, fontWeight: FontWeight.bold,
                letterSpacing: 1.5, fontFamily: 'monospace',
              )),
          const SizedBox(width: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            width: 6, height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? Colors.greenAccent : Colors.white24,
              boxShadow: on ? [BoxShadow(
                color: Colors.greenAccent.withValues(alpha: 0.8),
                blurRadius: 6,
              )] : null,
            ),
          ),
        ]),
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

  static const _colors = [
    Colors.greenAccent, Colors.cyanAccent, Colors.orangeAccent,
    Colors.pinkAccent, Colors.yellowAccent, Colors.lightBlueAccent,
    Colors.tealAccent, Colors.purpleAccent,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final det in detections) {
      final color = _colors[det.classIndex % _colors.length];

      // 박스
      canvas.drawRect(det.rect,
          Paint()..color = color..strokeWidth = 2.0..style = PaintingStyle.stroke);

      // 레이블
      final label = '${det.label} ${(det.confidence * 100).toInt()}%';
      final tp = TextPainter(
        text: TextSpan(text: ' $label ',
            style: const TextStyle(color: Colors.black,
                fontSize: 10, fontWeight: FontWeight.bold,
                fontFamily: 'monospace')),
        textDirection: TextDirection.ltr,
      )..layout();

      final lh   = tp.height + 2;
      final top  = (det.rect.top - lh).clamp(0.0, size.height - lh);
      final bgR  = Rect.fromLTWH(det.rect.left, top, tp.width, lh);
      canvas.drawRect(bgR, Paint()..color = color);
      tp.paint(canvas, Offset(bgR.left, bgR.top + 1));
    }
  }

  @override
  bool shouldRepaint(_DetectionPainter old) => old.detections != detections;
}

// ─────────────────────────────────────────────────────────────────
// CustomPainter: 코너 프레임
// ─────────────────────────────────────────────────────────────────
class _CornerFramePainter extends CustomPainter {
  final Color color;
  const _CornerFramePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color..strokeWidth = 2.5..style = PaintingStyle.stroke;
    const L = 20.0;
    const O = 8.0;
    // TL
    canvas.drawLine(Offset(O, O), Offset(O + L, O), p);
    canvas.drawLine(Offset(O, O), Offset(O, O + L), p);
    // TR
    canvas.drawLine(Offset(size.width - O, O), Offset(size.width - O - L, O), p);
    canvas.drawLine(Offset(size.width - O, O), Offset(size.width - O, O + L), p);
    // BL
    canvas.drawLine(Offset(O, size.height - O), Offset(O + L, size.height - O), p);
    canvas.drawLine(Offset(O, size.height - O), Offset(O, size.height - O - L), p);
    // BR
    canvas.drawLine(Offset(size.width - O, size.height - O),
        Offset(size.width - O - L, size.height - O), p);
    canvas.drawLine(Offset(size.width - O, size.height - O),
        Offset(size.width - O, size.height - O - L), p);
  }

  @override
  bool shouldRepaint(_CornerFramePainter old) => old.color != color;
}
