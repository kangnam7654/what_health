import SwiftUI

struct QuotaView: View {
    @State private var quota: QuotaResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
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
                    LabeledContent("플랜", value: quota.tier.capitalized)
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

                if quota.tier.lowercased() == "free" {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("더 많은 요청이 필요하신가요?", systemImage: "arrow.up.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.blue)
                            Text("Basic 또는 Premium 플랜으로 업그레이드하면 더 많은 요청을 사용하실 수 있습니다.")
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

    private func progressColor(used: Int, limit: Int) -> Color {
        let ratio = Double(used) / Double(limit)
        if ratio >= 0.9 { return .red }
        if ratio >= 0.7 { return .orange }
        return .blue
    }
}
