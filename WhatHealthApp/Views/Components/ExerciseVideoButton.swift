import SwiftUI
import SwiftData

/// fullScreenCover(item:) 용 Identifiable URL 래퍼
private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

struct ExerciseVideoButton: View {
    let exerciseName: String
    @Environment(\.modelContext) private var modelContext
    @Query private var allSavedVideos: [SavedExerciseVideo]
    @State private var safariItem: IdentifiableURL?
    @State private var showPasteSheet = false
    @State private var expectPasteOnDismiss = false
    @State private var showSearchGuide = false

    private var savedVideo: SavedExerciseVideo? {
        allSavedVideos.first { $0.exerciseName == exerciseName }
    }

    var body: some View {
        Button {
            if let saved = savedVideo, let url = URL(string: saved.videoURL) {
                expectPasteOnDismiss = false
                safariItem = IdentifiableURL(url: url)
            } else {
                showSearchGuide = true
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: savedVideo != nil ? "play.circle.fill" : "play.fill")
                Text(savedVideo != nil ? "저장된 영상" : "영상 보기")
                if savedVideo != nil {
                    Image(systemName: "ellipsis")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption2)
            .foregroundStyle(savedVideo != nil ? Color.accentColor : Color.red)
        }
        .contextMenu {
            if savedVideo != nil {
                Button {
                    showSearchGuide = true
                } label: {
                    Label("다른 영상 검색", systemImage: "magnifyingglass")
                }

                Button(role: .destructive) {
                    if let saved = savedVideo {
                        modelContext.delete(saved)
                    }
                } label: {
                    Label("저장 삭제", systemImage: "trash")
                }
            }
        }
        .alert("영상 검색 안내", isPresented: $showSearchGuide) {
            Button("검색하기") {
                if let url = YouTubeURLValidator.searchURL(for: exerciseName) {
                    expectPasteOnDismiss = true
                    safariItem = IdentifiableURL(url: url)
                }
            }
            Button("취소", role: .cancel) { }
        } message: {
            Text("유튜브에서 영상을 찾은 후\nURL을 복사하고 돌아오세요")
        }
        .fullScreenCover(item: $safariItem, onDismiss: {
            if expectPasteOnDismiss {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showPasteSheet = true
                }
            }
        }) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showPasteSheet) {
            ClipboardPasteSheet(exerciseName: exerciseName) { urlString in
                saveVideoURL(urlString)
            }
            .presentationDetents([.medium])
        }
    }

    private func saveVideoURL(_ urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, URL(string: trimmed) != nil else { return }

        if let existing = savedVideo {
            existing.videoURL = trimmed
            existing.savedAt = .now
        } else {
            let newVideo = SavedExerciseVideo(exerciseName: exerciseName, videoURL: trimmed)
            modelContext.insert(newVideo)
        }
    }
}
