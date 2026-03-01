import Foundation
import SwiftData
import Observation
import UIKit

@Observable
@MainActor
final class ChatViewModel {
    var inputText: String = ""
    var isLoading: Bool = false
    var errorMessage: String?
    var showError: Bool = false
    var showQuotaExceeded: Bool = false
    var canWatchRewardAd: Bool = false

    func sendMessage(session: ChatSession, modelContext: ModelContext, savedExerciseNames: [String] = []) async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        guard let service = LLMServiceFactory.createFromSettings() else {
            errorMessage = "로그인이 필요합니다."
            showError = true
            return
        }

        // Add user message
        let userMessage = ChatMessage(content: text, role: .user, session: session)
        modelContext.insert(userMessage)
        session.updatedAt = Date()

        inputText = ""
        isLoading = true
        errorMessage = nil

        // Build messages for LLM
        var llmMessages: [LLMMessage] = [
            .system(PromptBuilder.buildChatWithPlanSystemPrompt(savedExerciseNames: savedExerciseNames))
        ]

        // Add conversation history (last 20 messages for context)
        let recentMessages = session.sortedMessages.suffix(20)
        for msg in recentMessages {
            switch msg.role {
            case .user:
                llmMessages.append(.user(msg.content))
            case .assistant:
                llmMessages.append(.assistant(msg.content))
            case .system:
                break
            }
        }

        do {
            let response = try await service.sendMessage(messages: llmMessages)

            let assistantMessage = ChatMessage(content: response, role: .assistant, session: session)
            modelContext.insert(assistantMessage)
            session.updatedAt = Date()

            // Update session title from first exchange
            if session.sortedMessages.count <= 3 && session.title == "새 대화" {
                session.title = String(text.prefix(30))
                if text.count > 30 {
                    session.title += "..."
                }
            }

            try? modelContext.save()
        } catch let error as LLMError {
            if case .quotaExceeded = error {
                showQuotaExceeded = true
                await refreshQuotaStatus()
            } else {
                errorMessage = error.localizedDescription
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }

    func watchRewardAd() async {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        let watched = await AdManager.shared.showRewardAd(from: rootVC)
        if watched {
            _ = await AdManager.shared.claimRewardOnBackend()
            await AdManager.shared.loadRewardAd()
            await refreshQuotaStatus()
        }
    }

    func refreshQuotaStatus() async {
        do {
            let quota: QuotaResponse = try await APIClient.shared.get(endpoint: "/api/quota")
            canWatchRewardAd = quota.canWatchRewardAd
        } catch {
            canWatchRewardAd = false
        }
    }

    func deleteSession(_ session: ChatSession, modelContext: ModelContext) {
        modelContext.delete(session)
        try? modelContext.save()
    }

    func createNewSession(modelContext: ModelContext) -> ChatSession {
        let session = ChatSession(userId: AuthManager.shared.currentUser?.id)
        modelContext.insert(session)
        try? modelContext.save()
        return session
    }
}
