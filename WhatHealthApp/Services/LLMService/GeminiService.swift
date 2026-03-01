import Foundation

final class GeminiService: LLMServiceProtocol {
    let providerType: LLMProviderType = .gemini
    private let apiKey: String
    private let model: String

    private var baseURL: String {
        "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
    }

    init(apiKey: String, model: String = "gemini-3-flash-preview") {
        self.apiKey = apiKey
        self.model = model
    }

    func sendMessage(messages: [LLMMessage]) async throws -> String {
        var systemInstruction: GeminiModels.GenerateContentRequest.SystemInstruction? = nil
        var contents: [GeminiModels.GenerateContentRequest.Content] = []

        for message in messages {
            if message.role == "system" {
                systemInstruction = GeminiModels.GenerateContentRequest.SystemInstruction(
                    parts: [.init(text: message.content)]
                )
            } else {
                let role = message.role == "assistant" ? "model" : "user"
                contents.append(GeminiModels.GenerateContentRequest.Content(
                    role: role,
                    parts: [.init(text: message.content)]
                ))
            }
        }

        // Gemini requires at least one content
        if contents.isEmpty {
            contents.append(GeminiModels.GenerateContentRequest.Content(
                role: "user",
                parts: [.init(text: "Hello")]
            ))
        }

        let requestBody = GeminiModels.GenerateContentRequest(
            contents: contents,
            systemInstruction: systemInstruction,
            generationConfig: GeminiModels.GenerateContentRequest.GenerationConfig(
                temperature: 0.7,
                maxOutputTokens: 4096
            )
        )

        guard var urlComponents = URLComponents(string: baseURL) else {
            throw LLMError.invalidResponse
        }
        urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let url = urlComponents.url else {
            throw LLMError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
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
            let geminiResponse = try JSONDecoder().decode(GeminiModels.GenerateContentResponse.self, from: data)

            if let error = geminiResponse.error {
                throw LLMError.serverError(error.code, error.message)
            }

            guard let text = geminiResponse.candidates?.first?.content.parts.first?.text else {
                throw LLMError.invalidResponse
            }
            return text
        case 400:
            if let errorResponse = try? JSONDecoder().decode(GeminiModels.GenerateContentResponse.self, from: data),
               let error = errorResponse.error {
                throw LLMError.serverError(400, error.message)
            }
            throw LLMError.invalidAPIKey
        case 429:
            throw LLMError.rateLimited
        default:
            if let errorResponse = try? JSONDecoder().decode(GeminiModels.GenerateContentResponse.self, from: data),
               let error = errorResponse.error {
                throw LLMError.serverError(httpResponse.statusCode, error.message)
            }
            throw LLMError.serverError(httpResponse.statusCode, "Unknown error")
        }
    }
}
