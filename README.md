# WhatHealth

AI 기반 맞춤형 운동 플랜 생성 iOS 앱

## 주요 기능

- **AI 운동 플랜 생성** — 목표, 경험 수준, 장비, 요일, 시간에 맞춘 맞춤형 플랜
- **멀티 LLM 프로바이더** — OpenAI, Google Gemini, OpenAI Codex 지원
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
| 배포 | Fly.io (도쿄 리전) |
| 수익화 | StoreKit 2, Google Mobile Ads |

## 프로젝트 구조

```
what_health/
├── WhatHealthApp/          # iOS 앱 (SwiftUI + MVVM)
│   ├── Models/             # SwiftData 모델
│   ├── Views/              # SwiftUI 뷰
│   ├── ViewModels/         # @Observable 뷰모델
│   ├── Services/           # Auth, LLM, Network, Store, Ads
│   └── Utilities/          # Constants, Keychain, Extensions
├── backend-rust/           # Rust 백엔드
│   └── src/
│       ├── auth/           # Apple·Google·OpenAI OAuth, JWT
│       ├── llm/            # LLM 프록시 (OpenAI, Gemini, Codex)
│       ├── quota/          # 일일 사용량 관리
│       └── subscription/   # 인앱 구매 영수증 검증
└── project.yml             # XcodeGen 설정
```

## 시작하기

### 요구 사항

- Xcode 16.0+
- iOS 17.0+
- Rust 1.88+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### iOS 앱

```bash
# Xcode 프로젝트 생성
xcodegen generate

# Xcode에서 빌드 & 실행
open WhatHealth.xcodeproj
```

### 백엔드

```bash
cd backend-rust

# 환경 변수 설정
cp .env.example .env
# .env 파일에 JWT_SECRET_KEY, OPENAI_API_KEY 등 설정

# 로컬 실행 (포트 8080)
cargo run

# 배포
fly deploy
```

## 라이선스

Private repository. All rights reserved.
