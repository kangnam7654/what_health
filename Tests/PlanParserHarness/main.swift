// Offline regression harness for PlanParser / ChatResponseParser.
//
// Compiled together with the real app sources by run.sh
// (Enums, CodableTypes, LLMServiceProtocol, PlanParser, ChatResponseParser).
// All fixtures below are synthetic — no model/provider/network call is made.

import Foundation

// MARK: - Minimal check helpers

var passed = 0
var failures: [String] = []

func check(_ condition: Bool, _ name: String, _ detail: String = "") {
    if condition {
        passed += 1
        print("PASS  \(name)")
    } else {
        failures.append(name)
        print("FAIL  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    }
}

func expectValid(
    _ name: String,
    _ response: String,
    requiredDays: Set<DayOfWeek>? = nil,
    _ verify: (PlanParser.ParsedPlan) -> Bool = { _ in true }
) {
    do {
        let plan = try PlanParser.parse(response: response, requiredDays: requiredDays)
        check(verify(plan), name, "parsed but post-conditions did not hold")
    } catch {
        check(false, name, "unexpected error: \(error.localizedDescription)")
    }
}

func expectParsingError(_ name: String, _ response: String, requiredDays: Set<DayOfWeek>? = nil) {
    do {
        _ = try PlanParser.parse(response: response, requiredDays: requiredDays)
        check(false, name, "expected LLMError.parsingError but parse succeeded")
    } catch let error as LLMError {
        if case .parsingError(let detail) = error {
            check(!detail.isEmpty, name)
        } else {
            check(false, name, "wrong LLMError case: \(error.localizedDescription)")
        }
    } catch {
        check(false, name, "non-LLMError thrown: \(error)")
    }
}

// MARK: - Synthetic fixtures

func exercise(
    name: String = "스쿼트",
    sets: Int = 3,
    reps: String = "10-12",
    restSeconds: Int = 60
) -> [String: Any] {
    [
        "name": name,
        "exerciseType": "strength",
        "sets": sets,
        "reps": reps,
        "restSeconds": restSeconds,
        "description": "합성 테스트용 설명"
    ]
}

func routine(_ day: String, focus: String = "하체", exercises: [[String: Any]]? = nil) -> [String: Any] {
    [
        "dayOfWeek": day,
        "focus": focus,
        "exercises": exercises ?? [exercise()]
    ]
}

func plan(
    title: String = "합성 3일 플랜",
    summary: String = "오프라인 검증용 합성 플랜입니다.",
    goal: Any? = nil,
    routines: [[String: Any]]
) -> String {
    var object: [String: Any] = [
        "title": title,
        "summary": summary,
        "routines": routines
    ]
    if let goal { object["goal"] = goal }
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(data: data, encoding: .utf8)!
}

let monWedFri: Set<DayOfWeek> = [.monday, .wednesday, .friday]
let validThreeDay = plan(routines: [routine("월요일"), routine("수요일", focus: "상체"), routine("금요일", focus: "전신")])

// MARK: - Standalone generator (PlanParser with requiredDays)

expectValid("valid multi-day standalone plan without goal", validThreeDay, requiredDays: monWedFri) {
    $0.routines.count == 3 && $0.goal == nil && $0.routines.map(\.dayOfWeek) == ["월요일", "수요일", "금요일"]
}
expectValid("valid standalone plan in ```json fence", "```json\n\(validThreeDay)\n```", requiredDays: monWedFri) {
    $0.routines.count == 3
}
expectValid("valid standalone plan in bare ``` fence", "```\n\(validThreeDay)\n```", requiredDays: monWedFri)
expectValid("selected-day order does not matter",
            plan(routines: [routine("금요일"), routine("월요일"), routine("수요일")]),
            requiredDays: monWedFri)
expectValid("restSeconds 0 is allowed",
            plan(routines: [routine("월요일", exercises: [exercise(restSeconds: 0)])]),
            requiredDays: [.monday])
expectValid("recognized goal is kept",
            plan(goal: ExerciseGoal.weightLoss.rawValue, routines: [routine("화요일")])) {
    $0.goal == .weightLoss
}
expectValid("null goal is treated as omitted", plan(goal: NSNull(), routines: [routine("화요일")])) {
    $0.goal == nil
}

expectParsingError("empty routines", plan(routines: []))
expectParsingError("empty routines (with selected days)", plan(routines: []), requiredDays: monWedFri)
expectParsingError("duplicate weekday", plan(routines: [routine("월요일"), routine("월요일")]))
expectParsingError("non-canonical weekday (short name)", plan(routines: [routine("월")]))
expectParsingError("non-canonical weekday (English)", plan(routines: [routine("Monday")]))
expectParsingError("non-canonical weekday (padded)", plan(routines: [routine(" 월요일 ")]))
expectParsingError("missing selected weekday",
                   plan(routines: [routine("월요일"), routine("수요일")]),
                   requiredDays: monWedFri)
expectParsingError("extra unselected weekday",
                   plan(routines: [routine("월요일"), routine("수요일"), routine("금요일"), routine("일요일")]),
                   requiredDays: monWedFri)
expectParsingError("different weekday swapped in",
                   plan(routines: [routine("월요일"), routine("수요일"), routine("토요일")]),
                   requiredDays: monWedFri)
expectParsingError("blank title", plan(title: "  ", routines: [routine("월요일")]))
expectParsingError("blank summary", plan(summary: "\n", routines: [routine("월요일")]))
expectParsingError("blank focus", plan(routines: [routine("월요일", focus: " ")]))
expectParsingError("empty exercises", plan(routines: [routine("월요일", exercises: [])]))
expectParsingError("blank exercise name", plan(routines: [routine("월요일", exercises: [exercise(name: "")])]))
expectParsingError("blank reps", plan(routines: [routine("월요일", exercises: [exercise(reps: " ")])]))
expectParsingError("sets -1", plan(routines: [routine("월요일", exercises: [exercise(sets: -1)])]))
expectParsingError("sets 0", plan(routines: [routine("월요일", exercises: [exercise(sets: 0)])]))
expectParsingError("negative restSeconds", plan(routines: [routine("월요일", exercises: [exercise(restSeconds: -10)])]))
expectParsingError("unrecognized goal", plan(goal: "근력", routines: [routine("월요일")]))
expectParsingError("non-string goal", plan(goal: 1, routines: [routine("월요일")]))
expectParsingError("malformed JSON", "{\"title\": \"x\", ")
expectParsingError("missing required field", "{\"title\": \"x\", \"routines\": []}")

// MARK: - Chat-tagged plans (ChatResponseParser, no selected-day constraint)

func planSegments(_ segments: [ChatContentSegment]) -> [PlanParser.ParsedPlan] {
    segments.compactMap { segment -> PlanParser.ParsedPlan? in
        if case .exercisePlan(let parsed) = segment { return parsed }
        return nil
    }
}

func textSegments(_ segments: [ChatContentSegment]) -> [String] {
    segments.compactMap { segment -> String? in
        if case .text(let text) = segment { return text }
        return nil
    }
}

let chatPlan = plan(
    title: "채팅 합성 플랜",
    goal: ExerciseGoal.strength.rawValue,
    routines: [routine("화요일"), routine("토요일", focus: "상체")]
)

do {
    let response = "설명 문장입니다.\n[EXERCISE_PLAN]\n```json\n\(chatPlan)\n```\n[/EXERCISE_PLAN]\n마무리 문장입니다."
    let segments = ChatResponseParser.parse(response: response)
    let plans = planSegments(segments)
    check(segments.count == 3 && plans.count == 1, "chat: fenced tagged plan becomes one plan card between text")
    check(plans.first?.goal == .strength && plans.first?.routines.count == 2,
          "chat: tagged plan keeps goal and arbitrary distinct days")
}

do {
    let response = "[EXERCISE_PLAN]\(plan(routines: [routine("일요일")]))[/EXERCISE_PLAN]"
    check(planSegments(ChatResponseParser.parse(response: response)).count == 1,
          "chat: unfenced tagged plan without goal becomes plan card")
}

func expectChatText(_ name: String, _ block: String) {
    let response = "앞 문장\n[EXERCISE_PLAN]\n\(block)\n[/EXERCISE_PLAN]"
    let segments = ChatResponseParser.parse(response: response)
    let texts = textSegments(segments)
    check(planSegments(segments).isEmpty && texts.contains(block),
          name, "segments=\(segments.count)")
}

expectChatText("chat: empty routines stays readable text", plan(routines: []))
expectChatText("chat: duplicate days stays readable text", plan(routines: [routine("월요일"), routine("월요일")]))
expectChatText("chat: invalid weekday stays readable text", plan(routines: [routine("월")]))
expectChatText("chat: sets -1 stays readable text",
               plan(routines: [routine("월요일", exercises: [exercise(sets: -1)])]))
expectChatText("chat: unrecognized goal stays readable text", plan(goal: "근육", routines: [routine("월요일")]))
expectChatText("chat: malformed JSON stays readable text", "{ not json")

do {
    let segments = ChatResponseParser.parse(response: "질문 답변\n[EXERCISE_PLAN]\n\(chatPlan)")
    check(planSegments(segments).isEmpty && !textSegments(segments).isEmpty,
          "chat: unclosed tag stays readable text")
}

// MARK: - Summary

print("\n\(passed) passed, \(failures.count) failed")
if !failures.isEmpty {
    for name in failures { print("  - \(name)") }
    exit(1)
}
