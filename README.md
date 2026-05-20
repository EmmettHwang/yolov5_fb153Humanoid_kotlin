# Robo Commander

**fb153 휴머노이드 로봇 Bluetooth 제어 앱**  
Flutter 3.35.4 · Android (API 26+) · Bluetooth Classic SPP

---

## 버전 히스토리

버전 체계: `메이저.마이너.년월일` — 마이너 9 초과 시 메이저 증가

| 버전 | 날짜 | 변경 내용 |
|------|------|----------|
| **0.8.250520** | 2025-05-20 | YOLO 토글 버튼 (즉시 ON/OFF), 음성 인식 STT (버튼 이름 매칭 → 모션 실행), Bluetooth already bonded 에러 재시도 로직, 버전 체계 변경 |
| 0.7.250515 | 2025-05-15 | MAC 4자리 기기 선택 화면, 앱 재실행 시 자동 재연결 |
| 0.6.250510 | 2025-05-10 | 릴리스 APK 빌드 (서명 포함), ZIP 패키징, GitHub 초기 커밋 |
| 0.5.250505 | 2025-05-05 | 설정 화면 (버튼 편집, Bluetooth 탭), CommandSetManager |
| 0.4.250501 | 2025-05-01 | 카메라 프리뷰 시뮬레이션 UI, YOLO 오버레이 기반 구조 |
| 0.3.250428 | 2025-04-28 | ActionButtonPanel 3×3 그리드, 버튼 편집 다이얼로그 |
| 0.2.250425 | 2025-04-25 | JoystickView 커스텀 위젯 (8방향, 데드존), 50ms 반복 전송 |
| 0.1.250420 | 2025-04-20 | BluetoothManager SPP 연결, PacketBuilder 15-byte 패킷 |

---

## 주요 기능

### Bluetooth 제어
- **Bluetooth Classic SPP** (RFCOMM UUID: `00001101-0000-1000-8000-00805F9B34FB`)
- **MAC 4자리 식별**: 여러 fb153 로봇을 MAC 마지막 4자리(`AA:BB`)로 구분
- **자동 재연결**: 앱 재시작 시 마지막 연결 기기 자동 연결
- **already bonded 에러 해결**: PlatformException 감지 → 소켓 재생성 후 자동 재시도

### 제어 인터페이스
- **조이스틱**: 8방향 커스텀 조이스틱, 데드존 0.15, 50ms 간격 패킷 전송
- **액션 버튼**: 3×3 그리드, 버튼 이름/모션번호/시퀀스 편집 가능
- **YOLO 토글**: 카메라 뷰 내 버튼 탭 → 즉시 ON/OFF 전환

### 음성 명령 (STT)
- 헤더 마이크 버튼 탭 → 음성 인식 시작 (5초)
- 인식 텍스트 → 액션 버튼 이름 퍼지 매칭
- 매칭 성공 시 해당 모션 자동 실행
- 지원 언어: 한국어 (`ko_KR`)

### 패킷 프로토콜
```
FF FF 4C 53 00 00 00 00 30 0C 03 [motionIndex] 00 64 [checksum]
checksum = byte[6]~byte[13] 합산 & 0xFF
```

---

## 기술 스택

| 항목 | 내용 |
|------|------|
| Flutter | 3.35.4 |
| Dart | 3.9.2 |
| 대상 플랫폼 | Android API 26+ (arm64) |
| Bluetooth | `flutter_bluetooth_serial: 0.4.0` |
| 상태 관리 | `provider: 6.1.5+1` |
| 로컬 저장소 | `shared_preferences: 2.5.3` |
| 음성 인식 | `speech_to_text: 6.6.2` |
| 권한 관리 | `permission_handler: 11.3.1` |

---

## 패키지 정보

- **앱 이름**: Robo Commander
- **패키지 ID**: `com.robocommander.control`
- **서명 키**: `android/release-key.jks` (alias: robocommander)
- **Min SDK**: 26 (Android 8.0)
- **Target SDK**: 35 (Android 15)

---

## 빌드

```bash
# 의존성 설치
flutter pub get

# 릴리스 APK (arm64)
flutter build apk --release --target-platform android-arm64

# APK 위치
build/app/outputs/flutter-apk/app-release.apk
```

---

## 권한 (AndroidManifest.xml)

| 권한 | 용도 |
|------|------|
| `BLUETOOTH_CONNECT` | BT 기기 연결 |
| `BLUETOOTH_SCAN` | BT 기기 검색 |
| `BLUETOOTH`, `BLUETOOTH_ADMIN` | Android 11 이하 호환 |
| `CAMERA` | YOLO 카메라 피드 |
| `RECORD_AUDIO` | 음성 인식 STT |
| `ACCESS_FINE_LOCATION` | BT 스캔 (Android 11 이하) |

---

## 파일 구조

```
lib/
├── main.dart                          # 앱 진입점, 스플래시, 자동 재연결
├── bluetooth/
│   ├── bluetooth_manager.dart         # BT 연결/스캔/패킷 전송
│   ├── packet_builder.dart            # 15-byte 패킷 빌더
│   └── motion_repeater.dart           # 조이스틱 반복 전송
├── command/
│   └── command_set_manager.dart       # SharedPreferences 버튼 설정
├── models/
│   └── action_button_config.dart      # 버튼 설정 데이터 모델
├── services/
│   └── voice_command_service.dart     # STT + 버튼 이름 퍼지 매칭
└── ui/
    ├── bluetooth/
    │   └── bluetooth_scan_screen.dart # MAC 4자리 스캔/연결 화면
    ├── camera/
    │   └── camera_preview_widget.dart # YOLO 오버레이 + 토글 버튼
    ├── control/
    │   ├── control_screen.dart        # 메인 제어 화면
    │   ├── joystick_view.dart         # 커스텀 조이스틱
    │   ├── action_button_panel.dart   # 3×3 액션 버튼 패널
    │   └── voice_command_button.dart  # 음성 명령 마이크 버튼
    └── settings/
        ├── settings_screen.dart       # 설정 화면
        └── button_editor_dialog.dart  # 버튼 편집 다이얼로그
```

---

## 알려진 이슈 / 해결 이력

| 이슈 | 상태 | 해결 방법 |
|------|------|----------|
| `ConnectionState` 이름 충돌 | ✅ 해결 | `BtConnectionState`로 이름 변경 |
| `flutter_bluetooth_serial` namespace 누락 | ✅ 해결 | pub-cache build.gradle에 namespace 추가 |
| R8 minify Play Core 오류 | ✅ 해결 | `isMinifyEnabled = false` |
| arm+arm64 동시 빌드 타임아웃 | ✅ 해결 | arm64 단독 빌드 |
| Bluetooth "already bonded" 에러 | ✅ 해결 | PlatformException 캐치 → 800ms 후 재시도 |
