import SwiftUI
import SwiftData
import GoogleMobileAds
import AppTrackingTransparency

@main
struct WhatHealthApp: App {
    @State private var storeManager = StoreManager()

    init() {
        AdManager.shared.initialize()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserProfile.self,
            WhatHealth.self,
            WorkoutLog.self,
            ChatSession.self,
            ChatMessage.self,
            SavedExerciseVideo.self
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
                .task {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    await requestTrackingAuthorization()
                }
        }
        .modelContainer(sharedModelContainer)
    }

    private func requestTrackingAuthorization() async {
        await ATTrackingManager.requestTrackingAuthorization()
    }
}
