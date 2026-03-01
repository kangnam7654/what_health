import Foundation

enum ChatContentSegment {
    case text(String)
    case exercisePlan(PlanParser.ParsedPlan)
}

enum ChatResponseParser {
    private static let openTag = "[EXERCISE_PLAN]"
    private static let closeTag = "[/EXERCISE_PLAN]"

    static func parse(response: String) -> [ChatContentSegment] {
        var segments: [ChatContentSegment] = []
        var remaining = response

        while let openRange = remaining.range(of: openTag) {
            // Text before the tag
            let textBefore = String(remaining[remaining.startIndex..<openRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !textBefore.isEmpty {
                segments.append(.text(textBefore))
            }

            remaining = String(remaining[openRange.upperBound...])

            guard let closeRange = remaining.range(of: closeTag) else {
                // No closing tag — treat everything as text
                let fallback = openTag + remaining
                segments.append(.text(fallback))
                remaining = ""
                break
            }

            let jsonBlock = String(remaining[remaining.startIndex..<closeRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            remaining = String(remaining[closeRange.upperBound...])

            if let parsed = try? PlanParser.parse(response: jsonBlock) {
                segments.append(.exercisePlan(parsed))
            } else {
                // JSON parse failed — show as text
                segments.append(.text(jsonBlock))
            }
        }

        // Remaining text after last tag (or entire response if no tags)
        let tail = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            segments.append(.text(tail))
        }

        if segments.isEmpty && !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(.text(response))
        }

        return segments
    }
}
