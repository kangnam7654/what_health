import Foundation
import SwiftUI

@Observable
@MainActor
final class SettingsViewModel {
    var selectedProvider: LLMProviderType
    var apiKey: String = ""
    var isTestingConnection: Bool = false
    var connectionTestResult: ConnectionTestResult?
    var showAlert: Bool = false
    var alertMessage: String = ""
    var isConnectingChatGPT: Bool = false
    var isConnectingGoogle: Bool = false

    // Model selection
    var availableModels: [OpenAIModel] = []
    var selectedModel: String = ""
    var isLoadingModels: Bool = false
    var serverHasOAuth: Bool = true

    enum ConnectionTestResult {
        case success
        case failure(String)
    }

    init() {
        let providerRaw = KeychainHelper.shared.read(for: AppConstants.Keychain.selectedProvider) ?? LLMProviderType.openAI.rawValue
        self.selectedProvider = LLMProviderType(rawValue: providerRaw) ?? .openAI
        self.selectedModel = KeychainHelper.shared.read(for: AppConstants.Keychain.selectedModel) ?? ""
        loadAPIKey()
    }

    func loadAPIKey() {
        let key: String
        switch selectedProvider {
        case .openAI: key = AppConstants.Keychain.openAIAPIKey
        case .gemini: key = AppConstants.Keychain.geminiAPIKey
        case .codex: key = AppConstants.Keychain.openAIAPIKey  // OpenAI와 같은 키 사용
        }
        apiKey = KeychainHelper.shared.read(for: key) ?? ""
    }

    func saveAPIKey() {
        let key: String
        switch selectedProvider {
        case .openAI: key = AppConstants.Keychain.openAIAPIKey
        case .gemini: key = AppConstants.Keychain.geminiAPIKey
        case .codex: key = AppConstants.Keychain.openAIAPIKey
        }
        _ = KeychainHelper.shared.save(apiKey, for: key)
        _ = KeychainHelper.shared.save(selectedProvider.rawValue, for: AppConstants.Keychain.selectedProvider)
    }

    func saveSelectedModel() {
        _ = KeychainHelper.shared.save(selectedModel, for: AppConstants.Keychain.selectedModel)
    }

    func testConnection() async {
        guard !apiKey.isEmpty else {
            connectionTestResult = .failure("API 키를 입력해주세요.")
            return
        }

        isTestingConnection = true
        connectionTestResult = nil

        saveAPIKey()

        let service = LLMServiceFactory.create(provider: selectedProvider, apiKey: apiKey)

        do {
            let response = try await service.generateCompletion(
                systemPrompt: "You are a helpful assistant.",
                userPrompt: "Say 'connected' in one word."
            )
            if !response.isEmpty {
                connectionTestResult = .success
            } else {
                connectionTestResult = .failure("빈 응답을 받았습니다.")
            }
        } catch {
            connectionTestResult = .failure(error.localizedDescription)
        }

        isTestingConnection = false
    }

    var isAPIKeyConfigured: Bool {
        !apiKey.isEmpty
    }

    func connectGoogle() async {
        isConnectingGoogle = true
        defer { isConnectingGoogle = false }

        do {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first,
                  let window = scene.windows.first else {
                alertMessage = "화면을 찾을 수 없습니다."
                showAlert = true
                return
            }

            try await AuthManager.shared.connectGoogle(anchor: window)
            connectionTestResult = .success
            await fetchModels()
        } catch {
            if (error as? AuthError) != .cancelled {
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }

    func connectChatGPT() async {
        isConnectingChatGPT = true
        defer { isConnectingChatGPT = false }

        do {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first,
                  let window = scene.windows.first else {
                alertMessage = "화면을 찾을 수 없습니다."
                showAlert = true
                return
            }

            try await AuthManager.shared.connectChatGPT(anchor: window)
            connectionTestResult = .success
            // OAuth 연결 후 모델 목록 자동 로드
            await fetchModels()
        } catch {
            if (error as? AuthError) != .cancelled {
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }

    func fetchModels() async {
        isLoadingModels = true
        defer { isLoadingModels = false }

        do {
            let providerParam: String
            switch selectedProvider {
            case .codex: providerParam = "codex"
            case .gemini: providerParam = "gemini"
            case .openAI: providerParam = "openai"
            }
            let response: ModelsResponse = try await APIClient.shared.get(
                endpoint: "/api/models?provider=\(providerParam)"
            )
            availableModels = response.models
            serverHasOAuth = response.hasOauth ?? false
            // 서버에 OAuth 토큰이 없으면 재연결 필요
            if !serverHasOAuth {
                _ = KeychainHelper.shared.delete(for: AppConstants.Keychain.chatgptConnected)
                AuthManager.shared.isChatGPTConnected = false
            }
            // 저장된 모델이 목록에 없으면 초기화
            if !selectedModel.isEmpty && !availableModels.contains(where: { $0.id == selectedModel }) {
                selectedModel = ""
            }
        } catch {
            availableModels = []
            alertMessage = "모델 목록 불러오기 실패: \(error.localizedDescription)"
            showAlert = true
        }
    }

    func onProviderChanged() {
        loadAPIKey()
        connectionTestResult = nil
        availableModels = []
        selectedModel = KeychainHelper.shared.read(for: AppConstants.Keychain.selectedModel) ?? ""
    }
}
