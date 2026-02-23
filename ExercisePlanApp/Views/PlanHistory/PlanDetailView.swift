import SwiftUI
import SwiftData

struct PlanDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let plan: ExercisePlan
    let viewModel: PlanHistoryViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(plan.title)
                            .font(.title2.bold())
                        if plan.isActive {
                            Text("활성")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green)
                                .clipShape(Capsule())
                        }
                    }
                    Text(plan.summary)
                        .font(.body)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        Label(plan.goal.rawValue, systemImage: plan.goal.icon)
                        Label(plan.createdAt.fullFormatted, systemImage: "calendar")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                Divider()

                // Routines
                ForEach(plan.weeklyRoutines) { routine in
                    routineSection(routine)
                }

                if !plan.isActive {
                    Button {
                        viewModel.activatePlan(plan, modelContext: modelContext)
                    } label: {
                        Label("이 플랜으로 운동 시작", systemImage: "play.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("플랜 상세")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func routineSection(_ routine: DayRoutine) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(routine.dayOfWeek)
                    .font(.headline)
                Spacer()
                Text(routine.focus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            ForEach(routine.exercises) { exercise in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name)
                            .font(.subheadline.weight(.medium))
                        if let notes = exercise.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Text("\(exercise.sets)x\(exercise.reps)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("\(exercise.restSeconds)s")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }
}
