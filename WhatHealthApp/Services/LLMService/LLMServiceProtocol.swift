import Foundation

struct LLMMessage {
    let role: String
    let content: String

    static func system(_ content: String) -> LLMMessage {
        LLMMessage(role: "system", content: content)
    }

    static func user(_ content: String) -> LLMMessage {
        LLMMessage(role: "user", content: content)
    }

    static func assistant(_ content: String) -> LLMMessage {
        LLMMessage(role: "assistant", content: content)
    }
}

enum LLMError: LocalizedError {
    case invalidAPIKey
    case networkError(Error)
    case invalidResponse
    case rateLimited
    case serverError(Int, String)
    case parsingError(String)
    case unauthorized
    case quotaExceeded(String)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "API 키가 유효하지 않습니다. 설정에서 확인해주세요."
        case .networkError(let error):
            return "네트워크 오류: \(error.localizedDescription)"
        case .invalidResponse:
            return "서버로부터 유효하지 않은 응답을 받았습니다."
        case .rateLimited:
            return "요청 한도를 초과했습니다. 잠시 후 다시 시도해주세요."
        case .serverError(let code, let message):
            return "서버 오류 (\(code)): \(message)"
        case .parsingError(let detail):
            return "응답 파싱 오류: \(detail)"
        case .unauthorized:
            return "로그인이 필요합니다. 다시 로그인해주세요."
        case .quotaExceeded(let message):
            return "일일 사용 한도를 초과했습니다. \(message)"
        }
    }
}

protocol LLMServiceProtocol {
    var providerType: LLMProviderType { get }
    func sendMessage(messages: [LLMMessage]) async throws -> String
    func generateCompletion(systemPrompt: String, userPrompt: String) async throws -> String
}

extension LLMServiceProtocol {
    func generateCompletion(systemPrompt: String, userPrompt: String) async throws -> String {
        let messages = [
            LLMMessage.system(systemPrompt),
            LLMMessage.user(userPrompt)
        ]
        return try await sendMessage(messages: messages)
    }
}
