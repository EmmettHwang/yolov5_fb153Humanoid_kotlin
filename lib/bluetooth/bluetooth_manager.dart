import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'packet_builder.dart';

/// Bluetooth 연결 상태
enum BtConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

/// Bluetooth 기기 정보 (MAC 4자리 포함)
class BluetoothDeviceInfo {
  final String name;
  final String address; // 전체 MAC (예: 00:11:22:33:AA:BB)

  const BluetoothDeviceInfo({required this.name, required this.address});

  /// MAC 주소 마지막 4자리 (예: AA:BB)
  String get macSuffix {
    final parts = address.split(':');
    if (parts.length >= 2) {
      return '${parts[parts.length - 2]}:${parts[parts.length - 1]}'.toUpperCase();
    }
    return address.toUpperCase();
  }

  /// 표시 이름: "fb153 [AA:BB]"
  String get displayName => '$name  [$macSuffix]';

  /// fb153 로봇 여부
  bool get isFb153Robot =>
      name.toLowerCase().contains('fb153') ||
      name.toLowerCase().contains('robot');

  @override
  String toString() => displayName;
}

/// fb153 로봇 Bluetooth Classic 2.0 (SPP) 관리자
class BluetoothManager extends ChangeNotifier {
  static final BluetoothManager _instance = BluetoothManager._internal();
  factory BluetoothManager() => _instance;
  BluetoothManager._internal();

  // ── 상태 ──────────────────────────────────────────
  BtConnectionState _connectionState = BtConnectionState.disconnected;
  BtConnectionState get connectionState => _connectionState;
  bool get isConnected => _connectionState == BtConnectionState.connected;
  bool get isScanning  => _connectionState == BtConnectionState.scanning;

  // ── 기기 정보 ────────────────────────────────────
  BluetoothDeviceInfo? _connectedDevice;
  BluetoothDeviceInfo? get connectedDevice => _connectedDevice;

