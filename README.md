# Robo Commander

> **fb153 휴머노이드 로봇 Bluetooth 제어 앱**  
> Flutter 3.35.4 · Dart 3.9.2 · Android API 26+ · Bluetooth Classic SPP

---

## 최신 버전

| 항목 | 내용 |
|------|------|
| **버전** | `1.5.260624000000` (build 23) — 최신 |
| **빌드 날짜** | 2026-06-24 KST |
| **APK 크기** | ~80 MB (arm64) |
| **패키지** | `com.robocommander.control` |
| **Min SDK** | Android 8.0 (API 26) |

### v1.5.260624000000 (build 23) — 2026-06-24

#### 🔵 LED / Position 제어 시스템
- **`PacketBuilder.buildLed()`** — 16B LED 패킷 신규 구현  
  `FF FF 4C 53 00 00 00 00 30 05 04 [ID] [R] [G] [B] [CHK]`  
  CHK = byte[6..14] 합산 & 0xFF
- **`PacketBuilder.buildPosition()`** — 16B 포지션 패킷 신규 구현  
  `FF FF 4C 53 00 00 00 00 30 03 04 [ID] [TORQ] [POS_H] [POS_L] [CHK]`  
  16-bit signed position(big-endian), 음수 → `pos + 65536` 변환
- **모터 ID 상수**: `motorIdHead = 18` (머리), `motorIdWaist = 17` (허리)
- **`BluetoothManager`** — `sendLed()` / `sendLedOff()` / `sendPosition()` 헬퍼 추가

#### 💬 말하는 LED 애니메이션 (LedSpeechAnimator)
- **`AudioService`** — `onSpeechStart(estimatedMs)` / `onSpeechDone()` 콜백 추가  
  TTS 완료·취소 시 자동 호출, MP3 완료 이벤트 연동
- **`LedSpeechAnimator`** — 신규 클래스: 오디오 재생 중 18번(머리) LED를 sin 파형으로 반짝임  
  - 80ms 주기 `Timer.periodic` + `sin()` 함수로 밝기 40~255 변화  
  - 따뜻한 황색광 (`r=brightness`, `g=brightness÷4`, `b=0`) — "말하는 것처럼" 표현  
  - 예상 발화 시간 + 500ms 후 강제 종료 (TTS 미콜백 대비)  
  - `_stop()` 시 `buildLedOff()` 전송 → LED 완전 소등
- **`ControlScreen`** — `LedSpeechAnimator` 초기화 + `attach(AudioService())` 연결, `dispose()` 처리

#### 🎮 액션 버튼 15개 (3×5)
- **`ActionButtonPanel`** — `buttonCount` 파라미터 추가, 기본 9 → 15 지원  
  `childAspectRatio`: 버튼 수 > 9이면 1.4, 이하이면 1.0 동적 조정
- **`ActionButtonConfig.defaults()`** — 버튼 10~15 (motion 26~31) 추가
- **`CommandSetManager._buttonCount = 15`** 고정, `executeCommandSet()`에서 `AudioService().playForButton()` 직접 호출

#### 📸 카메라 영역 축소 + Epoch 수집
- **카메라 높이** `size.height × 0.46` → `× 0.30` (30% 축소)
- **Epoch 수집 UI** (`_buildEpochControl()`):  
  - 샘플 수 슬라이더 20~500 (200 이하 황색 경고)  
  - Epoch 슬라이더 1~10 (보라색)  
  - 수집 완료 조건: `captureCount ≥ captureTarget × epochCount`  
  - 버튼 레이블: `"[클래스]" 수집 ([N]장 × [E]회)`

#### 🤖 나의 로봇 탭 + 헤더 개선
- **`_filterMyRobots()`** — 별명 있거나 `lastMac`인 기기만 "나의 로봇" 탭에 표시
- **"미지정 로봇" → "안 사귄 로봇"** — 탭 제목 및 배너 문구 변경
- **배지 중복 제거** — 우측 Column에서 "별명" 배지 제거, "최근" 배지만 유지
- **헤더 별명+아바타** — 연결 시 `RobotNicknameService.displayName()` + `RobotAvatarWidget(size: 36)` 표시

