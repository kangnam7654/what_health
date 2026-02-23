import Foundation

enum OpenAIModels {
    struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double
        let max_tokens: Int

        struct Message: Encodable {
            let role: String
            let content: String
        }
    }

    struct ChatResponse: Decodable {
        let choices: [Choice]
        let usage: Usage?

        struct Choice: Decodable {
            let message: Message
            let finish_reason: String?
        }

        struct Message: Decodable {
            let role: String
            let content: String
        }

        struct Usage: Decodable {
            let prompt_tokens: Int
            let completion_tokens: Int
            let total_tokens: Int
        }
    }

    struct ErrorResponse: Decodable {
        let error: ErrorDetail

        struct ErrorDetail: Decodable {
            let message: String
            let type: String?
            let code: String?
        }
    }
}
