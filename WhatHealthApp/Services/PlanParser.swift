import Foundation

enum PlanParser {
    struct ParsedPlan {
        let title: String
        let summary: String
        let routines: [DayRoutine]
        let goal: ExerciseGoal?
    }

    /// LLM 응답(JSON, 코드 펜스 허용)을 파싱하고 구조를 검증합니다.
    ///
    /// - Parameters:
    ///   - response: 모델 응답 원문
    ///   - requiredDays: 전용 플랜 생성기에서 사용자가 선택한 요일 집합.
    ///     지정하면 응답의 요일 집합이 이 집합과 정확히 일치해야 합니다(누락·추가 모두 거부).
    ///     `nil`이면(채팅 태그 플랜) 요일 제약 없이 구조 검사만 수행합니다.
    /// - Throws: 디코딩 실패나 구조 검증 실패 시 `LLMError.parsingError`.
    ///   잘못된 모델 출력은 보정하지 않고 거부합니다. 이 검사는 형식 검증일 뿐
    ///   운동 내용의 의학적 안전성을 판단하지 않습니다.
    static func parse(response: String, requiredDays: Set<DayOfWeek>? = nil) throws -> ParsedPlan {
        let cleanedJSON = cleanJSONResponse(response)

        guard let data = cleanedJSON.data(using: .utf8) else {
            throw LLMError.parsingError("응답을 데이터로 변환할 수 없습니다")
        }

        let decoded: PlanJSON
        do {
            decoded = try JSONDecoder().decode(PlanJSON.self, from: data)
        } catch {
            throw LLMError.parsingError("JSON 파싱 실패: \(error.localizedDescription)")
        }

        let goal = try validate(decoded, requiredDays: requiredDays)

        return ParsedPlan(
            title: decoded.title,
            summary: decoded.summary,
            routines: decoded.routines,
            goal: goal
        )
    }

    // MARK: - Validation

    /// 구조 검증을 수행하고, 검증된 목표(goal)를 반환합니다. goal 생략은 허용됩니다.
    private static func validate(_ plan: PlanJSON, requiredDays: Set<DayOfWeek>?) throws -> ExerciseGoal? {
        guard !isBlank(plan.title) else {
            throw invalid("플랜 제목(title)이 비어 있습니다")
        }
        guard !isBlank(plan.summary) else {
            throw invalid("플랜 요약(summary)이 비어 있습니다")
        }

        var goal: ExerciseGoal?
        if let rawGoal = plan.goal {
            guard let recognized = ExerciseGoal(rawValue: rawGoal) else {
                let allowed = ExerciseGoal.allCases.map(\.rawValue).joined(separator: ", ")
                throw invalid("알 수 없는 운동 목표(goal) '\(rawGoal)' — 허용 값: \(allowed)")
            }
            goal = recognized
        }

        guard !plan.routines.isEmpty else {
            throw invalid("요일별 루틴(routines)이 하나도 없습니다")
        }

        var seenDays: Set<DayOfWeek> = []
        for (routineIndex, routine) in plan.routines.enumerated() {
            let routineLabel = "\(routineIndex + 1)번째 루틴"

            guard let day = canonicalDay(routine.dayOfWeek) else {
                throw invalid("\(routineIndex + 1)번째 루틴의 요일 '\(routine.dayOfWeek)'이(가) 올바른 요일명(월요일~일요일)이 아닙니다")
            }
            guard seenDays.insert(day).inserted else {
                throw invalid("\(day.fullName) 루틴이 중복되었습니다")
            }
            guard !isBlank(routine.focus) else {
                throw invalid("\(routineLabel)(\(day.fullName))의 운동 초점(focus)이 비어 있습니다")
            }
            guard !routine.exercises.isEmpty else {
                throw invalid("\(routineLabel)(\(day.fullName))에 운동(exercises)이 없습니다")
            }

            for (exerciseIndex, exercise) in routine.exercises.enumerated() {
                let exerciseLabel = "\(day.fullName) \(exerciseIndex + 1)번째 운동"
                guard !isBlank(exercise.name) else {
                    throw invalid("\(exerciseLabel)의 이름(name)이 비어 있습니다")
                }
                guard !isBlank(exercise.reps) else {
                    throw invalid("\(exerciseLabel)의 반복(reps)이 비어 있습니다")
                }
                guard exercise.sets > 0 else {
                    throw invalid("\(exerciseLabel)의 세트 수(sets)는 1 이상이어야 합니다 (받은 값: \(exercise.sets))")
                }
                guard exercise.restSeconds >= 0 else {
                    throw invalid("\(exerciseLabel)의 휴식 시간(restSeconds)은 0 이상이어야 합니다 (받은 값: \(exercise.restSeconds))")
                }
            }
        }

        if let requiredDays {
            let missing = requiredDays.subtracting(seenDays)
            let extra = seenDays.subtracting(requiredDays)
            if !missing.isEmpty || !extra.isEmpty {
                var details: [String] = []
                if !missing.isEmpty {
                    details.append("누락된 요일: \(dayList(missing))")
                }
                if !extra.isEmpty {
                    details.append("선택하지 않은 요일: \(dayList(extra))")
                }
                throw invalid("선택한 요일과 응답의 요일이 일치하지 않습니다 (\(details.joined(separator: ", ")))")
            }
        }

        return goal
    }

    private static func canonicalDay(_ name: String) -> DayOfWeek? {
        DayOfWeek.allCases.first { $0.fullName == name }
    }

    private static func dayList(_ days: Set<DayOfWeek>) -> String {
        days.sorted { $0.rawValue < $1.rawValue }.map(\.fullName).joined(separator: ", ")
    }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func invalid(_ detail: String) -> LLMError {
        .parsingError("플랜 검증 실패: \(detail)")
    }

    // MARK: - Cleaning

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
        let goal: String?
    }
}
