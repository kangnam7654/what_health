import Foundation

struct AuthUser: Codable {
    let id: String
    let email: String?
    let displayName: String?
    let subscriptionTier: SubscriptionTier

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case subscriptionTier = "subscription_tier"
    }
}

enum SubscriptionTier: String, Codable, CaseIterable {
    case free
    case basic
    case premium

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .basic: return "Basic"
        case .premium: return "Premium"
        }
    }

    var dailyLimit: Int {
        switch self {
        case .free: return 10
        case .basic: return 100
        case .premium: return 1000
        }
    }
}
