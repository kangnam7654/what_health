import Foundation

final class OpenAIService: LLMServiceProtocol {
    let providerType: LLMProviderType = .openAI
    private let apiKey: String
    private let model: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    init(apiKey: String, model: String = "gpt-4o-mini") {
        self.apiKey = apiKey
        self.model = model
    }

    func sendMessage(messages: [LLMMessage]) async throws -> String {
        let requestBody = OpenAIModels.ChatRequest(
            model: model,
            messages: messages.map {
                OpenAIModels.ChatRequest.Message(role: $0.role, content: $0.content)
            },
            temperature: 0.7,
            max_tokens: 4096
        )

        guard let url = URL(string: baseURL) else {
            throw LLMError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        request.timeoutInterval = 60

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LLMError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let chatResponse = try JSONDecoder().decode(OpenAIModels.ChatResponse.self, from: data)
            guard let content = chatResponse.choices.first?.message.content else {
                throw LLMError.invalidResponse
            }
            return content
        case 401:
            throw LLMError.invalidAPIKey
        case 429:
            throw LLMError.rateLimited
        default:
            if let errorResponse = try? JSONDecoder().decode(OpenAIModels.ErrorResponse.self, from: data) {
                throw LLMError.serverError(httpResponse.statusCode, errorResponse.error.message)
            }
            throw LLMError.serverError(httpResponse.statusCode, "Unknown error")
        }
    }
}
