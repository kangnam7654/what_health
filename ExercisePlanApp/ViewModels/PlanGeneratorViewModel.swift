import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class PlanGeneratorViewModel {
    var selectedGoal: ExerciseGoal = .strength
    var selectedExperience: ExperienceLevel = .beginner
    var selectedEquipment: Set<Equipment> = [.bodyweight]
    var selectedDays: Set<DayOfWeek> = [.monday, .wednesday, .friday]
    var selectedDuration: SessionDuration = .sixty
    var additionalNotes: String = ""

    var isGenerating: Bool = false
    var generatedPlan: GeneratedPlanResult?
    var errorMessage: String?
    var showError: Bool = false

    struct GeneratedPlanResult {
        let title: String
        let summary: String
        let routines: [DayRoutine]
    }

    func toggleEquipment(_ equipment: Equipment) {
        if selectedEquipment.contains(equipment) {
            if selectedEquipment.count > 1 {
                selectedEquipment.remove(equipment)
            }
        } else {
            selectedEquipment.insert(equipment)
        }
    }

    func toggleDay(_ day: DayOfWeek) {
        if selectedDays.contains(day) {
            if selectedDays.count > 1 {
                selectedDays.remove(day)
            }
        } else {
            selectedDays.insert(day)
        }
    }

    var canGenerate: Bool {
        !selectedEquipment.isEmpty && !selectedDays.isEmpty
    }

    func generatePlan() async {
        guard let service = LLMServiceFactory.createFromSettings() else {
            errorMessage = "로그인이 필요합니다. 로그인 후 이용해주세요."
            showError = true
            return
        }

        isGenerating = true
        errorMessage = nil
        generatedPlan = nil

        let sortedDays = Array(selectedDays).sorted { $0.rawValue < $1.rawValue }
        let (systemPrompt, userPrompt) = PromptBuilder.buildPlanGenerationPrompt(
            goal: selectedGoal,
            experience: selectedExperience,
            equipment: Array(selectedEquipment),
            trainingDays: sortedDays,
            sessionDuration: selectedDuration.rawValue,
            additionalNotes: additionalNotes
        )

        do {
            let response = try await service.generateCompletion(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt
            )

            let parsed = try PlanParser.parse(response: response)
            generatedPlan = GeneratedPlanResult(
                title: parsed.title,
                summary: parsed.summary,
                routines: parsed.routines
            )
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isGenerating = false
    }

    func savePlan(modelContext: ModelContext) {
        guard let result = generatedPlan else { return }

        let plan = ExercisePlan(
            title: result.title,
            summary: result.summary,
            weeklyRoutines: result.routines,
            goal: selectedGoal
        )

        modelContext.insert(plan)
        try? modelContext.save()
    }

    func saveAndActivatePlan(modelContext: ModelContext) {
        guard let result = generatedPlan else { return }

        // Deactivate all other plans
        let descriptor = FetchDescriptor<ExercisePlan>(predicate: #Predicate { $0.isActive })
        if let activePlans = try? modelContext.fetch(descriptor) {
            for plan in activePlans {
                plan.isActive = false
            }
        }

        let plan = ExercisePlan(
            title: result.title,
            summary: result.summary,
            weeklyRoutines: result.routines,
            goal: selectedGoal,
            isActive: true
        )

        modelContext.insert(plan)
        try? modelContext.save()
    }

    func reset() {
        generatedPlan = nil
        errorMessage = nil
    }
}
