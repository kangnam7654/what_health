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

    enum ConnectionTestResult {
        case success
        case failure(String)
    }

    init() {
        let providerRaw = KeychainHelper.shared.read(for: AppConstants.Keychain.selectedProvider) ?? LLMProviderType.openAI.rawValue
        self.selectedProvider = LLMProviderType(rawValue: providerRaw) ?? .openAI
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
        } catch {
            if (error as? AuthError) != .cancelled {
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }

    func onProviderChanged() {
        loadAPIKey()
        connectionTestResult = nil
    }
}
