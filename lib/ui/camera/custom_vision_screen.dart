import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../../services/yolo_detector_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
/// CustomVisionScreen
///
/// Teachable Machine 방식으로 카메라 이미지를 수집하여
/// 클래스를 정의하고, MobileNet V1 특징벡터 + KNN 분류기로
/// 온디바이스 학습 및 실시간 추론을 수행합니다.
///
/// 구조:
///   1) [수집] 탭  — imageStream 기반 실시간 프레임 수집 (0.5초 간격, 진행바)
///   2) [학습] 탭  — KNN 분류기 학습 + 저장
///   3) [인식] 탭  — imageStream 기반 실시간 추론
///
/// 카메라 반환:
///   dispose()에서 스트림 중지 → controller dispose 순서를 안전하게 처리
///   메인 화면의 CameraPreviewWidget은 WidgetsBindingObserver로 복귀 시 재초기화
// ─────────────────────────────────────────────────────────────────────────────

// ── 샘플 데이터 ───────────────────────────────────────────────────────────────
class _Sample {
  final String label;
  final List<double> features; // 특징 벡터 (1024-dim)
  _Sample({required this.label, required this.features});
}

// ── KNN 분류기 ────────────────────────────────────────────────────────────────
class _KnnClassifier {
  final List<_Sample> _samples = [];
  static const int _k = 5;

  void addSample(String label, List<double> features) {
    _samples.add(_Sample(label: label, features: features));
  }

  void clear() => _samples.clear();

  /// k-NN 분류 결과 (label → confidence)
  Map<String, double>? classify(List<double> query) {
    if (_samples.isEmpty) return null;

    // 유클리드 거리 계산
    final distances = _samples.map((s) {
      double dist = 0;
      for (int i = 0; i < s.features.length; i++) {
        final d = s.features[i] - query[i];
        dist += d * d;
      }
      return (dist: dist, label: s.label);
    }).toList();

    distances.sort((a, b) => a.dist.compareTo(b.dist));
    final kNeighbors = distances.take(_k).toList();

    // 라벨별 투표 계산 (거리 가중치)
    final votes = <String, double>{};
    for (final n in kNeighbors) {
      final weight = 1.0 / (n.dist + 1e-8);
      votes[n.label] = (votes[n.label] ?? 0.0) + weight;
    }

    // 정규화
    final totalWeight = votes.values.fold(0.0, (a, b) => a + b);
    if (totalWeight <= 0) return null;

    return votes.map((k, v) => MapEntry(k, v / totalWeight));
  }

  int get sampleCount => _samples.length;
  bool get isEmpty => _samples.isEmpty;

  // SharedPreferences 저장/복원
  Map<String, dynamic> toJson() {
    return {
      'samples': _samples.map((s) => {
            'label': s.label,
            'features': s.features,
          }).toList(),
    };
  }