### v1.4.260604000000 (build 22) — 2026-06-04
- **📸 아바타 카메라 촬영 지원**: 로봇 별명 편집 다이얼로그 사진 버튼 → 바텀시트로 **카메라 촬영** / **갤러리 선택** 분기
  - `image_picker 1.1.2` 적용 — 해상도 512×512, JPEG 85% 품질로 최적화
  - 카메라 촬영: 로봇을 직접 찍어 아바타로 즉시 등록
  - 갤러리 선택: 저장된 사진에서 아바타 선택
  - 권한 오류 시 명확한 안내 SnackBar 표시
- **🤖 나의 로봇 / 미지정 로봇 탭 재구성** (v1.3)
  - 탭1 "페어링된 기기" → **"나의 로봇"** (별명 있는 기기 상단, 최근 연결 강조)
  - 탭2 "새 기기 검색" → **"미지정 로봇"** (FB153 이름 포함 기기만 필터, MAC 4자리 20px bold 표시)
  - FB153 / 전체 발견 카운트 배너 실시간 표시
- **🔄 카메라 재초기화** (v1.3): `CustomVisionScreen` 닫고 복귀 시 카메라 블랙 현상 해결
  - `WidgetsBindingObserver.didChangeAppLifecycleState(resumed)` + `didChangeDependencies()` 조합
- **📡 BT 자동 재연결 개선** (v1.3): `tryAutoReconnect()` 네이티브 이벤트 도달 전 `isConnected` 오판 방지
  - 100ms 폴링 × 최대 30회(3초) 대기, splash에서 `await timeout(4s)` 결과 확인 후 화면 전환
- **✨ 학습 플로우 개선** (v1.3): `takePicture()` 루프 → `imageStream` 기반 0.5초 인터벌 + `compute()` isolate로 교체

### v1.2.260603190156 (build 20) — 2026-06-03
- **🤖 로봇 별명 짓기**: BT 연결 화면에서 기기 카드 길게 누르면 원하는 이름 지정 (MAC→별명 매핑, SharedPreferences 저장)
- **🔍 미페어링 BT 검색**: "새 기기 검색" 탭 추가 — 페어링 없이 `startDiscovery()` + BroadcastReceiver로 주변 기기 실시간 발견 → 탭하면 자동 페어링 후 연결
- **✨ 직접 학습 (Teachable Machine)**: 카메라로 직접 데이터 수집 → 클래스 생성 → KNN 학습 → 실시간 분류 (헤더 `✨` 버튼)
- **🎨 BT 화면 탭 UI**: 페어링된 기기 / 새 기기 검색 2탭 구조
- **📛 연결화면 별명 표시**: 별명 있으면 굵은 cyanAccent 텍스트 + "별명" 배지, 원래 이름 서브텍스트 표시
- **🔒 위치 권한 처리**: Android 11 이하 BT 검색에 필요한 `ACCESS_FINE_LOCATION` 런타임 요청 추가

### v1.1.250520193425 (build 19) — 2025-05-20
- **🚶 조이스틱 전진/후진 시퀀스**: 전진 2(준비)→3(반복)→4(마무리) 루프, 후진 9→10→11 루프 (`MotionRepeater.startSequence`)
- **🎙 음성 버튼 위치 변경**: 헤더 → 액션 버튼 패널 아래로 이동 (더 넓은 탭 영역)
- **👁 비전 설정 버튼**: 헤더에 `눈` 아이콘 추가 → VisionSettingsScreen 바로 접근
- **🤖 YOLO 동작 자동 트리거**: 인식된 라벨 → YoloActionManager 매칭 → 모션+오디오 자동 실행 (3초 쿨다운)
- **📛 로봇 이름 커스터마이징**: 설정 > 로봇 이름 탭 → 원하는 이름 입력, SharedPreferences 저장, 헤더 즉시 반영
- **💬 TTS 인사말에 로봇 이름 포함**: `"안녕하세요! [이름] 커맨더 시작합니다."`
- **🔗 Provider 완성**: `RobotNameService`, `YoloActionManager` MultiProvider 등록

