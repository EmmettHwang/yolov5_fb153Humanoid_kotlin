import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../bluetooth/bluetooth_manager.dart';
import '../../command/command_set_manager.dart';
import '../../models/action_button_config.dart';
import '../../services/robot_name_service.dart';
import 'button_editor_dialog.dart';
import '../bluetooth/bluetooth_scan_screen.dart';

/// 설정 화면 (Bluetooth / 버튼 설정 / 로봇 이름)
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
    _tabController = TabController(length: 3, vsync: this);
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
            Tab(icon: Icon(Icons.smart_toy, size: 16), text: '로봇 이름'),
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
          const BluetoothScanScreen(isFirstLaunch: false),
          _ButtonConfigTab(),
          const _RobotNameTab(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 로봇 이름 설정 탭
// ─────────────────────────────────────────────────────────────────────────────
class _RobotNameTab extends StatefulWidget {
  const _RobotNameTab();

  @override
  State<_RobotNameTab> createState() => _RobotNameTabState();
}

class _RobotNameTabState extends State<_RobotNameTab> {
  late TextEditingController _nameCtrl;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final currentName = context.read<RobotNameService>().name;
    _nameCtrl = TextEditingController(text: currentName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final name = _nameCtrl.text.trim();
    await context.read<RobotNameService>().setName(name);
    setState(() => _saved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _saved = false);
    });
    if (!mounted) return;
    final displayName = name.isEmpty ? RobotNameService.defaultName : name;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text('로봇 이름이 "$displayName"으로 변경되었습니다'),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _resetName() {
    _nameCtrl.text = RobotNameService.defaultName;
    _saveName();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 안내 카드
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.cyan.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.cyan.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    color: Colors.cyanAccent, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '헤더에 표시되는 로봇 이름을 원하는 이름으로 바꿀 수 있습니다.\n앱 재시작 후에도 유지됩니다.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // 현재 이름 미리보기
          Center(
            child: Consumer<RobotNameService>(
              builder: (context, svc, _) => Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1F2D),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.cyanAccent.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.smart_toy,
                            color: Colors.cyanAccent, size: 24),
                        const SizedBox(width: 10),
                        Text(
                          svc.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '현재 헤더 표시',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 28),

          // 이름 입력 필드
          Text(
            '새 이름 입력',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            maxLength: 20,
            decoration: InputDecoration(
              hintText: '예: ROBO, MyBot, fb153...',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
              filled: true,
              fillColor: const Color(0xFF0D1F2D),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.2)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.cyanAccent),
              ),
              counterStyle:
                  TextStyle(color: Colors.white.withValues(alpha: 0.4)),
              prefixIcon: const Icon(Icons.edit, color: Colors.cyanAccent, size: 20),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear, color: Colors.white38, size: 18),
                onPressed: () => _nameCtrl.clear(),
              ),
            ),
            onSubmitted: (_) => _saveName(),
          ),

          const SizedBox(height: 20),

          // 저장 버튼
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: Icon(
                _saved ? Icons.check : Icons.save,
                size: 18,
              ),
              label: Text(
                _saved ? '저장 완료!' : '이름 저장',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _saved ? Colors.greenAccent : Colors.cyanAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _saveName,
            ),
          ),

          const SizedBox(height: 12),

          // 기본값으로 재설정
          const SizedBox(height: 0), // spacer
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.restore, size: 16),
              label: Text(
                '기본값으로 재설정 (${RobotNameService.defaultName})',
                style: const TextStyle(fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orangeAccent,
                side: BorderSide(
                    color: Colors.orangeAccent.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _resetName,
            ),
          ),

          const SizedBox(height: 40),

          // 팁 섹션
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '💡 이름 팁',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _tipRow('영문, 숫자, 한글 모두 사용 가능'),
                _tipRow('최대 20자까지 입력 가능'),
                _tipRow('공백만 입력하면 기본값(ROBO)으로 설정됨'),
                _tipRow('TTS 인사말에도 새 이름이 반영됩니다'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tipRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.only(right: 8, top: 2),
            decoration: const BoxDecoration(
              color: Colors.cyanAccent,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 버튼 설정 탭
// ─────────────────────────────────────────────────────────────────────────────
class _ButtonConfigTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cmdManager = context.watch<CommandSetManager>();

    return Column(
      children: [
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
            child:
                const Text('취소', style: TextStyle(color: Colors.white54)),
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
        style: const TextStyle(color: Colors.white38, fontSize: 11),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.edit, color: Colors.cyanAccent, size: 20),
        onPressed: onEdit,
      ),
    );
  }
}

// ignore: unused_element
class _BluetoothTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final btManager = context.watch<BluetoothManager>();
    return Center(
      child: Text(
        btManager.isConnected ? '연결됨' : '미연결',
        style: const TextStyle(color: Colors.white),
      ),
    );
  }
}
