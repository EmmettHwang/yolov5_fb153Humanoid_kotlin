import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import '../ui/camera/camera_preview_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EfficientDet-Lite0 TFLite 사물인식 서비스
//
// 모델: EfficientDet-Lite0 (Google MediaPipe 공식)
//   - 파일: assets/models/efficientdet_lite0.tflite (13.2 MB)
//   - 입력: [1, 320, 320, 3]  float32  RGB  0~255
//   - 출력:
//       [0] boxes   [1, 25, 4]   — [top, left, bottom, right] 정규화 0~1
//       [1] classes [1, 25]      — 클래스 인덱스 (float)
//       [2] scores  [1, 25]      — 신뢰도 0~1
//       [3] count   [1]          — 유효 탐지 개수
//   - 레이블: COCO 80 클래스 (assets/models/labels.txt)
// ─────────────────────────────────────────────────────────────────────────────

/// 모델 로딩 상태
enum YoloModelState { idle, loading, ready, error }

class YoloDetectorService extends ChangeNotifier {
  // ── 경로 ──────────────────────────────────────────────────────────────────
  static const String _modelAsset  = 'assets/models/efficientdet_lite0.tflite';
  static const String _labelsAsset = 'assets/models/labels.txt';

  // ── 모델 파라미터 ─────────────────────────────────────────────────────────
  static const int    _inputSize   = 320;   // EfficientDet-Lite0 입력 크기
  static const int    _maxDetect   = 25;    // 모델 최대 탐지 수
  static const double _threshold   = 0.40; // 신뢰도 임계값

  // ── 상태 ─────────────────────────────────────────────────────────────────
  Interpreter?       _interpreter;
  List<String>       _labels       = [];

  YoloModelState     _state        = YoloModelState.idle;
  YoloModelState get modelState    => _state;

  double             _progress     = 0.0;
  double get        loadingProgress => _progress;

  String             _error        = '';
  String get        errorMessage   => _error;

  List<DetectionResult> _results   = [];
  List<DetectionResult> get results => List.unmodifiable(_results);

  int                _inferenceMs  = 0;
  int get           inferenceMs    => _inferenceMs;

  bool               _running      = false;
  bool               _disposed     = false;

  // 프레임 throttle — 최대 8fps
  DateTime?          _lastFrame;
  static const int   _frameGapMs  = 125;

