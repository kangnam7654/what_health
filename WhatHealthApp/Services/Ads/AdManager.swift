import Foundation
import GoogleMobileAds
import UIKit

@Observable
@MainActor
final class AdManager {
    static let shared = AdManager()

    var isRewardAdReady: Bool = false

    private var rewardedAd: RewardedAd?

    private var bannerAdUnitID: String {
        #if DEBUG
        "ca-app-pub-3940256099942544/2435281174"
        #else
        "YOUR_BANNER_AD_UNIT_ID"
        #endif
    }

    private var rewardAdUnitID: String {
        #if DEBUG
        "ca-app-pub-3940256099942544/1712485313"
        #else
        "YOUR_REWARD_AD_UNIT_ID"
        #endif
    }

    private init() {}

    func initialize() {
        MobileAds.shared.start()
        Task { await loadRewardAd() }
    }

    func loadRewardAd() async {
        do {
            rewardedAd = try await RewardedAd.load(with: rewardAdUnitID, request: Request())
            isRewardAdReady = true
        } catch {
            isRewardAdReady = false
        }
    }

    func showRewardAd(from viewController: UIViewController) async -> Bool {
        guard let rewardedAd else { return false }

        return await withCheckedContinuation { continuation in
            rewardedAd.present(from: viewController) {
                continuation.resume(returning: true)
            }
        }
    }

    func claimRewardOnBackend() async -> RewardClaimResponse? {
        struct EmptyBody: Encodable {}
        do {
            let response: RewardClaimResponse = try await APIClient.shared.post(
                endpoint: "/api/quota/reward",
                body: EmptyBody()
            )
            return response
        } catch {
            return nil
        }
    }
}
