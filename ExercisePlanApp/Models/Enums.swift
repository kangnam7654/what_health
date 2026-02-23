import Foundation

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

    var id: String { rawValue }

    var modelName: String {
        switch self {
        case .openAI: return "gpt-4o-mini"
        case .gemini: return "gemini-2.0-flash"
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