### v1.0.250520184336 (build 17) — 2025-05-20
- **🔊 버튼 오디오 연동**: 각 버튼에 MP3 파일 경로 또는 TTS 텍스트 설정 (한국어/영어 자동 감지)
- **🎤 TTS 시작 인사**: 앱 시작 시 로봇이 "안녕하세요! 로보 커맨더 시작합니다." 음성 출력
- **🎮 조이스틱 모션 수정**: 모션 테이블 기준으로 전/후/좌/우 번호 정확히 교정 (후진 9번 ST B)
- **📋 모션 테이블 내장**: 120+ 모션 이름·모드·설명 완전 매핑 (Basic/Fight/Soccer/Mission/Hockey/System)
- **🔢 모션 스피너 UI**: 슬라이더 → [−10][−][번호][+][+10] 스피너 + 모션 이름 자동 표시
- **⚡ 추론 일시정지**: 모션 전송 중 TFLite 추론 중단으로 딜레이 제거 (카메라 스트림 유지)

---

## 버전 체계

```
메이저 . 마이너 . YYMMDDHHmmss
  1    .   0    . 250520043801
                  ││││││││││└─ 초(ss)
                  ││││││││└─── 분(mm)
                  ││││││└───── 시(HH)
                  ││││└─────── 일(DD)
                  ││└───────── 월(MM)
                  └─────────── 년(YY, 2자리)
```

- 빌드할 때마다 타임스탬프가 자동으로 들어가므로 **빌드 시각으로 정확히 추적 가능**
- 마이너가 9를 초과하면 메이저 증가 (예: `1.9.xxx` → `2.0.xxx`)

---

## 버전 히스토리

| 버전 | 빌드 시각 | 주요 변경 내용 |
|------|-----------|----------------|
| **1.5.260624000000** | 2026-06-24 KST | LED/Position 제어, LedSpeechAnimator(sin 파형), 버튼 15개(3×5), Epoch 수집 UI, 카메라 30%, 나의 로봇 필터, 안 사귄 로봇 |
| 1.4.260604000000 | 2026-06-04 KST | 아바타 카메라 촬영+갤러리 선택 바텀시트, image_picker 1.1.2 |
| 1.3.260603193425 | 2026-06-03 19:34 KST | 나의 로봇/미지정 로봇 탭, imageStream 학습, 카메라 재초기화, BT 폴링 자동 재연결 |
| 1.2.260603190156 | 2026-06-03 19:01 KST | 로봇 별명/아바타, 미페어링 BT 검색, Teachable Machine KNN 직접 학습, 위치권한 |
| **1.1.250520193425** | 2025-05-20 19:34 KST | 조이스틱 시퀀스(2→3→4/9→10→11), 음성버튼 이동, 비전설정 버튼, YOLO 자동 트리거, 로봇이름 커스터마이징 |
| 1.0.250520184336 | 2025-05-20 18:43 KST | MP3/TTS 버튼 오디오, 모션 스피너, 모션 테이블, BT 자동 재연결, 햅틱, file_picker |
| 1.0.250520181205 | 2025-05-20 18:12 KST | flutter_bluetooth_serial 제거, MethodChannel+EventChannel 네이티브 BT, ch1 reflection 연결 |
| 1.0.250520043801 | 2025-05-20 04:38 | 버전 체계 변경 (년월일 → 년월일시분초) |
| 1.0.250520 | 2025-05-20 | 실제 카메라 + TFLite 사물인식, BT 권한 개선, tflite_flutter Dart 3.9 패치 |
| 1.0.250520 | 2025-05-20 | 메이저 버전 1.0 릴리스, BT 기기 인식 오류 수정, 메인 화면 우선 진입 |
| 0.9.250520 | 2025-05-20 | README 전면 정리, 릴리스 패키징 완료 |
| 0.8.250520 | 2025-05-20 | YOLO 토글 버튼, 음성 인식(STT) 통합, BT already bonded 에러 해결 |
| 0.7.250515 | 2025-05-15 | MAC 4자리 기기 선택 화면, 앱 재시작 자동 재연결 |
| 0.6.250510 | 2025-05-10 | 릴리스 APK 빌드(서명), ZIP 패키징, GitHub 초기 커밋 |
| 0.5.250505 | 2025-05-05 | 설정 화면, 버튼 편집 다이얼로그, CommandSetManager |
| 0.4.250501 | 2025-05-01 | 카메라 프리뷰 시뮬레이션 UI, YOLO 오버레이 기반 구조 |
| 0.3.250428 | 2025-04-28 | ActionButtonPanel 3×3 그리드 |
| 0.2.250425 | 2025-04-25 | JoystickView 커스텀 위젯 (8방향 + 데드존) |
| 0.1.250420 | 2025-04-20 | BluetoothManager SPP 연결, PacketBuilder 15-byte 패킷 |

