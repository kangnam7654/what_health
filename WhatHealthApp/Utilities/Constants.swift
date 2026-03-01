import Foundation

enum AppConstants {
    enum Keychain {
        static let openAIAPIKey = "com.whathealth.openai.apikey"
        static let geminiAPIKey = "com.whathealth.gemini.apikey"
        static let selectedProvider = "com.whathealth.selectedprovider"
        static let jwtToken = "com.whathealth.jwt.token"
        static let refreshToken = "com.whathealth.jwt.refresh"
        static let chatgptConnected = "com.whathealth.chatgpt.connected"
        static let googleConnected = "com.whathealth.google.connected"
        static let selectedModel = "com.whathealth.selected.model"
    }

    enum Defaults {
        static let sessionDuration = 60
        static let defaultProvider = LLMProviderType.openAI
    }

    enum API {
        #if targetEnvironment(simulator)
        static let baseURL = "http://localhost:8000"
        #else
        static let baseURL = "https://whathealth.fly.dev"
        #endif
    }

    enum OAuth {
        static let googleClientID = "YOUR_GOOGLE_CLIENT_ID"
        static let googleRedirectScheme = "com.whathealth.app"
    }

    enum Ads {
        static let bonusPerAd = 10
        static let maxRewardAdsPerDay = 5
    }
}
