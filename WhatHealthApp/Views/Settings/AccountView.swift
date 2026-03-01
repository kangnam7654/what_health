import SwiftUI

struct AccountView: View {
    private let authManager = AuthManager.shared

    var body: some View {
        List {
            if let user = authManager.currentUser {
                Section("프로필") {
                    LabeledContent("이름", value: user.displayName ?? "-")
                    LabeledContent("이메일", value: user.email ?? "-")
                    LabeledContent("플랜", value: user.subscriptionTier.displayName)
                }
            }

            Section {
                Button(role: .destructive) {
                    authManager.signOut()
                } label: {
                    Label("로그아웃", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("계정")
    }
}
