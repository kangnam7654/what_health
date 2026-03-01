import SwiftUI
import SwiftData

struct PlanGeneratorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WhatHealth.createdAt, order: .reverse) private var savedPlans: [WhatHealth]
    @Query private var savedVideos: [SavedExerciseVideo]
    @State private var viewModel = PlanGeneratorViewModel()
    @State private var historyViewModel = PlanHistoryViewModel()
    @State private var showGeneratorForm = false
    @State private var showResult = false
    @State private var pendingResult = false

    private var activePlan: WhatHealth? {
        savedPlans.first { $0.isActive }
    }

    private var inactivePlans: [WhatHealth] {
        savedPlans.filter { !$0.isActive }
    }

    var body: some View {
        Group {
            if savedPlans.isEmpty {
                ContentUnavailableView {
                    Label("운동 플랜이 없습니다", systemImage: "dumbbell")
                } description: {
                    Text("새 플랜을 생성하고 운동을 시작해보세요.")
                } actions: {
                    Button("새 플랜 생성") {
                        showGeneratorForm = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 0) {
                    planList
                    if !(AuthManager.shared.currentUser?.isPro ?? false) {
                        BannerAdView()
                            .frame(height: 50)
                    }
                }
            }
        }
        .navigationTitle("운동 플랜")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showGeneratorForm = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showGeneratorForm, onDismiss: {
            if pendingResult {
                pendingResult = false
                showResult = true
            }
        }) {
            NavigationStack {
                generatorFormSheet
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
                                await viewModel.generatePlan(savedExerciseNames: savedVideos.map(\.exerciseName))
                                if viewModel.generatedPlan != nil {
                                    showResult = true
                                }
                            }
                        }
                    )
                }
            }
        }
        .alert("오류", isPresented: $viewModel.showError) {
            Button("확인") {}
        } message: {
            Text(viewModel.errorMessage ?? "알 수 없는 오류")
        }
    }

    // MARK: - Plan List

    private var planList: some View {
        List {
            if let active = activePlan {
                Section {
                    NavigationLink {
                        PlanDetailView(plan: active, viewModel: historyViewModel)
                    } label: {
                        activePlanLabel(active)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            historyViewModel.deactivatePlan(active, modelContext: modelContext)
                        } label: {
                            Label("비활성화", systemImage: "pause.circle")
                        }
                        .tint(.orange)
                    }
                    .listRowBackground(Color.accentColor.opacity(0.08))
                }
            }

            if !inactivePlans.isEmpty {
                Section {
                    ForEach(inactivePlans) { plan in
                        NavigationLink {
                            PlanDetailView(plan: plan, viewModel: historyViewModel)
                        } label: {
                            inactivePlanLabel(plan)
                        }
                    }
                    .onDelete(perform: deleteInactivePlans)
                } header: {
                    Text("저장된 플랜")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Active Plan Label

    private func activePlanLabel(_ plan: WhatHealth) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: plan.goal.icon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                Text(plan.title)
                    .font(.headline)
                Spacer()
                Text("활성")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green)
                    .clipShape(Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(plan.weeklyRoutines) { routine in
                        Text(routine.dayOfWeek)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
            }

            Text(plan.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Inactive Plan Label

    private func inactivePlanLabel(_ plan: WhatHealth) -> some View {
        HStack(spacing: 12) {
            Image(systemName: plan.goal.icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(plan.title)
                    .font(.subheadline.weight(.medium))
                Text(plan.createdAt.shortFormatted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(plan.weeklyRoutines.count)일")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Delete

    private func deleteInactivePlans(at offsets: IndexSet) {
        for index in offsets {
            historyViewModel.deletePlan(inactivePlans[index], modelContext: modelContext)
        }
    }

    // MARK: - Generator Form Sheet

    private var generatorFormSheet: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("운동 목표")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(ExerciseGoal.allCases) { goal in
                                goalCard(goal)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("운동 경험")
                        Picker("경험 수준", selection: $viewModel.selectedExperience) {
                            ForEach(ExperienceLevel.allCases) { level in
                                Text(level.rawValue).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("사용 가능한 장비")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(Equipment.allCases) { equipment in
                                equipmentChip(equipment)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("운동 요일")
                        HStack(spacing: 8) {
                            ForEach(DayOfWeek.allCases) { day in
                                dayButton(day)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("세션 시간")
                        Picker("세션 시간", selection: $viewModel.selectedDuration) {
                            ForEach(SessionDuration.allCases) { duration in
                                Text(duration.displayName).tag(duration)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("추가 사항")
                        TextField("예: 허리 통증 있음, 상체 위주 원함...", text: $viewModel.additionalNotes, axis: .vertical)
                            .lineLimit(3...5)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding()
            }

            Button {
                Task {
                    await viewModel.generatePlan(savedExerciseNames: savedVideos.map(\.exerciseName))
                    if viewModel.generatedPlan != nil {
                        pendingResult = true
                        showGeneratorForm = false
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
                .background(viewModel.canGenerate && !viewModel.isGenerating ? Color.accentColor : Color.gray)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!viewModel.canGenerate || viewModel.isGenerating)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .navigationTitle("새 플랜 생성")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("닫기") {
                    showGeneratorForm = false
                }
            }
        }
        .alert("오류", isPresented: $viewModel.showError) {
            Button("확인") {}
        } message: {
            Text(viewModel.errorMessage ?? "알 수 없는 오류")
        }
        .alert("사용량 초과", isPresented: $viewModel.showQuotaExceeded) {
            if viewModel.canWatchRewardAd && AdManager.shared.isRewardAdReady {
                Button("광고 보고 +10회 받기") {
                    Task { await viewModel.watchRewardAd() }
                }
            }
            Button("확인") {}
        } message: {
            Text("일일 사용 한도를 초과했습니다.")
        }
    }

    // MARK: - Form Components

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
            .background(viewModel.selectedGoal == goal ? Color.accentColor.opacity(0.15) : Color(.systemGray6))
            .foregroundStyle(viewModel.selectedGoal == goal ? Color.accentColor : Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(viewModel.selectedGoal == goal ? Color.accentColor : Color.clear, lineWidth: 2)
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
