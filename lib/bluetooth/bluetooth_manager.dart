import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
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

  String get macSuffix {
    final parts = address.split(':');
    if (parts.length >= 2) {
      return '${parts[parts.length - 2]}:${parts[parts.length - 1]}'.toUpperCase();
    }
    return address.toUpperCase();
  }

  String get displayName => '$name  [$macSuffix]';

  bool get isFb153Robot {
    final n = name.toLowerCase().replaceAll(' ', '');
    return n.contains('fb153') || n.contains('robot');
  }

  @override
  String toString() => displayName;
}

// ─────────────────────────────────────────────────────────────────────────────
// BluetoothManager — MethodChannel + EventChannel 기반 네이티브 BT Classic
//
// Android 네이티브 (BluetoothClassicPlugin.kt) 연결 전략:
//   1순위: reflection createRfcommSocket(channel=1)  ← fb153 필수
//   2순위: createRfcommSocketToServiceRecord(SPP UUID) fallback
// ─────────────────────────────────────────────────────────────────────────────
class BluetoothManager extends ChangeNotifier {
  static final BluetoothManager _instance = BluetoothManager._internal();
  factory BluetoothManager() => _instance;
  BluetoothManager._internal() {
    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      _onNativeEvent,
      onError: (e) => debugPrint('[BT] 이벤트 오류: $e'),
    );
  }

  // ── 채널 ──────────────────────────────────────────────────────
  static const _methodChannel =
      MethodChannel('com.robocommander/bluetooth');
  static const _eventChannel =
      EventChannel('com.robocommander/bluetooth_events');

  StreamSubscription? _eventSub;

  // ── 상태 ──────────────────────────────────────────────────────
  BtConnectionState _connectionState = BtConnectionState.disconnected;
  BtConnectionState get connectionState => _connectionState;
  bool get isConnected  => _connectionState == BtConnectionState.connected;
  bool get isScanning   => _connectionState == BtConnectionState.scanning;

  // ── 기기 정보 ─────────────────────────────────────────────────
  BluetoothDeviceInfo? _connectedDevice;
  BluetoothDeviceInfo? get connectedDevice => _connectedDevice;

  final List<BluetoothDeviceInfo> _discoveredDevices = [];
  List<BluetoothDeviceInfo> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices);

  // ── 오류 / 통계 ───────────────────────────────────────────────
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  int _packetsSent = 0;
  int get packetsSent => _packetsSent;

  int _latencyMs = 0;
  int get latencyMs => _latencyMs;

  // ── 마지막 연결 기기 (자동 재연결용) ──────────────────────────
  static const _prefKeyLastMac  = 'last_connected_mac';
  static const _prefKeyLastName = 'last_connected_name';

  String? _lastMac;
  String? get lastMac => _lastMac;

  // ─────────────────────────────────────────────────────────────
  void _setState(BtConnectionState state) {
    _connectionState = state;
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════
  //  초기화 — 마지막 연결 기기 복원
  // ══════════════════════════════════════════════════════════════
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _lastMac = prefs.getString(_prefKeyLastMac);
    final lastName = prefs.getString(_prefKeyLastName);
    if (_lastMac != null && lastName != null) {
      debugPrint('[BT] 마지막 연결 기기 복원: $lastName [$_lastMac]');
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  Bluetooth 활성화 확인
  // ══════════════════════════════════════════════════════════════
  Future<bool> isBluetoothEnabled() async {
    try {
      return await _methodChannel.invokeMethod<bool>('isBluetoothEnabled') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestEnable() async {
    // Android 13+에서는 직접 켜기 API 없음 — 사용자에게 유도
    return await isBluetoothEnabled();
  }

  // ══════════════════════════════════════════════════════════════
  //  BT 권한 확인 (Android 12+)
  // ══════════════════════════════════════════════════════════════
  Future<bool> _ensureBluetoothPermissions() async {
    final connectStatus = await Permission.bluetoothConnect.status;
    if (connectStatus.isDenied || connectStatus.isRestricted) {
      final result = await Permission.bluetoothConnect.request();
      if (!result.isGranted) {
        _errorMessage = 'Bluetooth 연결 권한이 필요합니다.\n설정 > 앱 > 권한 > 근처 기기를 허용해 주세요.';
        debugPrint('[BT] BLUETOOTH_CONNECT 권한 거부됨');
        return false;
      }
    }

    final scanStatus = await Permission.bluetoothScan.status;
    if (scanStatus.isDenied || scanStatus.isRestricted) {
      await Permission.bluetoothScan.request();
      // scan 권한 없어도 getBondedDevices 동작 가능 — 계속 진행
    }

    return true;
  }

  // ══════════════════════════════════════════════════════════════
  //  스캔 — 페어링된 기기 목록 + fb153 필터
  // ══════════════════════════════════════════════════════════════
  Future<void> startScan({String filterPrefix = 'fb153'}) async {
    _discoveredDevices.clear();
    _errorMessage = null;
    _setState(BtConnectionState.scanning);

    final hasPermission = await _ensureBluetoothPermissions();
    if (!hasPermission) {
      _setState(BtConnectionState.error);
      return;
    }

    try {
      final raw = await _methodChannel.invokeMethod<List>('getBondedDevices');
      final bonded = (raw ?? []).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return BluetoothDeviceInfo(
          name:    m['name']    as String? ?? '알 수 없는 기기',
          address: m['address'] as String? ?? '',
        );
      }).toList();

      // fb153 필터
      final fb153List = filterPrefix.isEmpty
          ? bonded
          : bonded.where((d) {
              final n = d.name.toLowerCase().replaceAll(' ', '');
              final f = filterPrefix.toLowerCase().replaceAll(' ', '');
              return n.contains(f);
            }).toList();

      // fb153 없으면 전체 페어링 기기
      final targetList = fb153List.isNotEmpty ? fb153List : bonded;

      _discoveredDevices.addAll(
        targetList..sort((a, b) => a.macSuffix.compareTo(b.macSuffix)),
      );

      _setState(BtConnectionState.disconnected);
    } on PlatformException catch (e) {
      _errorMessage = '스캔 오류: ${e.message}';
      _setState(BtConnectionState.error);
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  자동 재연결
  // ══════════════════════════════════════════════════════════════
  Future<bool> tryAutoReconnect() async {
    if (_lastMac == null) return false;
    if (isConnected) return true;

    final prefs = await SharedPreferences.getInstance();
    final lastName = prefs.getString(_prefKeyLastName) ?? 'fb153 로봇';
    await connect(BluetoothDeviceInfo(name: lastName, address: _lastMac!));
    return isConnected;
  }

  // ══════════════════════════════════════════════════════════════
  //  연결 — 네이티브로 위임 (ch1 reflection 우선)
  // ══════════════════════════════════════════════════════════════
  Future<void> connect(BluetoothDeviceInfo device) async {
    if (isConnected) await disconnect();

    _setState(BtConnectionState.connecting);
    _errorMessage = null;

    try {
      await _methodChannel.invokeMethod<bool>(
        'connect',
        {'address': device.address},
      );
      // 실제 연결 완료는 EventChannel 'connected' 이벤트로 처리됨
      _connectedDevice = device;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyLastMac,  device.address);
      await prefs.setString(_prefKeyLastName, device.name);
      _lastMac = device.address;

    } on PlatformException catch (e) {
      _errorMessage = _buildErrorMessage(e.message);
      _connectedDevice = null;
      _setState(BtConnectionState.error);
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  네이티브 이벤트 수신 (connected / disconnected / data / error)
  // ══════════════════════════════════════════════════════════════
  void _onNativeEvent(dynamic event) {
    if (event is! Map) return;
    final type = event['type'] as String? ?? '';

    switch (type) {
      case 'connected':
        _setState(BtConnectionState.connected);

      case 'disconnected':
        _connectedDevice = null;
        if (_connectionState != BtConnectionState.error) {
          _setState(BtConnectionState.disconnected);
        }

      case 'error':
        _errorMessage = event['message'] as String?;
        _connectedDevice = null;
        _setState(BtConnectionState.error);

      case 'data':
        // 수신 데이터 (필요 시 확장)
        debugPrint('[BT] 수신 데이터: ${event['bytes']}');
    }
  }

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

  // ══════════════════════════════════════════════════════════════
  //  연결 해제
  // ══════════════════════════════════════════════════════════════
  Future<void> disconnect() async {
    try {
      await _methodChannel.invokeMethod<bool>('disconnect');
    } catch (_) {}
    _connectedDevice = null;
    _setState(BtConnectionState.disconnected);
  }

  // ══════════════════════════════════════════════════════════════
  //  패킷 전송
  // ══════════════════════════════════════════════════════════════
  Future<bool> sendPacket(List<int> packet) async {
    if (!isConnected) return false;
    final sw = Stopwatch()..start();
    try {
      await _methodChannel.invokeMethod<bool>(
        'send',
        {'data': Uint8List.fromList(packet)},
      );
      sw.stop();
      _latencyMs = sw.elapsedMilliseconds;
      _packetsSent++;
      notifyListeners();
      return true;
    } on PlatformException catch (e) {
      debugPrint('[BT] 전송 오류: ${e.message}');
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
    _eventSub?.cancel();
    disconnect();
    super.dispose();
  }
}
