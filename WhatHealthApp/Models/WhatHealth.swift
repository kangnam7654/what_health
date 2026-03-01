import Foundation
import SwiftData

@Model
final class WhatHealth {
    var title: String
    var summary: String
    var routinesData: Data
    var goal: ExerciseGoal
    var isActive: Bool
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \WorkoutLog.plan)
    var workoutLogs: [WorkoutLog]?

    var weeklyRoutines: [DayRoutine] {
        get {
            (try? JSONDecoder().decode([DayRoutine].self, from: routinesData)) ?? []
        }
        set {
            routinesData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    init(
        title: String,
        summary: String,
        weeklyRoutines: [DayRoutine],
        goal: ExerciseGoal,
        isActive: Bool = false
    ) {
        self.title = title
        self.summary = summary
        self.routinesData = (try? JSONEncoder().encode(weeklyRoutines)) ?? Data()
        self.goal = goal
        self.isActive = isActive
        self.createdAt = Date()
        self.workoutLogs = []
    }
}
