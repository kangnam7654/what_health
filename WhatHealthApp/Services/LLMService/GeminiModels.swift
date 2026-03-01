import Foundation

enum GeminiModels {
    struct GenerateContentRequest: Encodable {
        let contents: [Content]
        let systemInstruction: SystemInstruction?
        let generationConfig: GenerationConfig?

        struct Content: Encodable {
            let role: String
            let parts: [Part]
        }

        struct Part: Encodable {
            let text: String
        }

        struct SystemInstruction: Encodable {
            let parts: [Part]
        }

        struct GenerationConfig: Encodable {
            let temperature: Double?
            let maxOutputTokens: Int?
        }
    }

    struct GenerateContentResponse: Decodable {
        let candidates: [Candidate]?
        let error: ErrorInfo?

        struct Candidate: Decodable {
            let content: Content
            let finishReason: String?
        }

        struct Content: Decodable {
            let parts: [Part]
            let role: String?
        }

        struct Part: Decodable {
            let text: String
        }

        struct ErrorInfo: Decodable {
            let code: Int
            let message: String
            let status: String?
        }
    }
}
