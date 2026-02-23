import Foundation

enum AppConstants {
    enum Keychain {
        static let openAIAPIKey = "com.exerciseplan.openai.apikey"
        static let geminiAPIKey = "com.exerciseplan.gemini.apikey"
        static let selectedProvider = "com.exerciseplan.selectedprovider"
        static let jwtToken = "com.exerciseplan.jwt.token"
        static let refreshToken = "com.exerciseplan.jwt.refresh"
        static let chatgptConnected = "com.exerciseplan.chatgpt.connected"
    }

    enum Defaults {
        static let sessionDuration = 60
        static let defaultProvider = LLMProviderType.openAI
    }

    enum API {
        static let baseURL = "http://localhost:8000"
    }

    enum OAuth {
        static let googleClientID = "YOUR_GOOGLE_CLIENT_ID"
        static let googleRedirectScheme = "com.exerciseplan.app"
    }
}
