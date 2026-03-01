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
    var exerciseType: String?
    let sets: Int
    let reps: String
    let restSeconds: Int
    var notes: String?
    var description: String?

    enum CodingKeys: String, CodingKey {
        case name, exerciseType, sets, reps, restSeconds, notes, description
    }

    init(name: String, exerciseType: String? = nil, sets: Int, reps: String, restSeconds: Int, notes: String? = nil, description: String? = nil) {
        self.id = UUID()
        self.name = name
        self.exerciseType = exerciseType
        self.sets = sets
        self.reps = reps
        self.restSeconds = restSeconds
        self.notes = notes
        self.description = description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.exerciseType = try container.decodeIfPresent(String.self, forKey: .exerciseType)
        self.sets = try container.decode(Int.self, forKey: .sets)
        self.reps = try container.decode(String.self, forKey: .reps)
        self.restSeconds = try container.decode(Int.self, forKey: .restSeconds)
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
    }
}

struct CompletedExercise: Codable, Identifiable {
    let id: UUID
    let exerciseName: String
    var exerciseType: String?
    var sets: [SetRecord]
    var isCompleted: Bool

    init(exerciseName: String, exerciseType: String? = nil, sets: [SetRecord] = [], isCompleted: Bool = false) {
        self.id = UUID()
        self.exerciseName = exerciseName
        self.exerciseType = exerciseType
        self.sets = sets
        self.isCompleted = isCompleted
    }
}

struct SetRecord: Codable, Identifiable {
    let id: UUID
    var weight: Double
    var reps: Int
    var duration: Double
    var speed: Double
    var incline: Double
    var isCompleted: Bool

    enum CodingKeys: String, CodingKey {
        case id, weight, reps, duration, speed, incline, isCompleted
    }

    init(weight: Double = 0, reps: Int = 0, duration: Double = 0, speed: Double = 0, incline: Double = 0, isCompleted: Bool = false) {
        self.id = UUID()
        self.weight = weight
        self.reps = reps
        self.duration = duration
        self.speed = speed
        self.incline = incline
        self.isCompleted = isCompleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.weight = try container.decodeIfPresent(Double.self, forKey: .weight) ?? 0
        self.reps = try container.decodeIfPresent(Int.self, forKey: .reps) ?? 0
        self.duration = try container.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        self.speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? 0
        self.incline = try container.decodeIfPresent(Double.self, forKey: .incline) ?? 0
        self.isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
    }
}
