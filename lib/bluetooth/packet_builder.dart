/// fb153 로봇 패킷 빌더
///
/// 패킷 구조:
///
/// [A] Exe Motion (15 bytes):
///   FF FF 4C 53 00 00 | 00 00 30 0C 03 [M] 00 00 [CHK]
///   CHK = byte[6..13] 합산 & 0xFF
///
/// [B] LED Control (16 bytes):
///   FF FF 4C 53 00 00 | 00 00 30 05 04 [ID] [R] [G] [B] [CHK]
///   CHK = byte[6..14] 합산 & 0xFF
///   ID: 머리=18(0x12), 허리=17(0x11)
///
/// [C] Position Control (16 bytes):
///   FF FF 4C 53 00 00 | 00 00 30 03 04 [ID] [TORQ] [POS_H] [POS_L] [CHK]
///   CHK = byte[6..14] 합산 & 0xFF
///   TORQ: 0~100, position: -32768~32767 (0=중립)
class PacketBuilder {
  static const int packetSize    = 15; // ExeMotion 패킷 크기
  static const int packetSizeExt = 16; // LED/Position 패킷 크기
  static const int defaultSpeed  = 100;

  // 모터 ID 상수
  static const int motorIdHead  = 18; // ID 18: 머리 LED
  static const int motorIdWaist = 17; // ID 17: 허리

  // ── 공통 헤더 8바이트 ─────────────────────────────────────────────
  static List<int> _hdr() => [0xFF, 0xFF, 0x4C, 0x53, 0x00, 0x00, 0x00, 0x00];

  /// 체크섬 계산: packet[start..end](포함) 합산 & 0xFF
  static int _chk(List<int> p, int start, int end) {
    int c = 0;
    for (int i = start; i <= end; i++) {
      c = (c + p[i]) & 0xFF;
    }
    return c;
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // [A] Exe Motion
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 모션 패킷 생성 (15 bytes)
  static List<int> build(int motionIndex) {
    assert(motionIndex >= 0 && motionIndex <= 255);
    final p = [
      ..._hdr(),
      0x30, 0x0C, 0x03,
      motionIndex & 0xFF,
      0x00,
      defaultSpeed,
    ];
    p.add(_chk(p, 6, 13));
    return p;
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // [B] LED Control
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// LED 제어 패킷 (16 bytes)
  ///
  /// [motorId] 조작할 모터 ID (18=머리, 17=허리)
  /// [r][g][b] RGB 값 0~255
  static List<int> buildLed({
    int motorId = motorIdHead,
    int r = 0,
    int g = 0,
    int b = 0,
  }) {
    final p = [
      ..._hdr(),
      0x30, 0x05, 0x04,
      motorId & 0xFF,
      r & 0xFF,
      g & 0xFF,
      b & 0xFF,
    ];
    p.add(_chk(p, 6, 14));
    return p;
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // [C] Position Control
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// 포지션 제어 패킷 (16 bytes)
  ///
  /// [motorId]       모터 ID
  /// [torquePercent] 토크 0~100
  /// [position]      목표 위치 -32768~32767 (0=중립)
  static List<int> buildPosition({
    int motorId = motorIdHead,
    int torquePercent = 80,
    int position = 0,
  }) {
    final pos = position.clamp(-32768, 32767);
    final raw = pos < 0 ? (pos + 65536) : pos;
    final posH = (raw >> 8) & 0xFF;
    final posL = raw & 0xFF;
    final torq = torquePercent.clamp(0, 100) & 0xFF;

    final p = [
      ..._hdr(),
      0x30, 0x03, 0x04,
      motorId & 0xFF,
      torq,
      posH,
      posL,
    ];
    p.add(_chk(p, 6, 14));
    return p;
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 편의 메서드
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// LED OFF
  static List<int> buildLedOff({int motorId = motorIdHead}) =>
      buildLed(motorId: motorId, r: 0, g: 0, b: 0);

  /// 말하는 입술 반짝임 — 따뜻한 황색광 (brightness 0~255)
  /// r=brightness, g=brightness/4, b=0  (발화 느낌)
  static List<int> buildLedBlink(int brightness) {
    final b = brightness.clamp(0, 255);
    return buildLed(motorId: motorIdHead, r: b, g: b ~/ 4, b: 0);
  }

  /// 패킷 → hex 문자열 (디버깅)
  static String toHexString(List<int> packet) =>
      packet.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');

  /// 정지 패킷 (모션 1)
  static List<int> buildStop() => build(1);

  /// ExeMotion 유효성 검증
  static bool validate(List<int> packet) {
    if (packet.length != packetSize) return false;
    if (packet[0] != 0xFF || packet[1] != 0xFF) return false;
    if (packet[2] != 0x4C || packet[3] != 0x53) return false;
    return packet[14] == _chk(packet, 6, 13);
  }
}
