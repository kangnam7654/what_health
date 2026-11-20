# WhatHealth

AI 기반 맞춤형 운동 플랜 생성 iOS 앱

목표·경험 수준·장비·운동 요일·세션 시간을 고르면 LLM이 주간 운동 플랜을 JSON으로 만들어 주고, 앱은 이를 파싱해 저장·기록할 수 있는 플랜으로 보여줍니다. 모델 응답은 그대로 믿을 수 없기 때문에, 저장 가능한 플랜으로 보여주기 전에 구조를 검증합니다.

## 리뷰어용 안내

[합성 오프라인 예시](Tests/PlanParserHarness/main.swift)에서 `routines: []`는 검증 오류가 되고, 월·수·금요일 루틴은 같은 요일을 선택했을 때 파싱됩니다. 채팅에서도 빈 루틴은 저장 가능한 플랜 카드가 아닌 일반 텍스트로 남습니다. 실제 LLM 생성 결과나 운동 효과를 보여주는 예시는 아닙니다.

### 코드 경로

1. `WhatHealthApp/ViewModels/PlanGeneratorViewModel.swift` — `generatePlan()`이 프롬프트를 만들고(`PromptBuilder`), 응답을 사용자가 선택한 요일 집합과 함께 `PlanParser.parse(response:requiredDays:)`에 넘깁니다.
2. `WhatHealthApp/Services/PlanParser.swift` — JSON(코드 펜스 허용) 디코딩 후 구조 검증:
   - title·summary·focus·운동 이름·reps는 공백이 아니어야 함
   - 루틴 1개 이상, 루틴마다 운동 1개 이상
   - 요일은 `DayOfWeek.fullName`(월요일~일요일)과 정확히 일치, 중복 불가
   - `sets` 1 이상, `restSeconds` 0 이상
   - `goal`은 생략 가능하지만, 있으면 `ExerciseGoal` 값 중 하나여야 함
   - 전용 생성기에서는 응답 요일 집합이 선택한 요일과 **정확히** 같아야 함(누락·추가 모두 거부)
   - 잘못된 응답은 보정하지 않고 `LLMError.parsingError`로 읽을 수 있는 오류를 보여줍니다
3. `WhatHealthApp/Services/ChatResponseParser.swift` — 채팅 응답의 `[EXERCISE_PLAN]…[/EXERCISE_PLAN]` 블록을 같은 파서로 검사합니다(요일 선택 제약은 없음). 검증에 실패한 블록은 저장 가능한 플랜 카드가 아니라 일반 텍스트로 남습니다.

이 검증은 응답 **형식**을 확인할 뿐이며, 운동 내용의 의학적 안전성을 판단하지 않습니다.

### 로그인 없이 오프라인으로 확인하기

```bash
bash Tests/PlanParserHarness/run.sh
```

실제 앱 소스(`Enums`, `CodableTypes`, `LLMServiceProtocol`, `PlanParser`, `ChatResponseParser`)를 macOS용으로 함께 컴파일해, **합성(synthetic) 픽스처**로 파서를 검사하는 회귀 하네스입니다. 빈 루틴·중복/잘못된 요일·선택 요일 누락/추가·잘못된 필드·알 수 없는 goal과, 정상적인 다일(多日) 플랜 및 채팅 태그 플랜(코드 펜스 포함)을 다룹니다. 네트워크나 유료 모델 호출은 없고, 빌드 결과물은 임시 디렉터리에만 만들었다가 삭제합니다. 실패가 있으면 0이 아닌 종료 코드를 반환합니다. Xcode(또는 Swift 툴체인)가 설치된 macOS가 필요합니다.

하네스 결과는 실제 LLM 출력이 아닙니다. 실제 플랜 생성(프로바이더 연동)은 로그인과 백엔드가 필요하며, 이 저장소만으로는 그 결과를 재현하거나 보장하지 않습니다.

## 주요 기능

- **AI 운동 플랜 생성** — 목표, 경험 수준, 장비, 요일, 시간에 맞춘 맞춤형 플랜
- **멀티 LLM 프로바이더** — OpenAI, Google Gemini, OpenAI Codex 연동 코드
- **AI 채팅** — 운동 관련 질문에 AI가 답변, 채팅 중 플랜 생성 가능
- **운동 기록** — 세트/무게/횟수 기록, 유산소·스트레칭 타입별 입력, 휴식 타이머
- **운동 영상 연결** — 운동별 YouTube 영상 검색·저장
- **구독 & 쿼타** — Pro 구독(StoreKit 2), 리워드 광고로 무료 사용량 확장

## 기술 스택

| 구분 | 기술 |
|------|------|
| iOS | SwiftUI, SwiftData, iOS 17+ |
| 인증 | Sign in with Apple, Google OAuth, ChatGPT OAuth (PKCE) |
| 백엔드 | Rust (Axum + SQLite) |
| 배포 설정 | Fly.io (도쿄 리전) |
| 수익화 | StoreKit 2, Google Mobile Ads |

## 프로젝트 구조

```
what_health/
├── WhatHealthApp/          # iOS 앱 (SwiftUI + MVVM)
│   ├── Models/             # SwiftData 모델
│   ├── Views/              # SwiftUI 뷰
│   ├── ViewModels/         # @Observable 뷰모델
│   ├── Services/           # Auth, LLM, Network, Store, Ads, 파서
│   └── Utilities/          # Constants, Keychain, Extensions
├── Tests/
│   └── PlanParserHarness/  # 오프라인 파서 회귀 하네스
├── backend-rust/           # Rust 백엔드
│   └── src/
│       ├── auth/           # Apple·Google·OpenAI OAuth, JWT
│       ├── llm/            # LLM 프록시 (OpenAI, Gemini, Codex)
│       ├── quota/          # 일일 사용량 관리
│       └── subscription/   # 인앱 구매 영수증 검증
├── WhatHealth.xcodeproj    # 빌드에 사용하는 Xcode 프로젝트
└── project.yml             # 이전 XcodeGen 설정 (현재 경로와 맞지 않음)
```

## 시작하기

### 요구 사항

- Xcode 16.0+
- iOS 17.0+
- Rust 1.88+ (백엔드를 로컬에서 실행할 때)

### iOS 앱

저장소에 포함된 `WhatHealth.xcodeproj`를 그대로 사용합니다. `project.yml`은 리브랜딩 이전의 `ExercisePlanApp` 경로를 가리키고 있어 `xcodegen generate`로 다시 생성하면 안 됩니다.

```bash
open WhatHealth.xcodeproj
# Xcode에서 WhatHealth 타깃을 iPhone 시뮬레이터로 빌드 & 실행
```

Swift 패키지(Google Mobile Ads) 의존성은 처음 열 때 Xcode가 내려받습니다. 플랜 생성·채팅 같은 AI 기능은 로그인과 백엔드 연결이 있어야 동작합니다.

### 백엔드 (로컬 실행)

```bash
cd backend-rust

# 환경 변수 설정
cp .env.example .env
# .env 파일에 JWT_SECRET_KEY, OPENAI_API_KEY 등 설정

# 로컬 실행 (포트 8080)
cargo run
```

## 라이선스

공개 소스 저장소이지만 별도의 라이선스가 명시되어 있지 않습니다(LICENSE 파일 없음).
