import 'dart:async';
import 'bluetooth_manager.dart';

/// 조이스틱 연속 패킷 전송
///
/// 단일 모션: start(motionIndex) — 단일 모션 번호 반복 전송 (50ms)
/// 시퀀스 모션: startSequence([2,3,4]) — 전진: 2(준비 1회) → 3(반복) → 4(마무리) → 루프
///              startSequence([9,10,11]) — 후진: 9(준비 1회) → 10(반복) → 11(마무리) → 루프
///
/// 시퀀스 타이밍:
///   - prepare(index 0): 한 번만 전송 → stepMs 후 loop 진입
///   - loop  (index 1): repeatCount 회 반복 전송 (intervalMs 간격)
///   - finish(index 2): 한 번만 전송 → stepMs 후 다시 loop 로 복귀
class MotionRepeater {
  final BluetoothManager _btManager;
  Timer? _timer;
  int _currentMotion = 0;
  bool _isRunning = false;

  // 시퀀스 상태
  List<int>? _sequence;
  int _seqPhase = 0; // 0=prepare, 1=loop, 2=finish
  int _loopCount = 0;
  static const int _loopRepeat = 6; // loop 단계 반복 횟수
  static const int _intervalMs = 300; // 각 스텝 간격 (ms)

  bool get isRunning => _isRunning;
  int get currentMotion => _currentMotion;

  MotionRepeater(this._btManager);

  // ─────────────────────────────────────────
  // 단일 모션 반복 전송 (전진/후진 이외 방향)
  // ─────────────────────────────────────────
  void start(int motionIndex, {int intervalMs = 50}) {
    stop(sendReturn: false);
    _sequence = null;
    _currentMotion = motionIndex;
    _isRunning = true;

    _btManager.sendMotion(motionIndex);

    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (_isRunning) {
        _btManager.sendMotion(motionIndex);
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 시퀀스 전송: [prep, loop, finish]
  //   전진: [2, 3, 4]  — 2(준비) → 3반복×N → 4(마무리) → 3반복×N → 4 → …
  //   후진: [9, 10, 11] — 9(준비) → 10반복×N → 11(마무리) → 10반복×N → 11 → …
  // ─────────────────────────────────────────────────────────────────────────
  void startSequence(List<int> sequence) {
    assert(sequence.length == 3, 'sequence must have exactly 3 elements');
    stop(sendReturn: false);

    _sequence = List<int>.from(sequence);
    _seqPhase = 0;   // 0=prepare
    _loopCount = 0;
    _isRunning = true;
    _currentMotion = sequence[0];

    // Phase 0: 준비 동작 1회 즉시 전송
    _btManager.sendMotion(_sequence![0]);

    // 타이머로 나머지 시퀀스 진행
    _timer = Timer.periodic(const Duration(milliseconds: _intervalMs), _sequenceTick);
  }

  void _sequenceTick(Timer timer) {
    if (!_isRunning || _sequence == null) {
      timer.cancel();
      return;
    }

    switch (_seqPhase) {
      case 0: // prepare 전송 완료 → loop 진입
        _seqPhase = 1;
        _loopCount = 0;
        _currentMotion = _sequence![1];
        _btManager.sendMotion(_sequence![1]);

      case 1: // loop 반복
        _loopCount++;
        if (_loopCount >= _loopRepeat) {
          // loop 충분히 반복 → finish 전송
          _seqPhase = 2;
          _loopCount = 0;
          _currentMotion = _sequence![2];
          _btManager.sendMotion(_sequence![2]);
        } else {
          _btManager.sendMotion(_sequence![1]);
        }

      case 2: // finish 전송 완료 → 다시 loop 로 복귀 (준비는 첫 번만)
        _seqPhase = 1;
        _loopCount = 0;
        _currentMotion = _sequence![1];
        _btManager.sendMotion(_sequence![1]);
    }
  }

  // ─────────────────────────────────────────
  // 반복 전송 중단
  // ─────────────────────────────────────────
  void stop({bool sendReturn = true, int returnMotion = 1}) {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    _currentMotion = 0;
    _sequence = null;
    _seqPhase = 0;
    _loopCount = 0;

    if (sendReturn && _btManager.isConnected) {
      _btManager.sendMotion(returnMotion);
    }
  }

  void dispose() {
    stop(sendReturn: false);
  }
}
