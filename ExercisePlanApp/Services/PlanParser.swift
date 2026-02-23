import Foundation

enum PlanParser {
    struct ParsedPlan {
        let title: String
        let summary: String
        let routines: [DayRoutine]
    }

    static func parse(response: String) throws -> ParsedPlan {
        let cleanedJSON = cleanJSONResponse(response)

        guard let data = cleanedJSON.data(using: .utf8) else {
            throw LLMError.parsingError("응답을 데이터로 변환할 수 없습니다")
        }

        do {
            let decoded = try JSONDecoder().decode(PlanJSON.self, from: data)
            return ParsedPlan(
                title: decoded.title,
                summary: decoded.summary,
                routines: decoded.routines
            )
        } catch {
            throw LLMError.parsingError("JSON 파싱 실패: \(error.localizedDescription)")
        }
    }

    private static func cleanJSONResponse(_ response: String) -> String {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code fences
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }

        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct PlanJSON: Decodable {
        let title: String
        let summary: String
        let routines: [DayRoutine]
    }
}
