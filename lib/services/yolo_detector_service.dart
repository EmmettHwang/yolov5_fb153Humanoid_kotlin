import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import '../ui/camera/camera_preview_widget.dart';

/// YOLO 모델 로딩 상태
enum YoloModelState {
  idle,
  loading,
  ready,
  error,
}

/// TFLite 기반 사물인식 서비스
/// MobileNet SSD v1 COCO (4MB) 사용 — 80 클래스
class YoloDetectorService extends ChangeNotifier {
  static const String _modelPath = 'assets/models/yolov5s.tflite';
  static const String _labelsPath = 'assets/models/labels.txt';

  // 모델 입력 크기 (MobileNet SSD: 300×300)
  static const int _inputSize = 300;
  static const double _confidenceThreshold = 0.45;
  // ignore: unused_field
  static const double _iouThreshold = 0.45;
  static const int _maxDetections = 10;

  Interpreter? _interpreter;
  List<String> _labels = [];

  YoloModelState _modelState = YoloModelState.idle;
  YoloModelState get modelState => _modelState;

  double _loadingProgress = 0.0;
  double get loadingProgress => _loadingProgress;

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  // 추론 결과
  List<DetectionResult> _results = [];
  List<DetectionResult> get results => List.unmodifiable(_results);

  // 마지막 추론 시간 (ms)
  int _inferenceMs = 0;
  int get inferenceMs => _inferenceMs;

  // 프레임 처리 throttle (초당 최대 10 프레임)
  DateTime? _lastFrameTime;
  static const _frameIntervalMs = 100; // 10fps

  bool _disposed = false;

  /// 모델 초기화 (로딩 프로그레스 콜백 포함)
  Future<void> initialize() async {
    if (_modelState == YoloModelState.loading ||
        _modelState == YoloModelState.ready) return;

    _setModelState(YoloModelState.loading);
    _setProgress(0.0);

    try {
      // Step 1: 레이블 로딩 (10%)
      _setProgress(0.1);
      await _loadLabels();
      _setProgress(0.3);

      // Step 2: TFLite 모델 로딩 (30% → 90%)
      await _loadModel();
      _setProgress(0.9);

      // Step 3: 워밍업 (더미 추론)
      await _warmup();
      _setProgress(1.0);

      _setModelState(YoloModelState.ready);
      debugPrint('[YOLO] ✅ 모델 초기화 완료: $_labels.length 클래스');
    } catch (e) {
      _errorMessage = '모델 로딩 실패: $e';
      _setModelState(YoloModelState.error);
      debugPrint('[YOLO] ❌ 초기화 오류: $e');
    }
  }

  Future<void> _loadLabels() async {
    final labelsData = await rootBundle.loadString(_labelsPath);
    _labels = labelsData
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    debugPrint('[YOLO] 레이블 로딩: ${_labels.length}개');
  }

  Future<void> _loadModel() async {
    // TFLite Interpreter 옵션
    final options = InterpreterOptions()
      ..threads = 2; // 멀티스레드 추론

    _interpreter = await Interpreter.fromAsset(
      _modelPath,
      options: options,
    );
    debugPrint('[YOLO] 모델 로딩 완료');
    debugPrint('[YOLO] 입력 텐서: ${_interpreter!.getInputTensor(0).shape}');
    debugPrint('[YOLO] 출력 텐서 수: ${_interpreter!.getOutputTensors().length}');
  }

  Future<void> _warmup() async {
    if (_interpreter == null) return;
    try {
      // 더미 데이터로 워밍업
      final dummyInput = List.generate(
        1,
        (_) => List.generate(
          _inputSize,
          (_) => List.generate(
            _inputSize,
            (_) => List<double>.filled(3, 0.0),
          ),
        ),
      );
      final outputs = _buildOutputBuffers();
      _interpreter!.runForMultipleInputs([dummyInput], outputs);
      debugPrint('[YOLO] 워밍업 완료');
    } catch (e) {
      debugPrint('[YOLO] 워밍업 중 오류 (무시): $e');
    }
  }

  /// MobileNet SSD 출력 버퍼 구성
  /// 출력: [boxes(1,10,4), classes(1,10), scores(1,10), count(1)]
  Map<int, Object> _buildOutputBuffers() {
    return {
      0: List.generate(1, (_) => List.generate(_maxDetections, (_) => List<double>.filled(4, 0.0))),
      1: List.generate(1, (_) => List<double>.filled(_maxDetections, 0.0)),
      2: List.generate(1, (_) => List<double>.filled(_maxDetections, 0.0)),
      3: List<double>.filled(1, 0.0),
    };
  }

