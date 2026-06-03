import 'dart:async';
import 'bluetooth_manager.dart';

/// 조이스틱 연속 패킷 전송
///
/// startSequence([2,3,4], delaysMs:[3,24,8]) — 전진
///   2(3ms 홀드) → 3(24ms 홀드, 반복) → 4(8ms 홀드) → 3 → …
///
/// startSequence([9,10,11], delaysMs:[3,24,8]) — 후진
///   9 → 10(반복) → 11 → 10 → …
///
/// 각 전송 후 최소 20ms 딜레이, 실제 딜레이는 delaysMs[i] 중 큰 값 사용
class MotionRepeater {
  final BluetoothManager _btManager;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  int _currentMotion = 0;
  int get currentMotion => _currentMotion;

  // 시퀀스 루프 상태 (async loop 방식)
  List<int>? _sequence;
  List<int>? _delaysMs;

  static const int _minIntervalMs = 20; // 최소 명령 간격

  MotionRepeater(this._btManager);

  // ─────────────────────────────────────────────────────────────
  // 단일 모션 반복 (방향키: 좌/우/회전 등)
  // ─────────────────────────────────────────────────────────────
  void start(int motionIndex, {int intervalMs = 30}) {
    stop(sendReturn: false);
    _isRunning = true;
    _currentMotion = motionIndex;
    _runSingle(motionIndex, intervalMs);
  }

  Future<void> _runSingle(int motionIndex, int intervalMs) async {
    _btManager.sendMotion(motionIndex);
    while (_isRunning && _currentMotion == motionIndex) {
      final delay = intervalMs < _minIntervalMs ? _minIntervalMs : intervalMs;
      await Future.delayed(Duration(milliseconds: delay));
      if (_isRunning && _currentMotion == motionIndex) {
        _btManager.sendMotion(motionIndex);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 시퀀스 전송: [prep, loop, finish] + 각 모션별 홀드 시간
  //
  // 전진 [2,3,4] delaysMs:[3,24,8]
  //   ① motion 2 전송 → max(3, 20)ms 대기
  //   ② motion 3 전송 → max(24, 20)ms 대기  ← 반복
  //   ③ motion 4 전송 → max(8, 20)ms 대기
  //   ② 로 복귀
  //
  // 후진 [9,10,11] delaysMs:[3,24,8]
  //   동일 구조
  // ─────────────────────────────────────────────────────────────
  void startSequence(List<int> sequence, {List<int>? delaysMs}) {
    assert(sequence.length == 3, 'sequence must have 3 elements');
    stop(sendReturn: false);

    _sequence = List<int>.from(sequence);
    _delaysMs = delaysMs != null && delaysMs.length == 3
        ? List<int>.from(delaysMs)
        : [20, 20, 20];
    _isRunning = true;
    _currentMotion = sequence[0];

    _runSequenceLoop();
  }

  Future<void> _runSequenceLoop() async {
    final seq = _sequence!;
    final dels = _delaysMs!;

    // ① prepare (1회)
    _currentMotion = seq[0];
    _btManager.sendMotion(seq[0]);
    await Future.delayed(Duration(
        milliseconds: dels[0] < _minIntervalMs ? _minIntervalMs : dels[0]));

    // ② loop/finish 반복
    while (_isRunning) {
      // loop motion
      _currentMotion = seq[1];
      _btManager.sendMotion(seq[1]);
      await Future.delayed(Duration(
          milliseconds: dels[1] < _minIntervalMs ? _minIntervalMs : dels[1]));
      if (!_isRunning) break;

      // finish motion
      _currentMotion = seq[2];
      _btManager.sendMotion(seq[2]);
      await Future.delayed(Duration(
          milliseconds: dels[2] < _minIntervalMs ? _minIntervalMs : dels[2]));
    }
  }

  // ─────────────────────────────────────────────────────────────
  void stop({bool sendReturn = true, int returnMotion = 1}) {
    _isRunning = false;
    _currentMotion = 0;
    _sequence = null;
    _delaysMs = null;

    if (sendReturn && _btManager.isConnected) {
      _btManager.sendMotion(returnMotion);
    }
  }

  void dispose() {
    stop(sendReturn: false);
  }
}
