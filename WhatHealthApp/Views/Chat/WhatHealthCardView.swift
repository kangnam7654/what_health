import SwiftUI

struct WhatHealthCardView: View {
    let plan: PlanParser.ParsedPlan
    let onSave: () -> Void
    let onSaveAndActivate: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plan.title)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        Text(plan.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(isExpanded ? nil : 2)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            // Day capsules
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(plan.routines) { routine in
                        Text(routine.dayOfWeek)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
            }

            // Expanded detail
            if isExpanded {
                Divider()

                ForEach(plan.routines) { routine in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(routine.dayOfWeek) — \(routine.focus)")
                            .font(.caption.bold())

                        ForEach(routine.exercises) { exercise in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text("•")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(exercise.name)
                                        .font(.caption)
                                    Spacer()
                                    Text("\(exercise.sets)×\(exercise.reps)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if let desc = exercise.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 14)
                                }

                                ExerciseVideoButton(exerciseName: exercise.name)
                                    .padding(.leading, 14)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            // Action buttons
            HStack(spacing: 8) {
                Button(action: onSaveAndActivate) {
                    Text("저장 & 활성화")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(action: onSave) {
                    Text("저장")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: 300)
    }
}
