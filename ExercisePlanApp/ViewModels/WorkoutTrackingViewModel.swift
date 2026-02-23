import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class WorkoutTrackingViewModel {
    var todayExercises: [CompletedExercise] = []
    var workoutStartTime: Date?
    var isWorkoutActive: Bool = false
    var currentPlan: ExercisePlan?
    var todayRoutine: DayRoutine?
    var stats = WorkoutStats(totalWorkouts: 0, thisWeekCount: 0, currentStreak: 0)

    func loadData(modelContext: ModelContext) {
        loadTodayRoutine(modelContext: modelContext)
        stats = fetchStats(modelContext: modelContext)
    }

    func loadTodayRoutine(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<ExercisePlan>(predicate: #Predicate { $0.isActive })
        currentPlan = try? modelContext.fetch(descriptor).first

        guard let plan = currentPlan else {
            todayRoutine = nil
            todayExercises = []
            return
        }

        let today = DayOfWeek.fromCurrentWeekday()
        todayRoutine = plan.weeklyRoutines.first { $0.dayOfWeek == today.fullName }

        if let routine = todayRoutine, todayExercises.isEmpty {
            todayExercises = routine.exercises.map { exercise in
                var completed = CompletedExercise(exerciseName: exercise.name)
                completed.sets = (0..<exercise.sets).map { _ in SetRecord() }
                return completed
            }
        }
    }

    func startWorkout() {
        isWorkoutActive = true
        workoutStartTime = Date()
    }

    func updateSet(exerciseIndex: Int, setIndex: Int, weight: Double, reps: Int) {
        guard exerciseIndex < todayExercises.count,
              setIndex < todayExercises[exerciseIndex].sets.count else { return }

        todayExercises[exerciseIndex].sets[setIndex].weight = weight
        todayExercises[exerciseIndex].sets[setIndex].reps = reps
    }

    func toggleSetCompletion(exerciseIndex: Int, setIndex: Int) {
        guard exerciseIndex < todayExercises.count,
              setIndex < todayExercises[exerciseIndex].sets.count else { return }

        todayExercises[exerciseIndex].sets[setIndex].isCompleted.toggle()

        // Check if all sets are completed for this exercise
        let allSetsCompleted = todayExercises[exerciseIndex].sets.allSatisfy { $0.isCompleted }
        todayExercises[exerciseIndex].isCompleted = allSetsCompleted
    }

    var completionRate: Double {
        guard !todayExercises.isEmpty else { return 0 }
        let completed = todayExercises.filter { $0.isCompleted }.count
        return Double(completed) / Double(todayExercises.count)
    }

    func finishWorkout(modelContext: ModelContext) {
        guard let startTime = workoutStartTime else { return }

        let duration = Date().timeIntervalSince(startTime)

        let log = WorkoutLog(
            date: Date(),
            completedExercises: todayExercises,
            duration: duration,
            plan: currentPlan
        )

        modelContext.insert(log)
        try? modelContext.save()

        // Reset
        isWorkoutActive = false
        workoutStartTime = nil
        todayExercises = []
    }

    func fetchStats(modelContext: ModelContext) -> WorkoutStats {
        let descriptor = FetchDescriptor<WorkoutLog>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let logs = (try? modelContext.fetch(descriptor)) ?? []

        let totalWorkouts = logs.count

        // This week's completion
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let thisWeekLogs = logs.filter { $0.date >= startOfWeek }

        // Streak calculation
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())
        let logDates = Set(logs.map { calendar.startOfDay(for: $0.date) })

        while logDates.contains(checkDate) {
            streak += 1
            checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate)!
        }

        return WorkoutStats(
            totalWorkouts: totalWorkouts,
            thisWeekCount: thisWeekLogs.count,
            currentStreak: streak
        )
    }
}

struct WorkoutStats {
    let totalWorkouts: Int
    let thisWeekCount: Int
    let currentStreak: Int
}
