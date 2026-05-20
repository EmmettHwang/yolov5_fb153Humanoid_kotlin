# Robo Commander

> **fb153 휴머노이드 로봇 Bluetooth 제어 앱**  
> Flutter 3.35.4 · Dart 3.9.2 · Android API 26+ · Bluetooth Classic SPP

---

## 최신 버전

| 항목 | 내용 |
|------|------|
| **버전** | `0.9.250520` (build 9) |
| **빌드 날짜** | 2025-05-20 |
| **APK 크기** | 22.8 MB (arm64) |
| **패키지** | `com.robocommander.control` |
| **Min SDK** | Android 8.0 (API 26) |

---

## 버전 히스토리

> 체계: `메이저.마이너.년월일` — 마이너 9 초과 시 메이저 증가

| 버전 | 날짜 | 상태 | 주요 변경 내용 |
|------|------|------|--------------|
| **0.9.250520** | 2025-05-20 | ✅ 최신 | 버전 체계 정착, README 전면 정리, 릴리스 패키징 완료 |
| 0.8.250520 | 2025-05-20 | ✅ | YOLO 토글 버튼, 음성 인식(STT) 통합, BT already bonded 에러 해결 |
| 0.7.250515 | 2025-05-15 | ✅ | MAC 4자리 기기 선택 화면, 앱 재시작 자동 재연결 |
| 0.6.250510 | 2025-05-10 | ✅ | 릴리스 APK 빌드(서명), ZIP 패키징, GitHub 초기 커밋 |
| 0.5.250505 | 2025-05-05 | ✅ | 설정 화면, 버튼 편집 다이얼로그, CommandSetManager |
| 0.4.250501 | 2025-05-01 | ✅ | 카메라 프리뷰 시뮬레이션 UI, YOLO 오버레이 기반 구조 |
| 0.3.250428 | 2025-04-28 | ✅ | ActionButtonPanel 3×3 그리드 |
| 0.2.250425 | 2025-04-25 | ✅ | JoystickView 커스텀 위젯 (8방향 + 데드존) |
| 0.1.250420 | 2025-04-20 | ✅ | BluetoothManager SPP 연결, PacketBuilder 15-byte 패킷 |

---

## 주요 기능

### 🔵 Bluetooth 제어
- **Bluetooth Classic SPP** — UUID: `00001101-0000-1000-8000-00805F9B34FB`
- **MAC 4자리 식별** — 여러 fb153 로봇을 MAC 마지막 4자리(`AA:BB`)로 구분
- **자동 재연결** — 앱 재시작 시 마지막 기기 자동 연결 (SharedPreferences)
- **already bonded 에러 해결** — PlatformException 감지 → 소켓 재생성 → 800ms 후 자동 재시도

### 🕹️ 제어 인터페이스
- **조이스틱** — 8방향 커스텀 조이스틱, 데드존 0.15, 50ms 간격 패킷 전송
- **액션 버튼 3×3** — 버튼 이름 / 모션번호 / 시퀀스 편집 (길게 누르기)
- **YOLO 토글** — 카메라 뷰 하단 버튼 탭 → 즉시 ON/OFF + 상태바 탭도 동일 동작

### 🎙️ 음성 명령 (STT)
- 헤더 마이크 버튼 탭 → 한국어 음성 인식 시작 (최대 5초)
- 인식 텍스트 → 액션 버튼 이름 **퍼지 매칭** (정확 일치 → 단어 매칭 → 편집 거리)
- 매칭 성공 시 해당 모션 자동 실행 + SnackBar 피드백

### 📡 패킷 프로토콜
```
FF FF 4C 53 00 00 00 00 30 0C 03 [motionIdx] 00 64 [checksum]
                                                    ↑
                          checksum = byte[6]~byte[13] 합산 & 0xFF
```

---

## 기술 스택

