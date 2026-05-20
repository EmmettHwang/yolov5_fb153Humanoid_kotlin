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

  /// fb153 로봇 여부 (FB153 v1.0.0 등 대소문자·공백 무시)
  bool get isFb153Robot {
    final n = name.toLowerCase().replaceAll(' ', '');
    return n.contains('fb153') || n.contains('robot');
  }

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

      // fb153 관련 기기 필터 (대소문자 무시, 공백 제거 후 매칭)
      // 예: "fb153", "FB153", "FB153 v1.0.0", "FB153_v2" 모두 매칭
      final fb153List = bonded.where((d) {
        if (filterPrefix.isEmpty) return true;
        final n = (d.name ?? '').toLowerCase().replaceAll(' ', '');
        final f = filterPrefix.toLowerCase().replaceAll(' ', '');
        return n.contains(f);
      }).toList();

      // fb153 기기가 있으면 해당 목록만, 없으면 전체 페어링 기기 표시
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

    // 최대 2회 시도 (already bonded / read failed 에러 재시도 포함)
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        if (kDebugMode) debugPrint('BT 연결 시도 $attempt: ${device.displayName}');

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
        return; // 성공 시 종료

      } on TimeoutException {
        _errorMessage = '연결 시간 초과 (12초) — 로봇 전원 확인';
        _connectedDevice = null;
        _setState(BtConnectionState.error);
        return; // 타임아웃은 재시도 없음

      } on PlatformException catch (e) {
        final msg = e.message?.toLowerCase() ?? '';
        final isRetryable = msg.contains('already') ||
            msg.contains('read failed') ||
            msg.contains('socket might closed') ||
            msg.contains('broken pipe') ||
            msg.contains('connection was already requested') ||
            msg.contains('bonded');

        if (kDebugMode) debugPrint('BT PlatformException (시도 $attempt): ${e.message}');

        if (isRetryable && attempt == 1) {
          // "already bonded" 류 에러: 기존 소켓 정리 후 재시도
          if (kDebugMode) debugPrint('→ already bonded 에러 감지 — 소켓 정리 후 재시도...');
          try { await _connection?.close(); } catch (_) {}
          _connection = null;
          // 0.8초 대기 후 재시도 (Android BT 스택 안정화)
          await Future.delayed(const Duration(milliseconds: 800));
          continue; // 2회차 시도
        }

        // 재시도해도 실패하거나 다른 에러
        _errorMessage = _buildErrorMessage(e.message);
        _connectedDevice = null;
        _setState(BtConnectionState.error);
        return;

      } catch (e) {
        final msg = e.toString().toLowerCase();
        final isRetryable = msg.contains('already') ||
            msg.contains('read failed') ||
            msg.contains('socket') ||
            msg.contains('bonded');

        if (isRetryable && attempt == 1) {
          if (kDebugMode) debugPrint('→ 연결 에러 재시도: $e');
          try { await _connection?.close(); } catch (_) {}
          _connection = null;
          await Future.delayed(const Duration(milliseconds: 800));
          continue;
        }

        _errorMessage = '연결 실패: $e';
        _connectedDevice = null;
        _setState(BtConnectionState.error);
        return;
      }
    }
  }

  /// 에러 메시지를 사용자 친화적으로 변환
  String _buildErrorMessage(String? raw) {
    if (raw == null) return '연결 실패 — 다시 시도하세요';
    final msg = raw.toLowerCase();
    if (msg.contains('already') || msg.contains('bonded')) {
      return '이미 페어링된 기기입니다. 재연결 중...';
    }
    if (msg.contains('read failed') || msg.contains('socket')) {
      return 'BT 소켓 오류 — 로봇을 재시작 후 다시 연결하세요';
    }
    if (msg.contains('permission')) {
      return 'Bluetooth 권한이 없습니다 — 앱 설정에서 허용하세요';
    }
    return '연결 실패: $raw';
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
