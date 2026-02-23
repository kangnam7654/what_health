import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class PlanHistoryViewModel {

    func deletePlan(_ plan: ExercisePlan, modelContext: ModelContext) {
        modelContext.delete(plan)
        try? modelContext.save()
    }

    func activatePlan(_ plan: ExercisePlan, modelContext: ModelContext) {
        // Deactivate all other plans
        let descriptor = FetchDescriptor<ExercisePlan>(predicate: #Predicate { $0.isActive })
        if let activePlans = try? modelContext.fetch(descriptor) {
            for p in activePlans {
                p.isActive = false
            }
        }

        plan.isActive = true
        try? modelContext.save()
    }
}
