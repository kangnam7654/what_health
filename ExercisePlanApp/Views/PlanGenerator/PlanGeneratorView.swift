import SwiftUI
import SwiftData

struct PlanGeneratorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExercisePlan.createdAt, order: .reverse) private var savedPlans: [ExercisePlan]
    @State private var viewModel = PlanGeneratorViewModel()
    @State private var showResult = false
    @State private var showHistory = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    // Goal Selection
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("운동 목표")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(ExerciseGoal.allCases) { goal in
                                goalCard(goal)
                            }
                        }
                    }

                    // Experience Level
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("운동 경험")
                        Picker("경험 수준", selection: $viewModel.selectedExperience) {
                            ForEach(ExperienceLevel.allCases) { level in
                                Text(level.rawValue).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Equipment
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("사용 가능한 장비")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(Equipment.allCases) { equipment in
                                equipmentChip(equipment)
                            }
                        }
                    }

                    // Training Days
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("운동 요일")
                        HStack(spacing: 8) {
                            ForEach(DayOfWeek.allCases) { day in
                                dayButton(day)
                            }
                        }
                    }

                    // Session Duration
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("세션 시간")
                        Picker("세션 시간", selection: $viewModel.selectedDuration) {
                            ForEach(SessionDuration.allCases) { duration in
                                Text(duration.displayName).tag(duration)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Additional Notes
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("추가 사항")
                        TextField("예: 허리 통증 있음, 상체 위주 원함...", text: $viewModel.additionalNotes, axis: .vertical)
                            .lineLimit(3...5)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding()
            }

            // Generate Button (fixed at bottom)
            Button {
                Task {
                    await viewModel.generatePlan()
                    if viewModel.generatedPlan != nil {
                        showResult = true
                    }
                }
            } label: {
                HStack {
                    if viewModel.isGenerating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(viewModel.isGenerating ? "생성 중..." : "AI 운동 플랜 생성")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.canGenerate && !viewModel.isGenerating ? Color.blue : Color.gray)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!viewModel.canGenerate || viewModel.isGenerating)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .navigationTitle("운동 플랜")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .badge(savedPlans.count)
            }
        }
        .sheet(isPresented: $showResult) {
            if let plan = viewModel.generatedPlan {
                NavigationStack {
                    PlanResultView(
                        title: plan.title,
                        summary: plan.summary,
                        routines: plan.routines,
                        onSave: {
                            viewModel.savePlan(modelContext: modelContext)
                            showResult = false
                            viewModel.reset()
                        },
                        onSaveAndActivate: {
                            viewModel.saveAndActivatePlan(modelContext: modelContext)
                            showResult = false
                            viewModel.reset()
                        },
                        onRegenerate: {
                            showResult = false
                            Task {
                                await viewModel.generatePlan()
                                if viewModel.generatedPlan != nil {
                                    showResult = true
                                }
                            }
                        }
                    )
                }
            }
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack {
                PlanHistoryView()
            }
        }
        .alert("오류", isPresented: $viewModel.showError) {
            Button("확인") {}
        } message: {
            Text(viewModel.errorMessage ?? "알 수 없는 오류")
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
    }

    private func goalCard(_ goal: ExerciseGoal) -> some View {
        Button {
            viewModel.selectedGoal = goal
        } label: {
            VStack(spacing: 8) {
                Image(systemName: goal.icon)
                    .font(.title2)
                Text(goal.rawValue)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(viewModel.selectedGoal == goal ? Color.blue.opacity(0.15) : Color(.systemGray6))
            .foregroundStyle(viewModel.selectedGoal == goal ? .blue : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(viewModel.selectedGoal == goal ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func equipmentChip(_ equipment: Equipment) -> some View {
        Button {
            viewModel.toggleEquipment(equipment)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: equipment.icon)
                    .font(.title3)
                Text(equipment.rawValue)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(viewModel.selectedEquipment.contains(equipment) ? Color.green.opacity(0.15) : Color(.systemGray6))
            .foregroundStyle(viewModel.selectedEquipment.contains(equipment) ? .green : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(viewModel.selectedEquipment.contains(equipment) ? Color.green : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func dayButton(_ day: DayOfWeek) -> some View {
        Button {
            viewModel.toggleDay(day)
        } label: {
            Text(day.shortName)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(viewModel.selectedDays.contains(day) ? Color.orange.opacity(0.15) : Color(.systemGray6))
                .foregroundStyle(viewModel.selectedDays.contains(day) ? .orange : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(viewModel.selectedDays.contains(day) ? Color.orange : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }
}
