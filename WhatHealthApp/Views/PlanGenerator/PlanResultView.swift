import SwiftUI

struct PlanResultView: View {
    let title: String
    let summary: String
    let routines: [DayRoutine]
    let onSave: () -> Void
    let onSaveAndActivate: () -> Void
    let onRegenerate: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.title2.bold())
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                Divider()

                // Routines
                ForEach(routines) { routine in
                    routineSection(routine)
                }

                // Action Buttons
                VStack(spacing: 12) {
                    Button {
                        onSaveAndActivate()
                    } label: {
                        Label("저장하고 활성화", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        onSave()
                    } label: {
                        Label("저장만 하기", systemImage: "square.and.arrow.down")
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        onRegenerate()
                    } label: {
                        Label("다시 생성하기", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .padding(.vertical)
        }
        .navigationTitle("생성된 플랜")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("닫기") {
                    dismiss()
                }
            }
        }
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
                exerciseRow(exercise)
            }
        }
        .padding(.vertical, 8)
    }

    private func exerciseRow(_ exercise: ExerciseItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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

                HStack(spacing: 12) {
                    VStack(spacing: 0) {
                        Text("\(exercise.sets)")
                            .font(.subheadline.weight(.semibold))
                        Text("세트")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 0) {
                        Text(exercise.reps)
                            .font(.subheadline.weight(.semibold))
                        Text("반복")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 0) {
                        Text("\(exercise.restSeconds)s")
                            .font(.subheadline.weight(.semibold))
                        Text("휴식")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let desc = exercise.description, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ExerciseVideoButton(exerciseName: exercise.name)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
    }
}
