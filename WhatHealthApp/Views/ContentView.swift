import SwiftUI

struct ContentView: View {
    @State private var showSettings = false
    private let authManager = AuthManager.shared

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                mainTabView
            } else {
                LoginView()
            }
        }
        .task {
            await authManager.checkExistingAuth()
        }
    }

    private var mainTabView: some View {
        TabView {
            NavigationStack {
                PlanGeneratorView()
            }
            .tabItem {
                Label("운동 플랜", systemImage: "dumbbell.fill")
            }

            NavigationStack {
                WorkoutTrackingView()
            }
            .tabItem {
                Label("운동 기록", systemImage: "figure.run")
            }

            NavigationStack {
                ChatSessionListView()
            }
            .tabItem {
                Label("AI 상담", systemImage: "bubble.left.and.bubble.right.fill")
            }

            NavigationStack {
                SettingsView()
                    .navigationTitle("설정")
            }
            .tabItem {
                Label("설정", systemImage: "gearshape.fill")
            }
        }
    }
}
