import Foundation

enum LLMServiceFactory {
    static func create(provider: LLMProviderType, apiKey: String) -> LLMServiceProtocol {
        switch provider {
        case .openAI:
            return OpenAIService(apiKey: apiKey)
        case .codex:
            return OpenAIService(apiKey: apiKey, model: LLMProviderType.codex.modelName)
        case .gemini:
            return GeminiService(apiKey: apiKey)
        }
    }

    @MainActor static func createFromSettings() -> LLMServiceProtocol? {
        if AuthManager.shared.isAuthenticated {
            return BackendLLMService()
        }

        // Fallback: direct API key (legacy / unauthenticated mode)
        let providerRaw = KeychainHelper.shared.read(for: AppConstants.Keychain.selectedProvider) ?? LLMProviderType.openAI.rawValue
        guard let provider = LLMProviderType(rawValue: providerRaw) else { return nil }

        let keychainKey: String
        switch provider {
        case .openAI, .codex:
            keychainKey = AppConstants.Keychain.openAIAPIKey
        case .gemini:
            keychainKey = AppConstants.Keychain.geminiAPIKey
        }

        guard let apiKey = KeychainHelper.shared.read(for: keychainKey), !apiKey.isEmpty else {
            return nil
        }

        return create(provider: provider, apiKey: apiKey)
    }
}
