import SwiftUI
import SwiftData

@main
struct ExercisePlanApp: App {
    @State private var storeManager = StoreManager()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserProfile.self,
            ExercisePlan.self,
            WorkoutLog.self,
            ChatSession.self,
            ChatMessage.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(storeManager)
                .onAppear {
                    storeManager.listenForTransactions()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
