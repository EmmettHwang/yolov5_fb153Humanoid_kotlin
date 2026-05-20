/// fb153 로봇 패킷 빌더
/// Python robot_controller.py 로직을 Dart로 포팅
/// 
/// 패킷 구조 (15 bytes):
/// [0][1]  = 0xFF 0xFF  (Header 1, 2)
/// [2][3]  = 0x4C 0x53  (Header 'L', 'S')
/// [4][5]  = 0x00 0x00  (예약)
/// [6][7]  = 0x00 0x00  (체크섬 범위 시작)
/// [8]     = 0x30
/// [9]     = 0x0C
/// [10]    = 0x03
/// [11]    = motionIndex (모션 번호)
/// [12]    = 0x00
/// [13]    = 0x64 (100, 속도/파워)
/// [14]    = checksum (byte[6]~[13] 합산 & 0xFF)
class PacketBuilder {
  static const int packetSize = 15;
  static const int defaultSpeed = 100;

  /// 모션 패킷 생성
  static List<int> build(int motionIndex) {
    assert(motionIndex >= 0 && motionIndex <= 255,
        '모션 인덱스 범위 오류: $motionIndex (0~255 허용)');

    final packet = List<int>.filled(packetSize, 0);
    packet[0] = 0xFF;
    packet[1] = 0xFF;
    packet[2] = 0x4C; // 'L'
    packet[3] = 0x53; // 'S'
    packet[4] = 0x00;
    packet[5] = 0x00;
    packet[6] = 0x00;
    packet[7] = 0x00;
    packet[8] = 0x30;
    packet[9] = 0x0C;
    packet[10] = 0x03;
    packet[11] = motionIndex & 0xFF;
    packet[12] = 0x00;
    packet[13] = defaultSpeed;

    // 체크섬 계산: byte[6]~[13] 합산 & 0xFF
    int chk = 0;
    for (int i = 6; i <= 13; i++) {
      chk = (chk + packet[i]) & 0xFF;
    }
    packet[14] = chk;

    return packet;
  }

  /// 패킷을 16진수 문자열로 표시 (디버깅용)
  static String toHexString(List<int> packet) {
    return packet.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
  }

  /// 정지 패킷 (모션 1: 기본 자세)
  static List<int> buildStop() => build(1);

  /// 패킷 유효성 검증
  static bool validate(List<int> packet) {
    if (packet.length != packetSize) return false;
    if (packet[0] != 0xFF || packet[1] != 0xFF) return false;
    if (packet[2] != 0x4C || packet[3] != 0x53) return false;

    int chk = 0;
    for (int i = 6; i <= 13; i++) {
      chk = (chk + packet[i]) & 0xFF;
    }
    return packet[14] == chk;
  }
}
