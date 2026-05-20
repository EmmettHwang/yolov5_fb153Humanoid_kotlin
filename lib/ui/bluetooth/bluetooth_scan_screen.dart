import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../../bluetooth/bluetooth_manager.dart';
import '../control/control_screen.dart';

/// Bluetooth 스캔 & 연결 전용 화면
/// - fb153 기기를 MAC 마지막 4자리로 표시
/// - 선택 즉시 자동 연결
class BluetoothScanScreen extends StatefulWidget {
  final bool isFirstLaunch;
  const BluetoothScanScreen({super.key, this.isFirstLaunch = false});

  @override
  State<BluetoothScanScreen> createState() => _BluetoothScanScreenState();
}

class _BluetoothScanScreenState extends State<BluetoothScanScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  String? _connectingMac;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // 화면 진입 시 자동 스캔
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BluetoothManager>().startScan();
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── 기기 선택 → 즉시 연결 ─────────────────────────
  Future<void> _connectTo(BluetoothDeviceInfo device) async {
    setState(() => _connectingMac = device.address);
    final btManager = context.read<BluetoothManager>();
    await btManager.connect(device);

    if (!mounted) return;

    if (btManager.isConnected) {
      // 연결 성공 → 메인 제어 화면으로
      if (widget.isFirstLaunch) {
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const ControlScreen(),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      } else {
        Navigator.pop(context); // 설정에서 열었을 때
      }
    } else {
      setState(() => _connectingMac = null);
      _showError(btManager.errorMessage ?? '연결에 실패했습니다');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(msg)),
        ]),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final btManager = context.watch<BluetoothManager>();
    final devices = btManager.discoveredDevices;
    final scanning = btManager.isScanning;

    return Scaffold(
      backgroundColor: const Color(0xFF060E18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1F2D),
        leading: widget.isFirstLaunch
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios,
                    color: Colors.white, size: 18),
                onPressed: () => Navigator.pop(context),
              ),
        title: Row(children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Opacity(
              opacity: scanning ? _pulseAnim.value : 1.0,
              child: Icon(
                scanning ? Icons.bluetooth_searching : Icons.bluetooth,
                color: Colors.cyanAccent,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text('fb153 로봇 연결',
              style: TextStyle(color: Colors.white, fontSize: 16)),
        ]),
        actions: [
          // 새로고침 버튼
          IconButton(
            icon: scanning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.cyanAccent,
                    ),
                  )
                : const Icon(Icons.refresh, color: Colors.white70),
            onPressed:
                scanning ? null : () => btManager.startScan(),
          ),
          const SizedBox(width: 4),
        ],
      ),

      body: Column(children: [
        // ── 안내 배너 ─────────────────────────────────
        _buildInfoBanner(btManager),

        // ── 기기 목록 ─────────────────────────────────
        Expanded(
          child: scanning && devices.isEmpty
              ? _buildScanningIndicator()
              : devices.isEmpty
                  ? _buildEmptyState(btManager)
                  : _buildDeviceList(devices, btManager),
        ),

        // ── 하단 PIN 안내 ─────────────────────────────
        _buildPinGuide(),
      ]),
    );
  }

  // ── 안내 배너 ──────────────────────────────────────
  Widget _buildInfoBanner(BluetoothManager btManager) {
    final lastMac = btManager.lastMac;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.cyan.withValues(alpha: 0.15),
            Colors.blue.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyan.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.info_outline, color: Colors.cyanAccent, size: 16),
            const SizedBox(width: 6),
            Text(
              'MAC 4자리로 내 로봇 확인',
              style: TextStyle(
                color: Colors.cyanAccent.withValues(alpha: 0.9),
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            '여러 fb153이 있을 때 로봇 뒷면 스티커의\nMAC 주소 마지막 4자리로 내 로봇을 구분하세요.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
              height: 1.5,
            ),
          ),
          if (lastMac != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
              ),
              child: Row(children: [
                const Icon(Icons.history, color: Colors.greenAccent, size: 13),
                const SizedBox(width: 5),
                Text(
                  '마지막 연결: [${_macSuffix(lastMac)}]',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () async {
                    final prefs = await _getPrefs();
                    final lastName = prefs.getString('last_connected_name') ?? 'fb153';
                    _connectTo(
                      BluetoothDeviceInfo(name: lastName, address: lastMac),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '재연결',
                      style: TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  // ── 스캔 중 인디케이터 ────────────────────────────
  Widget _buildScanningIndicator() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Opacity(
              opacity: _pulseAnim.value,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.cyanAccent.withValues(alpha: 0.6),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.bluetooth_searching,
                  color: Colors.cyanAccent,
                  size: 40,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '페어링된 기기 검색 중...',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'fb153 로봇 전원을 켜주세요',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // ── 기기 없을 때 ──────────────────────────────────
  Widget _buildEmptyState(BluetoothManager btManager) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth_disabled,
                size: 56, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text(
              'fb153 기기를 찾지 못했습니다',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            // 기기 이름 안내 박스
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline, size: 14, color: Colors.amber),
                      const SizedBox(width: 6),
                      Text(
                        '기기 이름 확인',
                        style: TextStyle(
                          color: Colors.amber.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '안드로이드 BT 설정의 기기 이름이\n"FB153 v1.0.0" 형태인지 확인하세요.\n(fb153, FB153, FB153 v1.0.0 모두 인식됩니다)',
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),
            Text(
              '로봇이 페어링되어 있다면 아래\n"전체 기기 보기"를 눌러 선택하세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),

            // 다시 스캔
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('다시 스캔',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => btManager.startScan(),
            ),
            const SizedBox(height: 8),

            // 전체 기기 보기 (필터 없이)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white60,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.list, size: 16),
              label: const Text('전체 기기 보기', style: TextStyle(fontSize: 12)),
              onPressed: () => btManager.startScan(filterPrefix: ''),
            ),
            const SizedBox(height: 8),

            TextButton(
              onPressed: _openSystemBluetooth,
              child: Text(
                '블루투스 설정 열기 →',
                style: TextStyle(
                  color: Colors.cyan.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 기기 목록 ────────────────────────────────────
  Widget _buildDeviceList(
      List<BluetoothDeviceInfo> devices, BluetoothManager btManager) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      children: [
        // 목록 헤더
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Text(
              '발견된 기기 ${devices.length}개',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const Spacer(),
            Text(
              '탭하면 자동 연결',
              style: TextStyle(
                color: Colors.cyanAccent.withValues(alpha: 0.5),
                fontSize: 10,
              ),
            ),
          ]),
        ),

        // 기기 카드 목록
        ...devices.map((device) => _buildDeviceCard(device, btManager)),
      ],
    );
  }

  // ── 기기 카드 ────────────────────────────────────
  Widget _buildDeviceCard(
      BluetoothDeviceInfo device, BluetoothManager btManager) {
    final isConnecting = _connectingMac == device.address;
    final isConnected = btManager.connectedDevice?.address == device.address;
    final isLastUsed = btManager.lastMac == device.address;

    return GestureDetector(
      onTap: (isConnecting || isConnected)
          ? null
          : () => _connectTo(device),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isConnected
                ? [
                    Colors.green.withValues(alpha: 0.2),
                    Colors.green.withValues(alpha: 0.08),
                  ]
                : isConnecting
                    ? [
                        Colors.orange.withValues(alpha: 0.15),
                        Colors.orange.withValues(alpha: 0.05),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.08),
                        Colors.white.withValues(alpha: 0.03),
                      ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isConnected
                ? Colors.greenAccent.withValues(alpha: 0.6)
                : isConnecting
                    ? Colors.orangeAccent.withValues(alpha: 0.5)
                    : isLastUsed
                        ? Colors.cyan.withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.12),
            width: isConnected || isConnecting ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          // ── 아이콘 ────────────────
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected
                  ? Colors.green.withValues(alpha: 0.2)
                  : isConnecting
                      ? Colors.orange.withValues(alpha: 0.15)
                      : Colors.cyan.withValues(alpha: 0.1),
              border: Border.all(
                color: isConnected
                    ? Colors.greenAccent.withValues(alpha: 0.5)
                    : isConnecting
                        ? Colors.orangeAccent.withValues(alpha: 0.5)
                        : Colors.cyan.withValues(alpha: 0.3),
              ),
            ),
            child: isConnecting
                ? Padding(
                    padding: const EdgeInsets.all(14),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.orangeAccent,
                    ),
                  )
                : Icon(
                    isConnected ? Icons.bluetooth_connected : Icons.smart_toy,
                    color: isConnected
                        ? Colors.greenAccent
                        : Colors.cyanAccent,
                    size: 24,
                  ),
          ),

          const SizedBox(width: 14),

          // ── 기기 정보 ─────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 이름
                Text(
                  device.name,
                  style: TextStyle(
                    color: isConnected ? Colors.greenAccent : Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                // MAC 주소 (4자리 강조)
                _buildMacDisplay(device),
                if (isConnected)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '✓ 연결됨 · ${btManager.latencyMs}ms',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else if (isConnecting)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      '연결 중...',
                      style: TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── 배지 & 화살표 ─────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isLastUsed && !isConnected)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.cyan.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: Colors.cyan.withValues(alpha: 0.4)),
                  ),
                  child: const Text(
                    '최근',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (!isConnected && !isConnecting)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white.withValues(alpha: 0.3),
                    size: 14,
                  ),
                ),
            ],
          ),
        ]),
      ),
    );
  }

  // ── MAC 주소 표시 (4자리 강조) ────────────────────
  Widget _buildMacDisplay(BluetoothDeviceInfo device) {
    final full = device.address; // 예: 00:11:22:33:AA:BB
    final parts = full.split(':');

    if (parts.length < 6) {
      return Text(
        full,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.4),
          fontSize: 11,
          fontFamily: 'monospace',
        ),
      );
    }

    // 앞 4바이트: 흐리게 / 마지막 2바이트: 강조
    final prefix = parts.sublist(0, 4).join(':');
    final suffix = parts.sublist(4).join(':').toUpperCase();

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$prefix:',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          TextSpan(
            text: suffix,
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontSize: 13,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  // ── 하단 PIN 안내 ────────────────────────────────
  Widget _buildPinGuide() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(children: [
        Icon(Icons.lock_outline,
            color: Colors.white.withValues(alpha: 0.35), size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
              ),
              children: const [
                TextSpan(text: '최초 페어링 PIN: '),
                TextSpan(
                  text: '1234',
                  style: TextStyle(
                    color: Colors.cyanAccent,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                TextSpan(text: '  (또는 '),
                TextSpan(
                  text: '0000',
                  style: TextStyle(
                    color: Colors.white60,
                    fontFamily: 'monospace',
                  ),
                ),
                TextSpan(text: ')  — 스마트폰 블루투스 설정에서 1회만 진행'),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // ── 헬퍼 ─────────────────────────────────────────
  String _macSuffix(String mac) {
    final parts = mac.split(':');
    if (parts.length >= 2) {
      return '${parts[parts.length - 2]}:${parts[parts.length - 1]}'
          .toUpperCase();
    }
    return mac.toUpperCase();
  }

  Future<dynamic> _getPrefs() =>
      SharedPreferences.getInstance();

  void _openSystemBluetooth() {
    // Android 설정 앱 블루투스로 이동 (Intent)
    // flutter_bluetooth_serial에서 openSettings 지원
    FlutterBluetoothSerial.instance.openSettings();
  }
}