  // ── 초기화 ───────────────────────────────────────────────────────────────
  Future<void> initialize() async {
    if (_state == YoloModelState.loading || _state == YoloModelState.ready) return;

    _setState(YoloModelState.loading);
    _setProgress(0.0);

    try {
      // 1) 레이블 로딩
      _setProgress(0.1);
      final raw = await rootBundle.loadString(_labelsAsset);
      _labels = raw.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      debugPrint('[OD] 레이블 ${_labels.length}개 로딩 완료');
      _setProgress(0.35);

      // 2) 모델 로딩 (멀티스레드 옵션)
      final opts = InterpreterOptions()..threads = 2;
      _interpreter = await Interpreter.fromAsset(_modelAsset, options: opts);
      _setProgress(0.85);
      debugPrint('[OD] 입력 shape : ${_interpreter!.getInputTensor(0).shape}');
      debugPrint('[OD] 출력 텐서 수: ${_interpreter!.getOutputTensors().length}');

      // 3) 워밍업 — 첫 추론은 항상 느리므로 더미로 미리 실행
      _setProgress(0.92);
      await _warmup();
      _setProgress(1.0);

      _setState(YoloModelState.ready);
      debugPrint('[OD] ✅ EfficientDet-Lite0 준비 완료');
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

  // ── 출력 버퍼 ────────────────────────────────────────────────────────────
  // EfficientDet-Lite0 출력:
  //   index 0 → boxes   Float32List [1][25][4]
  //   index 1 → classes Float32List [1][25]
  //   index 2 → scores  Float32List [1][25]
  //   index 3 → count   Float32List [1]
  Map<int, Object> _buildOutputBuffers() => {
        0: [List.generate(_maxDetect, (_) => List<double>.filled(4, 0.0))],
        1: [List<double>.filled(_maxDetect, 0.0)],
        2: [List<double>.filled(_maxDetect, 0.0)],
        3: [0.0],
      };

  List<List<List<List<double>>>> _buildDummyInput() =>
      List.generate(1, (_) =>
        List.generate(_inputSize, (_) =>
          List.generate(_inputSize, (_) =>
            List<double>.filled(3, 0.0))));

  // ── 프레임 처리 ──────────────────────────────────────────────────────────
  Future<void> processFrame(CameraImage frame, Size displaySize) async {
    if (_interpreter == null || _state != YoloModelState.ready) return;
    if (_running) return;

    // throttle
    final now = DateTime.now();
    if (_lastFrame != null &&
        now.difference(_lastFrame!).inMilliseconds < _frameGapMs) {
      return;
    }
    _lastFrame = now;

    _running = true;
    final sw = Stopwatch()..start();

    try {
      // 1) YUV420 → RGB → resize 320×320 (isolate)
      final input = await compute(_yuv420ToInput, {
        'y'      : Uint8List.fromList(frame.planes[0].bytes),
        'u'      : Uint8List.fromList(frame.planes[1].bytes),
        'v'      : Uint8List.fromList(frame.planes[2].bytes),
        'width'  : frame.width,
        'height' : frame.height,
        'rowStrideY' : frame.planes[0].bytesPerRow,
        'rowStrideUV': frame.planes[1].bytesPerRow,
        'pixStrideUV': frame.planes[1].bytesPerPixel ?? 1,
        'inputSize'  : _inputSize,
      });

      if (input == null) { _running = false; return; }

      // 2) 추론 (메인 스레드에서 실행 — tflite_flutter 권장 방식)
      final out = _buildOutputBuffers();
      _interpreter!.runForMultipleInputs([input], out);

      // 3) 파싱
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

  // ── 결과 파싱 ────────────────────────────────────────────────────────────
  List<DetectionResult> _parseOutput(Map<int, Object> out, Size displaySize) {
    // out[0]: [[ [top,left,bottom,right], ... ]]  → [0][i][0..3]
    // out[1]: [[ classIdx, ... ]]                 → [0][i]
    // out[2]: [[ score, ... ]]                    → [0][i]
    // out[3]: [ count ]                           → scalar

    final rawBoxes   = (out[0] as List)[0] as List;   // List of [top,left,bottom,right]
    final rawClasses = (out[1] as List)[0] as List;   // List of classIdx (float)
    final rawScores  = (out[2] as List)[0] as List;   // List of score
    final count      = ((out[3] as List)[0] as double).toInt().clamp(0, _maxDetect);

    final results = <DetectionResult>[];
    final W = displaySize.width;
    final H = displaySize.height;

    for (int i = 0; i < count; i++) {
      final score = (rawScores[i] as double);
      if (score < _threshold) continue;

      final box = rawBoxes[i] as List;
      final top    = (box[0] as double).clamp(0.0, 1.0);
      final left   = (box[1] as double).clamp(0.0, 1.0);
      final bottom = (box[2] as double).clamp(0.0, 1.0);
      final right  = (box[3] as double).clamp(0.0, 1.0);

      final rect = Rect.fromLTRB(left * W, top * H, right * W, bottom * H);
      if (rect.width < 15 || rect.height < 15) continue;

      final classIdx = (rawClasses[i] as double).toInt();
      final label = classIdx < _labels.length ? _labels[classIdx] : 'object';

      results.add(DetectionResult(
        label: label,
        confidence: score,
        rect: rect,
        classIndex: classIdx,
      ));
    }
    return results;
  }

  // ── 내부 유틸 ────────────────────────────────────────────────────────────
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

  @override
  void dispose() {
    _disposed = true;
    _interpreter?.close();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// compute() isolate 함수 — YUV420 → Float32 입력 텐서 [1, 320, 320, 3]
// ─────────────────────────────────────────────────────────────────────────────
List<List<List<List<double>>>>? _yuv420ToInput(Map<String, dynamic> args) {
  try {
    final Uint8List y           = args['y']           as Uint8List;
    final Uint8List u           = args['u']           as Uint8List;
    final Uint8List v           = args['v']           as Uint8List;
    final int       width       = args['width']       as int;
    final int       height      = args['height']      as int;
    final int       rowStrideY  = args['rowStrideY']  as int;
    final int       rowStrideUV = args['rowStrideUV'] as int;
    final int       pixStrideUV = args['pixStrideUV'] as int;
    final int       inputSize   = args['inputSize']   as int;

    // YUV420 → img.Image (RGB)
    final rgb = img.Image(width: width, height: height);

    for (int row = 0; row < height; row++) {
      for (int col = 0; col < width; col++) {
        final yIdx  = row * rowStrideY + col;
        final uvRow = row >> 1;
        final uvCol = col >> 1;
        final uvIdx = uvRow * rowStrideUV + uvCol * pixStrideUV;

        final yv = yIdx < y.length ? y[yIdx] : 0;
        final uv = uvIdx < u.length ? u[uvIdx] - 128 : 0;
        final vv = uvIdx < v.length ? v[uvIdx] - 128 : 0;

        // BT.601 YUV → RGB
        final r = (yv + 1.370705 * vv).round().clamp(0, 255);
        final g = (yv - 0.698001 * vv - 0.337633 * uv).round().clamp(0, 255);
        final b = (yv + 1.732446 * uv).round().clamp(0, 255);

        rgb.setPixelRgb(col, row, r, g, b);
      }
    }

    // 320×320으로 리사이즈
    final resized = img.copyResize(
      rgb,
      width: inputSize,
      height: inputSize,
      interpolation: img.Interpolation.linear,
    );

    // Float32 텐서 [1, 320, 320, 3]  — EfficientDet 입력은 0~255 float
    final tensor = List.generate(
      1,
      (_) => List.generate(inputSize, (row) =>
        List.generate(inputSize, (col) {
          final px = resized.getPixel(col, row);
          return [px.r.toDouble(), px.g.toDouble(), px.b.toDouble()];
        }),
      ),
    );

    return tensor;
  } catch (e) {
    return null;
  }
}
