import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import '../ui/camera/camera_preview_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SSD MobileNet V1 COCO — TFLite Detection PostProcess (후처리 내장)
//
// 모델: ssd_mobilenet_v1_coco.tflite  (4.0 MB, TF Hub 공식)
//   입력 : [1, 300, 300, 3]  uint8   양자화 (scale=0.0078125, zp=128)
//   출력0: [1, 10, 4]        float32 boxes   [top,left,bottom,right] 정규화 0~1
//   출력1: [1, 10]           float32 classes 클래스 인덱스 (0-based)
//   출력2: [1, 10]           float32 scores  신뢰도 0~1
//   출력3: [1]               float32 count   유효 탐지 수
//   레이블: COCO 80 클래스 (labels.txt, 인덱스 0-based 직접 매핑)
// ─────────────────────────────────────────────────────────────────────────────

enum YoloModelState { idle, loading, ready, error }

class YoloDetectorService extends ChangeNotifier {

  // ── 모델 파라미터 ──────────────────────────────────────────────────────────
  static const String _modelAsset  = 'assets/models/ssd_mobilenet_v1_coco.tflite';
  static const String _labelsAsset = 'assets/models/labels.txt';
  static const int    _inputSize   = 300;       // 모델 입력 크기
  static const int    _maxDetect   = 10;        // 모델 최대 탐지 수
  static const double _threshold   = 0.45;      // 신뢰도 임계값

  // ── 상태 ──────────────────────────────────────────────────────────────────
  Interpreter?          _interpreter;
  List<String>          _labels       = [];

  YoloModelState        _state        = YoloModelState.idle;
  YoloModelState get    modelState    => _state;

  double                _progress     = 0.0;
  double get            loadingProgress => _progress;

  String                _error        = '';
  String get            errorMessage  => _error;

  List<DetectionResult> _results      = [];
  List<DetectionResult> get results   => List.unmodifiable(_results);

  int                   _inferenceMs  = 0;
  int get               inferenceMs   => _inferenceMs;

  bool                  _running      = false;
  bool                  _disposed     = false;
  bool                  _paused       = false;   // 동작 전송 중 추론 일시정지

  // 프레임 throttle — 주화면 60fps유지, 추론만 1fps (1000ms)
  DateTime?             _lastFrame;
  static const int      _frameGapMs   = 1000;  // 추론 1fps

  // 커스텀 KNN 모드 지원
  bool                  _useCustomKnn = false;
  bool get              useCustomKnn  => _useCustomKnn;
  List<String>          _knnClasses   = [];
  List<String> get      knnClasses    => List.unmodifiable(_knnClasses);

  // KNN 추론 콜백 (CustomVisionScreen의 _knn에서 제공)
  Map<String,double>? Function(List<double>)? _knnInfer;
  Map<String,double>? Function(List<double>)? get knnInferFn => _knnInfer;
  List<double> Function(CameraImage)? _knnFeatureExtractor;
  List<double> Function(CameraImage)? get knnFeatureFn => _knnFeatureExtractor;

  // ── 초기화 ────────────────────────────────────────────────────────────────
  Future<void> initialize() async {
    if (_state == YoloModelState.loading ||
        _state == YoloModelState.ready) {
      return;
    }

    _setState(YoloModelState.loading);
    _setProgress(0.0);

    try {
      // 1) 레이블 로딩
      _setProgress(0.10);
      final raw = await rootBundle.loadString(_labelsAsset);
      _labels = raw
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      debugPrint('[OD] 레이블 ${_labels.length}개 로딩 완료');
      _setProgress(0.35);

      // 2) 모델 로딩
      final opts = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(_modelAsset, options: opts);
      _setProgress(0.80);

      final inShape  = _interpreter!.getInputTensor(0).shape;
      final outCount = _interpreter!.getOutputTensors().length;
      debugPrint('[OD] 입력 shape: $inShape');
      debugPrint('[OD] 출력 텐서 수: $outCount');

      // 3) 워밍업
      _setProgress(0.92);
      await _warmup();
      _setProgress(1.0);

      _setState(YoloModelState.ready);
      debugPrint('[OD] ✅ SSD MobileNet V1 COCO 준비 완료');

    } catch (e, st) {
      _error = '모델 로딩 실패: $e';
      _setState(YoloModelState.error);
      debugPrint('[OD] ❌ 초기화 오류: $e\n$st');
    }
  }

  Future<void> _warmup() async {
    if (_interpreter == null) return;
    try {
      final dummy = _buildDummyInput();
      final out   = _buildOutputBuffers();
      _interpreter!.runForMultipleInputs([dummy], out);
    } catch (_) {}
  }