---

## 주요 기능

### 🔵 Bluetooth 제어
- **Bluetooth Classic SPP** — UUID: `00001101-0000-1000-8000-00805F9B34FB`
- **MAC 4자리 식별** — 여러 fb153 로봇을 MAC 마지막 4자리(`AA:BB`)로 구분
- **자동 재연결** — 앱 재시작 시 마지막 기기 백그라운드 자동 연결 (결과와 무관하게 메인 화면 진입)
- **기기 이름 유연 매칭** — `fb153`, `FB153`, `FB153 v1.0.0` 등 대소문자·공백 무시 인식
- **already bonded 에러 해결** — PlatformException 감지 → 소켓 재생성 → 800ms 후 자동 재시도
- **전체 기기 보기** — fb153 필터링 실패 시 페어링된 전체 기기 목록 표시
- **런타임 권한 확인** — `getBondedDevices()` 호출 전 `BLUETOOTH_CONNECT` / `BLUETOOTH_SCAN` 권한 먼저 요청 (Android 12+)

### 📷 카메라 + AI 사물인식 (YOLO)
- **실제 카메라 피드** — `CameraController`로 후면 카메라 실시간 표시 (시뮬레이션 아님)
- **TFLite 추론** — EfficientDet-Lite0 (Google MediaPipe 공식, 13.2MB, COCO 80 클래스) 온디바이스 추론
- **모델 로딩 프로그레스바** — 앱 내 모델 초기화 중 `LinearProgressIndicator` + % 표시
- **바운딩 박스 오버레이** — 인식된 객체에 클래스별 색상 바운딩 박스 + 레이블/신뢰도 표시
- **YOLO 토글** — 카메라 뷰 하단 버튼 탭 → 즉시 ON/OFF (상태바 탭도 동일 동작)
- **8fps 추론** — 125ms 간격 프레임 throttle, compute() isolate로 UI 비블로킹
- **추론 0ms 버그 수정** — `initialize()` await 완료 후 스트림 시작, 모델 ready 시 자동 재시작
- **추론 시간 표시** — 오버레이에 실시간 ms 단위 표시

### 🕹️ 제어 인터페이스
- **조이스틱** — 8방향 커스텀 조이스틱, 데드존 0.15, 50ms 간격 패킷 전송
- **액션 버튼 3×3** — 버튼 이름 / 모션번호 / 시퀀스 편집 (길게 누르기)
- **헤더 BT 버튼** — 항상 표시, 연결 상태 색상: 연결(녹색 + MAC 4자리) / 미연결(빨간색)

### 🎙️ 음성 명령 (STT)
- 헤더 마이크 버튼 탭 → 한국어 음성 인식 시작 (최대 5초)
- 인식 텍스트 → 액션 버튼 이름 **퍼지 매칭** (정확 일치 → 단어 매칭 → 편집 거리)
- 매칭 성공 시 해당 모션 자동 실행 + SnackBar 피드백

### 📡 패킷 프로토콜

