import SwiftUI
import UIKit

struct QuotaView: View {
    @State private var quota: QuotaResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isWatchingAd = false
    @State private var adResultMessage: String?
    private let authManager = AuthManager.shared

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if let quota = quota {
                Section("사용량") {
                    LabeledContent("일일 한도", value: "\(quota.dailyLimit)회")
                    LabeledContent("오늘 사용", value: "\(quota.requestsToday)회")
                    LabeledContent("남은 횟수", value: "\(quota.remaining)회")
                }

                Section("사용 현황") {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(
                            value: Double(quota.requestsToday),
                            total: Double(quota.dailyLimit)
                        )
                        .progressViewStyle(.linear)
                        .tint(progressColor(used: quota.requestsToday, limit: quota.dailyLimit))

                        Text("\(quota.requestsToday) / \(quota.dailyLimit) 사용")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("보너스 요청") {
                    LabeledContent("보너스 남은 횟수", value: "\(quota.bonusRemaining)회")
                    LabeledContent("오늘 광고 시청", value: "\(quota.rewardAdsWatched) / \(quota.maxRewardAds)회")

                    Button {
                        Task { await watchRewardAd() }
                    } label: {
                        HStack {
                            if isWatchingAd {
                                ProgressView()
                                    .controlSize(.small)
                                Text("광고 로딩 중...")
                            } else {
                                Image(systemName: "play.rectangle.fill")
                                    .foregroundStyle(.orange)
                                Text("광고 보고 +\(AppConstants.Ads.bonusPerAd)회 받기")
                            }
                        }
                    }
                    .disabled(!quota.canWatchRewardAd || isWatchingAd || !AdManager.shared.isRewardAdReady)

                    if let msg = adResultMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !(authManager.currentUser?.isPro ?? false) {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Pro로 업그레이드하세요", systemImage: "crown.fill")
                                .font(.headline)
                                .foregroundStyle(.orange)
                            Text("Pro 구독 시 광고 없이 하루 \(quota.dailyLimit)회 요청을 사용하실 수 있습니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } else if let errorMessage = errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("사용량")
        .task {
            await loadQuota()
        }
        .refreshable {
            await loadQuota()
        }
    }

    private func loadQuota() async {
        isLoading = true
        errorMessage = nil
        do {
            quota = try await APIClient.shared.get(endpoint: "/api/quota")
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func watchRewardAd() async {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        isWatchingAd = true
        adResultMessage = nil

        let watched = await AdManager.shared.showRewardAd(from: rootVC)
        if watched {
            if let result = await AdManager.shared.claimRewardOnBackend() {
                if result.success {
                    adResultMessage = "+\(result.bonusGranted)회 추가되었습니다. 보너스 잔여: \(result.bonusAvailable)회"
                    await loadQuota()
                } else {
                    adResultMessage = "보상 처리에 실패했습니다."
                }
            } else {
                adResultMessage = "서버 오류가 발생했습니다."
            }
        }

        await AdManager.shared.loadRewardAd()
        isWatchingAd = false
    }

    private func progressColor(used: Int, limit: Int) -> Color {
        let ratio = Double(used) / Double(limit)
        if ratio >= 0.9 { return .red }
        if ratio >= 0.7 { return .orange }
        return .accentColor
    }
}