  /// CameraImage 프레임 처리 (비동기 추론)
  Future<void> processFrame(CameraImage cameraImage, Size previewSize) async {
    if (_interpreter == null || _modelState != YoloModelState.ready) return;
  if (_isRunning) return;

    // 프레임 throttle
    final now = DateTime.now();
    if (_lastFrameTime != null &&
        now.difference(_lastFrameTime!).inMilliseconds < _frameIntervalMs) {
      return;
    }
    _lastFrameTime = now;

    _isRunning = true;
    final stopwatch = Stopwatch()..start();

    try {
      // 1. 카메라 이미지 → RGB Float32 [1,300,300,3]
      final inputData = await compute(_preprocessFrame, {
        'yuv': _yuv420ToBytes(cameraImage),
        'width': cameraImage.width,
        'height': cameraImage.height,
        'inputSize': _inputSize,
      });

      if (inputData == null) {
        _isRunning = false;
        return;
      }

      // 2. 추론
      final outputs = _buildOutputBuffers();
      _interpreter!.runForMultipleInputs([inputData], outputs);

      // 3. 결과 파싱
      final detections = _parseOutputs(outputs, previewSize);

      stopwatch.stop();
      _inferenceMs = stopwatch.elapsedMilliseconds;

      if (!_disposed) {
        _results = detections;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[YOLO] 추론 오류: $e');
    } finally {
      _isRunning = false;
    }
  }

  /// YUV420 → 바이트 배열 변환 (isolate 전달용)
  Uint8List _yuv420ToBytes(CameraImage image) {
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final int yLen = yPlane.bytes.length;
    final int uvLen = uPlane.bytes.length;

    final result = Uint8List(yLen + uvLen * 2);
    result.setRange(0, yLen, yPlane.bytes);
    result.setRange(yLen, yLen + uvLen, uPlane.bytes);
    result.setRange(yLen + uvLen, yLen + uvLen * 2, vPlane.bytes);

    return result;
  }

  /// MobileNet SSD 출력 파싱
  List<DetectionResult> _parseOutputs(
      Map<int, Object> outputs, Size previewSize) {
    final List<List<List<double>>> boxes =
        (outputs[0] as List<dynamic>).map((e) =>
          (e as List<dynamic>).map((row) =>
            (row as List<dynamic>).map((v) => (v as double)).toList()
          ).toList()
        ).toList();
    final List<List<double>> classes =
        (outputs[1] as List<dynamic>).map((e) =>
          (e as List<dynamic>).map((v) => (v as double)).toList()
        ).toList();
    final List<List<double>> scores =
        (outputs[2] as List<dynamic>).map((e) =>
          (e as List<dynamic>).map((v) => (v as double)).toList()
        ).toList();
    final int count = (outputs[3] as List<double>)[0].toInt();

    final List<DetectionResult> detections = [];

    final displayW = previewSize.width;
    final displayH = previewSize.height;

    for (int i = 0; i < count && i < _maxDetections; i++) {
      final score = scores[0][i];
      if (score < _confidenceThreshold) continue;

      final classIdx = classes[0][i].toInt();
      final label = classIdx < _labels.length ? _labels[classIdx] : 'unknown';

      // MobileNet SSD: box = [top, left, bottom, right] (정규화 0~1)
      final top = boxes[0][i][0].clamp(0.0, 1.0);
      final left = boxes[0][i][1].clamp(0.0, 1.0);
      final bottom = boxes[0][i][2].clamp(0.0, 1.0);
      final right = boxes[0][i][3].clamp(0.0, 1.0);

      final rect = Rect.fromLTRB(
        left * displayW,
        top * displayH,
        right * displayW,
        bottom * displayH,
      );

      // 너무 작은 박스 제외
      if (rect.width < 20 || rect.height < 20) continue;

      detections.add(DetectionResult(
        label: label,
        confidence: score,
        rect: rect,
        classIndex: classIdx,
      ));
    }

    return detections;
  }

  void _setModelState(YoloModelState state) {
    _modelState = state;
    if (!_disposed) notifyListeners();
  }

  void _setProgress(double progress) {
    _loadingProgress = progress;
    if (!_disposed) notifyListeners();
  }

  void clearResults() {
    _results = [];
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _interpreter?.close();
    super.dispose();
  }
}

// ──────────────────────────────────────────────────────────
// compute() isolate에서 실행되는 전처리 함수 (순수 함수 필수)
// ──────────────────────────────────────────────────────────

/// YUV420 바이트 → RGB Float32 [1, inputSize, inputSize, 3]
List<List<List<List<double>>>>? _preprocessFrame(Map<String, dynamic> args) {
  try {
    final Uint8List yuvBytes = args['yuv'] as Uint8List;
    final int width = args['width'] as int;
    final int height = args['height'] as int;
    final int inputSize = args['inputSize'] as int;

    // YUV → img.Image 변환 (간소화: Y 채널만으로 그레이스케일 후 RGB 확장)
    final rgbImage = img.Image(width: width, height: height);

    final int yLen = width * height;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int yIndex = y * width + x;
        final int uvIndex = yLen + (y ~/ 2) * (width ~/ 2) + (x ~/ 2);

        final int yVal = yuvBytes[yIndex];
        final int uVal = uvIndex < yuvBytes.length ? yuvBytes[uvIndex] - 128 : 0;
        final int vVal = (uvIndex + yLen ~/ 4) < yuvBytes.length
            ? yuvBytes[uvIndex + yLen ~/ 4] - 128
            : 0;

        // YUV → RGB 변환
        int r = (yVal + 1.370705 * vVal).round().clamp(0, 255);
        int g = (yVal - 0.698001 * vVal - 0.337633 * uVal).round().clamp(0, 255);
        int b = (yVal + 1.732446 * uVal).round().clamp(0, 255);

        rgbImage.setPixelRgb(x, y, r, g, b);
      }
    }

    // 리사이즈 300×300
    final resized = img.copyResize(
      rgbImage,
      width: inputSize,
      height: inputSize,
      interpolation: img.Interpolation.linear,
    );

    // Float32 정규화 [0, 1]
    final input = List.generate(
      1,
      (_) => List.generate(
        inputSize,
        (y) => List.generate(
          inputSize,
          (x) {
            final pixel = resized.getPixel(x, y);
            return [
              pixel.r / 255.0,
              pixel.g / 255.0,
              pixel.b / 255.0,
            ];
          },
        ),
      ),
    );

    return input;
  } catch (e) {
    return null;
  }
}
