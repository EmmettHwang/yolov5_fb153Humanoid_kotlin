import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../bluetooth/bluetooth_manager.dart';
import '../../services/robot_nickname_service.dart';
import '../control/control_screen.dart';

/// Bluetooth 스캔 & 연결 전용 화면
/// - 탭 1: 페어링된 기기 목록 (별명 표시/편집)
/// - 탭 2: 새 기기 검색 (미페어링 기기 발견 → 바로 연결)
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

  // ── 별명 편집 다이얼로그 ─────────────────────────────
  Future<void> _showNicknameDialog(
      BuildContext ctx, BluetoothDeviceInfo device) async {
    final nickSvc = ctx.read<RobotNicknameService>();
    final current = nickSvc.getNickname(device.address) ?? '';
    final controller = TextEditingController(text: current);

    await showDialog<void>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1F2D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.edit, color: Colors.cyanAccent, size: 20),
          const SizedBox(width: 8),
          const Text('로봇 이름 짓기',
              style: TextStyle(color: Colors.white, fontSize: 16)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 원래 이름 표시
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(children: [
                Icon(Icons.bluetooth,
                    size: 13, color: Colors.white.withValues(alpha: 0.4)),
                const SizedBox(width: 6),
                Text(
                  '${device.name}  [${device.macSuffix}]',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 16,
              style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: '예) 내 로봇1, 거실로봇...',
                hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
                enabledBorder: OutlineInputBorder(
                  borderSide:
                      BorderSide(color: Colors.cyan.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.cyanAccent),
                  borderRadius: BorderRadius.circular(10),
                ),
                counterStyle:
                    TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                prefixIcon: const Icon(Icons.smart_toy,
                    color: Colors.cyanAccent, size: 18),
              ),
            ),
          ],
        ),
        actions: [
          // 별명 삭제 버튼 (기존 별명 있을 때만)
          if (current.isNotEmpty)
            TextButton(
              onPressed: () async {
                await nickSvc.removeNickname(device.address);
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              },
              child: const Text('삭제',
                  style: TextStyle(color: Colors.redAccent, fontSize: 13)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('취소',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyanAccent,
              foregroundColor: Colors.black,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              await nickSvc.setNickname(device.address, controller.text);
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
            },
            child: const Text('저장',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ],
      ),
    );
    controller.dispose();
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
            Tab(icon: Icon(Icons.bluetooth, size: 16), text: '페어링된 기기'),
            Tab(
                icon: Icon(Icons.bluetooth_searching, size: 16),
                text: '새 기기 검색'),
          ],
        ),
      ),

      body: TabBarView(
        controller: _tabCtrl,
        children: [
          // ── 탭 1: 페어링된 기기 ──────────────────────
          _buildPairedTab(btManager),
          // ── 탭 2: 새 기기 검색 ──────────────────────
          _buildDiscoveryTab(btManager),
        ],
      ),
    );
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 탭 1: 페어링된 기기
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Widget _buildPairedTab(BluetoothManager btManager) {
    final devices = btManager.discoveredDevices;
    final scanning = btManager.isScanning;

    return Column(children: [
      _buildInfoBanner(btManager),
      Expanded(
        child: scanning && devices.isEmpty
            ? _buildScanningIndicator(text: '페어링된 기기 검색 중...')
            : devices.isEmpty
                ? _buildEmptyState(btManager)
                : _buildDeviceList(devices, btManager, isPaired: true),
      ),
      _buildPinGuide(),
    ]);
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 탭 2: 새 기기 검색 (미페어링)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Widget _buildDiscoveryTab(BluetoothManager btManager) {
    final devices = btManager.newDevices;
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
              const Icon(Icons.search, color: Colors.purpleAccent, size: 16),
              const SizedBox(width: 6),
              Text(
                '블루투스 기기 검색',
                style: TextStyle(
                  color: Colors.purpleAccent.withValues(alpha: 0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              '페어링 없이 근처 기기를 검색합니다.\n발견된 기기를 탭하면 자동으로 페어링 후 연결합니다.',
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
                text: '주변 기기 검색 중...',
                subText: '로봇 전원을 켜고 근처에 두세요',
                color: Colors.purpleAccent,
              )
            : devices.isEmpty
                ? _buildDiscoveryEmptyState()
                : _buildDeviceList(devices, btManager, isPaired: false),
      ),
    ]);
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
            '기기 카드를 길게 누르면 내 로봇에게\n원하는 이름을 붙여줄 수 있습니다.',
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

  // ── 기기 없을 때 (페어링 탭) ────────────────────────
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
                  '안드로이드 BT 설정의 기기 이름이\n"FB153 v1.0.0" 형태인지 확인하세요.\n미페어링 기기는 "새 기기 검색" 탭을 이용하세요.',
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
              icon: const Icon(Icons.list, size: 16),
              label: const Text('전체 기기 보기',
                  style: TextStyle(fontSize: 12)),
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

  // ── 기기 없을 때 (검색 탭) ────────────────────────
  Widget _buildDiscoveryEmptyState() {
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
              '주변 기기를 찾지 못했습니다',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '"주변 기기 검색 시작" 버튼을 눌러\n로봇 전원을 켠 상태에서 검색하세요.',
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
                  ? '페어링된 기기 ${devices.length}개'
                  : '발견된 기기 ${devices.length}개',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const Spacer(),
            Text(
              isPaired ? '탭: 연결   길게누름: 이름 편집' : '탭: 페어링 후 연결',
              style: TextStyle(
                color: Colors.cyanAccent.withValues(alpha: 0.5),
                fontSize: 10,
              ),
            ),
          ]),
        ),
        ...devices.map(
            (d) => _buildDeviceCard(d, btManager, isPaired: isPaired)),
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
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.orangeAccent,
                        ),
                      )
                    : Icon(
                        isConnected
                            ? Icons.bluetooth_connected
                            : Icons.smart_toy,
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
                        '${device.name}',
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
                  ],
                ),
              ),

              // ── 배지 & 화살표 ─────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isLastUsed && !isConnected)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
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
                              color: Colors.purpleAccent
                                  .withValues(alpha: 0.5)),
                        ),
                        child: const Text(
                          '미페어링',
                          style: TextStyle(
                            color: Colors.purpleAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
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
      },
    );
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
