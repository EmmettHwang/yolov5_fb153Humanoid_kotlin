import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 오디오 서비스
/// - MP3 파일 재생 (로컬 경로 또는 assets)
/// - TTS 텍스트 음성 출력 (한국어·영어 자동 감지)
/// - 우선순위: MP3 파일이 있으면 MP3, 없으면 TTS 텍스트
class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  // ── audioplayers ──────────────────────────────────────────────────────────
  final AudioPlayer _player = AudioPlayer();
  bool _playerReady = false;

  // ── flutter_tts ───────────────────────────────────────────────────────────
  final FlutterTts _tts = FlutterTts();
  bool _ttsReady = false;

  bool _initialized = false;

  // ── 초기화 ────────────────────────────────────────────────────────────────
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // audioplayers 초기화
    try {
      await _player.setVolume(1.0);
      _playerReady = true;
      if (kDebugMode) debugPrint('[Audio] audioplayers 준비 완료');
    } catch (e) {
      if (kDebugMode) debugPrint('[Audio] audioplayers 초기화 실패: $e');
    }

    // TTS 초기화
    try {
      await _tts.setVolume(1.0);
      await _tts.setSpeechRate(0.5);   // 0.0~1.0 (0.5 = 자연스러운 속도)
      await _tts.setPitch(1.0);
      // 한국어 우선, 없으면 영어
      final langs = await _tts.getLanguages as List?;
      if (langs != null && langs.contains('ko-KR')) {
        await _tts.setLanguage('ko-KR');
      } else {
        await _tts.setLanguage('en-US');
      }
      _ttsReady = true;
      if (kDebugMode) debugPrint('[Audio] TTS 준비 완료');
    } catch (e) {
      if (kDebugMode) debugPrint('[Audio] TTS 초기화 실패: $e');
    }
  }

  // ── 버튼용 통합 재생 ─────────────────────────────────────────────────────
  /// mp3FilePath 또는 ttsText 중 하나를 재생
  /// 우선순위: mp3FilePath > ttsText
  Future<void> playForButton({
    String? mp3FilePath,
    String? ttsText,
  }) async {
    if (!_initialized) await initialize();

    // 1) MP3 파일 경로가 있으면 MP3 재생
    if (mp3FilePath != null && mp3FilePath.trim().isNotEmpty) {
      await _playMp3(mp3FilePath.trim());
      return;
    }

    // 2) TTS 텍스트가 있으면 TTS 재생
    if (ttsText != null && ttsText.trim().isNotEmpty) {
      await _speakTts(ttsText.trim());
    }
  }

  // ── MP3 재생 ──────────────────────────────────────────────────────────────
  Future<void> _playMp3(String path) async {
    if (!_playerReady) return;
    try {
      await _player.stop();

      // assets 경로 판단 (assets/ 로 시작하면 AssetSource)
      if (path.startsWith('assets/')) {
        final assetPath = path.replaceFirst('assets/', '');
        await _player.play(AssetSource(assetPath));
      } else {
        // 절대경로 또는 상대경로 → DeviceFileSource
        final file = File(path);
        if (await file.exists()) {
          await _player.play(DeviceFileSource(path));
        } else {
          if (kDebugMode) debugPrint('[Audio] MP3 파일 없음: $path');
        }
      }
      if (kDebugMode) debugPrint('[Audio] MP3 재생: $path');
    } catch (e) {
      if (kDebugMode) debugPrint('[Audio] MP3 재생 오류: $e');
    }
  }

  // ── TTS 재생 ──────────────────────────────────────────────────────────────
  Future<void> _speakTts(String text) async {
    if (!_ttsReady) return;
    try {
      await _tts.stop();

      // 언어 자동 감지 (한글 포함 여부로 판단)
      final hasKorean = RegExp(r'[\uAC00-\uD7A3]').hasMatch(text);
      await _tts.setLanguage(hasKorean ? 'ko-KR' : 'en-US');

      await _tts.speak(text);
      if (kDebugMode) debugPrint('[Audio] TTS 발화: "$text"');
    } catch (e) {
      if (kDebugMode) debugPrint('[Audio] TTS 오류: $e');
    }
  }

  // ── 앱 시작 TTS 인사 (로봇 이름 포함) ────────────────────────────────────
  Future<void> speakGreeting({String robotName = 'ROBO'}) async {
    if (!_initialized) await initialize();
    await Future.delayed(const Duration(milliseconds: 500));
    await _speakTts('안녕하세요! $robotName 커맨더 시작합니다.');
  }

  // ── 외부에서 직접 TTS ─────────────────────────────────────────────────────
  Future<void> speak(String text) async {
    if (!_initialized) await initialize();
    await _speakTts(text);
  }

  // ── 정지 ──────────────────────────────────────────────────────────────────
  Future<void> stop() async {
    await _player.stop();
    await _tts.stop();
  }

  // ── TTS 볼륨/속도 설정 ────────────────────────────────────────────────────
  Future<void> setTtsRate(double rate) async {
    await _tts.setSpeechRate(rate.clamp(0.1, 1.0));
  }

  Future<void> setTtsVolume(double vol) async {
    await _tts.setVolume(vol.clamp(0.0, 1.0));
  }

  // ── 해제 ──────────────────────────────────────────────────────────────────
  void dispose() {
    _player.dispose();
    _tts.stop();
  }
}
