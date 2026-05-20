import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import '../models/action_button_config.dart';

/// 음성 인식 상태
enum VoiceState {
  idle,       // 대기
  listening,  // 듣는 중
  processing, // 분석 중
  matched,    // 매칭 성공
  noMatch,    // 매칭 실패
  error,      // 오류
}

/// 음성 명령 서비스
/// 음성 인식 → 버튼 이름 매칭 → 모션 실행
class VoiceCommandService extends ChangeNotifier {
  static final VoiceCommandService _instance = VoiceCommandService._internal();
  factory VoiceCommandService() => _instance;
  VoiceCommandService._internal();

  final SpeechToText _speech = SpeechToText();
  bool _isInitialized = false;

  VoiceState _state = VoiceState.idle;
  VoiceState get state => _state;
  bool get isListening => _state == VoiceState.listening;

  String _recognizedText = '';
  String get recognizedText => _recognizedText;

  String _matchedLabel = '';
  String get matchedLabel => _matchedLabel;

  String _errorMessage = '';
  String get errorMessage => _errorMessage;

  // 매칭된 버튼 결과 콜백
  Function(ActionButtonConfig)? onCommandMatched;

  // ── 초기화 ──────────────────────────────────────────
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    try {
      _isInitialized = await _speech.initialize(
        onError: (error) {
          if (kDebugMode) debugPrint('STT 오류: ${error.errorMsg}');
          _errorMessage = error.errorMsg;
          _setState(VoiceState.error);
        },
        onStatus: (status) {
          if (kDebugMode) debugPrint('STT 상태: $status');
          if (status == 'done' || status == 'notListening') {
            if (_state == VoiceState.listening) {
              _setState(VoiceState.idle);
            }
          }
        },
        debugLogging: kDebugMode,
      );
      if (kDebugMode) debugPrint('STT 초기화: $_isInitialized');
      return _isInitialized;
    } catch (e) {
      _errorMessage = '음성 인식 초기화 실패: $e';
      if (kDebugMode) debugPrint(_errorMessage);
      return false;
    }
  }

  // ── 음성 인식 시작 ───────────────────────────────────
  Future<void> startListening(List<ActionButtonConfig> buttons) async {
    if (_state == VoiceState.listening) {
      await stopListening();
      return;
    }

    if (!_isInitialized) {
      final ok = await initialize();
      if (!ok) {
        _errorMessage = '음성 인식을 사용할 수 없습니다';
        _setState(VoiceState.error);
        return;
      }
    }

    if (!_speech.isAvailable) {
      _errorMessage = '마이크를 사용할 수 없습니다';
      _setState(VoiceState.error);
      return;
    }

    _recognizedText = '';
    _matchedLabel = '';
    _setState(VoiceState.listening);

    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        _recognizedText = result.recognizedWords;
        notifyListeners();

        if (result.finalResult) {
          _processResult(_recognizedText, buttons);
        }
      },
      listenFor: const Duration(seconds: 5),
      pauseFor: const Duration(seconds: 2),
      localeId: 'ko_KR',
      listenOptions: SpeechListenOptions(
        cancelOnError: true,
        partialResults: true,
      ),
    );
  }

  // ── 음성 인식 중지 ───────────────────────────────────
  Future<void> stopListening() async {
    await _speech.stop();
    _setState(VoiceState.idle);
  }

  // ── 결과 처리 및 버튼 매칭 ────────────────────────────
  void _processResult(String text, List<ActionButtonConfig> buttons) {
    if (text.trim().isEmpty) {
      _setState(VoiceState.noMatch);
      return;
    }

    _setState(VoiceState.processing);
    if (kDebugMode) debugPrint('음성 인식 결과: "$text"');

    final matched = _findBestMatch(text, buttons);
    if (matched != null) {
      _matchedLabel = matched.label;
      _setState(VoiceState.matched);
      if (kDebugMode) debugPrint('매칭 성공: ${matched.label}');
      // 콜백 호출 (약간의 딜레이로 UI 피드백 후 실행)
      Future.delayed(const Duration(milliseconds: 300), () {
        onCommandMatched?.call(matched);
        Future.delayed(const Duration(seconds: 1), () {
          if (_state == VoiceState.matched) {
            _setState(VoiceState.idle);
          }
        });
      });
    } else {
      _matchedLabel = '';
      if (kDebugMode) debugPrint('매칭 실패: "$text"');
      _setState(VoiceState.noMatch);
      Future.delayed(const Duration(seconds: 2), () {
        if (_state == VoiceState.noMatch) {
          _setState(VoiceState.idle);
        }
      });
    }
  }

  /// 퍼지 매칭: 음성 인식 텍스트 → 버튼 이름 매칭
  ActionButtonConfig? _findBestMatch(
      String text, List<ActionButtonConfig> buttons) {
    final normalized = _normalize(text);

    // 1순위: 정확히 포함
    for (final btn in buttons) {
      if (btn.label.isEmpty) continue;
      final label = _normalize(btn.label);
      if (normalized.contains(label) || label.contains(normalized)) {
        return btn;
      }
    }

    // 2순위: 단어 단위 부분 매칭
    final words = normalized.split(RegExp(r'\s+'));
    int bestScore = 0;
    ActionButtonConfig? bestMatch;

    for (final btn in buttons) {
      if (btn.label.isEmpty) continue;
      final labelWords = _normalize(btn.label).split(RegExp(r'\s+'));
      int score = 0;
      for (final w in words) {
        if (w.length < 2) continue;
        for (final lw in labelWords) {
          if (lw.contains(w) || w.contains(lw)) {
              score += 2;
            } else if (_editDistance(w, lw) <= 1) {
              score += 1;
            }
        }
      }
      if (score > bestScore) {
        bestScore = score;
        bestMatch = btn;
      }
    }

    // 최소 점수 2 이상이어야 매칭 성공
    return bestScore >= 2 ? bestMatch : null;
  }

  String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^가-힣a-z0-9\s]'), '').trim();

  /// 편집 거리 (Levenshtein)
  int _editDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final dp = List.generate(
      a.length + 1,
      (i) => List.generate(b.length + 1, (j) => j == 0 ? i : (i == 0 ? j : 0)),
    );
    for (int i = 1; i <= a.length; i++) {
      for (int j = 1; j <= b.length; j++) {
        dp[i][j] = a[i - 1] == b[j - 1]
            ? dp[i - 1][j - 1]
            : 1 + [dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]]
                .reduce((x, y) => x < y ? x : y);
      }
    }
    return dp[a.length][b.length];
  }

  void _setState(VoiceState state) {
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }
}
