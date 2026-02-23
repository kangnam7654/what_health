import SwiftUI

struct ProviderSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: viewModel.selectedProvider.icon)
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.selectedProvider.rawValue)
                            .font(.headline)
                        Text(viewModel.selectedProvider.modelName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("활성")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.green, in: Capsule())
                }
            } header: {
                Text("현재 Provider")
            }

            Section {
                ForEach(LLMProviderType.allCases) { provider in
                    providerCard(for: provider)
                }
            } header: {
                Text("Provider 선택")
            } footer: {
                Text("Gemini는 Google OAuth, Codex는 ChatGPT OAuth로 무료 사용 가능합니다. OpenAI는 서버에 설정된 API 키를 사용합니다.")
            }

            if viewModel.selectedProvider == .codex {
                Section {
                    if AuthManager.shared.isChatGPTConnected {
                        Label("ChatGPT 계정 연결됨", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            Task { await viewModel.connectChatGPT() }
                        } label: {
                            HStack {
                                if viewModel.isConnectingChatGPT {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("연결 중...")
                                } else {
                                    Image(systemName: "person.badge.key.fill")
                                    Text("ChatGPT로 로그인")
                                }
                            }
                        }
                        .disabled(viewModel.isConnectingChatGPT)
                    }
                } header: {
                    Text("ChatGPT OAuth")
                } footer: {
                    Text("ChatGPT 구독으로 Codex를 사용할 수 있습니다. API 키 대안도 가능합니다.")
                }
            }

            if viewModel.selectedProvider.requiresAPIKey || viewModel.selectedProvider == .codex {
                Section {
                    SecureField("API Key", text: $viewModel.apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()

                    Button {
                        Task { await viewModel.testConnection() }
                    } label: {
                        HStack {
                            if viewModel.isTestingConnection {
                                ProgressView()
                                    .controlSize(.small)
                                Text("연결 테스트 중...")
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                Text("연결 테스트")
                            }
                        }
                    }
                    .disabled(viewModel.apiKey.isEmpty || viewModel.isTestingConnection)

                    if let result = viewModel.connectionTestResult {
                        connectionResultView(result)
                    }
                } header: {
                    if viewModel.selectedProvider == .codex {
                        Text("API 키 (대안)")
                    } else {
                        Text("API 키 설정")
                    }
                }
            }
        }
        .navigationTitle("Provider 설정")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func providerCard(for provider: LLMProviderType) -> some View {
        Button {
            viewModel.selectedProvider = provider
            viewModel.onProviderChanged()
            _ = KeychainHelper.shared.save(provider.rawValue, for: AppConstants.Keychain.selectedProvider)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: provider.icon)
                    .font(.title3)
                    .foregroundStyle(provider == viewModel.selectedProvider ? .blue : .secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.rawValue)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(provider.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(provider.modelName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    statusBadge(for: provider)
                }

                if provider == viewModel.selectedProvider {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statusBadge(for provider: LLMProviderType) -> some View {
        if provider == .gemini {
            if AuthManager.shared.isAuthenticated {
                Text("연결됨")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                Text("로그인 필요")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        } else if provider == .codex {
            if AuthManager.shared.isChatGPTConnected {
                Text("OAuth 연결됨")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                let hasKey = !(KeychainHelper.shared.read(for: AppConstants.Keychain.openAIAPIKey) ?? "").isEmpty
                if hasKey {
                    Text("API 키 설정됨")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    Text("로그인 필요")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        } else {
            let hasKey = !(KeychainHelper.shared.read(for: AppConstants.Keychain.openAIAPIKey) ?? "").isEmpty
            if hasKey {
                Text("API 키 설정됨")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                Text("API 키 필요")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func connectionResultView(_ result: SettingsViewModel.ConnectionTestResult) -> some View {
        switch result {
        case .success:
            Label("연결 성공", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }
}
