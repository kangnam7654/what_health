import SwiftUI
import SwiftData

struct ChatSessionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatSession.updatedAt, order: .reverse) private var sessions: [ChatSession]
    @State private var viewModel = ChatViewModel()
    @State private var selectedSession: ChatSession?
    @State private var navigateToChat = false

    var body: some View {
        Group {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "대화가 없습니다",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("AI 트레이너와 운동에 대해 대화해보세요.")
                )
            } else {
                List {
                    ForEach(sessions) { session in
                        Button {
                            viewModel.inputText = ""
                            viewModel.errorMessage = nil
                            selectedSession = session
                            navigateToChat = true
                        } label: {
                            sessionRow(session)
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            viewModel.deleteSession(sessions[index], modelContext: modelContext)
                        }
                    }
                }
            }
        }
        .navigationTitle("AI 상담")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let newSession = viewModel.createNewSession(modelContext: modelContext)
                    selectedSession = newSession
                    navigateToChat = true
                } label: {
                    Image(systemName: "plus.bubble.fill")
                }
            }
        }
        .navigationDestination(isPresented: $navigateToChat) {
            if let session = selectedSession {
                ChatView(session: session, viewModel: viewModel)
            }
        }
    }

    private func sessionRow(_ session: ChatSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title)
                .font(.headline)
            HStack {
                Text(session.updatedAt.relativeFormatted)
                Text("·")
                Text("\(session.sortedMessages.count)개 메시지")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