**[A] ExeMotion (15 bytes)**
```
FF FF 4C 53 00 00 | 00 00 30 0C 03 [M] 00 64 [CHK]
                                                ↑
                    CHK = byte[6..13] 합산 & 0xFF
```

**[B] LED Control (16 bytes)**
```
FF FF 4C 53 00 00 | 00 00 30 05 04 [ID] [R] [G] [B] [CHK]
                                                         ↑
                           CHK = byte[6..14] 합산 & 0xFF
  ID: 머리=18(0x12), 허리=17(0x11)
```

**[C] Position Control (16 bytes)**
```
FF FF 4C 53 00 00 | 00 00 30 03 04 [ID] [TORQ] [PH] [PL] [CHK]
                                                              ↑
                              CHK = byte[6..14] 합산 & 0xFF
  position: 16-bit signed big-endian (음수 → pos + 65536)
```

---

## 기술 스택

| 패키지 | 버전 | 용도 |
|--------|------|------|
| Flutter | 3.35.4 | 크로스플랫폼 프레임워크 |
| Dart | 3.9.2 | 언어 |
| flutter_bluetooth_serial | 0.4.0 | Bluetooth Classic SPP 통신 |
| camera | 0.11.1 | 실시간 카메라 피드 |
| tflite_flutter | 0.10.4 | TFLite 온디바이스 추론 |
| image | 4.1.7 | 카메라 프레임 전처리 (YUV→RGB) |
| image_picker | 1.1.2 | 아바타 카메라 촬영 / 갤러리 선택 |
| provider | 6.1.5+1 | 상태 관리 |
| shared_preferences | 2.5.3 | 마지막 연결 기기 / 버튼 설정 저장 |
| speech_to_text | 6.6.2 | 음성 인식 (STT) |
| permission_handler | 11.3.1 | 런타임 권한 요청 |

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
> `android/key.properties`는 `.gitignore`에 포함 — 클론 후 직접 생성 필요

---

## 권한 목록

| 권한 | 용도 |
|------|------|
| `BLUETOOTH_CONNECT` | BT 기기 연결 (API 31+) |
| `BLUETOOTH_SCAN` | BT 기기 검색 (API 31+) |
| `BLUETOOTH` / `BLUETOOTH_ADMIN` | Android 11 이하 호환 |
| `ACCESS_FINE_LOCATION` | BT 스캔 (API ≤30) |
| `CAMERA` | 실시간 카메라 피드 + TFLite 사물인식 + 아바타 촬영 |
| `READ_MEDIA_IMAGES` | 갤러리 이미지 접근 (API 33+) |
| `READ_EXTERNAL_STORAGE` | 갤러리 이미지 접근 (API ≤32) |
| `RECORD_AUDIO` | 음성 인식 STT |

---

## 프로젝트 구조

```
lib/
├── main.dart                           # 앱 진입점 · 스플래시 · 백그라운드 자동 재연결
├── bluetooth/
│   ├── bluetooth_manager.dart          # BT 연결/스캔/패킷 전송 · 권한 확인 · already bonded 처리
│   ├── packet_builder.dart             # 15-byte 패킷 빌더
│   └── motion_repeater.dart            # 조이스틱 50ms 반복 전송
├── command/
│   └── command_set_manager.dart        # SharedPreferences 버튼 설정 저장/로드
├── models/
│   └── action_button_config.dart       # 버튼 설정 데이터 모델
├── services/
│   ├── yolo_detector_service.dart      # TFLite 추론 · 모델 로딩 프로그레스 · YUV→RGB 전처리
│   └── voice_command_service.dart      # STT + 퍼지 매칭 + 모션 실행
└── ui/
    ├── bluetooth/
    │   └── bluetooth_scan_screen.dart  # MAC 4자리 스캔/연결 · 전체 기기 보기
    ├── camera/
    │   └── camera_preview_widget.dart  # 실제 CameraPreview · 바운딩 박스 · 로딩 프로그레스바
    ├── control/
    │   ├── control_screen.dart         # 메인 제어 화면 · YoloDetectorService 연동
    │   ├── joystick_view.dart          # 커스텀 조이스틱 위젯
    │   ├── action_button_panel.dart    # 3×3 액션 버튼 패널
    │   └── voice_command_button.dart   # 마이크 버튼 + 상태 표시
    └── settings/
        ├── settings_screen.dart        # 설정 화면 (BT / 버튼)
        └── button_editor_dialog.dart   # 버튼 이름·모션·시퀀스 편집

assets/
├── models/
│   ├── efficientdet_lite0.tflite       # EfficientDet-Lite0 Google MediaPipe 공식 (13.2MB)
│   └── labels.txt                      # COCO 80 클래스 레이블
├── sounds/                             # 효과음 (확장용)
└── images/                             # 이미지 리소스 (확장용)
```

