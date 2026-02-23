import Foundation
import SwiftData

@Model
final class ChatSession {
    var title: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.session)
    var messages: [ChatMessage]?

    var sortedMessages: [ChatMessage] {
        (messages ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    init(title: String = "새 대화") {
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.messages = []
    }
}

@Model
final class ChatMessage {
    var content: String
    var role: MessageRole
    var createdAt: Date
    var session: ChatSession?

    init(content: String, role: MessageRole, session: ChatSession? = nil) {
        self.content = content
        self.role = role
        self.createdAt = Date()
        self.session = session
    }
}
