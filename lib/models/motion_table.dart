/// fb153 휴머노이드 로봇 모션 테이블
/// 출처: MRT R&D Center Motion Table PDF
///
/// 구조: motionIndex → MotionInfo(name, mode, desc)
class MotionInfo {
  final int index;
  final String name;    // 모션 이름 (영문)
  final String mode;    // 모드 그룹
  final String desc;    // 한국어 설명

  const MotionInfo({
    required this.index,
    required this.name,
    required this.mode,
    required this.desc,
  });

  @override
  String toString() => '$index: $name ($desc)';
}

class MotionTable {
  MotionTable._();

  /// 전체 모션 목록 (인덱스 순)
  static const List<MotionInfo> all = [
    // ── [M0] Basic ─────────────────────────────────────────────────────────
    MotionInfo(index:   1, name: 'Ready',        mode: 'Basic',      desc: '준비'),
    MotionInfo(index:   2, name: 'ST F',         mode: 'Basic',      desc: '전진 시작'),
    MotionInfo(index:   3, name: 'Loop',         mode: 'Basic',      desc: '전진 루프'),
    MotionInfo(index:   4, name: 'End',          mode: 'Basic',      desc: '전진 종료'),
    MotionInfo(index:   5, name: 'Left',         mode: 'Basic',      desc: '좌이동'),
    MotionInfo(index:   6, name: 'Right',        mode: 'Basic',      desc: '우이동'),
    MotionInfo(index:   7, name: 'Turn L',       mode: 'Basic',      desc: '좌회전'),
    MotionInfo(index:   8, name: 'Turn R',       mode: 'Basic',      desc: '우회전'),
    MotionInfo(index:   9, name: 'ST B',         mode: 'Basic',      desc: '후진 시작'),
    MotionInfo(index:  10, name: 'End B',        mode: 'Basic',      desc: '후진 종료'),
    MotionInfo(index:  11, name: 'Loop B',       mode: 'Basic',      desc: '후진 루프'),
    // ── [M0] Front ─────────────────────────────────────────────────────────
    MotionInfo(index:  12, name: 'L Forward',    mode: 'Front',      desc: '좌전방'),
    MotionInfo(index:  13, name: 'R Forward',    mode: 'Front',      desc: '우전방'),
    MotionInfo(index:  14, name: 'Getup F',      mode: 'Front',      desc: '앞 기상'),
    MotionInfo(index:  15, name: 'Getup B',      mode: 'Front',      desc: '뒤 기상'),
    MotionInfo(index:  16, name: 'Lose1',        mode: 'Front',      desc: '패배'),
    MotionInfo(index:  17, name: 'Win1',         mode: 'Front',      desc: '승리'),
    MotionInfo(index:  18, name: 'Hi',           mode: 'Front',      desc: '인사'),
    MotionInfo(index:  19, name: 'Bow1',         mode: 'Front',      desc: '절'),
    MotionInfo(index:  20, name: 'Tumble F',     mode: 'Front',      desc: '앞구르기'),
    MotionInfo(index:  21, name: 'Tumble B',     mode: 'Front',      desc: '뒤구르기'),
    // ── [M1] Fight ─────────────────────────────────────────────────────────
    MotionInfo(index:  22, name: 'Ready',        mode: 'Fight',      desc: '공격 준비'),
    MotionInfo(index:  23, name: 'Defence',      mode: 'Fight',      desc: '방어'),
    MotionInfo(index:  24, name: 'Forward',      mode: 'Fight',      desc: '전진 공격'),
    MotionInfo(index:  25, name: 'Back',         mode: 'Fight',      desc: '후진 공격'),
    MotionInfo(index:  26, name: 'Left',         mode: 'Fight',      desc: '좌이동 공격'),
    MotionInfo(index:  27, name: 'Right',        mode: 'Fight',      desc: '우이동 공격'),
    MotionInfo(index:  28, name: 'Turn L',       mode: 'Fight',      desc: '좌회전 공격'),
    MotionInfo(index:  29, name: 'Turn R',       mode: 'Fight',      desc: '우회전 공격'),
    MotionInfo(index:  30, name: 'L Zap',        mode: 'Fight',      desc: '왼손 잽'),
    MotionInfo(index:  31, name: 'L Hook',       mode: 'Fight',      desc: '왼손 훅'),
    MotionInfo(index:  32, name: 'L Upper',      mode: 'Fight',      desc: '왼손 어퍼컷'),
    MotionInfo(index:  33, name: 'R Strait',     mode: 'Fight',      desc: '오른손 스트레이트'),
    MotionInfo(index:  34, name: 'R Hook',       mode: 'Fight',      desc: '오른손 훅'),
    MotionInfo(index:  35, name: 'R Upper',      mode: 'Fight',      desc: '오른손 어퍼컷'),
    MotionInfo(index:  36, name: 'RL OneTow',    mode: 'Fight',      desc: '원투 펀치'),
    MotionInfo(index:  37, name: 'Getup F',      mode: 'Fight',      desc: '전투 앞 기상'),
    MotionInfo(index:  38, name: 'Getup B',      mode: 'Fight',      desc: '전투 뒤 기상'),
    // ── [M2] Side Fight ────────────────────────────────────────────────────
    MotionInfo(index:  39, name: 'Ready',        mode: 'SideFight',  desc: '측면 준비'),
    MotionInfo(index:  40, name: 'Defence',      mode: 'SideFight',  desc: '측면 방어'),
    MotionInfo(index:  41, name: 'Forward',      mode: 'SideFight',  desc: '전방 방어'),
    MotionInfo(index:  42, name: 'Back',         mode: 'SideFight',  desc: '후방 방어'),
    MotionInfo(index:  43, name: 'Left',         mode: 'SideFight',  desc: '좌 방어'),
    MotionInfo(index:  44, name: 'Right',        mode: 'SideFight',  desc: '우 방어'),
    MotionInfo(index:  45, name: 'Turn L',       mode: 'SideFight',  desc: '좌회전 방어'),
    MotionInfo(index:  46, name: 'Turn R',       mode: 'SideFight',  desc: '우회전 방어'),
    MotionInfo(index:  47, name: 'L Shoulder',   mode: 'SideFight',  desc: '어깨치기'),
    MotionInfo(index:  48, name: 'L Elbow',      mode: 'SideFight',  desc: '팔꿈치'),
    MotionInfo(index:  49, name: 'L Punch',      mode: 'SideFight',  desc: '측면 펀치'),
    MotionInfo(index:  50, name: 'L Spin Blow',  mode: 'SideFight',  desc: '스핀 블로우'),
    MotionInfo(index:  51, name: 'Zap',          mode: 'SideFight',  desc: '오른손 잽'),
    MotionInfo(index:  52, name: 'R OneTwo',     mode: 'SideFight',  desc: '더블 펀치'),
    MotionInfo(index:  53, name: 'Getup F',      mode: 'SideFight',  desc: '측면 앞 기상'),
    MotionInfo(index:  54, name: 'Getup B',      mode: 'SideFight',  desc: '측면 뒤 기상'),
    // ── [M3] Soccer ────────────────────────────────────────────────────────
    MotionInfo(index:  55, name: 'Ready',        mode: 'Soccer',     desc: '달리기 준비'),
    MotionInfo(index:  56, name: 'F STLoop',     mode: 'Soccer',     desc: '달리기 전진'),
    MotionInfo(index:  57, name: 'F End',        mode: 'Soccer',     desc: '달리기 전진 종료'),
    MotionInfo(index:  58, name: 'B STLoop',     mode: 'Soccer',     desc: '달리기 후진'),
    MotionInfo(index:  59, name: 'B End',        mode: 'Soccer',     desc: '달리기 후진 종료'),
    MotionInfo(index:  60, name: 'Left',         mode: 'Soccer',     desc: '달리기 좌'),
    MotionInfo(index:  61, name: 'Right',        mode: 'Soccer',     desc: '달리기 우'),
    MotionInfo(index:  62, name: 'Turn L',       mode: 'Soccer',     desc: '달리기 좌회전'),
    MotionInfo(index:  63, name: 'Turn R',       mode: 'Soccer',     desc: '달리기 우회전'),
    MotionInfo(index:  64, name: 'L Floop',      mode: 'Soccer',     desc: '좌 전진 루프'),
    MotionInfo(index:  65, name: 'R Floop',      mode: 'Soccer',     desc: '우 전진 루프'),
    MotionInfo(index:  66, name: 'Shoot L',      mode: 'Soccer',     desc: '왼발 슛'),
    MotionInfo(index:  67, name: 'Shoot R',      mode: 'Soccer',     desc: '오른발 슛'),
    MotionInfo(index:  68, name: 'PK Shoot L',   mode: 'Soccer',     desc: 'PK 왼발 슛'),
    MotionInfo(index:  69, name: 'PK Shoot R',   mode: 'Soccer',     desc: 'PK 오른발 슛'),
    MotionInfo(index:  70, name: 'Keeper D L',   mode: 'Soccer',     desc: 'GK 왼쪽 방어'),
    MotionInfo(index:  71, name: 'Keeper D R',   mode: 'Soccer',     desc: 'GK 오른쪽 방어'),
    MotionInfo(index:  72, name: 'Keeper D C',   mode: 'Soccer',     desc: 'GK 중앙 방어'),
    MotionInfo(index:  73, name: 'Getup F',      mode: 'Soccer',     desc: '축구 앞 기상'),
    MotionInfo(index:  74, name: 'Getup B',      mode: 'Soccer',     desc: '축구 뒤 기상'),
    // ── [M4] Mission ───────────────────────────────────────────────────────
    MotionInfo(index:  75, name: 'Ready',        mode: 'Mission',    desc: '미션 준비'),
    MotionInfo(index:  76, name: 'SW FLoop',     mode: 'Mission',    desc: '미션 전진'),
    MotionInfo(index:  77, name: 'F End',        mode: 'Mission',    desc: '미션 전진 종료'),
    MotionInfo(index:  78, name: 'BLoop',        mode: 'Mission',    desc: '미션 후진'),
    MotionInfo(index:  79, name: 'B End',        mode: 'Mission',    desc: '미션 후진 종료'),
    MotionInfo(index:  80, name: 'Left',         mode: 'Mission',    desc: '미션 좌'),
    MotionInfo(index:  81, name: 'Right',        mode: 'Mission',    desc: '미션 우'),
    MotionInfo(index:  82, name: 'Turn L',       mode: 'Mission',    desc: '미션 좌회전'),
    MotionInfo(index:  83, name: 'Turn R',       mode: 'Mission',    desc: '미션 우회전'),
    MotionInfo(index:  84, name: '2hand Grip',   mode: 'Mission',    desc: '양손 잡기'),
    MotionInfo(index:  85, name: 'GW FLp',       mode: 'Mission',    desc: '잡고 전진'),
    MotionInfo(index:  86, name: 'F End',        mode: 'Mission',    desc: '잡고 전진 종료'),
    MotionInfo(index:  87, name: 'BLp',          mode: 'Mission',    desc: '잡고 후진'),
    MotionInfo(index:  88, name: 'B End',        mode: 'Mission',    desc: '잡고 후진 종료'),
    MotionInfo(index:  89, name: 'Left',         mode: 'Mission',    desc: '잡고 좌'),
    MotionInfo(index:  90, name: 'Right',        mode: 'Mission',    desc: '잡고 우'),
    MotionInfo(index:  91, name: 'Turn L',       mode: 'Mission',    desc: '잡고 좌회전'),
    MotionInfo(index:  92, name: 'Turn R',       mode: 'Mission',    desc: '잡고 우회전'),
    MotionInfo(index:  93, name: 'S Laydown',    mode: 'Mission',    desc: '내려놓기'),
    MotionInfo(index:  94, name: 'D Laydown',    mode: 'Mission',    desc: '놓기'),
    MotionInfo(index:  95, name: 'Getup F',      mode: 'Mission',    desc: '미션 앞 기상'),
    MotionInfo(index:  96, name: 'Getup B',      mode: 'Mission',    desc: '미션 뒤 기상'),
    MotionInfo(index:  97, name: 'FallDown FD',  mode: 'Mission',    desc: '숙이기'),
    MotionInfo(index:  98, name: 'FD Turn L',    mode: 'Mission',    desc: '엉금엉금'),
    MotionInfo(index:  99, name: 'FD Turn R',    mode: 'Mission',    desc: '좌 엉금'),
    MotionInfo(index: 100, name: 'FD Getup B',   mode: 'Mission',    desc: '우 엉금·기상'),
    // ── [M5] Hockey ────────────────────────────────────────────────────────
    MotionInfo(index: 101, name: 'Ready',        mode: 'Hockey',     desc: '하키 준비'),
    MotionInfo(index: 102, name: 'H FLoop',      mode: 'Hockey',     desc: '하키 전진'),
    MotionInfo(index: 103, name: 'F End',        mode: 'Hockey',     desc: '하키 전진 종료'),
    MotionInfo(index: 104, name: 'BLoop',        mode: 'Hockey',     desc: '하키 후진'),
    MotionInfo(index: 105, name: 'B End',        mode: 'Hockey',     desc: '하키 후진 종료'),
    MotionInfo(index: 106, name: 'Left',         mode: 'Hockey',     desc: '하키 좌'),
    MotionInfo(index: 107, name: 'Right',        mode: 'Hockey',     desc: '하키 우'),
    MotionInfo(index: 108, name: 'Turn L',       mode: 'Hockey',     desc: '하키 좌회전'),
    MotionInfo(index: 109, name: 'Turn R',       mode: 'Hockey',     desc: '하키 우회전'),
    MotionInfo(index: 110, name: 'Shoot L',      mode: 'Hockey',     desc: '하키 왼쪽 슛'),
    MotionInfo(index: 111, name: 'Shoot R',      mode: 'Hockey',     desc: '하키 오른쪽 슛'),
    MotionInfo(index: 112, name: 'Getup F',      mode: 'Hockey',     desc: '하키 앞 기상'),
    MotionInfo(index: 113, name: 'Getup B',      mode: 'Hockey',     desc: '하키 뒤 기상'),
    // ── [M6] System ────────────────────────────────────────────────────────
    MotionInfo(index: 114, name: 'Safe',         mode: 'System',     desc: '앉기'),
    MotionInfo(index: 115, name: 'Down 계단',    mode: 'System',     desc: '일어나기'),
    MotionInfo(index: 116, name: 'Mission Ready',mode: 'System',     desc: '내려가기'),
    MotionInfo(index: 118, name: '허들 넘기',    mode: 'System',     desc: '장애물 허들'),
    MotionInfo(index: 119, name: '계단 올라가기',mode: 'System',     desc: '계단 상행'),
    MotionInfo(index: 120, name: 'Power ON',     mode: 'System',     desc: 'SafeSit & ON'),
    MotionInfo(index: 240, name: 'SafeUp OFF',   mode: 'System',     desc: '전원 OFF'),
  ];

  /// 인덱스로 MotionInfo 조회 (없으면 null)
  static MotionInfo? byIndex(int index) {
    for (final m in all) {
      if (m.index == index) return m;
    }
    return null;
  }

  /// 인덱스로 표시 레이블 반환: "2: ST F (전진 시작)"
  static String labelFor(int index) {
    final info = byIndex(index);
    if (info == null) return '$index: (알 수 없음)';
    return '$index: ${info.name} · ${info.desc}';
  }

  /// 모드별로 필터링
  static List<MotionInfo> byMode(String mode) =>
      all.where((m) => m.mode == mode).toList();

  /// 유효한 모션 인덱스 목록 (0~255, 없는 번호는 제외)
  static List<int> get validIndices => all.map((m) => m.index).toList();

  /// 0~255 전체를 커버하는 순서 목록 (없는 번호는 숫자만 표시)
  static String quickLabel(int index) {
    final info = byIndex(index);
    if (info == null) return '$index';
    return '$index  ${info.name}';
  }
}
