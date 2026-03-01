import Foundation
import SwiftData

@Model
final class UserProfile {
    var goal: ExerciseGoal
    var experienceLevel: ExperienceLevel
    var equipmentData: Data
    var trainingDaysData: Data
    var sessionDuration: Int
    var additionalNotes: String
    var createdAt: Date
    var updatedAt: Date

    var equipment: [Equipment] {
        get {
            (try? JSONDecoder().decode([Equipment].self, from: equipmentData)) ?? []
        }
        set {
            equipmentData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var trainingDays: [DayOfWeek] {
        get {
            (try? JSONDecoder().decode([DayOfWeek].self, from: trainingDaysData)) ?? []
        }
        set {
            trainingDaysData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    init(
        goal: ExerciseGoal = .strength,
        experienceLevel: ExperienceLevel = .beginner,
        equipment: [Equipment] = [.bodyweight],
        trainingDays: [DayOfWeek] = [.monday, .wednesday, .friday],
        sessionDuration: Int = 60,
        additionalNotes: String = ""
    ) {
        self.goal = goal
        self.experienceLevel = experienceLevel
        self.equipmentData = (try? JSONEncoder().encode(equipment)) ?? Data()
        self.trainingDaysData = (try? JSONEncoder().encode(trainingDays)) ?? Data()
        self.sessionDuration = sessionDuration
        self.additionalNotes = additionalNotes
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
