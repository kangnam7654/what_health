import SwiftUI

struct SettingsView: View {
    @Environment(StoreManager.self) private var storeManager
    @State private var settingsViewModel = SettingsViewModel()

    var body: some View {
        Form {
            Section("계정") {
                NavigationLink {
                    AccountView()
                } label: {
                    Label("내 계정", systemImage: "person.circle")
                }
            }

            Section("구독") {
                NavigationLink {
                    SubscriptionView(storeManager: storeManager)
                } label: {
                    HStack {
                        Label("구독 관리", systemImage: "crown")
                        Spacer()
                        if let tier = AuthManager.shared.currentUser?.subscriptionTier {
                            Text(tier.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("AI 모델") {
                NavigationLink {
                    ProviderSettingsView(viewModel: settingsViewModel)
                } label: {
                    HStack {
                        Label("Provider 설정", systemImage: "cpu")
                        Spacer()
                        Text(settingsViewModel.selectedProvider.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("사용량") {
                NavigationLink {
                    QuotaView()
                } label: {
                    Label("사용 현황", systemImage: "chart.bar")
                }
            }

            Section("앱 정보") {
                LabeledContent("버전") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("설정")
    }
}
