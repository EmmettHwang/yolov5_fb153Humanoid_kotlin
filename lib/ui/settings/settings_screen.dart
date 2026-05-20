import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../bluetooth/bluetooth_manager.dart';
import '../../command/command_set_manager.dart';
import '../../models/action_button_config.dart';
import 'button_editor_dialog.dart';
import '../bluetooth/bluetooth_scan_screen.dart';

/// 설정 화면
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060E18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1F2D),
        title: const Row(
          children: [
            Icon(Icons.settings, color: Colors.cyanAccent, size: 20),
            SizedBox(width: 8),
            Text(
              '설정',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.cyanAccent,
          unselectedLabelColor: Colors.white54,
          indicatorColor: Colors.cyanAccent,
          tabs: const [
            Tab(icon: Icon(Icons.bluetooth, size: 16), text: 'Bluetooth'),
            Tab(icon: Icon(Icons.gamepad, size: 16), text: '버튼 설정'),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Bluetooth 탭 → 전용 스캔 화면 임베드
          const BluetoothScanScreen(isFirstLaunch: false),
          _ButtonConfigTab(),
        ],
      ),
    );
  }
}

/// Bluetooth 연결 탭
class _BluetoothTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final btManager = context.watch<BluetoothManager>();

    return Column(
      children: [
        // 현재 연결 상태
        _buildConnectionStatus(context, btManager),

        // 스캔 버튼
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                '페어링된 기기',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                icon: btManager.connectionState == BtConnectionState.scanning
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.refresh, size: 14),
                label: Text(
                  btManager.connectionState == BtConnectionState.scanning
                      ? '스캔 중...'
                      : '새로고침',
                  style: const TextStyle(fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: btManager.connectionState == BtConnectionState.scanning
                    ? null
                    : () => btManager.startScan(),
              ),
            ],
          ),
        ),

        // 기기 목록
        Expanded(
          child: btManager.discoveredDevices.isEmpty
              ? _buildEmptyDeviceList()
              : ListView.builder(
                  itemCount: btManager.discoveredDevices.length,
                  itemBuilder: (context, index) {
                    final device = btManager.discoveredDevices[index];
                    final isConnected =
                        btManager.connectedDevice?.address == device.address;
                    return _DeviceTile(
                      device: device,
                      isConnected: isConnected,
                      onTap: () => isConnected
                          ? btManager.disconnect()
                          : btManager.connect(device),
                    );
                  },
                ),
        ),

        // 안내 텍스트
        Padding(
          padding: const EdgeInsets.all(16),
          child: _buildInfo(),
        ),
      ],
    );
  }

  Widget _buildConnectionStatus(BuildContext context, BluetoothManager btManager) {
    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (btManager.connectionState) {
      case BtConnectionState.connected:
        statusColor = Colors.greenAccent;
        statusText = '연결됨: ${btManager.connectedDevice?.name ?? '-'}';
        statusIcon = Icons.bluetooth_connected;
        break;
      case BtConnectionState.connecting:
        statusColor = Colors.orangeAccent;
        statusText = '연결 중...';
        statusIcon = Icons.bluetooth_searching;
        break;
      case BtConnectionState.scanning:
        statusColor = Colors.blueAccent;
        statusText = '스캔 중...';
        statusIcon = Icons.bluetooth_searching;
        break;
      case BtConnectionState.error:
        statusColor = Colors.redAccent;
        statusText = btManager.errorMessage ?? '오류 발생';
        statusIcon = Icons.error_outline;
        break;
      default:
        statusColor = Colors.white38;
        statusText = '연결 안됨';
        statusIcon = Icons.bluetooth_disabled;
    }

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(color: statusColor, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          if (btManager.isConnected)
            TextButton(
              onPressed: () => btManager.disconnect(),
              child: const Text(
                '연결 해제',
                style: TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyDeviceList() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bluetooth_disabled, size: 48, color: Colors.white24),
          const SizedBox(height: 16),
          Text(
            '기기를 찾을 수 없습니다',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            'fb153 로봇의 전원을 켜고\n스마트폰과 먼저 페어링하세요',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white24, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Colors.blueAccent, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '설정 → Bluetooth에서 fb153 로봇을 먼저 페어링한 후 이 화면에서 연결하세요.\nSPP UUID: 00001101-0000-1000-8000-00805F9B34FB',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 기기 목록 타일
class _DeviceTile extends StatelessWidget {
  final BluetoothDeviceInfo device;
  final bool isConnected;
  final VoidCallback onTap;

  const _DeviceTile({
    required this.device,
    required this.isConnected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isFb153 = device.name.toLowerCase().contains('fb153');
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isConnected
              ? Colors.green.withValues(alpha: 0.2)
              : isFb153
                  ? Colors.cyan.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          isFb153 ? Icons.smart_toy : Icons.bluetooth,
          color: isConnected
              ? Colors.greenAccent
              : isFb153
                  ? Colors.cyanAccent
                  : Colors.white38,
          size: 20,
        ),
      ),
      title: Text(
        device.name,
        style: TextStyle(
          color: isConnected ? Colors.greenAccent : Colors.white,
          fontWeight: isFb153 ? FontWeight.bold : FontWeight.normal,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        device.address,
        style: TextStyle(color: Colors.white38, fontSize: 11),
      ),
      trailing: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isConnected
              ? Colors.redAccent.withValues(alpha: 0.8)
              : Colors.cyanAccent,
          foregroundColor: isConnected ? Colors.white : Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          minimumSize: const Size(70, 30),
        ),
        onPressed: onTap,
        child: Text(
          isConnected ? '해제' : '연결',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

/// 버튼 설정 탭
class _ButtonConfigTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cmdManager = context.watch<CommandSetManager>();

    return Column(
      children: [
        // 초기화 버튼
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                '버튼 명령어 설정',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.restore, size: 14),
                label: const Text('기본값', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.orangeAccent,
                ),
                onPressed: () => _confirmReset(context, cmdManager),
              ),
            ],
          ),
        ),

        // 버튼 설정 목록
        Expanded(
          child: ListView.builder(
            itemCount: 9,
            itemBuilder: (context, index) {
              final config = cmdManager.getConfig(index + 1);
              return _ButtonConfigTile(
                config: config,
                onEdit: () => showDialog(
                  context: context,
                  builder: (_) => ChangeNotifierProvider.value(
                    value: cmdManager,
                    child: ButtonEditorDialog(config: config),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _confirmReset(BuildContext context, CommandSetManager manager) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1F2D),
        title: const Text('초기화', style: TextStyle(color: Colors.white)),
        content: const Text(
          '모든 버튼 설정을 기본값으로 초기화하시겠습니까?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
            ),
            onPressed: () {
              manager.resetToDefaults();
              Navigator.pop(context);
            },
            child: const Text('초기화'),
          ),
        ],
      ),
    );
  }
}

class _ButtonConfigTile extends StatelessWidget {
  final ActionButtonConfig config;
  final VoidCallback onEdit;

  const _ButtonConfigTile({required this.config, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Color(config.color),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            '${config.id}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      ),
      title: Text(
        config.label,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      subtitle: Text(
        '모션 ${config.motionIndex} · 시퀀스 ${config.commandSequence.length}단계',
        style: TextStyle(color: Colors.white38, fontSize: 11),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.edit, color: Colors.cyanAccent, size: 20),
        onPressed: onEdit,
      ),
    );
  }
}
