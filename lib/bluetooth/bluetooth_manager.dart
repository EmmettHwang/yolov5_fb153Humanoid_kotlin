import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  final int rssi;       // 신호 세기 (discovery 전용)
  final bool bonded;    // 이미 페어링됨

  const BluetoothDeviceInfo({
    required this.name,
    required this.address,
    this.rssi = 0,
    this.bonded = false,
  });

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

  // ── Discovery 상태 ────────────────────────────────────────────
  bool _isDiscovering = false;
  bool get isDiscovering => _isDiscovering;

  // ── 기기 정보 ─────────────────────────────────────────────────
  BluetoothDeviceInfo? _connectedDevice;
  BluetoothDeviceInfo? get connectedDevice => _connectedDevice;

  // 페어링된 기기 목록 (탭 1)
  final List<BluetoothDeviceInfo> _discoveredDevices = [];
  List<BluetoothDeviceInfo> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices);

  // 미페어링 새 기기 목록 (탭 2)
  final List<BluetoothDeviceInfo> _newDevices = [];
  List<BluetoothDeviceInfo> get newDevices => List.unmodifiable(_newDevices);

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

  // ── 페어링 대기 상태 ──────────────────────────────────────────
  // ignore: unused_field
  String? _bondingAddress;

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
    }

    return true;
  }

  // ══════════════════════════════════════════════════════════════
  //  Discovery용 위치 권한 (Android 11 이하 필요)
  // ══════════════════════════════════════════════════════════════
  Future<bool> _ensureLocationPermission({BuildContext? context}) async {
    final locStatus = await Permission.locationWhenInUse.status;
    if (locStatus.isGranted) return true;

    if (locStatus.isDenied) {
      final result = await Permission.locationWhenInUse.request();
      if (result.isGranted) return true;
    }

    if (locStatus.isPermanentlyDenied) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                '위치 권한이 필요합니다 (BT 검색). 앱 설정에서 허용해 주세요.'),
            action: SnackBarAction(
              label: '설정',
              onPressed: openAppSettings,
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return false;
    }

    return false;
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
          bonded:  true,
        );
      }).toList();

      final fb153List = filterPrefix.isEmpty
          ? bonded
          : bonded.where((d) {
              final n = d.name.toLowerCase().replaceAll(' ', '');
              final f = filterPrefix.toLowerCase().replaceAll(' ', '');
              return n.contains(f);
            }).toList();

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
  //  discoverDevices — 미페어링 기기 실시간 검색
  // ══════════════════════════════════════════════════════════════
  Future<void> discoverDevices({BuildContext? context}) async {
    _newDevices.clear();
    _errorMessage = null;
    _isDiscovering = true;
    notifyListeners();

    // BT 권한
    final hasBt = await _ensureBluetoothPermissions();
    if (!hasBt) {
      _isDiscovering = false;
      _errorMessage = 'Bluetooth 권한이 필요합니다';
      notifyListeners();
      return;
    }

    // 위치 권한 (Android 11 이하)
    await _ensureLocationPermission(context: context);
    // 위치 권한 거부되어도 Android 12+에서는 진행 가능

    try {
      await _methodChannel.invokeMethod<bool>('startDiscovery');
      // 결과는 EventChannel로 수신 (_onNativeEvent에서 처리)
      // 타임아웃: 12초 후 자동 종료
      Future.delayed(const Duration(seconds: 12), () {
        if (_isDiscovering) {
          stopDiscovery();
        }
      });
    } on PlatformException catch (e) {
      _isDiscovering = false;
      _errorMessage = 'Discovery 오류: ${e.message}';
      notifyListeners();
    }
  }

  // ── Discovery 중지 ────────────────────────────────────────────
  Future<void> stopDiscovery() async {
    try {
      await _methodChannel.invokeMethod<bool>('stopDiscovery');
    } catch (_) {}
    _isDiscovering = false;
    notifyListeners();
  }

  // ── 페어링 요청 ───────────────────────────────────────────────
  Future<String> requestBond(String address) async {
    try {
      _bondingAddress = address;
      notifyListeners();
      final result = await _methodChannel.invokeMethod<String>(
          'createBond', {'address': address});
      return result ?? 'failed';
    } on PlatformException catch (e) {
      return 'error: ${e.message}';
    }
  }

  // ══════════════════════════════════════════════════════════════
  //  자동 재연결
  // ══════════════════════════════════════════════════════════════
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;

  void _scheduleAutoReconnect() {
    if (_lastMac == null) return;
    _reconnectTimer?.cancel();
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _reconnectAttempts = 0;
      debugPrint('[BT] 자동 재연결 최대 시도 초과 — 중단');
      return;
    }
    final delay = Duration(seconds: 3 + _reconnectAttempts * 2);
    debugPrint('[BT] ${delay.inSeconds}초 후 자동 재연결 시도 (${_reconnectAttempts + 1}/$_maxReconnectAttempts)');
    _reconnectTimer = Timer(delay, () async {
      if (!isConnected && _lastMac != null) {
        _reconnectAttempts++;
        await tryAutoReconnect();
      }
    });
  }

  Future<bool> tryAutoReconnect() async {
    if (_lastMac == null) return false;
    if (isConnected) return true;

    final prefs = await SharedPreferences.getInstance();
    final lastName = prefs.getString(_prefKeyLastName) ?? 'fb153 로봇';
    debugPrint('[BT] 자동연결 시도: $lastName [$_lastMac]');

    await connect(BluetoothDeviceInfo(name: lastName, address: _lastMac!));

    // 네이티브 'connected' 이벤트가 비동기로 오므로 최대 3초 대기
    if (!isConnected) {
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (isConnected) break;
        if (_connectionState == BtConnectionState.error) break;
      }
    }

    if (isConnected) {
      _reconnectAttempts = 0;
      debugPrint('[BT] 자동연결 성공: $lastName');
    } else {
      debugPrint('[BT] 자동연결 실패: $lastName');
    }
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
  //  네이티브 이벤트 수신 (connected / disconnected / data / error
  //                        / device_found / discovery_finished
  //                        / bond_success / bond_failed)
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
        _scheduleAutoReconnect();

      case 'error':
        _errorMessage = event['message'] as String?;
        _connectedDevice = null;
        _setState(BtConnectionState.error);

      case 'data':
        debugPrint('[BT] 수신 데이터: ${event['bytes']}');

      // ── Discovery 이벤트 ────────────────────────────
      case 'discovery_started':
        _isDiscovering = true;
        notifyListeners();

      case 'device_found':
        final address = event['address'] as String? ?? '';
        final name    = event['name']    as String? ?? '알 수 없는 기기';
        final rssi    = event['rssi']    as int? ?? 0;
        final bonded  = event['bonded']  as bool? ?? false;

        // 중복 제거
        final exists = _newDevices.any((d) => d.address == address);
        if (!exists && address.isNotEmpty) {
          _newDevices.add(BluetoothDeviceInfo(
            name:    name,
            address: address,
            rssi:    rssi,
            bonded:  bonded,
          ));
          // RSSI 강한 순 정렬
          _newDevices.sort((a, b) => b.rssi.compareTo(a.rssi));
          notifyListeners();
        }

      case 'discovery_finished':
        _isDiscovering = false;
        notifyListeners();

      // ── Bond 이벤트 ─────────────────────────────────
      case 'bond_success':
        final address = event['address'] as String? ?? '';
        debugPrint('[BT] 페어링 성공: $address');
        _bondingAddress = null;
        // 페어링된 기기 목록 갱신
        if (address.isNotEmpty) {
          final idx = _newDevices.indexWhere((d) => d.address == address);
          if (idx >= 0) {
            final dev = _newDevices[idx];
            _newDevices[idx] = BluetoothDeviceInfo(
              name: dev.name, address: dev.address,
              rssi: dev.rssi, bonded: true,
            );
          }
        }
        notifyListeners();

      case 'bond_failed':
        final address = event['address'] as String? ?? '';
        debugPrint('[BT] 페어링 실패: $address');
        _bondingAddress = null;
        notifyListeners();
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

  /// LED 제어 패킷 전송
  /// [motorId] 18=머리, 17=허리 (PacketBuilder.motorIdHead/Waist)
  /// [r][g][b] RGB 0~255
  Future<bool> sendLed({
    int motorId = PacketBuilder.motorIdHead,
    int r = 0,
    int g = 0,
    int b = 0,
  }) async {
    final packet = PacketBuilder.buildLed(motorId: motorId, r: r, g: g, b: b);
    if (kDebugMode) {
      debugPrint('TX LED($motorId) R=$r G=$g B=$b → ${PacketBuilder.toHexString(packet)}');
    }
    return sendPacket(packet);
  }

  /// LED OFF
  Future<bool> sendLedOff({int motorId = PacketBuilder.motorIdHead}) =>
      sendLed(motorId: motorId);

  /// 포지션 제어 패킷 전송
  /// [motorId] 모터 ID, [torquePercent] 0~100, [position] -32768~32767
  Future<bool> sendPosition({
    int motorId = PacketBuilder.motorIdHead,
    int torquePercent = 80,
    int position = 0,
  }) async {
    final packet = PacketBuilder.buildPosition(
      motorId: motorId,
      torquePercent: torquePercent,
      position: position,
    );
    if (kDebugMode) {
      debugPrint('TX POS($motorId) torq=$torquePercent pos=$position → ${PacketBuilder.toHexString(packet)}');
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
