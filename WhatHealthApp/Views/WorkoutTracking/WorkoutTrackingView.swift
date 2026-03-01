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
                exerciseCard(exercise: exercise, exerciseItem: routine.exercises[safe: index], index: index)
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

    private func exerciseCard(exercise: CompletedExercise, exerciseItem: ExerciseItem?, index: Int) -> some View {
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
                    // Exercise type badge
                    let type = ExerciseType.infer(from: exercise.exerciseName, raw: exercise.exerciseType)
                    Text(type.badge)
                        .font(.caption2)
                        .foregroundStyle(type.color)
                    Image(systemName: expandedExercise == index ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if expandedExercise == index && viewModel.isWorkoutActive {
                let type = ExerciseType.infer(from: exercise.exerciseName, raw: exercise.exerciseType)
                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { setIndex, setRecord in
                    setRow(exerciseIndex: index, setIndex: setIndex, setRecord: setRecord, exerciseType: type)
                }

                // Rest timer inline
                if viewModel.isRestTimerActive && viewModel.restExerciseIndex == index {
                    restTimerView
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Set Row by Exercise Type

    private func setRow(exerciseIndex: Int, setIndex: Int, setRecord: SetRecord, exerciseType: ExerciseType) -> some View {
        Group {
            switch exerciseType {
            case .strength:
                strengthSetRow(exerciseIndex: exerciseIndex, setIndex: setIndex, setRecord: setRecord)
            case .cardio:
                cardioSetRow(exerciseIndex: exerciseIndex, setIndex: setIndex, setRecord: setRecord)
            case .stretching:
                stretchingSetRow(exerciseIndex: exerciseIndex, setIndex: setIndex, setRecord: setRecord)
            }
        }
    }

    private func strengthSetRow(exerciseIndex: Int, setIndex: Int, setRecord: SetRecord) -> some View {
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

            setCompletionButton(exerciseIndex: exerciseIndex, setIndex: setIndex, setRecord: setRecord)
        }
        .padding(.leading, 8)
    }

    private func cardioSetRow(exerciseIndex: Int, setIndex: Int, setRecord: SetRecord) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text("세트 \(setIndex + 1)")
                    .font(.caption)
                    .frame(width: 50, alignment: .leading)

                HStack(spacing: 4) {
                    TextField("분", value: Binding(
                        get: { setRecord.duration },
                        set: { viewModel.updateSet(exerciseIndex: exerciseIndex, setIndex: setIndex, duration: $0, speed: setRecord.speed, incline: setRecord.incline) }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                    .keyboardType(.decimalPad)

                    Text("분")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    TextField("km/h", value: Binding(
                        get: { setRecord.speed },
                        set: { viewModel.updateSet(exerciseIndex: exerciseIndex, setIndex: setIndex, duration: setRecord.duration, speed: $0, incline: setRecord.incline) }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                    .keyboardType(.decimalPad)

                    Text("km/h")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                setCompletionButton(exerciseIndex: exerciseIndex, setIndex: setIndex, setRecord: setRecord)
            }

            HStack(spacing: 12) {
                Spacer().frame(width: 50)

                HStack(spacing: 4) {
                    Text("경사")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("%", value: Binding(
                        get: { setRecord.incline },
                        set: { viewModel.updateSet(exerciseIndex: exerciseIndex, setIndex: setIndex, duration: setRecord.duration, speed: setRecord.speed, incline: $0) }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                    .keyboardType(.decimalPad)

                    Text("%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding(.leading, 8)
    }

    private func stretchingSetRow(exerciseIndex: Int, setIndex: Int, setRecord: SetRecord) -> some View {
        HStack(spacing: 12) {
            Text("세트 \(setIndex + 1)")
                .font(.caption)
                .frame(width: 50, alignment: .leading)

            HStack(spacing: 4) {
                TextField("초", value: Binding(
                    get: { setRecord.duration },
                    set: { viewModel.updateSet(exerciseIndex: exerciseIndex, setIndex: setIndex, duration: $0) }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .keyboardType(.decimalPad)

                Text("초")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            setCompletionButton(exerciseIndex: exerciseIndex, setIndex: setIndex, setRecord: setRecord)
        }
        .padding(.leading, 8)
    }

    private func setCompletionButton(exerciseIndex: Int, setIndex: Int, setRecord: SetRecord) -> some View {
        Button {
            let restSeconds = viewModel.todayRoutine?.exercises[safe: exerciseIndex]?.restSeconds ?? 0
            viewModel.toggleSetCompletion(exerciseIndex: exerciseIndex, setIndex: setIndex, restSeconds: restSeconds)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: setRecord.isCompleted ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.title3)
                Text(setRecord.isCompleted ? "완료" : "완료")
                    .font(.caption2)
            }
            .foregroundStyle(setRecord.isCompleted ? Color.green : Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(setRecord.isCompleted ? Color.green.opacity(0.12) : Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: setRecord.isCompleted)
    }

    // MARK: - Rest Timer

    private var restTimerView: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                Image(systemName: "bed.double.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                Text("세트 간 휴식")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(formatRestTime(viewModel.restTimeRemaining))
                    .font(.system(size: 40, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
                    .contentTransition(.numericText())

                ProgressView(value: Double(viewModel.restTimeRemaining), total: Double(max(viewModel.restTimeDuration, 1)))
                    .tint(.orange)
                    .padding(.horizontal)

                Text("다음 세트까지 \(viewModel.restTimeRemaining)초 남았습니다")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    viewModel.stopRestTimer()
                } label: {
                    Text("휴식 건너뛰기")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }
            .padding()
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func formatRestTime(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
