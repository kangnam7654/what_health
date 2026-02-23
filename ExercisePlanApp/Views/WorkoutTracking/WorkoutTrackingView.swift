import SwiftUI
import SwiftData

struct WorkoutTrackingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = WorkoutTrackingViewModel()
    @State private var showFinishAlert = false
    @State private var expandedExercise: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Stats Card
                statsSection

                Divider()

                // Today's Workout
                if let routine = viewModel.todayRoutine {
                    todaySection(routine)
                } else if viewModel.currentPlan != nil {
                    ContentUnavailableView(
                        "오늘은 휴식일입니다",
                        systemImage: "bed.double.fill",
                        description: Text("충분히 쉬고 다음 운동을 준비하세요!")
                    )
                } else {
                    ContentUnavailableView(
                        "활성 플랜이 없습니다",
                        systemImage: "dumbbell",
                        description: Text("운동 플랜 탭에서 새 플랜을 생성해보세요.")
                    )
                }
            }
            .padding()
        }
        .navigationTitle("운동 기록")
        .onAppear {
            viewModel.loadData(modelContext: modelContext)
        }
        .alert("운동 완료", isPresented: $showFinishAlert) {
            Button("완료") {
                viewModel.finishWorkout(modelContext: modelContext)
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("오늘의 운동을 완료하시겠습니까?")
        }
    }

    private var statsSection: some View {
        HStack(spacing: 0) {
            statItem(value: "\(viewModel.stats.totalWorkouts)", label: "총 운동")
            Divider().frame(height: 40)
            statItem(value: "\(viewModel.stats.thisWeekCount)", label: "이번 주")
            Divider().frame(height: 40)
            statItem(value: "\(viewModel.stats.currentStreak)일", label: "연속")
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func todaySection(_ routine: DayRoutine) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("오늘의 운동")
                        .font(.headline)
                    Text("\(routine.dayOfWeek) - \(routine.focus)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if !viewModel.isWorkoutActive {
                    Button("시작") {
                        viewModel.startWorkout()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if viewModel.isWorkoutActive {
                // Progress Bar
                ProgressView(value: viewModel.completionRate)
                    .tint(.green)

                Text("완료율: \(Int(viewModel.completionRate * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Exercise List
            ForEach(Array(viewModel.todayExercises.enumerated()), id: \.element.id) { index, exercise in
                exerciseCard(exercise: exercise, index: index)
            }

            if viewModel.isWorkoutActive {
                Button {
                    showFinishAlert = true
                } label: {
                    Label("운동 완료", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func exerciseCard(exercise: CompletedExercise, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation {
                    if expandedExercise == index {
                        expandedExercise = nil
                    } else {
                        expandedExercise = index
                    }
                }
            } label: {
                HStack {
                    Image(systemName: exercise.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(exercise.isCompleted ? .green : .secondary)
                    Text(exercise.exerciseName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: expandedExercise == index ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if expandedExercise == index && viewModel.isWorkoutActive {
                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { setIndex, setRecord in
                    setRow(exerciseIndex: index, setIndex: setIndex, setRecord: setRecord)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func setRow(exerciseIndex: Int, setIndex: Int, setRecord: SetRecord) -> some View {
        HStack(spacing: 12) {
            Text("세트 \(setIndex + 1)")
                .font(.caption)
                .frame(width: 50, alignment: .leading)

            HStack(spacing: 4) {
                TextField("kg", value: Binding(
                    get: { setRecord.weight },
                    set: { viewModel.updateSet(exerciseIndex: exerciseIndex, setIndex: setIndex, weight: $0, reps: setRecord.reps) }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .keyboardType(.decimalPad)

                Text("kg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                TextField("회", value: Binding(
                    get: { setRecord.reps },
                    set: { viewModel.updateSet(exerciseIndex: exerciseIndex, setIndex: setIndex, weight: setRecord.weight, reps: $0) }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 50)
                .keyboardType(.numberPad)

                Text("회")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                viewModel.toggleSetCompletion(exerciseIndex: exerciseIndex, setIndex: setIndex)
            } label: {
                Image(systemName: setRecord.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(setRecord.isCompleted ? .green : .secondary)
            }
        }
        .padding(.leading, 8)
    }
}
