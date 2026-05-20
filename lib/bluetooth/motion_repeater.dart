import 'dart:async';
import 'bluetooth_manager.dart';

/// 조이스틱 연속 패킷 전송 (50ms 간격)
class MotionRepeater {
  final BluetoothManager _btManager;
  Timer? _timer;
  int _currentMotion = 0;
  bool _isRunning = false;

  bool get isRunning => _isRunning;
  int get currentMotion => _currentMotion;

  MotionRepeater(this._btManager);

  /// 반복 전송 시작
  void start(int motionIndex, {int intervalMs = 50}) {
    stop(sendReturn: false);
    _currentMotion = motionIndex;
    _isRunning = true;

    // 즉시 한 번 전송
    _btManager.sendMotion(motionIndex);

    // 이후 intervalMs 간격으로 반복
    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (_isRunning) {
        _btManager.sendMotion(motionIndex);
      }
    });
  }

  /// 반복 전송 중단
  void stop({bool sendReturn = true, int returnMotion = 1}) {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    _currentMotion = 0;

    if (sendReturn && _btManager.isConnected) {
      _btManager.sendMotion(returnMotion);
    }
  }

  void dispose() {
    stop(sendReturn: false);
  }
}