  // ── 출력 버퍼 ─────────────────────────────────────────────────────────────
  // runForMultipleInputs의 outputs Map은 텐서 인덱스가 아닌
  // 출력 텐서의 순서(0,1,2,3)로 접근함
  Map<int, Object> _buildOutputBuffers() => {
        0: [List.generate(_maxDetect, (_) => List<double>.filled(4, 0.0))],  // boxes
        1: [List<double>.filled(_maxDetect, 0.0)],                           // classes
        2: [List<double>.filled(_maxDetect, 0.0)],                           // scores
        3: [0.0],                                                              // count
      };

  // uint8 더미 입력
  List<List<List<List<int>>>> _buildDummyInput() =>
      List.generate(1, (_) =>
        List.generate(_inputSize, (_) =>
          List.generate(_inputSize, (_) =>
            List<int>.filled(3, 128))));  // uint8 zero_point=128

  // ── 추론 일시정지 / 재개 ──────────────────────────────────────────────────
  /// 모션 전송 중 TFLite 추론 중단 (카메라 스트림은 유지)
  void pauseInference() {
    _paused = true;
    debugPrint('[OD] 추론 일시정지');
  }

  /// 모션 전송 완료 후 추론 재개
  void resumeInference() {
    _paused = false;
    debugPrint('[OD] 추론 재개');
  }

  bool get isPaused => _paused;

