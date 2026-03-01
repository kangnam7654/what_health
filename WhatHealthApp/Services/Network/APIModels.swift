import Foundation

// MARK: - Auth

struct AppleAuthRequest: Codable {
    let identityToken: String
    let fullName: String?

    enum CodingKeys: String, CodingKey {
        case identityToken = "identity_token"
        case fullName = "full_name"
    }
}

struct GoogleAuthRequest: Codable {
    let authorizationCode: String
    let redirectURI: String

    enum CodingKeys: String, CodingKey {
        case authorizationCode = "authorization_code"
        case redirectURI = "redirect_uri"
    }
}

struct ChatGPTAuthRequest: Codable {
    let authorizationCode: String
    let redirectURI: String
    let codeVerifier: String

    enum CodingKeys: String, CodingKey {
        case authorizationCode = "authorization_code"
        case redirectURI = "redirect_uri"
        case codeVerifier = "code_verifier"
    }
}

struct ChatGPTConnectResponse: Codable {
    let status: String
    let email: String?
}

struct GoogleConnectResponse: Codable {
    let status: String
    let email: String?
}

// MARK: - LLM Proxy

struct LLMProxyRequest: Codable {
    let messages: [LLMMessageDTO]
    let provider: String?
    let model: String?
}

struct OpenAIModel: Codable, Identifiable {
    let id: String
    let ownedBy: String

    enum CodingKeys: String, CodingKey {
        case id
        case ownedBy = "owned_by"
    }
}

struct ModelsResponse: Codable {
    let models: [OpenAIModel]
    let hasOauth: Bool?

    enum CodingKeys: String, CodingKey {
        case models
        case hasOauth = "has_oauth"
    }
}

struct LLMMessageDTO: Codable {
    let role: String
    let content: String
}

struct LLMProxyResponse: Codable {
    let content: String
    let provider: String?
    let model: String?
    let usage: [String: Int]?
}

// MARK: - Quota

struct QuotaResponse: Codable {
    let dailyLimit: Int
    let requestsToday: Int
    let remaining: Int
    let resetsAt: String?
    let bonusRemaining: Int
    let rewardAdsWatched: Int
    let maxRewardAds: Int

    enum CodingKeys: String, CodingKey {
        case dailyLimit = "daily_limit"
        case requestsToday = "requests_today"
        case remaining
        case resetsAt = "resets_at"
        case bonusRemaining = "bonus_remaining"
        case rewardAdsWatched = "reward_ads_watched"
        case maxRewardAds = "max_reward_ads"
    }

    var canWatchRewardAd: Bool { rewardAdsWatched < maxRewardAds }
}

struct RewardClaimResponse: Codable {
    let success: Bool
    let bonusGranted: Int
    let bonusAvailable: Int
    let rewardAdsRemaining: Int

    enum CodingKeys: String, CodingKey {
        case success
        case bonusGranted = "bonus_granted"
        case bonusAvailable = "bonus_available"
        case rewardAdsRemaining = "reward_ads_remaining"
    }
}

// MARK: - Subscription

struct VerifyReceiptRequest: Codable {
    let receiptData: String
    let productId: String

    enum CodingKeys: String, CodingKey {
        case receiptData = "receipt_data"
        case productId = "product_id"
    }
}

struct VerifyReceiptResponse: Codable {
    let success: Bool
    let newTier: String?
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case success
        case newTier = "new_tier"
        case expiresAt = "expires_at"
    }
}

// MARK: - API Error

enum APIError: LocalizedError {
    case unauthorized
    case quotaExceeded(String)
    case networkError(Error)
    case serverError(Int, String)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "인증이 만료되었습니다. 다시 로그인해주세요."
        case .quotaExceeded(let message):
            return "일일 사용 한도를 초과했습니다. \(message)"
        case .networkError(let error):
            return "네트워크 오류: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "서버 오류 (\(code)): \(message)"
        case .decodingError:
            return "응답 데이터를 처리할 수 없습니다."
        }
    }
}
