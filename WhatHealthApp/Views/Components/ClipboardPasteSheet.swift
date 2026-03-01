import SwiftUI

struct ClipboardPasteSheet: View {
    let exerciseName: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var pastedFromClipboard = false

    private var isValidURL: Bool {
        YouTubeURLValidator.isValid(urlText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(exerciseName)
                    .font(.headline)
                    .padding(.top, 8)

                // 안내 문구
                Label("영상 URL을 복사한 후 아래 버튼을 눌러주세요", systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // 클립보드 붙여넣기 버튼
                Button {
                    if let clip = UIPasteboard.general.string {
                        urlText = clip
                        pastedFromClipboard = true
                    }
                } label: {
                    Label("클립보드에서 붙여넣기", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                // 유효성 피드백
                if !urlText.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: isValidURL ? "checkmark.circle.fill" : "xmark.circle.fill")
                        Text(isValidURL ? "유효한 YouTube URL" : "유효한 YouTube URL이 아닙니다")
                    }
                    .font(.caption)
                    .foregroundStyle(isValidURL ? .green : .red)
                }

                // 직접 입력 (fallback)
                TextField("또는 URL 직접 입력", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                Spacer()
            }
            .padding()
            .navigationTitle("영상 URL 저장")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed)
                        dismiss()
                    }
                    .disabled(!isValidURL)
                }
            }
        }
    }
}
