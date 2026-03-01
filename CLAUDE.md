# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

WhatHealth — AI 기반 맞춤형 운동 플랜 iOS 앱 + Rust 백엔드. 멀티 LLM 프로바이더(OpenAI, Gemini, Codex)를 지원하며, 각 프로바이더별 OAuth 인증 흐름을 갖추고 있음.

## Build & Run

### iOS App
```bash
# Xcode 프로젝트 생성 (project.yml 수정 후 반드시 실행)
xcodegen generate

# 빌드 (시뮬레이터)
xcodebuild -project WhatHealth.xcodeproj -scheme WhatHealth \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# 실기기 빌드는 Xcode에서 직접 실행
```

### Rust Backend
```bash
cd backend-rust

# 로컬 실행
cargo run

# 릴리스 빌드
cargo build --release

# 배포 (Fly.io)
fly deploy
```

### Environment Setup
- `backend-rust/.env.example` 참고하여 `.env` 생성
- 필수 변수: `DATABASE_URL`, `JWT_SECRET_KEY`, `OPENAI_API_KEY`

## Architecture

### iOS (SwiftUI + SwiftData, MVVM)

```
Views → ViewModels (@Observable) → Services → APIClient → Rust Backend
                                       ↓
                                  SwiftData (로컬 저장)
```

- **SwiftData 모델**: `WhatHealth` (운동 플랜), `ChatSession`/`ChatMessage`, `WorkoutLog`, `UserProfile`, `SavedExerciseVideo`
- **Auth 흐름**: Apple/Google/ChatGPT OAuth → 백엔드에서 JWT 발급 → Keychain 저장 → APIClient가 Bearer 토큰 자동 첨부
- **LLM 라우팅**: `LLMServiceFactory`가 선택된 프로바이더에 따라 `BackendLLMService` (프록시) 또는 직접 호출 서비스 생성
- **수익화**: StoreKit 2 (Pro 구독) + GoogleMobileAds (리워드 광고로 보너스 쿼타)
- **싱글톤**: `AuthManager.shared`, `APIClient.shared`, `StoreManager.shared`, `AdManager.shared`
- **API Base URL**: 시뮬레이터 → `localhost:8000`, 프로덕션 → `whathealth.fly.dev` (Constants.swift에서 자동 분기)

### Rust Backend (Axum + SQLite)

```
Axum Router → Auth Middleware (JWT) → Route Handlers → SQLite (sqlx)
```

- **모듈**: `auth/` (Apple·Google·OpenAI OAuth, JWT), `llm/` (프록시·라우팅), `quota/` (일일 사용량), `subscription/` (인앱 구매 영수증 검증)
- **DB**: SQLite, `CREATE TABLE IF NOT EXISTS` 패턴 (마이그레이션 없음). 테이블: `users`, `subscriptions`, `usage_records`
- **배포**: Fly.io (도쿄 nrt 리전), 256MB RAM, 영구 볼륨 `/data`에 SQLite 파일 저장
- **포트**: 8080

## Key Conventions

- iOS UI 텍스트는 **한국어**
- 커밋 메시지는 한국어 (예: `feat: Rust 백엔드 추가`)
- AccentColor: `#FF6B35` (오렌지), ExerciseType.strength 컬러는 `.indigo` (accent과 충돌 방지)
- `project.yml` 수정 시 `xcodegen generate`로 xcodeproj 재생성 필요
- Deployment target: iOS 17.0
