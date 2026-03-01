import Foundation

struct AuthUser: Codable {
    let id: String
    let email: String?
    let displayName: String?
    let subscriptionTier: SubscriptionTier
    let isPro: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case subscriptionTier = "subscription_tier"
        case isPro = "is_pro"
    }
}

enum SubscriptionTier: String, Codable, CaseIterable {
    case free
    case pro

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        }
    }
}
