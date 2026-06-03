import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../bluetooth/bluetooth_manager.dart';
import '../../services/robot_nickname_service.dart';
import '../control/control_screen.dart';

/// Bluetooth 스캔 & 연결 전용 화면
/// - 탭 1: 나의 로봇 — 페어링된 FB153 목록 (최근 연결 상단, 별명/아바타 편집)
/// - 탭 2: 미지정 로봇 — 이름 미지정 FB153 검색 (미페어링 기기 → 탭하면 페어링+연결)
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
  late TabController _tabCtrl;

  String? _connectingMac;

  @override
  void initState() {
    super.initState();

    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) setState(() {});
    });

    _pulseCtrl = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // 화면 진입 시 자동 스캔 (페어링 탭)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BluetoothManager>().startScan();
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  // ── 기기 선택 → 즉시 연결 ─────────────────────────
  Future<void> _connectTo(BluetoothDeviceInfo device) async {
    setState(() => _connectingMac = device.address);
    final btManager = context.read<BluetoothManager>();
    await btManager.connect(device);

    if (!mounted) return;

    if (btManager.isConnected) {
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
        Navigator.pop(context);
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

  // ── 로봇 프로필 편집 다이얼로그 ──────────────────────────────
  Future<void> _showNicknameDialog(
      BuildContext ctx, BluetoothDeviceInfo device) async {
    final nickSvc = ctx.read<RobotNicknameService>();
    await showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => _RobotProfileDialog(
        device: device,
        service: nickSvc,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final btManager = context.watch<BluetoothManager>();
    final scanning = btManager.isScanning;
    final discovering = btManager.isDiscovering;

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
              opacity: (scanning || discovering) ? _pulseAnim.value : 1.0,
              child: Icon(
                (scanning || discovering)
                    ? Icons.bluetooth_searching
                    : Icons.bluetooth,
                color: Colors.cyanAccent,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text('로봇 연결',
              style: TextStyle(color: Colors.white, fontSize: 16)),
        ]),
        actions: [
          // 탭에 따른 새로고침 버튼
          IconButton(
            icon: (scanning || discovering)
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.cyanAccent,
                    ),
                  )
                : const Icon(Icons.refresh, color: Colors.white70),
            onPressed: (scanning || discovering)
                ? null
                : () {
                    if (_tabCtrl.index == 0) {
                      btManager.startScan();
                    } else {
                      btManager.discoverDevices(context: context);
                    }
                  },
          ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.cyanAccent,
          labelColor: Colors.cyanAccent,
          unselectedLabelColor: Colors.white54,
          labelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.smart_toy, size: 16), text: '나의 로봇'),
            Tab(
                icon: Icon(Icons.bluetooth_searching, size: 16),
                text: '안 사귄 로봇'),
          ],
        ),
      ),

      body: TabBarView(
        controller: _tabCtrl,
        children: [
          // ── 탭 1: 나의 로봇 ────────────────────────
          _buildMyRobotsTab(btManager),
          // ── 탭 2: 미지정 로봇 검색 ─────────────────
          _buildDiscoveryTab(btManager),
        ],
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 탭 1: 나의 로봇 (페어링된 FB153, 최근 연결 상단)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Widget _buildMyRobotsTab(BluetoothManager btManager) {
    final devices = btManager.discoveredDevices;
    final scanning = btManager.isScanning;

    return Column(children: [
      _buildMyRobotsBanner(btManager),
      Expanded(
        child: scanning && devices.isEmpty
            ? _buildScanningIndicator(text: '나의 로봇 검색 중...')
            : devices.isEmpty
                ? _buildMyRobotsEmptyState(btManager)
                : _buildDeviceList(_filterMyRobots(devices, btManager), btManager, isPaired: true),
      ),
      _buildPinGuide(),
    ]);
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 탭 2: 미지정 로봇 (FB153 이름 포함된 미페어링 기기)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Widget _buildDiscoveryTab(BluetoothManager btManager) {
    // FB153 이름 포함된 기기만 필터링
    final allDevices = btManager.newDevices;
    final devices = allDevices.where((d) {
      final n = d.name.toLowerCase().replaceAll(' ', '');
      return n.contains('fb153') || n.contains('robot');
    }).toList();
    final discovering = btManager.isDiscovering;

    return Column(children: [
      // 안내 배너
      Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.purple.withValues(alpha: 0.15),
              Colors.blue.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.bluetooth_searching,
                  color: Colors.purpleAccent, size: 16),
              const SizedBox(width: 6),
              Text(
                '안 사귄 로봇 검색 (FB153)',
                style: TextStyle(
                  color: Colors.purpleAccent.withValues(alpha: 0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (allDevices.isNotEmpty) ...[   
                const Spacer(),
                Text(
                  'FB153: ${devices.length} / 전체: ${allDevices.length}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 10,
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 6),
            Text(
              '이름이 등록되지 않은 FB153 로봇을 검색합니다.\n탭하면 자동으로 페어링 후 연결됩니다.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),

      // 검색 시작 버튼
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: discovering
                  ? Colors.orange.withValues(alpha: 0.2)
                  : Colors.purple.withValues(alpha: 0.3),
              foregroundColor:
                  discovering ? Colors.orangeAccent : Colors.purpleAccent,
              side: BorderSide(
                  color: discovering
                      ? Colors.orangeAccent.withValues(alpha: 0.5)
                      : Colors.purple.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: discovering
                ? () => btManager.stopDiscovery()
                : () => btManager.discoverDevices(context: context),
            icon: Icon(
                discovering ? Icons.stop : Icons.bluetooth_searching,
                size: 18),
            label: Text(
              discovering ? '검색 중지' : '주변 기기 검색 시작',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),

      Expanded(
        child: discovering && devices.isEmpty
            ? _buildScanningIndicator(
                text: allDevices.isEmpty
                    ? 'FB153 로봇 검색 중...'
                    : 'FB153 로봇 검색 중... (전체 ${allDevices.length}개 발견)',
                subText: '로봇 전원을 켜고 근처에 두세요',
                color: Colors.purpleAccent,
              )
            : devices.isEmpty
                ? _buildDiscoveryEmptyState(
                    totalFound: allDevices.length)
                : _buildDeviceList(devices, btManager, isPaired: false),
      ),
    ]);
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 탭 1 배너 — 나의 로봇
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Widget _buildMyRobotsBanner(BluetoothManager btManager) {
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
              '길게 눌러 로봇 이름 짓기',
              style: TextStyle(
                color: Colors.cyanAccent.withValues(alpha: 0.9),
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            '기기 카드를 길게 누르면 별명·아바타·색상을 설정할 수 있습니다.',
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
                border:
                    Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
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
                    final prefs = await SharedPreferences.getInstance();
                    if (!mounted) return;
                    final lastName =
                        prefs.getString('last_connected_name') ?? 'fb153';
                    _connectTo(
                        BluetoothDeviceInfo(name: lastName, address: lastMac));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
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
  Widget _buildScanningIndicator({
    required String text,
    String? subText,
    Color color = Colors.cyanAccent,
  }) {
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
                    color: color.withValues(alpha: 0.6),
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.bluetooth_searching,
                  color: color,
                  size: 40,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
          if (subText != null) ...[
            const SizedBox(height: 8),
            Text(
              subText,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 기기 없을 때 (나의 로봇 탭) ─────────────────────
  Widget _buildMyRobotsEmptyState(BluetoothManager btManager) {
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
              '등록된 FB153 로봇이 없습니다',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: Column(children: [
                Row(children: [
                  const Icon(Icons.info_outline,
                      size: 14, color: Colors.amber),
                  const SizedBox(width: 6),
                  Text(
                    '기기 이름 확인',
                    style: TextStyle(
                      color: Colors.amber.withValues(alpha: 0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(
                  '스마트폰 BT 설정에서 FB153 로봇과 먼저 페어링하세요.\n아직 페어링 전이라면 "미지정 로봇" 탭에서 검색하세요.',
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('다시 스캔',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => btManager.startScan(),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white60,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.bluetooth_searching, size: 16),
              label: const Text('미지정 로봇 검색',
                  style: TextStyle(fontSize: 12)),
              onPressed: () {
                _tabCtrl.animateTo(1);
                btManager.discoverDevices(context: context);
              },
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

  // ── 기기 없을 때 (미지정 로봇 탭) ──────────────────
  Widget _buildDiscoveryEmptyState({int totalFound = 0}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off,
                size: 56, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text(
              totalFound > 0
                  ? 'FB153 로봇을 찾지 못했습니다'
                  : '주변 기기를 찾지 못했습니다',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              totalFound > 0
                  ? '다른 기기 $totalFound개가 발견됐지만\nFB153 이름의 로봇은 없습니다.\n로봇 전원을 켠 후 다시 검색하세요.'
                  : '검색 버튼을 눌러 로봇 전원을 켠 상태에서\nFB153 로봇을 검색하세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 기기 목록 ────────────────────────────────────
  Widget _buildDeviceList(
      List<BluetoothDeviceInfo> devices, BluetoothManager btManager,
      {required bool isPaired}) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Text(
              isPaired
                  ? '나의 FB153 로봇 ${devices.length}대'
                  : 'FB153 미지정 ${devices.length}대',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const Spacer(),
            Text(
              isPaired ? '탭: 연결   길게누름: 별명/아바타 편집' : '탭: 페어링 후 연결  · MAC 4자리 표시',
              style: TextStyle(
                color: Colors.cyanAccent.withValues(alpha: 0.5),
                fontSize: 10,
              ),
            ),
          ]),
        ),
        ...(() {
          // 별명 있는 기기 먼저, 그 다음 최근 연결, 나머지
          final nickSvc = context.read<RobotNicknameService>();
          final lastMac = btManager.lastMac;
          final sorted = List<BluetoothDeviceInfo>.from(devices)
            ..sort((a, b) {
              final aNick = nickSvc.hasNickname(a.address) ? 0 : 1;
              final bNick = nickSvc.hasNickname(b.address) ? 0 : 1;
              if (aNick != bNick) return aNick.compareTo(bNick);
              final aLast = a.address == lastMac ? 0 : 1;
              final bLast = b.address == lastMac ? 0 : 1;
              return aLast.compareTo(bLast);
            });
          return sorted.map((d) => _buildDeviceCard(d, btManager, isPaired: isPaired));
        })(),
      ],
    );
  }

  // ── 기기 카드 ────────────────────────────────────
  Widget _buildDeviceCard(
      BluetoothDeviceInfo device, BluetoothManager btManager,
      {required bool isPaired}) {
    final isConnecting = _connectingMac == device.address;
    final isConnected = btManager.connectedDevice?.address == device.address;
    final isLastUsed = btManager.lastMac == device.address;

    return Consumer<RobotNicknameService>(
      builder: (ctx, nickSvc, _) {
        final displayName =
            nickSvc.displayName(device.address, device.name);
        final hasNick = nickSvc.hasNickname(device.address);

        return GestureDetector(
          onTap: (isConnecting || isConnected)
              ? null
              : () => _connectTo(device),
          onLongPress: () {
            HapticFeedback.mediumImpact();
            _showNicknameDialog(ctx, device);
          },
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
              // ── 아바타 아이콘 ─────────
              isConnecting
                ? Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.orange.withValues(alpha: 0.15),
                      border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.5)),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orangeAccent),
                    ),
                  )
                : isConnected
                  ? Container(
                      width: 50, height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.green.withValues(alpha: 0.2),
                        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5)),
                      ),
                      child: const Icon(Icons.bluetooth_connected, color: Colors.greenAccent, size: 24),
                    )
                  : RobotAvatarWidget(mac: device.address, service: nickSvc, size: 50),

              const SizedBox(width: 14),

              // ── 기기 정보 ─────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isPaired) ...
                      // ━━ 미지정 로봇: MAC 4자리 크게 중앙 표시 ━━
                      _buildUnnamedRobotInfo(device, isConnected, isConnecting)
                    else ...
                      // ━━ 나의 로봇: 별명/이름 + MAC + 최근 연결 강조 ━━
                      [
                    // 별명 또는 기기명
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            style: TextStyle(
                              color: isConnected
                                  ? Colors.greenAccent
                                  : hasNick
                                      ? Colors.cyanAccent
                                      : Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasNick)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.cyanAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                  color: Colors.cyanAccent
                                      .withValues(alpha: 0.4)),
                            ),
                            child: const Text(
                              '별명',
                              style: TextStyle(
                                  color: Colors.cyanAccent,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // 별명이 있으면 원래 이름도 작게 표시
                    if (hasNick)
                      Text(
                        device.name,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.35),
                          fontSize: 10,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 2),
                    // MAC 주소
                    _buildMacDisplay(device),
                    // 연결 상태
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
                    ],  // end 나의 로봇 else
                  ],
                ),
              ),

              // ── 배지 & 화살표 ─────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // #17: 배지 중복 제거 — 우측엔 '최근' 배지만 1개
                  if (isLastUsed && !isConnected)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: Colors.greenAccent.withValues(alpha: 0.5)),
                      ),
                      child: const Text('최근',
                          style: TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 9,
                              fontWeight: FontWeight.bold)),
                    ),
                  if (!isPaired && !isConnected && !isConnecting)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: Colors.purpleAccent.withValues(alpha: 0.5)),
                        ),
                        child: const Text('미페어링',
                            style: TextStyle(
                              color: Colors.purpleAccent,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            )),
                      ),
                    ),
                  if (!isConnected && !isConnecting)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Icon(Icons.arrow_forward_ios,
                          color: Colors.white.withValues(alpha: 0.3), size: 14),
                    ),
                ],
              ),
            ]),
          ),
        );
      },
    );
  }

  // ── 미지정 로봇 카드 정보: MAC 4자리 크게 표시 ─────
  List<Widget> _buildUnnamedRobotInfo(
      BluetoothDeviceInfo device, bool isConnected, bool isConnecting) {
    final parts = device.address.split(':');
    final mac4 = parts.length >= 2
        ? '${parts[parts.length - 2]}:${parts[parts.length - 1]}'.toUpperCase()
        : device.address.toUpperCase();

    // RSSI 신호 강도 아이콘
    IconData rssiIcon;
    Color rssiColor;
    final rssi = device.rssi;
    if (rssi >= -60) {
      rssiIcon = Icons.signal_cellular_alt;
      rssiColor = Colors.greenAccent;
    } else if (rssi >= -80) {
      rssiIcon = Icons.signal_cellular_alt_2_bar;
      rssiColor = Colors.orangeAccent;
    } else {
      rssiIcon = Icons.signal_cellular_alt_1_bar;
      rssiColor = Colors.redAccent;
    }

    return [
      // FB153 이름 (작게)
      Text(
        device.name,
        style: TextStyle(
          color: isConnected ? Colors.greenAccent : Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: 4),
      // MAC 4자리 크게 강조
      Row(
        children: [
          Text(
            mac4,
            style: TextStyle(
              color: isConnected
                  ? Colors.greenAccent
                  : isConnecting
                      ? Colors.orangeAccent
                      : Colors.cyanAccent,
              fontSize: 20,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
      const SizedBox(height: 3),
      // RSSI + 전체 MAC (아주 작게)
      Row(
        children: [
          if (rssi != 0) ...[
            Icon(rssiIcon, color: rssiColor, size: 11),
            const SizedBox(width: 3),
            Text(
              '${rssi}dBm',
              style: TextStyle(
                color: rssiColor,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            device.address.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.25),
              fontSize: 9,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
      if (isConnected)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '✓ 연결됨',
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
    ]; // end _buildUnnamedRobotInfo
  }

  // ── MAC 주소 표시 (4자리 강조) ────────────────────
  Widget _buildMacDisplay(BluetoothDeviceInfo device) {
    final full = device.address;
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
  /// #6: 나의 로봇 탭 — 별명 있거나 최근 연결된 기기만 표시
  List<BluetoothDeviceInfo> _filterMyRobots(
      List<BluetoothDeviceInfo> devices, BluetoothManager btManager) {
    final nickSvc = context.read<RobotNicknameService>();
    final lastMac = btManager.lastMac;
    return devices.where((d) {
      final hasNick = nickSvc.hasNickname(d.address);
      final isLast = d.address == lastMac;
      return hasNick || isLast;
    }).toList();
  }

  String _macSuffix(String mac) {
    final parts = mac.split(':');
    if (parts.length >= 2) {
      return '${parts[parts.length - 2]}:${parts[parts.length - 1]}'
          .toUpperCase();
    }
    return mac.toUpperCase();
  }

  void _openSystemBluetooth() {
    const platform = MethodChannel('com.robocommander/bluetooth');
    platform.invokeMethod<void>('openBluetoothSettings').catchError((_) {});
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 로봇 프로필 편집 다이얼로그 (별명 + 아바타 아이콘 + 색상 + 사진)
// ══════════════════════════════════════════════════════════════════════════════
class _RobotProfileDialog extends StatefulWidget {
  final BluetoothDeviceInfo device;
  final RobotNicknameService service;

  const _RobotProfileDialog({required this.device, required this.service});

  @override
  State<_RobotProfileDialog> createState() => _RobotProfileDialogState();
}

class _RobotProfileDialogState extends State<_RobotProfileDialog> {
  late TextEditingController _nameCtrl;
  late int _iconIndex;
  late int _colorValue;
  late RobotAvatarType _avatarType;
  late String? _photoPath;

  // 팔레트 색상
  static const _palette = [
    0xFF00BCD4, // cyan
    0xFF4CAF50, // green
    0xFFFF9800, // orange
    0xFF9C27B0, // purple
    0xFFF44336, // red
    0xFF2196F3, // blue
    0xFFFFEB3B, // yellow
    0xFFE91E63, // pink
    0xFF607D8B, // blue-grey
    0xFFFFFFFF, // white
  ];

  @override
  void initState() {
    super.initState();
    final mac = widget.device.address;
    final svc = widget.service;
    _nameCtrl = TextEditingController(text: svc.getNickname(mac) ?? '');
    _iconIndex = svc.getAvatarIconIndex(mac);
    _colorValue = svc.getAvatarColor(mac);
    _avatarType = svc.getAvatarType(mac);
    _photoPath = svc.getPhotoPath(mac);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // ── 아바타 사진 소스 선택 바텀시트 ─────────────────────
  Future<void> _showPhotoSourceSheet() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF0D1F2D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 핸들
              Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                '아바타 사진 선택',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              // 카메라 촬영
              ListTile(
                leading: Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.camera_alt, color: Colors.cyanAccent, size: 20),
                ),
                title: const Text('카메라로 촬영',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: Text('지금 바로 로봇을 찍어 아바타로 사용',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              const Divider(color: Colors.white12, height: 1),
              // 갤러리 선택
              ListTile(
                leading: Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: Colors.purpleAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.photo_library, color: Colors.purpleAccent, size: 20),
                ),
                title: const Text('갤러리에서 선택',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: Text('저장된 사진에서 아바타 선택',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 11)),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              const SizedBox(height: 4),
              // 취소
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('취소',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13)),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;
    await _pickPhotoFrom(source);
  }

  // ── 실제 이미지 선택/촬영 ────────────────────────────
  Future<void> _pickPhotoFrom(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (picked != null) {
        setState(() {
          _photoPath = picked.path;
          _avatarType = RobotAvatarType.photo;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              source == ImageSource.camera
                  ? '카메라를 사용할 수 없습니다. 권한을 확인하세요.'
                  : '갤러리를 열 수 없습니다. 권한을 확인하세요.',
            ),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _save() async {
    await widget.service.setProfile(
      widget.device.address,
      nickname: _nameCtrl.text.trim(),
      iconIndex: _iconIndex,
      colorValue: _colorValue,
      photoPath: _avatarType == RobotAvatarType.photo ? _photoPath : null,
      avatarType: _avatarType,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final hasExisting = widget.service.hasNickname(widget.device.address);
    final avatarColor = Color(_colorValue);

    return Dialog(
      backgroundColor: const Color(0xFF0D1F2D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 헤더 ─────────────────────────────────────────────
            Row(children: [
              const Icon(Icons.edit_note, color: Colors.cyanAccent, size: 22),
              const SizedBox(width: 8),
              const Text('로봇 이름 짓기',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              '${widget.device.name}  [${widget.device.macSuffix}]',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 11,
                  fontFamily: 'monospace'),
            ),

            const SizedBox(height: 18),

            // ── 미리보기 ──────────────────────────────────────────
            Center(
              child: Column(children: [
                // 아바타 미리보기
                _buildPreviewAvatar(avatarColor),
                const SizedBox(height: 8),
                Text(
                  _nameCtrl.text.isEmpty
                      ? widget.device.name
                      : _nameCtrl.text,
                  style: TextStyle(
                    color: avatarColor,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ]),
            ),

            const SizedBox(height: 18),

            // ── 이름 입력 ─────────────────────────────────────────
            TextField(
              controller: _nameCtrl,
              maxLength: 16,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: '예) 내 로봇, 거실봇...',
                hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.cyan.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.cyanAccent),
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
                counterStyle:
                    TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                prefixIcon:
                    const Icon(Icons.drive_file_rename_outline, color: Colors.cyanAccent, size: 18),
              ),
            ),

            const SizedBox(height: 14),

            // ── 아바타 선택 ───────────────────────────────────────
            Text('아바타 선택',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),

            // 아이콘 6개 + 사진 버튼
            SizedBox(
              height: 60,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  // 아이콘 6종
                  ...List.generate(kAvatarIcons.length, (i) {
                    final selected =
                        _avatarType == RobotAvatarType.icon && _iconIndex == i;
                    return GestureDetector(
                      onTap: () => setState(() {
                        _iconIndex = i;
                        _avatarType = RobotAvatarType.icon;
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 56,
                        height: 56,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected
                              ? avatarColor.withValues(alpha: 0.25)
                              : Colors.white.withValues(alpha: 0.06),
                          border: Border.all(
                            color: selected
                                ? avatarColor
                                : Colors.white.withValues(alpha: 0.2),
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Icon(
                          RobotAvatarWidget.iconDataFromName(kAvatarIcons[i]),
                          color: selected ? avatarColor : Colors.white54,
                          size: 26,
                        ),
                      ),
                    );
                  }),

                  // 사진/카메라 선택 버튼
                  GestureDetector(
                    onTap: _showPhotoSourceSheet,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 56,
                      height: 56,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _avatarType == RobotAvatarType.photo
                            ? Colors.orange.withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.06),
                        border: Border.all(
                          color: _avatarType == RobotAvatarType.photo
                              ? Colors.orangeAccent
                              : Colors.white.withValues(alpha: 0.2),
                          width: _avatarType == RobotAvatarType.photo ? 2 : 1,
                        ),
                      ),
                      child: _photoPath != null && File(_photoPath!).existsSync()
                          ? ClipOval(
                              child: Image.file(
                                File(_photoPath!),
                                fit: BoxFit.cover,
                                width: 56,
                                height: 56,
                              ),
                            )
                          : Stack(
                              alignment: Alignment.center,
                              children: [
                                const Icon(Icons.add_a_photo, color: Colors.white54, size: 22),
                                Positioned(
                                  bottom: 6,
                                  right: 6,
                                  child: Container(
                                    width: 14, height: 14,
                                    decoration: BoxDecoration(
                                      color: Colors.cyanAccent.withValues(alpha: 0.9),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.add, color: Colors.black, size: 10),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── 색상 선택 ─────────────────────────────────────────
            Text('색상',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _palette.map((c) {
                final selected = _colorValue == c;
                return GestureDetector(
                  onTap: () => setState(() => _colorValue = c),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(c),
                      border: selected
                          ? Border.all(color: Colors.white, width: 2.5)
                          : Border.all(
                              color: Colors.white.withValues(alpha: 0.2)),
                      boxShadow: selected
                          ? [BoxShadow(
                              color: Color(c).withValues(alpha: 0.6),
                              blurRadius: 8)]
                          : null,
                    ),
                    child: selected
                        ? const Icon(Icons.check, color: Colors.black, size: 16)
                        : null,
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 22),

            // ── 버튼 ──────────────────────────────────────────────
            Row(children: [
              if (hasExisting)
                TextButton(
                  onPressed: () async {
                    await widget.service.removeProfile(widget.device.address);
                    if (mounted) Navigator.pop(context);
                  },
                  child: const Text('초기화',
                      style: TextStyle(color: Colors.redAccent)),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('취소',
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: 0.5))),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _save,
                icon: const Icon(Icons.save, size: 16),
                label: const Text('저장',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewAvatar(Color color) {
    if (_avatarType == RobotAvatarType.photo &&
        _photoPath != null &&
        File(_photoPath!).existsSync()) {
      return CircleAvatar(
        radius: 36,
        backgroundImage: FileImage(File(_photoPath!)),
      );
    }
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 12)
        ],
      ),
      child: Icon(
        RobotAvatarWidget.iconDataFromName(
            kAvatarIcons[_iconIndex < kAvatarIcons.length ? _iconIndex : 0]),
        color: color,
        size: 36,
      ),
    );
  }
}
