import Foundation
import SwiftData
import Observation
import UIKit

@Observable
@MainActor
final class WorkoutTrackingViewModel {
    var todayExercises: [CompletedExercise] = []
    var workoutStartTime: Date?
    var isWorkoutActive: Bool = false
    var currentPlan: WhatHealth?
    var todayRoutine: DayRoutine?
    var stats = WorkoutStats(totalWorkouts: 0, thisWeekCount: 0, currentStreak: 0)

    // Rest timer state
    var restTimer: Timer?
    var restTimeRemaining: Int = 0
    var restTimeDuration: Int = 0
    var isRestTimerActive: Bool = false
    var restExerciseIndex: Int?

    func loadData(modelContext: ModelContext) {
        loadTodayRoutine(modelContext: modelContext)
        stats = fetchStats(modelContext: modelContext)
    }

    func loadTodayRoutine(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<WhatHealth>(predicate: #Predicate { $0.isActive })
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
                var completed = CompletedExercise(
                    exerciseName: exercise.name,
                    exerciseType: exercise.exerciseType
                )
                completed.sets = (0..<exercise.sets).map { _ in SetRecord() }
                return completed
            }
        }
    }

    func startWorkout() {
        isWorkoutActive = true
        workoutStartTime = Date()
    }

    func updateSet(exerciseIndex: Int, setIndex: Int,
                   weight: Double = 0, reps: Int = 0,
                   duration: Double = 0, speed: Double = 0, incline: Double = 0) {
        guard exerciseIndex < todayExercises.count,
              setIndex < todayExercises[exerciseIndex].sets.count else { return }

        todayExercises[exerciseIndex].sets[setIndex].weight = weight
        todayExercises[exerciseIndex].sets[setIndex].reps = reps
        todayExercises[exerciseIndex].sets[setIndex].duration = duration
        todayExercises[exerciseIndex].sets[setIndex].speed = speed
        todayExercises[exerciseIndex].sets[setIndex].incline = incline
    }

    func toggleSetCompletion(exerciseIndex: Int, setIndex: Int, restSeconds: Int = 0) {
        guard exerciseIndex < todayExercises.count,
              setIndex < todayExercises[exerciseIndex].sets.count else { return }

        todayExercises[exerciseIndex].sets[setIndex].isCompleted.toggle()

        // Check if all sets are completed for this exercise
        let allSetsCompleted = todayExercises[exerciseIndex].sets.allSatisfy { $0.isCompleted }
        todayExercises[exerciseIndex].isCompleted = allSetsCompleted

        // Start rest timer if set was just completed (not unchecked) and not the last set
        let justCompleted = todayExercises[exerciseIndex].sets[setIndex].isCompleted
        let isLastSet = setIndex == todayExercises[exerciseIndex].sets.count - 1
        if justCompleted && !isLastSet && restSeconds > 0 {
            startRestTimer(seconds: restSeconds, exerciseIndex: exerciseIndex)
        }
    }

    func startRestTimer(seconds: Int, exerciseIndex: Int) {
        stopRestTimer()
        restTimeRemaining = seconds
        restTimeDuration = seconds
        restExerciseIndex = exerciseIndex
        isRestTimerActive = true

        restTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else {
                    timer.invalidate()
                    return
                }
                if self.restTimeRemaining > 1 {
                    self.restTimeRemaining -= 1
                } else {
                    self.restTimeRemaining = 0
                    self.finishRestTimer()
                }
            }
        }
    }

    func stopRestTimer() {
        restTimer?.invalidate()
        restTimer = nil
        isRestTimerActive = false
        restExerciseIndex = nil
        restTimeRemaining = 0
        restTimeDuration = 0
    }

    private func finishRestTimer() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        stopRestTimer()
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
        stopRestTimer()
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
