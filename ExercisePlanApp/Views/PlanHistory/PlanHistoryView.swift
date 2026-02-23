import SwiftUI
import SwiftData

struct PlanHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ExercisePlan.createdAt, order: .reverse) private var plans: [ExercisePlan]
    @State private var viewModel = PlanHistoryViewModel()

    var body: some View {
        Group {
            if plans.isEmpty {
                ContentUnavailableView(
                    "저장된 플랜이 없습니다",
                    systemImage: "dumbbell",
                    description: Text("운동 플랜을 생성하고 저장해보세요.")
                )
            } else {
                List {
                    ForEach(plans) { plan in
                        NavigationLink {
                            PlanDetailView(plan: plan, viewModel: viewModel)
                        } label: {
                            planRow(plan)
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            viewModel.deletePlan(plans[index], modelContext: modelContext)
                        }
                    }
                }
            }
        }
        .navigationTitle("플랜 히스토리")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("닫기") {
                    dismiss()
                }
            }
        }
    }

    private func planRow(_ plan: ExercisePlan) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(plan.title)
                        .font(.headline)
                    if plan.isActive {
                        Text("활성")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .clipShape(Capsule())
                    }
                }
                Text(plan.createdAt.shortFormatted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: plan.goal.icon)
                .foregroundStyle(.blue)
        }
        .padding(.vertical, 4)
    }
}