  final List<BluetoothDeviceInfo> _discoveredDevices = [];
  List<BluetoothDeviceInfo> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices);

  // ── 연결 소켓 ───────────────────────────────────
  BluetoothConnection? _connection;

  // ── 오류 / 통계 ──────────────────────────────────
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  int _packetsSent = 0;
  int get packetsSent => _packetsSent;

  int _latencyMs = 0;
  int get latencyMs => _latencyMs;

  // ── 마지막 연결 기기 (자동 재연결용) ───────────────
  static const _prefKeyLastMac  = 'last_connected_mac';
  static const _prefKeyLastName = 'last_connected_name';

  String? _lastMac;
  String? get lastMac => _lastMac;

  // ── 내부 유틸 ───────────────────────────────────
  void _setState(BtConnectionState state) {
    _connectionState = state;
    notifyListeners();
  }

  // ══════════════════════════════════════════════════
  //  초기화 - 마지막 연결 기기 복원
  // ══════════════════════════════════════════════════
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _lastMac = prefs.getString(_prefKeyLastMac);
    final lastName = prefs.getString(_prefKeyLastName);
    if (_lastMac != null && lastName != null) {
      if (kDebugMode) debugPrint('마지막 연결 기기 복원: $lastName [$_lastMac]');
    }
  }

  // ══════════════════════════════════════════════════
  //  Bluetooth 활성화
  // ══════════════════════════════════════════════════
  Future<bool> isBluetoothEnabled() async {
    try {
      return await FlutterBluetoothSerial.instance.isEnabled ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestEnable() async {
    try {
      return await FlutterBluetoothSerial.instance.requestEnable() ?? false;
    } catch (_) {
      return false;
    }
  }

  // ══════════════════════════════════════════════════
  //  스캔 - 페어링된 기기 목록 + fb153 필터
  // ══════════════════════════════════════════════════
  Future<void> startScan({String filterPrefix = 'fb153'}) async {
    _discoveredDevices.clear();
    _errorMessage = null;
    _setState(BtConnectionState.scanning);

    try {
      final bonded = await FlutterBluetoothSerial.instance.getBondedDevices();

      // 1차: fb153 이름 필터
      final fb153List = bonded.where((d) {
        final n = (d.name ?? '').toLowerCase();
        return filterPrefix.isEmpty || n.contains(filterPrefix.toLowerCase());
      }).toList();

      // fb153이 있으면 해당 목록만, 없으면 전체 페어링 기기 표시
      final targetList = fb153List.isNotEmpty ? fb153List : bonded;

      for (final d in targetList) {
        _discoveredDevices.add(BluetoothDeviceInfo(
          name: d.name?.isNotEmpty == true ? d.name! : '알 수 없는 기기',
          address: d.address,
        ));
      }

      // MAC 주소 마지막 4자리 기준 정렬
      _discoveredDevices.sort((a, b) => a.macSuffix.compareTo(b.macSuffix));

      _setState(BtConnectionState.disconnected);
    } catch (e) {
      _errorMessage = '스캔 오류: $e';
      _setState(BtConnectionState.error);
    }
  }

  // ══════════════════════════════════════════════════
  //  자동 재연결 - 마지막 기기로 자동 연결 시도
  // ══════════════════════════════════════════════════
  Future<bool> tryAutoReconnect() async {
    if (_lastMac == null) return false;
    if (isConnected) return true;

    final prefs = await SharedPreferences.getInstance();
    final lastName = prefs.getString(_prefKeyLastName) ?? 'fb153 로봇';

    final device = BluetoothDeviceInfo(name: lastName, address: _lastMac!);
    if (kDebugMode) debugPrint('자동 재연결 시도: ${device.displayName}');

    await connect(device);
    return isConnected;
  }

  // ══════════════════════════════════════════════════
  //  연결
  // ══════════════════════════════════════════════════
  Future<void> connect(BluetoothDeviceInfo device) async {
    if (isConnected) await disconnect();

    _setState(BtConnectionState.connecting);
    _errorMessage = null;

    try {
      _connection = await BluetoothConnection.toAddress(device.address)
          .timeout(const Duration(seconds: 12));

      _connectedDevice = device;

      // 마지막 연결 기기 저장 (자동 재연결용)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyLastMac, device.address);
      await prefs.setString(_prefKeyLastName, device.name);
      _lastMac = device.address;

      _setState(BtConnectionState.connected);

      // 연결 끊김 감지
      _connection!.input?.listen(
        (_) {},
        onDone: () {
          if (kDebugMode) debugPrint('Bluetooth 연결 종료됨');
          _onDisconnected();
        },
        onError: (e) {
          if (kDebugMode) debugPrint('Bluetooth 오류: $e');
          _onDisconnected();
        },
        cancelOnError: true,
      );
    } on TimeoutException {
      _errorMessage = '연결 시간 초과 (12초) — 로봇 전원 확인';
      _connectedDevice = null;
      _setState(BtConnectionState.error);
    } catch (e) {
      _errorMessage = '연결 실패: $e';
      _connectedDevice = null;
      _setState(BtConnectionState.error);
    }
  }

  void _onDisconnected() {
    _connection = null;
    _connectedDevice = null;
    _setState(BtConnectionState.disconnected);
  }

  // ══════════════════════════════════════════════════
  //  연결 해제
  // ══════════════════════════════════════════════════
  Future<void> disconnect() async {
    try {
      await _connection?.close();
    } catch (_) {}
    _connection = null;
    _connectedDevice = null;
    _setState(BtConnectionState.disconnected);
  }

  // ══════════════════════════════════════════════════
  //  패킷 전송
  // ══════════════════════════════════════════════════
  Future<bool> sendPacket(List<int> packet) async {
    if (!isConnected || _connection == null) return false;
    try {
      final sw = Stopwatch()..start();
      _connection!.output.add(Uint8List.fromList(packet));
      await _connection!.output.allSent;
      sw.stop();
      _latencyMs = sw.elapsedMilliseconds;
      _packetsSent++;
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('패킷 전송 오류: $e');
      return false;
    }
  }

  Future<bool> sendMotion(int motionIndex) async {
    final packet = PacketBuilder.build(motionIndex);
    if (kDebugMode) {
      debugPrint('TX 모션 $motionIndex → ${PacketBuilder.toHexString(packet)}');
    }
    return sendPacket(packet);
  }

  Future<bool> sendStop() => sendMotion(1);

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
