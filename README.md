# 🤖 HumanoidRobot Android App — 설계 문서

> **프로젝트명**: fb153 휴머노이드 로봇 Android 블루투스 제어 앱  
> **원본 소스**: [202605_001-YoloV5WithRobot](https://github.com/EmmettHwang/202605_001-YoloV5WithRobot)  
> **목표**: PC Python 기반 YOLOv5 + 시리얼 제어 → Android 네이티브 앱 (Bluetooth Classic 2.0 + 카메라 + YOLO 추론)  
> **작성일**: 2026-05-20  
> **버전**: v1.0 설계 초안

---

## 📋 목차

1. [시스템 개요](#1-시스템-개요)
2. [기존 소스 분석 결과](#2-기존-소스-분석-결과)
3. [Android 앱 전체 아키텍처](#3-android-앱-전체-아키텍처)
4. [Bluetooth 통신 설계](#4-bluetooth-통신-설계)
5. [UI 화면 설계](#5-ui-화면-설계)
6. [조이스틱 모듈 설계](#6-조이스틱-모듈-설계)
7. [동작 버튼 9개 설계](#7-동작-버튼-9개-설계)
8. [명령어 셋 (Command Set) 설계](#8-명령어-셋-command-set-설계)
9. [MP3 연동 설계](#9-mp3-연동-설계)
10. [카메라 + 사물인식 설계](#10-카메라--사물인식-설계)
11. [모듈별 클래스 설계](#11-모듈별-클래스-설계)
12. [데이터 모델](#12-데이터-모델)
13. [Android 프로젝트 구조](#13-android-프로젝트-구조)
14. [개발 환경 및 의존성](#14-개발-환경-및-의존성)
15. [구현 로드맵](#15-구현-로드맵)
16. [미구현 항목 및 향후 계획](#16-미구현-항목-및-향후-계획)

---

## 1. 시스템 개요

### 1-1. 기존 시스템 (PC 기반)
```
[PC]
 ├── Python (main.py)
 ├── YOLOv5 (torch, cv2) ─── 카메라 추론
 ├── robot_controller.py ─── 15-byte 패킷 생성
 └── pyserial (COM 포트) ─── Bluetooth 2.0 Classic (SPP)
                                     │
                              [fb153 로봇]
```

### 1-2. 목표 시스템 (Android 네이티브 앱)
```
[Android 스마트폰]
 ├── MainActivity (UI 통합)
 │    ├── JoystickView (커스텀 뷰)       ─── 이동 방향 제어
 │    ├── ActionButtonPanel (버튼 9개)   ─── 모션 명령 + MP3
 │    ├── CameraPreview (카메라 스트림)  ─── 실시간 영상
 │    └── DetectionOverlay              ─── YOLO 인식 결과 오버레이
 │
 ├── BluetoothManager                   ─── fb153 연결/통신
 ├── PacketBuilder                      ─── 15-byte 패킷 생성
 ├── YOLOv5Detector (TFLite)            ─── On-device 추론
 ├── AudioPlayer                        ─── MP3 재생
 └── CommandSetManager                  ─── 버튼별 명령어 셋 관리
         │
  [Bluetooth Classic 2.0 (SPP, RFCOMM)]
         │
  [fb153 휴머노이드 로봇]
```

---

## 2. 기존 소스 분석 결과

### 2-1. 통신 프로토콜 (패킷 규격)

```
패킷 크기  : 15 bytes (고정)
Baudrate  : 115,200 bps
```

| Byte 위치 | 값 | 설명 |
|:---------:|:--:|------|
| [0] | `0xFF` | Header 1 |
| [1] | `0xFF` | Header 2 |
| [2] | `0x4C` | Header 3 ('L') |
| [3] | `0x53` | Header 4 ('S') |
| [4] | `0x00` | 예약 |
| [5] | `0x00` | 예약 |
| [6] | `0x00` | 체크섬 범위 시작 |
| [7] | `0x00` | — |
| [8] | `0x30` | — |
| [9] | `0x0C` | — |
| [10] | `0x03` | — |
| **[11]** | **motion_index** | **모션 번호 (0~255)** |
| [12] | `0x00` | — |
| [13] | `100 (0x64)` | 속도/파워 |
| [14] | **checksum** | byte[6]~[13] 합산 & 0xFF |

#### 체크섬 계산
```python
chk = 0
for i in range(6, 14):
    chk = (chk + packet[i]) & 0xFF
packet[14] = chk
```

#### 패킷 예시
| 모션 | Hex 패킷 |
|------|---------|
| 모션 1 (기본자세) | `FF FF 4C 53 00 00 00 00 30 0C 03 01 00 64 A4` |
| 모션 18 (손흔들기) | `FF FF 4C 53 00 00 00 00 30 0C 03 12 00 64 B5` |
| 모션 19 (인사) | `FF FF 4C 53 00 00 00 00 30 0C 03 13 00 64 B6` |
| 모션 20 (사용자정의) | `FF FF 4C 53 00 00 00 00 30 0C 03 14 00 64 B7` |

### 2-2. 기존 모션-라벨 매핑
```python
LABEL_TO_MOTION = {
    "person":     19,   # 인사
    "bottle":     18,   # 손흔들기
    "cell phone": 20,   # 사용자 정의
}
CONF_THRESHOLD = 0.60   # 60% 이상 신뢰도에서 모션 트리거
RETURN_MOTION  = 1      # 기본 자세 복귀 모션
ACTION_HOLD_SEC = 7     # 모션 유지 시간 (초)
RETURN_HOLD_SEC = 3     # 복귀 후 대기 시간 (초)
```

### 2-3. 기존 시퀀스 상태 머신
```
[IDLE] ──trigger(N)──▶ [ACTION: N번 실행] ──7초──▶ [RETURN: 1번 실행] ──3초──▶ [IDLE]
```

---

## 3. Android 앱 전체 아키텍처

### 3-1. 레이어 구조
```
┌─────────────────────────────────────────────┐
│              Presentation Layer              │
│  MainActivity / Fragment / Custom Views      │
├─────────────────────────────────────────────┤
│               Domain Layer                   │
│  RobotCommandUseCase / DetectionUseCase      │
├─────────────────────────────────────────────┤
│               Data Layer                     │
│  BluetoothRepository / CommandSetRepository │
│  AudioRepository / DetectionRepository       │
└─────────────────────────────────────────────┘
```

### 3-2. 화면 구성 (단일 Activity)
```
MainActivity
├── Fragment: ControlFragment (메인 제어 화면)
│    ├── CameraPreviewView        (상단 60%)
│    ├── DetectionOverlayView     (카메라 위 오버레이)
│    ├── StatusBar               (연결 상태, 배터리)
│    ├── JoystickView            (좌측 하단)
│    └── ActionButtonPanel       (우측 하단, 3×3 그리드)
│
└── Fragment: SettingsFragment (설정 화면)
     ├── BluetoothScanView        (BT 기기 스캔/연결)
     ├── ButtonCommandEditor      (버튼별 명령어 셋 편집)
     └── DetectionMappingEditor   (인식 라벨→모션 매핑)
```

---

## 4. Bluetooth 통신 설계

### 4-1. 연결 방식
- **프로토콜**: Bluetooth Classic 2.0 (SPP — Serial Port Profile)
- **RFCOMM UUID**: `00001101-0000-1000-8000-00805F9B34FB` (SPP 표준)
- **Baudrate**: 115,200 bps
- **검색 조건**: 기기명이 `fb153`으로 시작하는 기기 자동 필터링

### 4-2. 연결 흐름
```
앱 시작
  │
  ▼
[BT 권한 요청]
  │ (BLUETOOTH_CONNECT, BLUETOOTH_SCAN)
  ▼
[기기 스캔] ── 기기명 필터: startsWith("fb153")
  │
  ▼
[fb153 선택] ─── createRfcommSocketToServiceRecord(SPP_UUID)
  │
  ▼
[소켓 connect()] ── 성공 → OutputStream 획득
  │
  ▼
[패킷 전송 준비 완료]
```

### 4-3. BluetoothManager 클래스 인터페이스
```kotlin
class BluetoothManager(context: Context) {
    
    // 상태
    val connectionState: StateFlow<ConnectionState>
    //   ConnectionState: DISCONNECTED | SCANNING | CONNECTING | CONNECTED | ERROR
    
    // 스캔
    fun startScan(filterPrefix: String = "fb153")
    fun stopScan()
    val discoveredDevices: StateFlow<List<BluetoothDeviceInfo>>
    
    // 연결
    fun connect(device: BluetoothDeviceInfo)
    fun disconnect()
    val isConnected: Boolean
    
    // 전송
    fun sendPacket(packet: ByteArray): Boolean
    fun sendMotion(motionIndex: Int): Boolean  // PacketBuilder 내부 호출
}
```

### 4-4. PacketBuilder (Python robot_controller.py 포팅)
```kotlin
object PacketBuilder {
    
    private val HEADER = byteArrayOf(0xFF.toByte(), 0xFF.toByte(), 0x4C, 0x53)
    const val PACKET_SIZE = 15
    
    fun build(motionIndex: Int): ByteArray {
        require(motionIndex in 0..255) { "모션 인덱스 범위 오류: $motionIndex" }
        
        val packet = ByteArray(15).apply {
            this[0] = 0xFF.toByte(); this[1] = 0xFF.toByte()
            this[2] = 0x4C;          this[3] = 0x53
            this[4] = 0x00;          this[5] = 0x00
            this[6] = 0x00;          this[7] = 0x00
            this[8] = 0x30;          this[9] = 0x0C
            this[10] = 0x03;         this[11] = motionIndex.toByte()
            this[12] = 0x00;         this[13] = 100.toByte()
        }
        // checksum
        var chk = 0
        for (i in 6..13) chk = (chk + packet[i].toInt() and 0xFF) and 0xFF
        packet[14] = chk.toByte()
        return packet
    }
}
```

### 4-5. 연속 패킷 전송 (조이스틱용)
```kotlin
// 조이스틱 이동 시 50ms 간격으로 반복 전송
class MotionRepeater(private val btManager: BluetoothManager) {
    private var repeatJob: Job? = null
    
    fun start(motionIndex: Int, intervalMs: Long = 50L) {
        repeatJob?.cancel()
        repeatJob = CoroutineScope(Dispatchers.IO).launch {
            while (isActive) {
                btManager.sendMotion(motionIndex)
                delay(intervalMs)
            }
        }
    }
    
    fun stop(returnMotion: Int = 1) {
        repeatJob?.cancel()
        btManager.sendMotion(returnMotion)  // 정지 명령
    }
}
```

---

## 5. UI 화면 설계

### 5-1. 메인 제어 화면 레이아웃

```
┌─────────────────────────────────────────────────────┐
│  📷 카메라 프리뷰 + YOLO 인식 오버레이               │
│  ┌───────────────────────────────────────────────┐  │
│  │  [BBox] person 94%   [BBox] bottle 72%        │  │
│  │                                               │  │
│  │         실시간 카메라 영상                     │  │
│  │                                               │  │
│  └───────────────────────────────────────────────┘  │
│  ● 연결됨: fb153_Robot  🔋 배터리: 82%  ⏱ 지연:12ms │
├──────────────────────────┬──────────────────────────┤
│     🕹️ JOYSTICK          │    🎮 ACTION BUTTONS      │
│                          │  ┌───┐ ┌───┐ ┌───┐       │
│       ┌───────┐          │  │ 1 │ │ 2 │ │ 3 │       │
│       │   ↑   │          │  └───┘ └───┘ └───┘       │
│    ←  │  [●]  │  →       │  ┌───┐ ┌───┐ ┌───┐       │
│       │   ↓   │          │  │ 4 │ │ 5 │ │ 6 │       │
│       └───────┘          │  └───┘ └───┘ └───┘       │
│   방향 + 속도 제어        │  ┌───┐ ┌───┐ ┌───┐       │
│                          │  │ 7 │ │ 8 │ │ 9 │       │
│                          │  └───┘ └───┘ └───┘       │
└──────────────────────────┴──────────────────────────┘
```

### 5-2. 화면 비율 (Portrait 기준)
| 영역 | 높이 비율 | 설명 |
|------|:---------:|------|
| 카메라 + YOLO | 55% | 상단 영역 |
| 상태바 | 5% | BT 연결 상태, 지연시간 |
| 조이스틱 영역 | 40% | 하단 좌측 절반 |
| 액션 버튼 영역 | 40% | 하단 우측 절반 |

### 5-3. 상태바 표시 항목
```
● 연결됨: [기기명]    또는    ○ 연결 안됨 [연결 버튼]
🔋 배터리: xx%
⏱ 지연: xxms
🎯 인식: [현재 인식 중인 객체명]
```

---

## 6. 조이스틱 모듈 설계

### 6-1. JoystickView 동작 방식

```
조이스틱 중심 → 좌표 (dx, dy) 계산 → 방향 + 속도 결정 → 모션 번호 매핑 → 패킷 전송
```

### 6-2. 방향 판정 로직
```kotlin
data class JoystickOutput(
    val direction: Direction,   // STOP, FORWARD, BACKWARD, LEFT, RIGHT,
                                // FORWARD_LEFT, FORWARD_RIGHT,
                                // BACKWARD_LEFT, BACKWARD_RIGHT
    val power: Float            // 0.0 ~ 1.0 (중심에서 거리 비율)
)

enum class Direction {
    STOP,
    FORWARD, BACKWARD, LEFT, RIGHT,
    FORWARD_LEFT, FORWARD_RIGHT,
    BACKWARD_LEFT, BACKWARD_RIGHT
}
```

### 6-3. 방향 → 모션 번호 기본 매핑 (사용자 변경 가능)
| 방향 | 기본 모션 번호 | 설명 |
|------|:-----------:|------|
| STOP | 1 | 기본 자세 (정지) |
| FORWARD | 2 | 전진 |
| BACKWARD | 3 | 후진 |
| LEFT | 4 | 왼쪽 회전 |
| RIGHT | 5 | 오른쪽 회전 |
| FORWARD_LEFT | 6 | 전진 + 좌회전 |
| FORWARD_RIGHT | 7 | 전진 + 우회전 |
| BACKWARD_LEFT | 8 | 후진 + 좌회전 |
| BACKWARD_RIGHT | 9 | 후진 + 우회전 |

> ⚠️ 실제 로봇의 이동 모션 번호는 하드웨어에 맞게 설정 화면에서 변경 필요

### 6-4. JoystickView 핵심 코드 구조
```kotlin
class JoystickView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null
) : View(context, attrs) {
    
    var onJoystickMove: ((output: JoystickOutput) -> Unit)? = null
    
    private val baseRadius = 0f  // 외부 원 반경
    private val stickRadius = 0f // 스틱 반경
    private var stickX = 0f
    private var stickY = 0f
    private var centerX = 0f
    private var centerY = 0f
    
    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.action) {
            MotionEvent.ACTION_DOWN,
            MotionEvent.ACTION_MOVE -> updateStickPosition(event.x, event.y)
            MotionEvent.ACTION_UP   -> resetToCenter()
        }
        return true
    }
    
    private fun updateStickPosition(x: Float, y: Float) {
        val dx = x - centerX
        val dy = y - centerY
        val distance = sqrt(dx * dx + dy * dy)
        val maxDistance = baseRadius - stickRadius
        
        if (distance > maxDistance) {
            // 원 경계에 클램핑
            stickX = centerX + dx / distance * maxDistance
            stickY = centerY + dy / distance * maxDistance
        } else {
            stickX = x; stickY = y
        }
        
        val power = min(distance / maxDistance, 1.0f)
        val direction = calcDirection(dx, dy, power)
        onJoystickMove?.invoke(JoystickOutput(direction, power))
        invalidate()
    }
    
    private fun calcDirection(dx: Float, dy: Float, power: Float): Direction {
        if (power < 0.15f) return Direction.STOP  // 데드존
        val angle = Math.toDegrees(atan2(dy.toDouble(), dx.toDouble()))
        return when {
            angle in -22.5..22.5   -> Direction.RIGHT
            angle in 22.5..67.5    -> Direction.BACKWARD_RIGHT
            angle in 67.5..112.5   -> Direction.BACKWARD
            angle in 112.5..157.5  -> Direction.BACKWARD_LEFT
            angle >= 157.5 || angle <= -157.5 -> Direction.LEFT
            angle in -157.5..-112.5 -> Direction.FORWARD_LEFT
            angle in -112.5..-67.5  -> Direction.FORWARD
            angle in -67.5..-22.5   -> Direction.FORWARD_RIGHT
            else -> Direction.STOP
        }
    }
}
```

### 6-5. 조이스틱 전송 주기
```
터치 시작  → 방향 감지 → 50ms 간격으로 패킷 반복 전송
터치 종료  → STOP (모션 1) 패킷 즉시 전송 → 반복 중단
```

---

## 7. 동작 버튼 9개 설계

### 7-1. 버튼 배치 (3×3 그리드)

```
┌─────────┬─────────┬─────────┐
│  BTN 1  │  BTN 2  │  BTN 3  │
│  [이름] │  [이름] │  [이름] │
│  모션N  │  모션N  │  모션N  │
├─────────┼─────────┼─────────┤
│  BTN 4  │  BTN 5  │  BTN 6  │
│  [이름] │  [이름] │  [이름] │
│  모션N  │  모션N  │  모션N  │
├─────────┼─────────┼─────────┤
│  BTN 7  │  BTN 8  │  BTN 9  │
│  [이름] │  [이름] │  [이름] │
│  모션N  │  모션N  │  모션N  │
└─────────┴─────────┴─────────┘
```

### 7-2. 각 버튼의 기본 설정

| 버튼 | 기본 이름 | 기본 모션 번호 | 기본 MP3 파일 |
|:----:|---------|:----------:|--------------|
| 1 | 인사 | 19 | hello.mp3 |
| 2 | 손흔들기 | 18 | wave.mp3 |
| 3 | 사용자정의1 | 20 | custom1.mp3 |
| 4 | 사용자정의2 | 21 | custom2.mp3 |
| 5 | 사용자정의3 | 22 | custom3.mp3 |
| 6 | 사용자정의4 | 23 | custom4.mp3 |
| 7 | 사용자정의5 | 24 | custom5.mp3 |
| 8 | 사용자정의6 | 25 | custom6.mp3 |
| 9 | 복귀 | 1 | return.mp3 |

### 7-3. 버튼 동작 흐름
```
버튼 누름 (단일 탭)
  │
  ├──▶ ① MP3 재생 시작 (AudioPlayer.play)
  ├──▶ ② BT 패킷 전송 (BluetoothManager.sendMotion)
  └──▶ ③ 버튼 시각적 피드백 (누름 애니메이션, 색상 변화)

버튼 설정 (길게 누름)
  └──▶ CommandSetEditor Dialog 열기
         ├── 버튼 이름 변경
         ├── 모션 번호 변경 (슬라이더 0~255)
         ├── MP3 파일 선택 (파일 피커 or URL 입력)
         └── 저장 → SharedPreferences 영구 저장
```

### 7-4. ActionButton 데이터 모델
```kotlin
data class ActionButtonConfig(
    val id: Int,                    // 버튼 번호 (1~9)
    val label: String,              // 버튼 표시 이름
    val motionIndex: Int,           // 전송할 모션 번호 (0~255)
    val mp3FilePath: String?,       // MP3 파일 경로 (null = 소리 없음)
    val mp3Url: String?,            // MP3 URL (파일 없을 때)
    val color: Int,                 // 버튼 배경색 (ARGB)
    val iconResId: Int?,            // 아이콘 리소스 ID (optional)
    val commandSequence: List<Int>  // 연속 모션 시퀀스 (고급)
)
```

---

## 8. 명령어 셋 (Command Set) 설계

### 8-1. 명령어 셋 구조

각 버튼은 **단일 모션** 또는 **연속 모션 시퀀스**를 가질 수 있습니다.

```kotlin
data class CommandSet(
    val buttonId: Int,
    val name: String,
    val commands: List<CommandStep>   // 순서대로 실행
)

data class CommandStep(
    val motionIndex: Int,       // 실행할 모션 번호
    val holdDurationMs: Long,   // 해당 모션 유지 시간 (ms)
    val repeatCount: Int = 1    // 반복 횟수
)
```

### 8-2. 명령어 셋 예시

**단순 모션 (1개):**
```json
{
  "buttonId": 1,
  "name": "인사",
  "commands": [
    { "motionIndex": 19, "holdDurationMs": 3000, "repeatCount": 1 }
  ]
}
```

**연속 모션 시퀀스 (복합 동작):**
```json
{
  "buttonId": 4,
  "name": "댄스",
  "commands": [
    { "motionIndex": 15, "holdDurationMs": 1000, "repeatCount": 1 },
    { "motionIndex": 16, "holdDurationMs": 1000, "repeatCount": 2 },
    { "motionIndex": 17, "holdDurationMs": 1500, "repeatCount": 1 },
    { "motionIndex": 1,  "holdDurationMs": 500,  "repeatCount": 1 }
  ]
}
```

### 8-3. CommandSetManager 클래스
```kotlin
class CommandSetManager(context: Context) {
    
    private val prefs = context.getSharedPreferences("command_sets", Context.MODE_PRIVATE)
    
    // 저장 (JSON 직렬화)
    fun saveCommandSet(config: ActionButtonConfig)
    
    // 불러오기
    fun loadCommandSet(buttonId: Int): ActionButtonConfig
    fun loadAllCommandSets(): List<ActionButtonConfig>
    
    // 초기화 (기본값으로 리셋)
    fun resetToDefaults()
    
    // 실행
    suspend fun executeCommandSet(
        config: ActionButtonConfig,
        btManager: BluetoothManager
    )
}
```

### 8-4. 명령어 셋 편집 UI (SettingsFragment)

```
┌─────────────────────────────────────┐
│  버튼 3 설정                   [✕]  │
├─────────────────────────────────────┤
│  버튼 이름: [댄스             ]     │
│                                     │
│  아이콘: 🎵 [변경]                  │
│                                     │
│  색상: [■■■■■■■■■] [선택]          │
│                                     │
│  ─── 명령어 시퀀스 ───              │
│  ┌────────────────────────────────┐ │
│  │ 1단계: 모션 [15] 유지 [1000]ms │ │
│  │ 2단계: 모션 [16] 유지 [1000]ms │ │
│  │ 3단계: 모션 [17] 유지 [1500]ms │ │
│  │ [+ 단계 추가]                  │ │
│  └────────────────────────────────┘ │
│                                     │
│  ─── MP3 연동 ───                   │
│  파일: [hello.mp3         ] [선택]  │
│  URL:  [https://...       ]         │
│  [▶ 미리듣기]                       │
│                                     │
│         [취소]    [저장]            │
└─────────────────────────────────────┘
```

---

## 9. MP3 연동 설계

### 9-1. MP3 소스 방식 (2가지 지원)

| 방식 | 설명 | 우선순위 |
|------|------|:-------:|
| **로컬 파일** | 앱 내부 저장소 또는 외부 SD의 MP3 | 1순위 |
| **URL 스트리밍** | http/https URL의 MP3 직접 재생 | 2순위 (파일 없을 때) |

### 9-2. AudioPlayer 클래스
```kotlin
class AudioPlayer(private val context: Context) {
    
    private var mediaPlayer: MediaPlayer? = null
    
    // 로컬 파일 재생
    fun playFile(filePath: String) {
        release()
        mediaPlayer = MediaPlayer().apply {
            setDataSource(filePath)
            prepare()
            start()
        }
    }
    
    // URL 스트리밍 재생
    fun playUrl(url: String) {
        release()
        mediaPlayer = MediaPlayer().apply {
            setDataSource(context, Uri.parse(url))
            prepareAsync()
            setOnPreparedListener { it.start() }
        }
    }
    
    // 앱 내 Asset 재생 (기본 사운드)
    fun playAsset(assetName: String) {
        release()
        val afd = context.assets.openFd(assetName)
        mediaPlayer = MediaPlayer().apply {
            setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            prepare()
            start()
        }
    }
    
    // 중지 및 해제
    fun stop() { mediaPlayer?.stop() }
    fun release() {
        mediaPlayer?.release()
        mediaPlayer = null
    }
}
```

### 9-3. 버튼 동작 시 MP3 재생 흐름
```
버튼 탭 이벤트
  │
  ├─ mp3FilePath != null?
  │     YES ──▶ AudioPlayer.playFile(mp3FilePath)
  │     NO  ──▶ mp3Url != null?
  │                  YES ──▶ AudioPlayer.playUrl(mp3Url)
  │                  NO  ──▶ (기본 효과음 재생 or 무음)
  │
  └─ BluetoothManager.sendMotion(motionIndex) (동시 실행)
```

### 9-4. 기본 내장 사운드 (assets/sounds/)
```
assets/
  sounds/
    hello.mp3       (인사 모션용)
    wave.mp3        (손흔들기 모션용)
    beep.mp3        (기본 효과음)
    connect.mp3     (BT 연결 성공음)
    disconnect.mp3  (BT 연결 해제음)
```

---

## 10. 카메라 + 사물인식 설계

### 10-1. 카메라 스트림 (CameraX 사용)
```kotlin
// CameraX 기반 프리뷰 + 분석
val preview = Preview.Builder().build()
val imageAnalysis = ImageAnalysis.Builder()
    .setTargetResolution(Size(640, 480))
    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
    .build()

imageAnalysis.setAnalyzer(executor) { imageProxy ->
    yoloDetector.detect(imageProxy) { results ->
        overlayView.updateDetections(results)
        handleDetectionResults(results)
    }
    imageProxy.close()
}
```

### 10-2. YOLOv5 On-device 추론 (TFLite)

> 📌 기존 PC의 `torch` 모델 → Android용 **TFLite** 변환 필요

#### 모델 변환 순서
```
YOLOv5s (PyTorch .pt)
  │
  ▼ python export.py --weights yolov5s.pt --include tflite --img 320
  │
YOLOv5s_fp16.tflite
  │
  ▼ (앱 assets 폴더에 배치)
  │
Android TFLite Interpreter
```

#### YOLOv5Detector 클래스
```kotlin
class YOLOv5Detector(context: Context) {
    
    private val interpreter: Interpreter
    private val inputSize = 320  // 모델 입력 크기
    private val labels: List<String>  // COCO 80개 클래스
    
    // LABEL_TO_MOTION 매핑 (기존 Python 코드 동일)
    private val labelToMotion = mutableMapOf(
        "person"     to 19,
        "bottle"     to 18,
        "cell phone" to 20
    )
    
    data class Detection(
        val label: String,
        val confidence: Float,
        val boundingBox: RectF
    )
    
    fun detect(imageProxy: ImageProxy): List<Detection> {
        val bitmap = imageProxy.toBitmap()
        val resized = Bitmap.createScaledBitmap(bitmap, inputSize, inputSize, true)
        // TFLite 추론 수행
        // NMS(Non-Maximum Suppression) 후처리
        // Detection 리스트 반환
    }
    
    // 설정에서 매핑 변경 가능
    fun updateLabelMapping(label: String, motionIndex: Int)
    fun removeLabelMapping(label: String)
}
```

### 10-3. DetectionOverlayView
```kotlin
class DetectionOverlayView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null
) : View(context, attrs) {
    
    private var detections: List<YOLOv5Detector.Detection> = emptyList()
    
    fun updateDetections(results: List<YOLOv5Detector.Detection>) {
        detections = results
        invalidate()  // 다시 그리기
    }
    
    override fun onDraw(canvas: Canvas) {
        for (det in detections) {
            // 바운딩 박스 그리기
            canvas.drawRect(det.boundingBox, boxPaint)
            // 라벨 + 신뢰도 텍스트
            canvas.drawText(
                "${det.label} ${(det.confidence * 100).toInt()}%",
                det.boundingBox.left,
                det.boundingBox.top - 10,
                textPaint
            )
        }
    }
}
```

### 10-4. 인식 결과 → 자동 모션 트리거 (기존 Python 로직 포팅)
```kotlin
class DetectionMotionHandler(
    private val btManager: BluetoothManager,
    private val detector: YOLOv5Detector
) {
    // Python의 MotionSequencer 동일 로직
    private var state = State.IDLE
    private var currentMotion = 0
    private var actionStartTime = 0L
    
    val CONF_THRESHOLD = 0.60f
    val ACTION_HOLD_MS = 7_000L
    val RETURN_HOLD_MS = 3_000L
    val RETURN_MOTION = 1
    
    enum class State { IDLE, ACTION, RETURN }
    
    fun onDetectionResults(results: List<YOLOv5Detector.Detection>) {
        // Python main.py의 메인 루프 로직과 동일
        val top = results
            .filter { it.label in detector.labelToMotion }
            .maxByOrNull { it.confidence }
        
        update()  // 상태 머신 업데이트
        
        if (state == State.IDLE && top != null && top.confidence >= CONF_THRESHOLD) {
            val motion = detector.labelToMotion[top.label]!!
            trigger(motion)
        }
    }
}
```

### 10-5. 카메라 + YOLO 성능 요구사항
| 항목 | 목표값 | 비고 |
|------|:------:|------|
| 추론 FPS | 10~15 fps | YOLOv5s TFLite fp16 |
| 추론 지연 | < 100ms | 320×320 입력 기준 |
| 카메라 해상도 | 640×480 | 프리뷰 |
| 지원 기기 | Android 8.0+ | API 26 이상 |

---

## 11. 모듈별 클래스 설계

### 11-1. 전체 클래스 다이어그램

```
MainActivity
├── ControlFragment
│    ├── JoystickView (Custom View)
│    │    └── JoystickOutput (data class)
│    ├── ActionButtonPanel (Custom ViewGroup)
│    │    └── ActionButtonView × 9
│    ├── CameraPreviewView (CameraX)
│    └── DetectionOverlayView (Custom View)
│
├── SettingsFragment
│    ├── BluetoothScanAdapter
│    ├── ButtonCommandEditorDialog
│    └── DetectionMappingAdapter
│
├── BluetoothManager (Singleton)
│    ├── PacketBuilder (Object)
│    └── MotionRepeater
│
├── YOLOv5Detector
│    └── Detection (data class)
│
├── DetectionMotionHandler
│
├── CommandSetManager
│    └── ActionButtonConfig (data class)
│    └── CommandSet (data class)
│
└── AudioPlayer
```

---

## 12. 데이터 모델

### 12-1. 저장소: SharedPreferences

**키 구조:**
```
button_1_label       = "인사"
button_1_motion      = 19
button_1_mp3_path    = "/storage/.../hello.mp3"
button_1_mp3_url     = ""
button_1_color       = "#FF6200EE"
button_1_sequence    = "[{\"motionIndex\":19,\"holdMs\":3000}]"

button_2_label       = "손흔들기"
button_2_motion      = 18
...
```

### 12-2. 저장소: Room Database (선택적)

```kotlin
@Entity(tableName = "action_buttons")
data class ActionButtonEntity(
    @PrimaryKey val id: Int,
    val label: String,
    val motionIndex: Int,
    val mp3FilePath: String?,
    val mp3Url: String?,
    val color: Int,
    val commandSequenceJson: String  // JSON 직렬화
)

@Entity(tableName = "detection_mappings")
data class DetectionMappingEntity(
    @PrimaryKey val label: String,  // YOLO 클래스명
    val motionIndex: Int,
    val isEnabled: Boolean
)
```

---

## 13. Android 프로젝트 구조

```
app/
├── src/main/
│    ├── java/com/fb153/robotcontrol/
│    │    ├── MainActivity.kt
│    │    ├── bluetooth/
│    │    │    ├── BluetoothManager.kt
│    │    │    ├── PacketBuilder.kt
│    │    │    └── MotionRepeater.kt
│    │    ├── ui/
│    │    │    ├── control/
│    │    │    │    ├── ControlFragment.kt
│    │    │    │    ├── JoystickView.kt
│    │    │    │    ├── ActionButtonPanel.kt
│    │    │    │    └── ActionButtonView.kt
│    │    │    ├── camera/
│    │    │    │    ├── CameraPreviewView.kt
│    │    │    │    └── DetectionOverlayView.kt
│    │    │    └── settings/
│    │    │         ├── SettingsFragment.kt
│    │    │         ├── BluetoothScanFragment.kt
│    │    │         └── ButtonCommandEditorDialog.kt
│    │    ├── detection/
│    │    │    ├── YOLOv5Detector.kt
│    │    │    ├── DetectionMotionHandler.kt
│    │    │    └── Detection.kt
│    │    ├── audio/
│    │    │    └── AudioPlayer.kt
│    │    ├── command/
│    │    │    ├── CommandSetManager.kt
│    │    │    ├── ActionButtonConfig.kt
│    │    │    └── CommandSet.kt
│    │    └── data/
│    │         ├── database/
│    │         │    ├── AppDatabase.kt
│    │         │    └── dao/
│    │         └── repository/
│    │              ├── CommandSetRepository.kt
│    │              └── DetectionMappingRepository.kt
│    │
│    ├── res/
│    │    ├── layout/
│    │    │    ├── activity_main.xml
│    │    │    ├── fragment_control.xml
│    │    │    ├── fragment_settings.xml
│    │    │    ├── view_joystick.xml
│    │    │    ├── view_action_button.xml
│    │    │    └── dialog_button_editor.xml
│    │    └── values/
│    │         ├── colors.xml
│    │         ├── strings.xml
│    │         └── themes.xml
│    │
│    └── assets/
│         ├── models/
│         │    ├── yolov5s.tflite
│         │    └── coco_labels.txt
│         └── sounds/
│              ├── hello.mp3
│              ├── wave.mp3
│              ├── beep.mp3
│              ├── connect.mp3
│              └── disconnect.mp3
│
├── build.gradle (app)
└── AndroidManifest.xml
```

---

## 14. 개발 환경 및 의존성

### 14-1. 개발 환경
| 항목 | 버전/사양 |
|------|---------|
| Android Studio | Ladybug 2024.2.1 이상 |
| Kotlin | 1.9.x |
| minSdk | 26 (Android 8.0) |
| targetSdk | 34 (Android 14) |
| Gradle | 8.x |

### 14-2. build.gradle 주요 의존성
```groovy
dependencies {
    // Kotlin Coroutines
    implementation 'org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3'
    
    // CameraX (카메라 프리뷰 + 분석)
    implementation 'androidx.camera:camera-camera2:1.3.0'
    implementation 'androidx.camera:camera-lifecycle:1.3.0'
    implementation 'androidx.camera:camera-view:1.3.0'
    
    // TensorFlow Lite (YOLOv5 추론)
    implementation 'org.tensorflow:tensorflow-lite:2.13.0'
    implementation 'org.tensorflow:tensorflow-lite-gpu:2.13.0'
    implementation 'org.tensorflow:tensorflow-lite-support:0.4.4'
    
    // Room Database (명령어 셋 저장)
    implementation 'androidx.room:room-runtime:2.6.0'
    implementation 'androidx.room:room-ktx:2.6.0'
    kapt 'androidx.room:room-compiler:2.6.0'
    
    // Gson (JSON 직렬화)
    implementation 'com.google.code.gson:gson:2.10.1'
    
    // ViewBinding
    buildFeatures { viewBinding = true }
}
```

### 14-3. AndroidManifest.xml 권한
```xml
<!-- Bluetooth 권한 -->
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />

<!-- 카메라 권한 -->
<uses-permission android:name="android.permission.CAMERA" />

<!-- 저장소 권한 (MP3 파일 접근) -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />

<!-- 인터넷 (MP3 URL 스트리밍) -->
<uses-permission android:name="android.permission.INTERNET" />

<!-- 하드웨어 기능 선언 -->
<uses-feature android:name="android.hardware.bluetooth" android:required="true" />
<uses-feature android:name="android.hardware.camera" android:required="true" />
```

---

## 15. 구현 로드맵

### Phase 1 — Bluetooth 기본 통신 (1~2주)
- [ ] Android 프로젝트 생성 (Kotlin, MVVM)
- [ ] BluetoothManager 구현 (스캔, 연결, SPP 통신)
- [ ] PacketBuilder 구현 (Python 로직 포팅)
- [ ] 간단한 테스트 UI로 fb153 연결 및 패킷 전송 확인

### Phase 2 — 조이스틱 + 버튼 UI (2~3주)
- [ ] JoystickView 커스텀 뷰 구현
- [ ] ActionButtonPanel (3×3 그리드) 구현
- [ ] CommandSetManager 구현 (저장/불러오기)
- [ ] 버튼 편집 다이얼로그 구현

### Phase 3 — MP3 연동 (1주)
- [ ] AudioPlayer 구현 (로컬/URL/Asset)
- [ ] 버튼-MP3 연결 UI
- [ ] 기본 사운드 파일 준비

### Phase 4 — 카메라 + YOLO (2~3주)
- [ ] CameraX 연동 (프리뷰)
- [ ] YOLOv5s TFLite 모델 변환
- [ ] YOLOv5Detector 구현
- [ ] DetectionOverlayView 구현
- [ ] DetectionMotionHandler 구현 (Python 로직 포팅)

### Phase 5 — 통합 및 최적화 (1~2주)
- [ ] 전체 화면 레이아웃 통합
- [ ] 성능 최적화 (추론 fps, 배터리)
- [ ] 설정 화면 완성
- [ ] 실기기 테스트 (fb153 로봇)

---

## 16. 미구현 항목 및 향후 계획

### 현재 미구현 (향후 추가 예정)
| 항목 | 설명 |
|------|------|
| TTS 연동 | 인식 결과를 음성으로 읽어주는 기능 |
| 로봇 배터리 모니터링 | BT로 로봇 배터리 잔량 수신 |
| 모션 스크립트 녹화 | 버튼 입력 시퀀스를 녹화/재생 |
| 다국어 지원 | 영어/한국어 전환 |
| 클라우드 백업 | 버튼 설정 클라우드 동기화 |
| iOS 버전 | Swift로 동일 기능 구현 |
| Wi-Fi 모드 | BT 대신 Wi-Fi TCP 소켓 제어 |

### 알려진 제약사항
- iOS는 Bluetooth Classic SPP 지원 불가 → Android 전용
- YOLOv5 TFLite 추론은 GPU 델리게이트 미지원 기기에서 느릴 수 있음
- MP3 URL 스트리밍은 인터넷 연결 필요
- Android 12+ 에서 정확한 BT 권한 처리 필요 (BLUETOOTH_CONNECT)

---

## 📞 참고 자료

| 항목 | 링크 |
|------|------|
| 원본 소스 | https://github.com/EmmettHwang/202605_001-YoloV5WithRobot |
| Android BT Classic | https://developer.android.com/guide/topics/connectivity/bluetooth/connect-bluetooth-devices |
| CameraX | https://developer.android.com/training/camerax |
| TFLite YOLOv5 | https://github.com/ultralytics/yolov5/issues/251 |
| Android Audio | https://developer.android.com/guide/topics/media/mediaplayer |

---

*이 문서는 설계 초안입니다. 실제 구현 시 하드웨어 로봇의 모션 번호 테이블을 확인하고 매핑을 조정하세요.*