  // ── 프레임 처리 ───────────────────────────────────────────────────────────
  Future<void> processFrame(CameraImage frame, Size displaySize) async {
    if (_interpreter == null || _state != YoloModelState.ready) return;
    if (_running || _paused) return;   // 일시정지 중이면 스킵

    final now = DateTime.now();
    if (_lastFrame != null &&
        now.difference(_lastFrame!).inMilliseconds < _frameGapMs) {
      return;
    }
    _lastFrame = now;
    _running = true;

    final sw = Stopwatch()..start();

    try {
      // 1) YUV420 → RGB → resize 300×300 → uint8 텐서 (isolate)
      final input = await compute(_yuv420ToUint8Input, {
        'y'          : frame.planes[0].bytes,
        'u'          : frame.planes[1].bytes,
        'v'          : frame.planes[2].bytes,
        'width'      : frame.width,
        'height'     : frame.height,
        'rowStrideY' : frame.planes[0].bytesPerRow,
        'rowStrideUV': frame.planes[1].bytesPerRow,
        'pixStrideUV': frame.planes[1].bytesPerPixel ?? 1,
        'inputSize'  : _inputSize,
      });

      if (input == null) {
        _running = false;
        return;
      }

      // 2) 추론
      final out = _buildOutputBuffers();
      _interpreter!.runForMultipleInputs([input], out);

      // 3) 결과 파싱
      final detections = _parseOutput(out, displaySize);

      sw.stop();
      _inferenceMs = sw.elapsedMilliseconds;

      if (!_disposed) {
        _results = detections;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[OD] 추론 오류: $e');
    } finally {
      _running = false;
    }
  }

  // ── 결과 파싱 ─────────────────────────────────────────────────────────────
  List<DetectionResult> _parseOutput(Map<int, Object> out, Size displaySize) {
    // out[0] → [[top,left,bottom,right], ...]  (boxes, 배치 1개)
    // out[1] → [classIdx, ...]
    // out[2] → [score, ...]
    // out[3] → [count]
    final rawBoxes   = (out[0]! as List)[0] as List;
    final rawClasses = (out[1]! as List)[0] as List;
    final rawScores  = (out[2]! as List)[0] as List;
    final count      = ((out[3]! as List)[0] as double)
        .round()
        .clamp(0, _maxDetect);

    final W = displaySize.width;
    final H = displaySize.height;
    final results = <DetectionResult>[];

    for (int i = 0; i < count; i++) {
      final score = (rawScores[i] as double);
      if (score < _threshold) continue;

      final box    = rawBoxes[i] as List;
      final top    = (box[0] as double).clamp(0.0, 1.0);
      final left   = (box[1] as double).clamp(0.0, 1.0);
      final bottom = (box[2] as double).clamp(0.0, 1.0);
      final right  = (box[3] as double).clamp(0.0, 1.0);

      final rect = Rect.fromLTRB(left * W, top * H, right * W, bottom * H);
      if (rect.width < 10 || rect.height < 10) continue;

      // 클래스 인덱스 (0-based → labels.txt 직접 매핑)
      final classIdx = (rawClasses[i] as double).round().clamp(0, _labels.length - 1);
      final label = classIdx < _labels.length ? _labels[classIdx] : 'object';

      results.add(DetectionResult(
        label:      label,
        confidence: score,
        rect:       rect,
        classIndex: classIdx,
      ));
    }

    return results;
  }

  // ── 내부 유틸 ─────────────────────────────────────────────────────────────
  void _setState(YoloModelState s) {
    _state = s;
    if (!_disposed) notifyListeners();
  }

  void _setProgress(double v) {
    _progress = v;
    if (!_disposed) notifyListeners();
  }

  void clearResults() {
    _results = [];
    if (!_disposed) notifyListeners();
  }

  // ── 커스텀 KNN 모드 설정 ─────────────────────────────────────────────────
  /// KNN 학습 완료 후 호출 — 이후 processFrame은 KNN으로 추론
  void setCustomKnnMode({
    required List<String> classes,
    required Map<String, double>? Function(List<double>) inferFn,
    required List<double> Function(CameraImage) featureFn,
  }) {
    _knnClasses = List<String>.from(classes);
    _knnInfer = inferFn;
    _knnFeatureExtractor = featureFn;
    _useCustomKnn = true;
    debugPrint('[OD] 커스텀 KNN 모드 활성화: ${_knnClasses.length}개 클래스');
    notifyListeners();
  }

  /// KNN 모드 해제 → YOLO SSD 복귀
  void clearCustomKnnMode() {
    _useCustomKnn = false;
    _knnClasses = [];
    _knnInfer = null;
    _knnFeatureExtractor = null;
    debugPrint('[OD] YOLO SSD 모드 복귀');
    notifyListeners();
  }

  // ── KNN 결과 주입 (camera_preview_widget에서 호출) ──────────────────────
  /// KNN 추론 결과를 DetectionResult로 변환하여 상태에 주입
  void injectKnnResult(String label, double confidence, Size displaySize) {
    if (_disposed) return;
    _results = [
      DetectionResult(
        label: label,
        confidence: confidence,
        rect: Rect.fromLTWH(
          displaySize.width * 0.05, displaySize.height * 0.05,
          displaySize.width * 0.9, displaySize.height * 0.9,
        ),
      ),
    ];
    notifyListeners();
  }

  /// 1fps throttle 체크 — 외부에서 호출 전 확인용
  bool shouldProcessFrame() {
    if (_running || _paused) return false;
    final now = DateTime.now();
    if (_lastFrame != null &&
        now.difference(_lastFrame!).inMilliseconds < _frameGapMs) return false;
    _lastFrame = now;
    return true;
  }

  void setRunning(bool v) => _running = v;

  @override
  void dispose() {
    _disposed = true;
    _interpreter?.close();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// compute() isolate — YUV420 → uint8 텐서 [1, 300, 300, 3]
//
// SSD MobileNet V1은 uint8 입력 (양자화 모델)
// zero_point=128 이므로 0~255 값을 그대로 사용
// ─────────────────────────────────────────────────────────────────────────────
List<List<List<List<int>>>>? _yuv420ToUint8Input(Map<String, dynamic> args) {
  try {
    final y           = args['y']           as Uint8List;
    final u           = args['u']           as Uint8List;
    final v           = args['v']           as Uint8List;
    final width       = args['width']       as int;
    final height      = args['height']      as int;
    final rowStrideY  = args['rowStrideY']  as int;
    final rowStrideUV = args['rowStrideUV'] as int;
    final pixStrideUV = args['pixStrideUV'] as int;
    final inputSize   = args['inputSize']   as int;

    // YUV420 → RGB img.Image
    final rgb = img.Image(width: width, height: height);

    for (int row = 0; row < height; row++) {
      for (int col = 0; col < width; col++) {
        final yIdx  = row * rowStrideY + col;
        final uvRow = row >> 1;
        final uvCol = col >> 1;
        final uvIdx = uvRow * rowStrideUV + uvCol * pixStrideUV;

        final yv = yIdx  < y.length ? y[yIdx]  : 0;
        final uv = uvIdx < u.length ? u[uvIdx] - 128 : 0;
        final vv = uvIdx < v.length ? v[uvIdx] - 128 : 0;

        // BT.601 YUV → RGB
        final r = (yv + 1.370705 * vv).round().clamp(0, 255);
        final g = (yv - 0.698001 * vv - 0.337633 * uv).round().clamp(0, 255);
        final b = (yv + 1.732446 * uv).round().clamp(0, 255);

        rgb.setPixelRgb(col, row, r, g, b);
      }
    }

    // 300×300 리사이즈
    final resized = img.copyResize(
      rgb,
      width:  inputSize,
      height: inputSize,
      interpolation: img.Interpolation.linear,
    );

    // uint8 텐서 [1, 300, 300, 3]
    return List.generate(
      1,
      (_) => List.generate(inputSize, (row) =>
        List.generate(inputSize, (col) {
          final px = resized.getPixel(col, row);
          return [px.r.toInt(), px.g.toInt(), px.b.toInt()];
        }),
      ),
    );
  } catch (e) {
    return null;
  }
}
