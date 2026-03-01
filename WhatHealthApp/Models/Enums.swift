import Foundation
import SwiftUI

enum ExerciseGoal: String, Codable, CaseIterable, Identifiable {
    case strength = "근력 증가"
    case weightLoss = "체중 감량"
    case endurance = "체력 향상"
    case flexibility = "유연성 향상"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .strength: return "figure.strengthtraining.traditional"
        case .weightLoss: return "flame.fill"
        case .endurance: return "figure.run"
        case .flexibility: return "figure.yoga"
        }
    }
}

enum ExperienceLevel: String, Codable, CaseIterable, Identifiable {
    case beginner = "초보자"
    case intermediate = "중급자"
    case advanced = "고급자"

    var id: String { rawValue }
}

enum Equipment: String, Codable, CaseIterable, Identifiable {
    case bodyweight = "맨몸"
    case dumbbell = "덤벨"
    case barbell = "바벨"
    case machine = "머신"
    case band = "밴드"
    case kettlebell = "케틀벨"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .bodyweight: return "figure.stand"
        case .dumbbell: return "dumbbell.fill"
        case .barbell: return "figure.strengthtraining.traditional"
        case .machine: return "gearshape.2.fill"
        case .band: return "circle.dotted"
        case .kettlebell: return "figure.cross.training"
        }
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

enum LLMProviderType: String, Codable, CaseIterable, Identifiable {
    case openAI = "OpenAI"
    case gemini = "Google Gemini"
    case codex = "OpenAI Codex"

    var id: String { rawValue }

    var modelName: String {
        switch self {
        case .openAI: return "gpt-4o-mini"
        case .gemini: return "gemini-3-flash-preview"
        case .codex: return "gpt-5.3-codex"
        }
    }

    var icon: String {
        switch self {
        case .openAI: return "brain"
        case .gemini: return "sparkles"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        }
    }

    var description: String {
        switch self {
        case .openAI: return "범용 AI 모델"
        case .gemini: return "Google OAuth 무료 사용"
        case .codex: return "ChatGPT OAuth 또는 API 키"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .gemini, .codex: return false
        case .openAI: return true
        }
    }
}

enum DayOfWeek: Int, Codable, CaseIterable, Identifiable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: Int { rawValue }

    var shortName: String {
        switch self {
        case .monday: return "월"
        case .tuesday: return "화"
        case .wednesday: return "수"
        case .thursday: return "목"
        case .friday: return "금"
        case .saturday: return "토"
        case .sunday: return "일"
        }
    }

    var fullName: String {
        switch self {
        case .monday: return "월요일"
        case .tuesday: return "화요일"
        case .wednesday: return "수요일"
        case .thursday: return "목요일"
        case .friday: return "금요일"
        case .saturday: return "토요일"
        case .sunday: return "일요일"
        }
    }

    static func fromCurrentWeekday() -> DayOfWeek {
        let weekday = Calendar.current.component(.weekday, from: Date())
        // Calendar weekday: 1=Sunday, 2=Monday, ...
        let mapped = weekday == 1 ? 7 : weekday - 1
        return DayOfWeek(rawValue: mapped) ?? .monday
    }
}

enum ExerciseType: String, Codable {
    case strength, cardio, stretching

    var badge: String {
        switch self {
        case .strength: return "근력"
        case .cardio: return "유산소"
        case .stretching: return "스트레칭"
        }
    }

    var color: Color {
        switch self {
        case .strength: return .indigo
        case .cardio: return .orange
        case .stretching: return .green
        }
    }

    static func from(_ raw: String?) -> ExerciseType {
        guard let raw else { return .strength }
        return ExerciseType(rawValue: raw) ?? .strength
    }

    /// exerciseType 필드가 nil인 기존 데이터용 — 운동 이름으로 타입 추론
    static func infer(from name: String, raw: String?) -> ExerciseType {
        if let raw, let type = ExerciseType(rawValue: raw) {
            return type
        }
        let lower = name.lowercased()
        let cardioKeywords = ["트레드밀", "러닝", "달리기", "걷기", "워킹", "자전거", "사이클", "바이크",
                              "조깅", "로잉", "줄넘기", "유산소", "계단", "스텝", "elliptical", "treadmill",
                              "running", "cycling", "rowing", "jumping jack", "burpee", "버피"]
        let stretchKeywords = ["스트레칭", "요가", "폼롤러", "쿨다운", "cooldown", "stretch", "유연성"]

        if cardioKeywords.contains(where: { lower.contains($0) }) {
            return .cardio
        }
        if stretchKeywords.contains(where: { lower.contains($0) }) {
            return .stretching
        }
        return .strength
    }
}

enum SessionDuration: Int, CaseIterable, Identifiable {
    case thirty = 30
    case fortyFive = 45
    case sixty = 60
    case ninety = 90

    var id: Int { rawValue }

    var displayName: String {
        "\(rawValue)분"
    }
}
