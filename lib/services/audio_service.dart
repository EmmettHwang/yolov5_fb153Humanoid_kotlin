import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 오디오 서비스
/// - MP3 파일 재생 (로컬 경로 또는 assets)
/// - TTS 텍스트 음성 출력 (한국어·영어 자동 감지)
/// - onSpeechStart / onSpeechDone 콜백 — LED 반짝임 트리거용
class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  // ── audioplayers ────────────────────────────────────────────────
  final AudioPlayer _player = AudioPlayer();
  bool _playerReady = false;

  // ── flutter_tts ─────────────────────────────────────────────────
  final FlutterTts _tts = FlutterTts();
  bool _ttsReady = false;
  bool _initialized = false;

  // ── 발화 콜백 (LED 제어 연동용) ─────────────────────────────────
  /// 오디오(TTS/MP3) 시작 직전 호출
  /// 인자: 총 예상 발화 시간(ms), 0이면 미확정
  void Function(int estimatedDurationMs)? onSpeechStart;

  /// 오디오 완전 종료 후 호출
  void Function()? onSpeechDone;

  // ── 초기화 ────────────────────────────────────────────────────
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await _player.setVolume(1.0);
      _playerReady = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[Audio] audioplayers 초기화 실패: $e');
    }

    try {
      await _tts.setVolume(1.0);
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);
      final langs = await _tts.getLanguages as List?;
      if (langs != null && langs.contains('ko-KR')) {
        await _tts.setLanguage('ko-KR');
      } else {
        await _tts.setLanguage('en-US');
      }

      // TTS 완료 콜백
      _tts.setCompletionHandler(() {
        onSpeechDone?.call();
      });
      _tts.setCancelHandler(() {
        onSpeechDone?.call();
      });
      _ttsReady = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[Audio] TTS 초기화 실패: $e');
    }

    // MP3 완료 콜백
    _player.onPlayerComplete.listen((_) {
      onSpeechDone?.call();
    });
  }

  // ── 버튼용 통합 재생 ────────────────────────────────────────────
  Future<void> playForButton({
    String? mp3FilePath,
    String? ttsText,
  }) async {
    if (!_initialized) await initialize();

    if (mp3FilePath != null && mp3FilePath.trim().isNotEmpty) {
      await _playMp3(mp3FilePath.trim());
      return;
    }
    if (ttsText != null && ttsText.trim().isNotEmpty) {
      await _speakTts(ttsText.trim());
    }
  }

  // ── MP3 재생 ────────────────────────────────────────────────────
  Future<void> _playMp3(String path) async {
    if (!_playerReady) return;
    try {
      await _player.stop();
      onSpeechStart?.call(0); // 길이 미확정
      if (path.startsWith('assets/')) {
        await _player.play(AssetSource(path.replaceFirst('assets/', '')));
      } else {
        final file = File(path);
        if (await file.exists()) {
          await _player.play(DeviceFileSource(path));
        } else {
          if (kDebugMode) debugPrint('[Audio] MP3 파일 없음: $path');
          onSpeechDone?.call();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Audio] MP3 재생 오류: $e');
      onSpeechDone?.call();
    }
  }

  // ── TTS 재생 ────────────────────────────────────────────────────
  Future<void> _speakTts(String text) async {
    if (!_ttsReady) return;
    try {
      await _tts.stop();
      // 글자 수 기반 예상 재생 시간 (한글 기준 ~130ms/자)
      final estimatedMs = (text.length * 130).clamp(300, 10000);
      onSpeechStart?.call(estimatedMs);
      final hasKorean = RegExp(r'[\uAC00-\uD7A3]').hasMatch(text);
      await _tts.setLanguage(hasKorean ? 'ko-KR' : 'en-US');
      await _tts.speak(text);
    } catch (e) {
      if (kDebugMode) debugPrint('[Audio] TTS 오류: $e');
      onSpeechDone?.call();
    }
  }

  // ── 앱 시작 TTS 인사 ────────────────────────────────────────────
  Future<void> speakGreeting({String robotName = 'ROBO'}) async {
    if (!_initialized) await initialize();
    await Future.delayed(const Duration(milliseconds: 500));
    await _speakTts('안녕하세요! $robotName 커맨더 시작합니다.');
  }

  // ── 외부에서 직접 TTS ────────────────────────────────────────────
  Future<void> speak(String text) async {
    if (!_initialized) await initialize();
    await _speakTts(text);
  }

  // ── 정지 ────────────────────────────────────────────────────────
  Future<void> stop() async {
    await _player.stop();
    await _tts.stop();
    onSpeechDone?.call();
  }

  // ── TTS 볼륨/속도 설정 ──────────────────────────────────────────
  Future<void> setTtsRate(double rate) async {
    await _tts.setSpeechRate(rate.clamp(0.1, 1.0));
  }

  Future<void> setTtsVolume(double vol) async {
    await _tts.setVolume(vol.clamp(0.0, 1.0));
  }

  // ── 해제 ────────────────────────────────────────────────────────
  void dispose() {
    _player.dispose();
    _tts.stop();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
/// LED 발화 애니메이터
///
/// AudioService.onSpeechStart/onSpeechDone 에 연결하여
/// 말하는 동안 18번(머리) LED를 따뜻한 황색으로 반짝이게 합니다.
///
/// 사용법:
///   final anim = LedSpeechAnimator(btManager);
///   anim.attach(AudioService());
///   // 이후 AudioService.playForButton() 호출 시 자동으로 LED 깜박임
// ─────────────────────────────────────────────────────────────────────────────
class LedSpeechAnimator {
  final dynamic btManager; // BluetoothManager (순환 import 방지용 dynamic)
  Timer? _timer;
  bool _active = false;

  // 반짝임 주기: 100ms 간격, sin 파형으로 밝기 변화
  static const _intervalMs = 80;
  int _tick = 0;

  LedSpeechAnimator(this.btManager);

  /// AudioService 에 콜백 등록
  void attach(AudioService audio) {
    audio.onSpeechStart = (int estimatedMs) {
      _start(estimatedMs);
    };
    audio.onSpeechDone = () {
      _stop();
    };
  }

  void _start(int estimatedMs) {
    if (_active) return;
    _active = true;
    _tick = 0;

    _timer = Timer.periodic(
      const Duration(milliseconds: _intervalMs),
      (_) => _sendBlink(),
    );

    // 예상 시간 + 500ms 후 강제 종료 (TTS 콜백 미발화 대비)
    if (estimatedMs > 0) {
      Future.delayed(Duration(milliseconds: estimatedMs + 500), () {
        if (_active) _stop();
      });
    }
  }

  void _sendBlink() {
    if (!_active) return;
    _tick++;
    // sin 파형: 0.0~1.0 → brightness 40~255
    final phase = (_tick * _intervalMs * math.pi) / 400.0;
    final norm  = (math.sin(phase) + 1.0) / 2.0; // 0.0~1.0
    final brightness = (40 + (norm * 215).round()).clamp(40, 255);

    // ignore: avoid_dynamic_calls
    btManager.sendLed(
      motorId: 18, // PacketBuilder.motorIdHead
      r: brightness,
      g: brightness ~/ 4,
      b: 0,
    );
  }

  void _stop() {
    _active = false;
    _timer?.cancel();
    _timer = null;
    _tick = 0;

    // LED OFF
    // ignore: avoid_dynamic_calls
    btManager.sendLedOff(motorId: 18);
  }

  void dispose() {
    _stop();
  }
}
