import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter/services.dart';
import 'packet_builder.dart';

/// Bluetooth 연결 상태 (Flutter의 ConnectionState와 충돌 방지를 위해 BtConnectionState 사용)
enum BtConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

/// Bluetooth 기기 정보
class BluetoothDeviceInfo {
  final String name;
  final String address;

  const BluetoothDeviceInfo({required this.name, required this.address});

  @override
  String toString() => '$name ($address)';
}

/// fb153 로봇 Bluetooth Classic 2.0 (SPP) 관리자
class BluetoothManager extends ChangeNotifier {
  static final BluetoothManager _instance = BluetoothManager._internal();
  factory BluetoothManager() => _instance;
  BluetoothManager._internal();

  // 상태
  BtConnectionState _connectionState = BtConnectionState.disconnected;
  BtConnectionState get connectionState => _connectionState;
  bool get isConnected => _connectionState == BtConnectionState.connected;

  // 연결된 기기
  BluetoothDeviceInfo? _connectedDevice;
  BluetoothDeviceInfo? get connectedDevice => _connectedDevice;

  // 스캔된 기기 목록
  final List<BluetoothDeviceInfo> _discoveredDevices = [];
  List<BluetoothDeviceInfo> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices);

  // 블루투스 연결
  BluetoothConnection? _connection;

  // 오류 메시지
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  // 통계
  int _packetsSent = 0;
  int get packetsSent => _packetsSent;
  int _latencyMs = 0;
  int get latencyMs => _latencyMs;

  // fb153 기기 이름 필터
  static const String _deviceFilter = 'fb153';

  void _setState(BtConnectionState state) {
    _connectionState = state;
    notifyListeners();
  }

  /// Bluetooth 활성화 확인
  Future<bool> isBluetoothEnabled() async {
    try {
      final isEnabled =
          await FlutterBluetoothSerial.instance.isEnabled ?? false;
      return isEnabled;
    } catch (e) {
      return false;
    }
  }

  /// Bluetooth 활성화 요청
  Future<bool> requestEnable() async {
    try {
      final result =
          await FlutterBluetoothSerial.instance.requestEnable() ?? false;
      return result;
    } catch (e) {
      return false;
    }
  }

  /// 기기 스캔 시작 (페어링된 기기에서 fb153 필터링)
  Future<void> startScan({String filterPrefix = _deviceFilter}) async {
    _discoveredDevices.clear();
    _setState(BtConnectionState.scanning);

    try {
      // 페어링된 기기 목록 조회
      final bondedDevices =
          await FlutterBluetoothSerial.instance.getBondedDevices();

      for (final device in bondedDevices) {
        final name = device.name ?? '';
        if (filterPrefix.isEmpty ||
            name.toLowerCase().contains(filterPrefix.toLowerCase())) {
          _discoveredDevices.add(BluetoothDeviceInfo(
            name: name.isEmpty ? '알 수 없는 기기' : name,
            address: device.address,
          ));
        }
      }

      if (_discoveredDevices.isEmpty && filterPrefix.isNotEmpty) {
        // fb153이 없으면 모든 페어링된 기기 표시
        for (final device in bondedDevices) {
          _discoveredDevices.add(BluetoothDeviceInfo(
            name: device.name ?? '알 수 없는 기기',
            address: device.address,
          ));
        }
      }

      _setState(BtConnectionState.disconnected);
      notifyListeners();
    } catch (e) {
      _errorMessage = '스캔 오류: $e';
      _setState(BtConnectionState.error);
    }
  }

  /// 기기 연결
  Future<void> connect(BluetoothDeviceInfo device) async {
    _setState(BtConnectionState.connecting);
    _errorMessage = null;

    try {
      _connection = await BluetoothConnection.toAddress(device.address)
          .timeout(const Duration(seconds: 10));

      _connectedDevice = device;
      _setState(BtConnectionState.connected);

      // 연결 끊김 감지
      _connection!.input?.listen(
        (data) {
          // 로봇에서 수신 데이터 처리 (필요시)
        },
        onDone: () {
          if (kDebugMode) debugPrint('Bluetooth 연결 종료됨');
          disconnect();
        },
        onError: (error) {
          if (kDebugMode) debugPrint('Bluetooth 수신 오류: $error');
          disconnect();
        },
      );
    } catch (e) {
      _errorMessage = '연결 실패: $e';
      _connectedDevice = null;
      _setState(BtConnectionState.error);
    }
  }

  /// 기기 연결 해제
  Future<void> disconnect() async {
    try {
      await _connection?.close();
    } catch (_) {}
    _connection = null;
    _connectedDevice = null;
    _setState(BtConnectionState.disconnected);
  }

  /// 패킷 전송
  Future<bool> sendPacket(List<int> packet) async {
    if (!isConnected || _connection == null) return false;

    try {
      final stopwatch = Stopwatch()..start();
      _connection!.output.add(Uint8List.fromList(packet));
      await _connection!.output.allSent;
      stopwatch.stop();

      _latencyMs = stopwatch.elapsedMilliseconds;
      _packetsSent++;
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('패킷 전송 오류: $e');
      return false;
    }
  }

  /// 모션 번호로 패킷 전송
  Future<bool> sendMotion(int motionIndex) async {
    final packet = PacketBuilder.build(motionIndex);
    if (kDebugMode) {
      debugPrint(
          '전송: 모션 $motionIndex → ${PacketBuilder.toHexString(packet)}');
    }
    return sendPacket(packet);
  }

  /// 정지 명령 전송 (모션 1)
  Future<bool> sendStop() => sendMotion(1);

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
