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
        let key = selectedProvider == .openAI
            ? AppConstants.Keychain.openAIAPIKey
            : AppConstants.Keychain.geminiAPIKey
        apiKey = KeychainHelper.shared.read(for: key) ?? ""
    }

    func saveAPIKey() {
        let key = selectedProvider == .openAI
            ? AppConstants.Keychain.openAIAPIKey
            : AppConstants.Keychain.geminiAPIKey
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

    func onProviderChanged() {
        loadAPIKey()
        connectionTestResult = nil
    }
}