| 항목 | 버전 | 용도 |
|------|------|------|
| Flutter | 3.35.4 | 크로스플랫폼 프레임워크 |
| Dart | 3.9.2 | 언어 |
| flutter_bluetooth_serial | 0.4.0 | Bluetooth Classic 통신 |
| provider | 6.1.5+1 | 상태 관리 |
| shared_preferences | 2.5.3 | 마지막 연결 기기 / 버튼 설정 저장 |
| speech_to_text | 6.6.2 | 음성 인식 (STT) |
| permission_handler | 11.3.1 | 런타임 권한 요청 |
| camera | 0.11.1 | 카메라 피드 (준비됨) |

---

## 빌드 방법

```bash
# 의존성 설치
flutter pub get

# 코드 분석
flutter analyze

# 릴리스 APK (arm64, 서명 포함)
flutter build apk --release --target-platform android-arm64

# APK 위치
build/app/outputs/flutter-apk/app-release.apk
```

> **서명 키**: `android/release-key.jks` — alias: `robocommander` / pw: `robocommander2024`  
> `android/key.properties`는 `.gitignore`에 포함되어 있으므로 클론 후 직접 생성 필요

---

## 권한 목록

| 권한 | 용도 |
|------|------|
| `BLUETOOTH_CONNECT` | BT 기기 연결 (API 31+) |
| `BLUETOOTH_SCAN` | BT 기기 검색 (API 31+) |
| `BLUETOOTH` / `BLUETOOTH_ADMIN` | Android 11 이하 호환 |
| `ACCESS_FINE_LOCATION` | BT 스캔 (API ≤30) |
| `CAMERA` | YOLO 카메라 피드 |
| `RECORD_AUDIO` | 음성 인식 STT |

---

## 프로젝트 구조

```
lib/
├── main.dart                           # 앱 진입점 · 스플래시 · 자동 재연결
├── bluetooth/
│   ├── bluetooth_manager.dart          # BT 연결/스캔/패킷 전송 · already bonded 처리
│   ├── packet_builder.dart             # 15-byte 패킷 빌더
│   └── motion_repeater.dart            # 조이스틱 50ms 반복 전송
├── command/
│   └── command_set_manager.dart        # SharedPreferences 버튼 설정 저장/로드
├── models/
│   └── action_button_config.dart       # 버튼 설정 데이터 모델
├── services/
│   └── voice_command_service.dart      # STT + 퍼지 매칭 + 모션 실행
└── ui/
    ├── bluetooth/
    │   └── bluetooth_scan_screen.dart  # MAC 4자리 스캔/연결 화면
    ├── camera/
    │   └── camera_preview_widget.dart  # YOLO 오버레이 + 토글 버튼
    ├── control/
    │   ├── control_screen.dart         # 메인 제어 화면
    │   ├── joystick_view.dart          # 커스텀 조이스틱 위젯
    │   ├── action_button_panel.dart    # 3×3 액션 버튼 패널
    │   └── voice_command_button.dart   # 마이크 버튼 + 상태 표시
    └── settings/
        ├── settings_screen.dart        # 설정 화면 (BT / 버튼)
        └── button_editor_dialog.dart   # 버튼 이름·모션·시퀀스 편집
```

---

## 이슈 해결 이력

| 이슈 | 상태 | 해결 방법 |
|------|------|----------|
| `ConnectionState` 이름 충돌 | ✅ | `BtConnectionState` enum으로 이름 변경 |
| `flutter_bluetooth_serial` namespace 누락 | ✅ | pub-cache `build.gradle`에 `namespace` 직접 추가 |
| R8 minify Play Core missing class | ✅ | `isMinifyEnabled = false` |
| arm+arm64 동시 빌드 타임아웃 | ✅ | `--target-platform android-arm64` 단독 빌드 |
| Bluetooth "already bonded" 에러 | ✅ | `PlatformException` 캐치 → 소켓 정리 → 800ms 후 재시도 |
| `speech_to_text` PluginRegistry.Registrar 컴파일 오류 | ✅ | pub-cache 플러그인 Kotlin 패치 (registerWith stub 제거) |

---

## 로봇 PIN 페어링 안내

fb153 로봇 최초 페어링 시:
1. Android 설정 → Bluetooth → fb153 기기 선택
2. PIN 입력: `1234` (또는 `0000`)
3. 앱 실행 후 기기 선택 화면에서 해당 기기 탭
