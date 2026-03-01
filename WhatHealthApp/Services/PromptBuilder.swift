import Foundation

enum PromptBuilder {
    static func buildPlanGenerationPrompt(
        goal: ExerciseGoal,
        experience: ExperienceLevel,
        equipment: [Equipment],
        trainingDays: [DayOfWeek],
        sessionDuration: Int,
        additionalNotes: String,
        savedExerciseNames: [String] = []
    ) -> (system: String, user: String) {
        var systemPrompt = """
        당신은 전문 운동 트레이너입니다. 사용자의 정보를 바탕으로 맞춤형 운동 프로그램을 JSON 형식으로 생성해주세요.

        반드시 아래 JSON 형식으로만 응답하세요. 다른 텍스트는 포함하지 마세요.

        {
            "title": "프로그램 제목",
            "summary": "프로그램 요약 설명 (2-3문장)",
            "routines": [
                {
                    "dayOfWeek": "요일명",
                    "focus": "해당 요일 운동 초점",
                    "exercises": [
                        {
                            "name": "운동 이름",
                            "exerciseType": "strength 또는 cardio 또는 stretching",
                            "sets": 3,
                            "reps": "10-12",
                            "restSeconds": 60,
                            "notes": "운동 시 주의사항 (선택)",
                            "description": "운동 수행 방법 1-2문장 (필수)"
                        }
                    ]
                }
            ]
        }

        규칙:
        - 사용자가 선택한 운동 요일에 대해서만 루틴을 생성하세요
        - 사용 가능한 장비만 활용하세요
        - 경험 수준에 맞는 난이도로 설계하세요
        - 각 세션은 지정된 시간 내에 완료할 수 있어야 합니다
        - 워밍업과 쿨다운을 포함하세요
        - reps는 문자열입니다 (예: "10-12", "30초", "실패까지")
        - exerciseType: 근력운동은 "strength", 유산소(러닝/걷기/자전거 등)는 "cardio", 스트레칭/유연성은 "stretching"
        """

        if !savedExerciseNames.isEmpty {
            let names = savedExerciseNames.joined(separator: ", ")
            systemPrompt += "\n- 다음 운동이 포함될 경우 반드시 이 이름을 그대로 사용하세요: \(names)"
        }

        let equipmentList = equipment.map { $0.rawValue }.joined(separator: ", ")
        let daysList = trainingDays.sorted(by: { $0.rawValue < $1.rawValue }).map { $0.fullName }.joined(separator: ", ")

        var userPrompt = """
        다음 조건에 맞는 운동 프로그램을 만들어주세요:

        - 운동 목표: \(goal.rawValue)
        - 운동 경험: \(experience.rawValue)
        - 사용 가능한 장비: \(equipmentList)
        - 운동 요일: \(daysList)
        - 세션 시간: \(sessionDuration)분
        """

        if !additionalNotes.isEmpty {
            userPrompt += "\n- 추가 사항: \(additionalNotes)"
        }

        return (systemPrompt, userPrompt)
    }

    static func buildChatSystemPrompt() -> String {
        """
        당신은 친절하고 전문적인 운동 트레이너 AI 어시스턴트입니다.

        역할:
        - 운동 관련 질문에 답변합니다
        - 운동 자세, 루틴, 영양, 회복 등에 대해 조언합니다
        - 부상 예방과 안전한 운동 방법을 강조합니다
        - 한국어로 응답합니다

        주의사항:
        - 의학적 진단이나 처방은 하지 않습니다
        - 심각한 부상이나 건강 문제는 전문의 상담을 권합니다
        - 과학적 근거에 기반한 정보를 제공합니다
        """
    }

    static func buildChatWithPlanSystemPrompt(savedExerciseNames: [String] = []) -> String {
        let goalList = ExerciseGoal.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")

        var prompt = """
        당신은 친절하고 전문적인 운동 트레이너 AI 어시스턴트입니다.

        역할:
        - 운동 관련 질문에 답변합니다
        - 운동 자세, 루틴, 영양, 회복 등에 대해 조언합니다
        - 부상 예방과 안전한 운동 방법을 강조합니다
        - 사용자가 요청하면 맞춤형 운동 플랜을 생성합니다
        - 한국어로 응답합니다

        운동 플랜 생성 규칙:
        - 사용자가 운동 플랜, 프로그램, 루틴 생성을 요청하면 자연어 설명과 함께 JSON 데이터를 제공합니다
        - JSON은 반드시 [EXERCISE_PLAN] 태그와 [/EXERCISE_PLAN] 태그 사이에 넣어주세요
        - 자연어 설명을 먼저 작성하고, 그 뒤에 태그로 감싼 JSON을 포함합니다
        - JSON 스키마:
        {
            "title": "프로그램 제목",
            "summary": "프로그램 요약 설명 (2-3문장)",
            "goal": "운동 목표",
            "routines": [
                {
                    "dayOfWeek": "요일명",
                    "focus": "해당 요일 운동 초점",
                    "exercises": [
                        {
                            "name": "운동 이름",
                            "exerciseType": "strength 또는 cardio 또는 stretching",
                            "sets": 3,
                            "reps": "10-12",
                            "restSeconds": 60,
                            "notes": "운동 시 주의사항 (선택)",
                            "description": "운동 수행 방법 1-2문장 (필수)"
                        }
                    ]
                }
            ]
        }
        - goal 값은 반드시 다음 중 하나: \(goalList)
        - reps는 문자열입니다 (예: "10-12", "30초", "실패까지")
        - exerciseType: 근력운동은 "strength", 유산소(러닝/걷기/자전거 등)는 "cardio", 스트레칭/유연성은 "stretching"
        - 워밍업과 쿨다운을 포함하세요
        - 일반 대화에서는 [EXERCISE_PLAN] 태그를 절대 사용하지 마세요

        주의사항:
        - 의학적 진단이나 처방은 하지 않습니다
        - 심각한 부상이나 건강 문제는 전문의 상담을 권합니다
        - 과학적 근거에 기반한 정보를 제공합니다
        """

        if !savedExerciseNames.isEmpty {
            let names = savedExerciseNames.joined(separator: ", ")
            prompt += "\n- 다음 운동이 포함될 경우 반드시 이 이름을 그대로 사용하세요: \(names)"
        }

        return prompt
    }
}
