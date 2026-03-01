import Foundation

final class BackendLLMService: LLMServiceProtocol {
    var providerType: LLMProviderType {
        let raw = KeychainHelper.shared.read(for: AppConstants.Keychain.selectedProvider)
        return LLMProviderType(rawValue: raw ?? "") ?? .openAI
    }

    func sendMessage(messages: [LLMMessage]) async throws -> String {
        let dtos = messages.map { LLMMessageDTO(role: $0.role, content: $0.content) }
        let providerRaw = KeychainHelper.shared.read(for: AppConstants.Keychain.selectedProvider)
        let provider = LLMProviderType(rawValue: providerRaw ?? "")
        let providerString: String? = switch provider {
        case .gemini: "gemini"
        case .codex: "codex"
        default: nil
        }
        let selectedModel = KeychainHelper.shared.read(for: AppConstants.Keychain.selectedModel)
        let requestBody = LLMProxyRequest(messages: dtos, provider: providerString, model: selectedModel)

        do {
            let response: LLMProxyResponse = try await APIClient.shared.post(
                endpoint: "/api/chat",
                body: requestBody
            )
            return response.content
        } catch let apiError as APIError {
            switch apiError {
            case .unauthorized:
                throw LLMError.unauthorized
            case .quotaExceeded(let message):
                throw LLMError.quotaExceeded(message)
            case .networkError(let error):
                throw LLMError.networkError(error)
            case .serverError(let code, let message):
                throw LLMError.serverError(code, message)
            case .decodingError:
                throw LLMError.invalidResponse
            }
        }
    }
}
