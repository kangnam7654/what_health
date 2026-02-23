import SwiftUI
import StoreKit

struct SubscriptionView: View {
    @State private var storeManager: StoreManager
    private let authManager = AuthManager.shared

    init(storeManager: StoreManager) {
        self._storeManager = State(initialValue: storeManager)
    }

    var body: some View {
        List {
            currentPlanSection
            availablePlansSection

            Section {
                Button("구매 복원") {
                    Task { await storeManager.restorePurchases() }
                }
                .disabled(storeManager.isLoading)
            }
        }
        .navigationTitle("구독 관리")
        .task {
            await storeManager.loadProducts()
        }
        .overlay {
            if storeManager.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.1))
            }
        }
        .alert("오류", isPresented: Binding(
            get: { storeManager.errorMessage != nil },
            set: { if !$0 { storeManager.errorMessage = nil } }
        )) {
            Button("확인") { storeManager.errorMessage = nil }
        } message: {
            Text(storeManager.errorMessage ?? "")
        }
    }

    // MARK: - Sections

    private var currentPlanSection: some View {
        Section("현재 플랜") {
            if let user = authManager.currentUser {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.subscriptionTier.displayName)
                            .font(.headline)
                        Text("일일 \(user.subscriptionTier.dailyLimit)회 요청")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    tierBadge(for: user.subscriptionTier)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var availablePlansSection: some View {
        Section("플랜 업그레이드") {
            if storeManager.products.isEmpty && !storeManager.isLoading {
                Text("이용 가능한 플랜이 없습니다.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(storeManager.products, id: \.id) { product in
                    productRow(for: product)
                }
            }
        }
    }

    // MARK: - Views

    @ViewBuilder
    private func productRow(for product: Product) -> some View {
        let isCurrentPlan = storeManager.purchasedSubscription?.id == product.id

        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(product.displayName)
                    .font(.headline)
                Text(product.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isCurrentPlan {
                Text("현재 플랜")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button(product.displayPrice) {
                    Task { await storeManager.purchase(product) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(storeManager.isLoading)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func tierBadge(for tier: SubscriptionTier) -> some View {
        let color: Color = switch tier {
        case .free: .gray
        case .basic: .blue
        case .premium: .purple
        }

        Text(tier.displayName)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
