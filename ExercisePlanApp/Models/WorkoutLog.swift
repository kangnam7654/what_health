import Foundation
import SwiftData

@Model
final class WorkoutLog {
    var date: Date
    var exercisesData: Data
    var duration: TimeInterval
    var notes: String
    var plan: ExercisePlan?

    var completedExercises: [CompletedExercise] {
        get {
            (try? JSONDecoder().decode([CompletedExercise].self, from: exercisesData)) ?? []
        }
        set {
            exercisesData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    init(
        date: Date = Date(),
        completedExercises: [CompletedExercise] = [],
        duration: TimeInterval = 0,
        notes: String = "",
        plan: ExercisePlan? = nil
    ) {
        self.date = date
        self.exercisesData = (try? JSONEncoder().encode(completedExercises)) ?? Data()
        self.duration = duration
        self.notes = notes
        self.plan = plan
    }
}
