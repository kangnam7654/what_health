import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    let session: ChatSession
    @Bindable var viewModel: ChatViewModel
    @Query private var savedVideos: [SavedExerciseVideo]
    @FocusState private var isInputFocused: Bool
    @State private var toastMessage: String?
    @State private var segmentCache: [PersistentIdentifier: [ChatContentSegment]] = [:]

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

            // Banner Ad (non-Pro users only)
            if !(AuthManager.shared.currentUser?.isPro ?? false) {
                BannerAdView()
                    .frame(height: 50)
            }

            // Input Bar
            HStack(spacing: 12) {
                TextField("메시지를 입력하세요...", text: $viewModel.inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)

                Button {
                    Task {
                        await viewModel.sendMessage(session: session, modelContext: modelContext, savedExerciseNames: savedVideos.map(\.exerciseName))
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.accentColor)
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
        .overlay(alignment: .bottom) {
            if let toast = toastMessage {
                Text(toast)
                    .font(.subheadline.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .shadow(radius: 4)
                    .padding(.bottom, 80)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private func messageBubble(_ message: ChatMessage) -> some View {
        if message.role == .user {
            userBubble(message)
        } else {
            assistantBubble(message)
        }
    }

    private func userBubble(_ message: ChatMessage) -> some View {
        HStack {
            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Text(message.createdAt.timeFormatted)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 280, alignment: .trailing)
            .padding(.horizontal)
        }
    }

    private func segmentsFor(_ message: ChatMessage) -> [ChatContentSegment] {
        if let cached = segmentCache[message.id] {
            return cached
        }
        let parsed = ChatResponseParser.parse(response: message.content)
        // @State 변경을 뷰 렌더링 밖으로 지연시키기 위함
        DispatchQueue.main.async {
            segmentCache[message.id] = parsed
        }
        return parsed
    }

    private func assistantBubble(_ message: ChatMessage) -> some View {
        let segments = segmentsFor(message)

        return HStack {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(segments.enumerated()), id: \.offset) { item in
                    switch item.element {
                    case .text(let text):
                        Text(text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray5))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 16))

                    case .exercisePlan(let parsed):
                        WhatHealthCardView(
                            plan: parsed,
                            onSave: { savePlan(parsed, activate: false) },
                            onSaveAndActivate: { savePlan(parsed, activate: true) }
                        )
                    }
                }

                Text(message.createdAt.timeFormatted)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 300, alignment: .leading)
            .padding(.horizontal)

            Spacer()
        }
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { toastMessage = nil }
        }
    }

    private func savePlan(_ parsed: PlanParser.ParsedPlan, activate: Bool) {
        if activate {
            let descriptor = FetchDescriptor<WhatHealth>(predicate: #Predicate { $0.isActive })
            if let activePlans = try? modelContext.fetch(descriptor) {
                for plan in activePlans {
                    plan.isActive = false
                }
            }
        }

        let plan = WhatHealth(
            title: parsed.title,
            summary: parsed.summary,
            weeklyRoutines: parsed.routines,
            goal: parsed.goal ?? .strength,
            isActive: activate
        )
        modelContext.insert(plan)
        do {
            try modelContext.save()
        } catch {
            showToast("저장 실패: \(error.localizedDescription)")
            return
        }

        showToast(activate ? "플랜이 저장되고 활성화되었습니다" : "플랜이 저장되었습니다")
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