---

## 이슈 해결 이력

| 이슈 | 버전 | 상태 | 해결 방법 |
|------|------|------|----------|
| `ConnectionState` 이름 충돌 | 0.1 | ✅ | `BtConnectionState` enum으로 이름 변경 |
| `flutter_bluetooth_serial` namespace 누락 | 0.6 | ✅ | pub-cache `build.gradle`에 `namespace` 직접 추가 |
| R8 minify Play Core missing class | 0.6 | ✅ | `isMinifyEnabled = false` |
| arm+arm64 동시 빌드 타임아웃 | 0.6 | ✅ | `--target-platform android-arm64` 단독 빌드 |
| Bluetooth "already bonded" 에러 | 0.8 | ✅ | `PlatformException` 캐치 → 소켓 재생성 → 800ms 후 재시도 |
| `speech_to_text` PluginRegistry.Registrar 컴파일 오류 | 0.8 | ✅ | pub-cache 플러그인 Kotlin 패치 (registerWith/인터페이스 제거) |
| `FB153 v1.0.0` 기기 인식 안됨 | 1.0 | ✅ | 필터 매칭 시 대소문자·공백 무시 (`toLowerCase` + `replaceAll`) |
| 앱 시작 시 BT 연결 강제로 YOLO 못 봄 | 1.0 | ✅ | 스플래시에서 BT 결과 무관하게 메인 화면 직행, 자동 재연결은 백그라운드 |
| YOLO 활성화해도 카메라 안 보임 (시뮬레이션) | 1.0 | ✅ | `camera_preview_widget.dart` 전면 교체 → 실제 `CameraController` 사용 |
| TFLite `UnmodifiableUint8ListView` Dart 3.9 오류 | 1.0 | ✅ | pub-cache `tensor.dart` 패치 → `Uint8List.fromList()` 로 교체 |
| `getBondedDevices()` Android 12+에서 실패 | 1.0 | ✅ | `BLUETOOTH_CONNECT` 런타임 권한 선확인 후 호출 |
| 모델 로딩 중 UI 피드백 없음 | 1.0 | ✅ | `YoloModelState.loading` + `loadingProgress` → `LinearProgressIndicator` 표시 |
| 가짜 모델(`yolov5s.tflite` = MobileNet SSD) 배치 | 1.0 | ✅ | 올바른 EfficientDet-Lite0 (13.2MB) 로 완전 교체 |
| 추론 0ms — 실제 인식 안 됨 | 1.0 | ✅ | `initialize()` await 추가 + `_onSvcChanged()`에서 ready 시 스트림 자동 재시작 |
| 버전 타임스탬프 UTC로 표기 | 1.0 | ✅ | `TZ='Asia/Seoul'` 고정, 연도 `25` 하드코딩 (샌드박스 시계 오류 우회) |

---

## 로봇 페어링 안내

fb153 로봇 최초 페어링 시:

1. Android 설정 → 블루투스 → `FB153 v1.0.0` 기기 선택
2. PIN 입력: `1234` (또는 `0000`)
3. 앱 실행 → 헤더 빨간 **BT 연결** 버튼 탭 → 기기 선택
4. 기기가 보이지 않으면 **전체 기기 보기** 버튼 탭
5. 연결 성공 시 헤더 버튼이 **녹색 + MAC 4자리**로 변경됨
