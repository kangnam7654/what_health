import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    let session: ChatSession
    @Bindable var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool

    private var messages: [ChatMessage] {
        session.sortedMessages
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            messageBubble(message)
                                .id(message.id)
                        }

                        if viewModel.isLoading {
                            HStack {
                                loadingBubble
                                Spacer()
                            }
                            .padding(.horizontal)
                            .id("loading")
                        }
                    }
                    .padding(.vertical)
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation {
                        if let lastMessage = messages.last {
                            scrollProxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.isLoading) { _, isLoading in
                    if isLoading {
                        withAnimation {
                            scrollProxy.scrollTo("loading", anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input Bar
            HStack(spacing: 12) {
                TextField("메시지를 입력하세요...", text: $viewModel.inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)

                Button {
                    Task {
                        await viewModel.sendMessage(session: session, modelContext: modelContext)
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                }
                .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("오류", isPresented: $viewModel.showError) {
            Button("확인") {}
        } message: {
            Text(viewModel.errorMessage ?? "알 수 없는 오류")
        }
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer() }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.role == .user ? Color.blue : Color(.systemGray5))
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Text(message.createdAt.timeFormatted)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 280, alignment: message.role == .user ? .trailing : .leading)
            .padding(.horizontal)

            if message.role == .assistant { Spacer() }
        }
    }

    private var loadingBubble: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .opacity(0.4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}