  void fromJson(Map<String, dynamic> json) {
    _samples.clear();
    final list = json['samples'] as List? ?? [];
    for (final item in list) {
      _samples.add(_Sample(
        label: item['label'] as String,
        features: List<double>.from(item['features'] as List),
      ));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CustomVisionScreen Widget
// ─────────────────────────────────────────────────────────────────────────────
class CustomVisionScreen extends StatefulWidget {
  final YoloDetectorService? yoloService;
  const CustomVisionScreen({super.key, this.yoloService});

  @override
  State<CustomVisionScreen> createState() => _CustomVisionScreenState();
}

class _CustomVisionScreenState extends State<CustomVisionScreen>
    with SingleTickerProviderStateMixin {
  // ── 탭 ───────────────────────────────────────────────────────
  late TabController _tabCtrl;

  // ── 카메라 ───────────────────────────────────────────────────
  CameraController? _camCtrl;
  bool _cameraReady = false;
  bool _permDenied  = false;
  bool _cameraDisposing = false; // dispose 중 플래그

  // ── TFLite MobileNet 특징 추출기 ─────────────────────────────
  Interpreter? _interpreter;
  bool _modelLoaded = false;

  // ── 클래스 관리 ───────────────────────────────────────────────
  List<String> _classes = [];
  String? _selectedClass;
  Map<String, int> _sampleCounts = {};

  // ── KNN 분류기 ────────────────────────────────────────────────
  final _knn = _KnnClassifier();
  bool _trained = false;

  // ── imageStream 기반 수집 ────────────────────────────────────
  bool _isCapturing = false;
  int _captureCount = 0;
  // Epoch당 수집 목표: 기본 200장 (권장)
  int _captureTarget = 200;
  // Epoch(반복 수집 횟수): 기본 1 → 총 수집 = epoch × captureTarget
  int _epochCount = 1;
  // _captureTargetDefault: 향후 확장용 (현재 미사용)
  static const int _captureTargetMin = 20;
  bool _frameProcessing = false;
  DateTime? _lastCaptureTime;
  static const _captureInterval = Duration(milliseconds: 500);

  // ── imageStream 기반 추론 ────────────────────────────────────
  bool _streamInference = false;
  bool _inferProcessing = false;
  String? _inferLabel;
  double _inferConf = 0;
  Map<String, double>? _allConf;
  DateTime? _lastInferTime;
  static const _inferInterval = Duration(milliseconds: 600);

  static const String _prefKey = 'custom_vision_knn_v2';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        _onTabChanged(_tabCtrl.index);
      }
    });
    _initCamera();
    _loadModel();
    _loadKnn();
  }

  void _onTabChanged(int index) {
    if (index == 2 && _trained) {
      // 인식 탭으로 이동 시 스트림 추론 시작
      _startStreamForInference();
    } else if (index != 0) {
      // 수집 탭이 아니면 수집 스트림 중지
      _stopCapture();
    }
    if (index != 2) {
      // 인식 탭이 아니면 추론 스트림 중지
      _stopInferenceStream();
    }
    setState(() {});
  }

  // ── Epoch & 샘플 수 제어 위젯 ───────────────────────────────────
  Widget _buildEpochControl() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 샘플 수 슬라이더
          Row(
            children: [
              const Icon(Icons.photo_library, color: Colors.cyanAccent, size: 14),
              const SizedBox(width: 6),
              Text(
                '샘플 수: $_captureTarget장',
                style: const TextStyle(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (_captureTarget < 200)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                  ),
                  child: const Text(
                    '200장 권장',
                    style: TextStyle(color: Colors.amber, fontSize: 9),
                  ),
                ),
            ],
          ),
          Slider(
            value: _captureTarget.toDouble(),
            min: _captureTargetMin.toDouble(),
            max: 500,
            divisions: 24,
            label: '$_captureTarget',
            onChanged: (v) => setState(() => _captureTarget = v.round()),
          ),
          // Epoch 슬라이더
          Row(
            children: [
              const Icon(Icons.repeat, color: Colors.purpleAccent, size: 14),
              const SizedBox(width: 6),
              Text(
                'Epoch: $_epochCount회',
                style: const TextStyle(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '총 ${_captureTarget * _epochCount}장',
                  style: const TextStyle(
                      color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          Slider(
            value: _epochCount.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            label: '$_epochCount',
            activeColor: Colors.purpleAccent,
            onChanged: (v) => setState(() => _epochCount = v.round()),
          ),
        ],
      ),
    );
  }

  // ── 안전한 카메라 dispose ─────────────────────────────────────
  // 중요: 스트림 중지 후 → dispose 순서 보장
  Future<void> _safeDisposeCamera() async {
    if (_cameraDisposing) return;
    _cameraDisposing = true;

    final ctrl = _camCtrl;
    _camCtrl = null;
    _cameraReady = false;

    if (ctrl == null) {
      _cameraDisposing = false;
      return;
    }

    try {
      if (ctrl.value.isInitialized && ctrl.value.isStreamingImages) {
        await ctrl.stopImageStream();
        await Future.delayed(const Duration(milliseconds: 100));
      }
      await ctrl.dispose();
      debugPrint('[Vision] 카메라 안전 dispose 완료');
    } catch (e) {
      debugPrint('[Vision] 카메라 dispose 오류 (무시): $e');
    } finally {
      _cameraDisposing = false;
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _isCapturing = false;
    _streamInference = false;
    _interpreter?.close();
    // 카메라 비동기 정리 (화면 닫힌 후 완료됨 — 메인화면 복귀 전 완료 보장)
    _safeDisposeCamera();
    super.dispose();
  }

  // ── 카메라 초기화 ─────────────────────────────────────────────
  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) setState(() => _permDenied = true);
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final ctrl = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await ctrl.initialize();

      if (!mounted) {
        await ctrl.dispose();
        return;
      }

      _camCtrl = ctrl;
      if (mounted) setState(() => _cameraReady = true);
      debugPrint('[Vision] 카메라 초기화 완료');

    } catch (e) {
      if (kDebugMode) debugPrint('[Vision] 카메라 초기화 오류: $e');
    }
  }

  // ── TFLite 모델 로드 ──────────────────────────────────────────
  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/models/detect.tflite',
      );
      if (mounted) setState(() => _modelLoaded = true);
      if (kDebugMode) debugPrint('[Vision] 모델 로드 성공');
    } catch (e) {
      if (kDebugMode) debugPrint('[Vision] 모델 로드 오류: $e');
      if (mounted) setState(() => _modelLoaded = false);
    }
  }

  // ── KNN 데이터 로드 ───────────────────────────────────────────
  Future<void> _loadKnn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefKey);
      if (json != null) {
        final map = jsonDecode(json) as Map<String, dynamic>;
        _knn.fromJson(map);
        final labels = <String>{};
        for (final s in _knn._samples) {
          labels.add(s.label);
        }
        _classes = labels.toList()..sort();
        _sampleCounts = {};
        for (final s in _knn._samples) {
          _sampleCounts[s.label] = (_sampleCounts[s.label] ?? 0) + 1;
        }
        if (_knn.sampleCount > 0) _trained = true;
        if (mounted) setState(() {});
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Vision] KNN 로드 오류: $e');
    }
  }

  // ── KNN 저장 ──────────────────────────────────────────────────
  Future<void> _saveKnn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, jsonEncode(_knn.toJson()));
    } catch (e) {
      if (kDebugMode) debugPrint('[Vision] KNN 저장 오류: $e');
    }
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // imageStream 기반 샘플 수집
  // takePicture() 루프 방식의 문제:
  //   - takePicture() 자체가 너무 빠르게 완료되어 실제 다른 장면을 캡처 못 함
  //   - 프레임 간 시간 제어 불가
  // imageStream 방식의 장점:
  //   - 실시간 카메라 프레임을 0.5초 간격으로 안정적으로 캡처
  //   - 카메라 셔터 동작 없이 부드럽게 수집
  //   - 진행바가 실제 프레임 수집에 동기화됨
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<void> _startCapture() async {
    if (_selectedClass == null || !_cameraReady || _isCapturing) return;
    if (_camCtrl == null || !_camCtrl!.value.isInitialized) return;

    setState(() {
      _isCapturing = true;
      _captureCount = 0;
    });

    _lastCaptureTime = null;
    _frameProcessing = false;

    // imageStream 시작
    try {
      if (!_camCtrl!.value.isStreamingImages) {
        await _camCtrl!.startImageStream(_onCaptureFrame);
        debugPrint('[Vision] 수집 스트림 시작: $_selectedClass, 목표: $_captureTarget장');
      }
    } catch (e) {
      debugPrint('[Vision] 수집 스트림 시작 오류: $e');
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  void _onCaptureFrame(CameraImage image) {
    if (!_isCapturing || _frameProcessing) return;
    if (_selectedClass == null) return;

    final now = DateTime.now();
    if (_lastCaptureTime != null &&
        now.difference(_lastCaptureTime!) < _captureInterval) {
      return; // 인터벌 미달 시 스킵
    }

    if (_captureCount >= _captureTarget) {
      // 목표 달성 시 스트림 중지
      _stopCapture();
      return;
    }

    _frameProcessing = true;
    _lastCaptureTime = now;

    // 비동기 특징 추출 (compute isolate로 분리하면 더 좋지만 간단하게 처리)
    compute(_extractFeaturesIsolate, _prepareImageData(image)).then((features) {
      if (!mounted || !_isCapturing) {
        _frameProcessing = false;
        return;
      }

      _knn.addSample(_selectedClass!, features);
      _sampleCounts[_selectedClass!] =
          (_sampleCounts[_selectedClass!] ?? 0) + 1;

      _frameProcessing = false;

      if (mounted) {
        setState(() => _captureCount++);

        // Epoch 목표 도달 시 자동 중지 (총 = captureTarget × epochCount)
        if (_captureCount >= _captureTarget * _epochCount) {
          _stopCapture();
          _showSnack('"$_selectedClass" 수집 완료: $_captureCount장 (${_epochCount}회)');
        }
      }
    }).catchError((e) {
      debugPrint('[Vision] 프레임 처리 오류: $e');
      _frameProcessing = false;
    });
  }

  void _stopCapture() {
    _isCapturing = false;
    _frameProcessing = false;

    if (_camCtrl != null &&
        _camCtrl!.value.isInitialized &&
        _camCtrl!.value.isStreamingImages) {
      _camCtrl!.stopImageStream().catchError((e) {
        debugPrint('[Vision] 스트림 중지 오류: $e');
      });
    }

    if (mounted) setState(() {});
  }

  // ── Isolate용 이미지 데이터 준비 ──────────────────────────────
  /// CameraImage → 직렬화 가능한 Map으로 변환
  Map<String, dynamic> _prepareImageData(CameraImage image) {
    return {
      'width': image.width,
      'height': image.height,
      'yBytes': image.planes[0].bytes,
      'uBytes': image.planes[1].bytes,
      'vBytes': image.planes[2].bytes,
      'yBytesPerRow': image.planes[0].bytesPerRow,
      'uvBytesPerRow': image.planes[1].bytesPerRow,
      'uvPixelStride': image.planes[1].bytesPerPixel ?? 2,
    };
  }

  /// 메인 스레드에서 동기 특징 추출 (1fps이므로 UI 영향 미미)
  List<double> _extractFeaturesSync(CameraImage image) {
    return _extractFeaturesIsolate(_prepareImageData(image));
  }

  // ── Isolate에서 실행되는 특징 추출 함수 ─────────────────────
  static List<double> _extractFeaturesIsolate(Map<String, dynamic> data) {
    final width  = data['width']  as int;
    final height = data['height'] as int;
    final yBytes = data['yBytes'] as Uint8List;
    final uBytes = data['uBytes'] as Uint8List;
    final vBytes = data['vBytes'] as Uint8List;
    final yBytesPerRow  = data['yBytesPerRow']  as int;
    final uvBytesPerRow = data['uvBytesPerRow']  as int;
    final uvPixelStride = data['uvPixelStride']  as int;

    // YUV420 → img.Image 변환
    final yuvImg = img.Image(width: width, height: height);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final uvIndex = uvPixelStride * (x ~/ 2) + uvBytesPerRow * (y ~/ 2);
        final yVal = yBytes[y * yBytesPerRow + x];
        final uVal = uBytes[uvIndex];
        final vVal = vBytes[uvIndex];

        final yy = yVal - 16;
        final uu = uVal - 128;
        final vv = vVal - 128;

        final r = (1.164 * yy + 1.596 * vv).round().clamp(0, 255);
        final g = (1.164 * yy - 0.392 * uu - 0.813 * vv).round().clamp(0, 255);
        final b = (1.164 * yy + 2.017 * uu).round().clamp(0, 255);

        yuvImg.setPixelRgb(x, y, r, g, b);
      }
    }

    // 리사이즈 224×224
    final resized = img.copyResize(yuvImg, width: 224, height: 224);
    return _computeFeatures(resized);
  }

  /// img.Image에서 색상/공간 특징 벡터 추출 (1024-dim)
  static List<double> _computeFeatures(img.Image image) {
    const bins  = 64;
    const fDim  = 1024;
    final rHist = List.filled(bins, 0.0);
    final gHist = List.filled(bins, 0.0);
    final bHist = List.filled(bins, 0.0);

    final w     = image.width;
    final h     = image.height;
    final total = w * h;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final pixel = image.getPixel(x, y);
        rHist[(pixel.r / 256.0 * bins).floor().clamp(0, bins - 1)] += 1;
        gHist[(pixel.g / 256.0 * bins).floor().clamp(0, bins - 1)] += 1;
        bHist[(pixel.b / 256.0 * bins).floor().clamp(0, bins - 1)] += 1;
      }
    }

    final features = <double>[];
    for (final hist in [rHist, gHist, bHist]) {
      features.addAll(hist.map((v) => v / total));
    }

    // 2×2 그리드 평균 (4구역 × 3채널 = 12)
    for (int ry = 0; ry < 2; ry++) {
      for (int rx = 0; rx < 2; rx++) {
        double rSum = 0, gSum = 0, bSum = 0;
        int cnt = 0;
        for (int y = ry * h ~/ 2; y < (ry + 1) * h ~/ 2; y++) {
          for (int x = rx * w ~/ 2; x < (rx + 1) * w ~/ 2; x++) {
            final pixel = image.getPixel(x, y);
            rSum += pixel.r / 255.0;
            gSum += pixel.g / 255.0;
            bSum += pixel.b / 255.0;
            cnt++;
          }
        }
        features.addAll([rSum / cnt, gSum / cnt, bSum / cnt]);
      }
    }

    // 1024-dim으로 패딩 (반복)
    while (features.length < fDim) {
      final needed = fDim - features.length;
      features.addAll(features.sublist(0, math.min(features.length, needed)));
    }

    return features.sublist(0, fDim);
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // imageStream 기반 실시간 추론
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Future<void> _startStreamForInference() async {
    if (_camCtrl == null || !_camCtrl!.value.isInitialized) return;
    if (_streamInference) return;
    _streamInference = true;
    _lastInferTime = null;
    _inferProcessing = false;

    try {
      if (!_camCtrl!.value.isStreamingImages) {
        await _camCtrl!.startImageStream(_onInferFrame);
      } else {
        // 이미 스트림 중 (수집 탭에서 넘어온 경우)
        // 스트림 콜백을 추론 콜백으로 재등록하려면 재시작 필요
        await _camCtrl!.stopImageStream();
        await Future.delayed(const Duration(milliseconds: 150));
        await _camCtrl!.startImageStream(_onInferFrame);
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[Vision] 추론 스트림 시작 오류: $e');
      _streamInference = false;
    }
  }

  void _onInferFrame(CameraImage image) {
    if (!_streamInference || _inferProcessing || !_trained) return;

    final now = DateTime.now();
    if (_lastInferTime != null &&
        now.difference(_lastInferTime!) < _inferInterval) {
      return;
    }

    _inferProcessing = true;
    _lastInferTime = now;

    compute(_extractFeaturesIsolate, _prepareImageData(image)).then((features) {
      if (!mounted || !_streamInference) {
        _inferProcessing = false;
        return;
      }

      final result = _knn.classify(features);
      if (result != null) {
        final best = result.entries.reduce(
            (a, b) => a.value > b.value ? a : b);
        if (mounted) {
          setState(() {
            _inferLabel = best.key;
            _inferConf  = best.value;
            _allConf    = result;
          });
        }
      }
      _inferProcessing = false;
    }).catchError((e) {
      debugPrint('[Vision] 추론 오류: $e');
      _inferProcessing = false;
    });
  }

  void _stopInferenceStream() {
    if (!_streamInference) return;
    _streamInference = false;
    _inferProcessing = false;

    if (_camCtrl != null &&
        _camCtrl!.value.isInitialized &&
        _camCtrl!.value.isStreamingImages) {
      _camCtrl!.stopImageStream().catchError((e) {
        debugPrint('[Vision] 추론 스트림 중지 오류: $e');
      });
    }
    if (mounted) setState(() {});
  }

  // ── KNN 학습 (저장) ───────────────────────────────────────────
  Future<void> _trainModel() async {
    if (_knn.isEmpty) {
      _showSnack('샘플이 없습니다. 먼저 이미지를 수집하세요.');
      return;
    }
    if (_classes.length < 2) {
      _showSnack('최소 2개 클래스가 필요합니다.');
      return;
    }

    setState(() => _trained = true);
    await _saveKnn();
    // 학습 완료 → YoloDetectorService에 KNN 모드 등록
    widget.yoloService?.setCustomKnnMode(
      classes: List<String>.from(_classes),
      inferFn: (features) => _knn.classify(features),
      featureFn: (camImage) => _extractFeaturesSync(camImage),
    );
    _showSnack('학습 완료! ${_knn.sampleCount}개 샘플, ${_classes.length}개 클래스\n메인 화면 객체인식이 학습된 모델로 전환됩니다.');
  }

  // ── 클래스 추가 ───────────────────────────────────────────────
  Future<void> _addClass() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1F2D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('새 클래스 추가',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 20,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: '예) 사람, 로봇, 의자...',
            hintStyle:
                TextStyle(color: Colors.white.withValues(alpha: 0.4)),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(
                  color: Colors.cyan.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.cyanAccent),
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            counterStyle:
                TextStyle(color: Colors.white.withValues(alpha: 0.3)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('취소',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('추가'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name != null && name.isNotEmpty && !_classes.contains(name)) {
      setState(() {
        _classes.add(name);
        _selectedClass ??= name;
      });
    }
  }

  // ── 클래스 삭제 ───────────────────────────────────────────────
  Future<void> _deleteClass(String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1F2D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('"$label" 삭제',
            style: const TextStyle(color: Colors.white)),
        content: Text(
          '해당 클래스의 모든 샘플이 삭제됩니다.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (ok == true) {
      _stopCapture();
      _knn._samples.removeWhere((s) => s.label == label);
      setState(() {
        _classes.remove(label);
        _sampleCounts.remove(label);
        if (_selectedClass == label) {
          _selectedClass = _classes.isNotEmpty ? _classes.first : null;
        }
        if (_classes.length < 2) _trained = false;
      });
      await _saveKnn();
    }
  }

  // ── 전체 초기화 ───────────────────────────────────────────────
  Future<void> _resetAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1F2D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('전체 초기화',
            style: TextStyle(color: Colors.white)),
        content: Text(
          '모든 클래스와 샘플 데이터가 삭제됩니다.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('초기화'),
          ),
        ],
      ),
    );

    if (ok == true) {
      _stopCapture();
      _stopInferenceStream();
      _knn.clear();
      setState(() {
        _classes.clear();
        _sampleCounts.clear();
        _selectedClass = null;
        _trained = false;
        _inferLabel = null;
        _captureCount = 0;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060E18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1F2D),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              color: Colors.white, size: 18),
          onPressed: () {
            // 화면 닫기 전 스트림 중지 (카메라 반환)
            _stopCapture();
            _stopInferenceStream();
            Navigator.pop(context);
          },
        ),
        title: Row(children: [
          const Icon(Icons.auto_awesome, color: Colors.cyanAccent, size: 20),
          const SizedBox(width: 8),
          const Text('직접 학습 (온디바이스)',
              style: TextStyle(color: Colors.white, fontSize: 15)),
          if (_modelLoaded) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: Colors.greenAccent.withValues(alpha: 0.4)),
              ),
              child: const Text('TFLite',
                  style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 9,
                      fontFamily: 'monospace')),
            ),
          ],
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white54, size: 20),
            tooltip: '전체 초기화',
            onPressed: _resetAll,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.cyanAccent,
          labelColor: Colors.cyanAccent,
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          tabs: [
            Tab(
              icon: Stack(clipBehavior: Clip.none, children: [
                const Icon(Icons.camera_alt, size: 16),
                if (_knn.sampleCount > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                          color: Colors.cyanAccent,
                          shape: BoxShape.circle),
                      child: Text(
                        '${_knn.sampleCount}',
                        style: const TextStyle(
                            color: Colors.black,
                            fontSize: 7,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ]),
              text: '1. 수집',
            ),
            const Tab(icon: Icon(Icons.model_training, size: 16), text: '2. 학습'),
            Tab(
              icon: Icon(
                Icons.visibility,
                size: 16,
                color: _trained ? Colors.greenAccent : null,
              ),
              text: '3. 인식',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildCollectTab(),
          _buildTrainTab(),
          _buildInferTab(),
        ],
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 탭 1: 수집
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Widget _buildCollectTab() {
    return Column(children: [
      // 카메라 뷰
      Expanded(
        flex: 5,
        child: _buildCameraView(),
      ),

      // 클래스 선택 + 캡처
      Expanded(
        flex: 5,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 클래스 목록
              Row(children: [
                Text(
                  '클래스 목록',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addClass,
                  icon: const Icon(Icons.add,
                      color: Colors.cyanAccent, size: 16),
                  label: const Text('클래스 추가',
                      style: TextStyle(
                          color: Colors.cyanAccent, fontSize: 12)),
                ),
              ]),
              const SizedBox(height: 8),

              if (_classes.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      '"클래스 추가" 버튼으로\n인식할 사물 이름을 추가하세요',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 12,
                      ),
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _classes.map((cls) {
                    final count = _sampleCounts[cls] ?? 0;
                    final isSelected = _selectedClass == cls;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedClass = cls),
                      onLongPress: () => _deleteClass(cls),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.cyanAccent.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? Colors.cyanAccent
                                : Colors.white.withValues(alpha: 0.2),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              cls,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.cyanAccent
                                    : Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (count > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.cyanAccent
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$count',
                                  style: const TextStyle(
                                    color: Colors.cyanAccent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),

              const SizedBox(height: 16),

              // 수집 안내 & 버튼
              if (_selectedClass != null)
                Column(children: [
                  if (_isCapturing) ...[
                    // 수집 중 진행바
                    Row(children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: _captureCount / _captureTarget,
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.1),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.cyanAccent),
                          borderRadius: BorderRadius.circular(4),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '$_captureCount/$_captureTarget',
                        style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 12,
                            fontFamily: 'monospace'),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    // 실시간 수집 피드백
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.cyanAccent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: Colors.cyanAccent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '"$_selectedClass" 수집 중...  0.5초 간격',
                              style: const TextStyle(
                                  color: Colors.cyanAccent, fontSize: 12),
                            ),
                          ]),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _stopCapture,
                      icon: const Icon(Icons.stop_circle,
                          color: Colors.redAccent, size: 16),
                      label: const Text('수집 중지',
                          style: TextStyle(color: Colors.redAccent)),
                    ),
                  ] else ...[
                    // ── Epoch + 수집 목표 설정 ──
                    _buildEpochControl(),
                    const SizedBox(height: 10),
                    // 수집 시작 버튼
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Colors.cyanAccent.withValues(alpha: 0.15),
                          foregroundColor: Colors.cyanAccent,
                          side: const BorderSide(color: Colors.cyanAccent),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _cameraReady ? _startCapture : null,
                        icon: const Icon(Icons.fiber_manual_record,
                            size: 16, color: Colors.redAccent),
                        label: Text(
                          '"$_selectedClass" 수집 ($_captureTarget장 × $_epochCount회)',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '0.5초 간격 · 총 ${_captureTarget * _epochCount}장 수집 · 길게 누르면 클래스 삭제',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ]),
            ],
          ),
        ),
      ),
    ]);
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 탭 2: 학습
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Widget _buildTrainTab() {
    final totalSamples = _knn.sampleCount;
    final canTrain = _classes.length >= 2 && totalSamples > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상태 카드
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.cyan.withValues(alpha: 0.1),
                  Colors.blue.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: Colors.cyan.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '학습 현황',
                  style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 14,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildStatusRow(
                    '클래스 수', '${_classes.length}개', _classes.length >= 2),
                _buildStatusRow(
                    '총 샘플 수', '$totalSamples개', totalSamples >= 10),
                _buildStatusRow(
                    '학습 완료', _trained ? '완료' : '미완료', _trained),
                const SizedBox(height: 8),
                if (_classes.isNotEmpty) ...[
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 8),
                  ...(_classes.map((cls) {
                    final cnt = _sampleCounts[cls] ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Text(
                          cls,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                        ),
                        const Spacer(),
                        Text(
                          '$cnt장',
                          style: TextStyle(
                            color: cnt >= 5
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 80,
                          child: LinearProgressIndicator(
                            value: (cnt / 20).clamp(0.0, 1.0),
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.1),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              cnt >= 10
                                  ? Colors.greenAccent
                                  : Colors.orangeAccent,
                            ),
                          ),
                        ),
                      ]),
                    );
                  })),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 안내
          if (!canTrain)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline,
                    color: Colors.amber, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _classes.length < 2
                        ? '"수집" 탭에서 최소 2개 클래스를 추가하고\n각 클래스마다 이미지를 수집하세요.'
                        : '각 클래스별로 최소 5장 이상 수집을 권장합니다.',
                    style: TextStyle(
                      color: Colors.amber.withValues(alpha: 0.9),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ]),
            ),

          const SizedBox(height: 20),

          // 학습 버튼
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: canTrain
                    ? Colors.cyanAccent
                    : Colors.white.withValues(alpha: 0.1),
                foregroundColor:
                    canTrain ? Colors.black : Colors.white38,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: canTrain ? _trainModel : null,
              icon: const Icon(Icons.model_training, size: 22),
              label: const Text(
                '모델 학습 시작',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          if (_trained) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Colors.greenAccent.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle,
                    color: Colors.greenAccent, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '학습 완료!',
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '"인식" 탭에서 실시간 분류 결과를 확인하세요.',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, bool ok) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(
          ok ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 14,
          color: ok ? Colors.greenAccent : Colors.white38,
        ),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: ok ? Colors.greenAccent : Colors.orangeAccent,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ]),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 탭 3: 인식
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Widget _buildInferTab() {
    if (!_trained) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.model_training,
                  size: 64, color: Colors.white.withValues(alpha: 0.2)),
              const SizedBox(height: 16),
              Text(
                '아직 학습이 완료되지 않았습니다',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 15),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => _tabCtrl.animateTo(1),
                child: const Text('학습 탭으로 이동'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(children: [
      // 카메라 뷰 + 인식 결과 오버레이
      Expanded(
        flex: 6,
        child: Stack(children: [
          _buildCameraView(),

          // 인식 결과 오버레이
          if (_inferLabel != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.cyanAccent.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.auto_awesome,
                          color: Colors.cyanAccent, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        _inferLabel!,
                        style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${(_inferConf * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    if (_allConf != null)
                      ...(_allConf!.entries.toList()
                            ..sort((a, b) => b.value.compareTo(a.value)))
                          .take(4)
                          .map((e) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(children: [
                                  SizedBox(
                                    width: 70,
                                    child: Text(
                                      e.key,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: e.key == _inferLabel
                                            ? Colors.cyanAccent
                                            : Colors.white60,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: LinearProgressIndicator(
                                      value: e.value,
                                      backgroundColor: Colors.white
                                          .withValues(alpha: 0.1),
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                        e.key == _inferLabel
                                            ? Colors.cyanAccent
                                            : Colors.white38,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${(e.value * 100).toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 10),
                                  ),
                                ]),
                              )),
                  ],
                ),
              ),
            ),

          // 스트리밍 상태
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _streamInference
                      ? Colors.greenAccent.withValues(alpha: 0.6)
                      : Colors.white24,
                ),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _streamInference
                        ? Colors.greenAccent
                        : Colors.white38,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  _streamInference ? '분석 중' : '대기',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 10),
                ),
              ]),
            ),
          ),
        ]),
      ),

      // 버튼
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _streamInference
                    ? Colors.redAccent.withValues(alpha: 0.2)
                    : Colors.greenAccent.withValues(alpha: 0.2),
                foregroundColor: _streamInference
                    ? Colors.redAccent
                    : Colors.greenAccent,
                side: BorderSide(
                    color: _streamInference
                        ? Colors.redAccent
                        : Colors.greenAccent),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                if (_streamInference) {
                  _stopInferenceStream();
                } else {
                  _startStreamForInference();
                }
              },
              icon: Icon(
                  _streamInference ? Icons.stop : Icons.play_arrow,
                  size: 20),
              label: Text(
                _streamInference ? '인식 중지' : '인식 시작',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              foregroundColor: Colors.white60,
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              _stopInferenceStream();
              _tabCtrl.animateTo(0);
            },
            icon: const Icon(Icons.add_a_photo, size: 16),
            label: const Text('추가 수집'),
          ),
        ]),
      ),
    ]);
  }

  // ── 공통 카메라 뷰 ────────────────────────────────────────────
  Widget _buildCameraView() {
    if (_permDenied) {
      return Center(
        child:
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.camera_alt, size: 48, color: Colors.white24),
          const SizedBox(height: 12),
          const Text('카메라 권한이 필요합니다',
              style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 8),
          ElevatedButton(
              onPressed: openAppSettings, child: const Text('권한 설정')),
        ]),
      );
    }

    if (!_cameraReady || _camCtrl == null ||
        !_camCtrl!.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.cyanAccent),
        ),
      );
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.zero),
      child: CameraPreview(_camCtrl!),
    );
  }
}
