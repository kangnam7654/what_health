import SwiftUI

struct ProviderSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: viewModel.selectedProvider.icon)
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
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

            if viewModel.selectedProvider == .gemini {
                Section {
                    if AuthManager.shared.isGoogleConnected {
                        Label("Google 계정 연결됨", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            Task { await viewModel.connectGoogle() }
                        } label: {
                            HStack {
                                if viewModel.isConnectingGoogle {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("연결 중...")
                                } else {
                                    Image(systemName: "person.badge.key.fill")
                                    Text("Google 계정 연결")
                                }
                            }
                        }
                        .disabled(viewModel.isConnectingGoogle)
                    }
                } header: {
                    Text("Google OAuth")
                } footer: {
                    Text("Google 계정을 연결하면 Gemini를 무료로 사용할 수 있습니다.")
                }
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

            if viewModel.selectedProvider == .codex || viewModel.selectedProvider == .gemini {
                Section {
                    if viewModel.isLoadingModels {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("모델 목록 로딩 중...")
                                .foregroundStyle(.secondary)
                        }
                    } else if viewModel.availableModels.isEmpty {
                        Button {
                            Task { await viewModel.fetchModels() }
                        } label: {
                            Label("모델 목록 불러오기", systemImage: "arrow.clockwise")
                        }
                    } else {
                        Picker("모델 선택", selection: $viewModel.selectedModel) {
                            Text("기본값").tag("")
                            ForEach(viewModel.availableModels) { model in
                                Text(model.id).tag(model.id)
                            }
                        }
                        .onChange(of: viewModel.selectedModel) {
                            viewModel.saveSelectedModel()
                        }

                        Button {
                            Task { await viewModel.fetchModels() }
                        } label: {
                            Label("새로고침", systemImage: "arrow.clockwise")
                        }
                    }
                } header: {
                    Text("모델 선택")
                } footer: {
                    if viewModel.selectedModel.isEmpty {
                        Text("기본 모델이 사용됩니다. 사용 가능한 모델을 불러와 선택할 수 있습니다.")
                    } else {
                        Text("선택된 모델: \(viewModel.selectedModel)")
                    }
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
        .alert("알림", isPresented: $viewModel.showAlert) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage)
        }
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
                    .foregroundStyle(provider == viewModel.selectedProvider ? Color.accentColor : Color.secondary)
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
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var hasOpenAIKey: Bool {
        !(KeychainHelper.shared.read(for: AppConstants.Keychain.openAIAPIKey) ?? "").isEmpty
    }

    private func statusInfo(for provider: LLMProviderType) -> (text: String, color: Color) {
        switch provider {
        case .gemini:
            return AuthManager.shared.isGoogleConnected
                ? ("Google 연결됨", .green)
                : ("Google 연결 필요", .orange)
        case .codex:
            if AuthManager.shared.isChatGPTConnected { return ("OAuth 연결됨", .green) }
            return hasOpenAIKey ? ("API 키 설정됨", .green) : ("로그인 필요", .orange)
        case .openAI:
            return hasOpenAIKey ? ("API 키 설정됨", .green) : ("API 키 필요", .orange)
        }
    }

    private func statusBadge(for provider: LLMProviderType) -> some View {
        let info = statusInfo(for: provider)
        return Text(info.text)
            .font(.caption2)
            .foregroundStyle(info.color)
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
