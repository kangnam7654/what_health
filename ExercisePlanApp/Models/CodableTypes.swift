import Foundation

struct DayRoutine: Codable, Identifiable {
    var id: UUID = UUID()
    let dayOfWeek: String
    let focus: String
    let exercises: [ExerciseItem]

    enum CodingKeys: String, CodingKey {
        case dayOfWeek, focus, exercises
    }

    init(dayOfWeek: String, focus: String, exercises: [ExerciseItem]) {
        self.id = UUID()
        self.dayOfWeek = dayOfWeek
        self.focus = focus
        self.exercises = exercises
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.dayOfWeek = try container.decode(String.self, forKey: .dayOfWeek)
        self.focus = try container.decode(String.self, forKey: .focus)
        self.exercises = try container.decode([ExerciseItem].self, forKey: .exercises)
    }
}

struct ExerciseItem: Codable, Identifiable {
    var id: UUID = UUID()
    let name: String
    let sets: Int
    let reps: String
    let restSeconds: Int
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case name, sets, reps, restSeconds, notes
    }

    init(name: String, sets: Int, reps: String, restSeconds: Int, notes: String? = nil) {
        self.id = UUID()
        self.name = name
        self.sets = sets
        self.reps = reps
        self.restSeconds = restSeconds
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.sets = try container.decode(Int.self, forKey: .sets)
        self.reps = try container.decode(String.self, forKey: .reps)
        self.restSeconds = try container.decode(Int.self, forKey: .restSeconds)
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
}

struct CompletedExercise: Codable, Identifiable {
    let id: UUID
    let exerciseName: String
    var sets: [SetRecord]
    var isCompleted: Bool

    init(exerciseName: String, sets: [SetRecord] = [], isCompleted: Bool = false) {
        self.id = UUID()
        self.exerciseName = exerciseName
        self.sets = sets
        self.isCompleted = isCompleted
    }
}

struct SetRecord: Codable, Identifiable {
    let id: UUID
    var weight: Double
    var reps: Int
    var isCompleted: Bool

    init(weight: Double = 0, reps: Int = 0, isCompleted: Bool = false) {
        self.id = UUID()
        self.weight = weight
        self.reps = reps
        self.isCompleted = isCompleted
    }
}
