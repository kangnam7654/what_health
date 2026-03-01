import Foundation
import SwiftData

@Model
final class SavedExerciseVideo {
    @Attribute(.unique) var exerciseName: String
    var videoURL: String
    var savedAt: Date

    init(exerciseName: String, videoURL: String, savedAt: Date = .now) {
        self.exerciseName = exerciseName
        self.videoURL = videoURL
        self.savedAt = savedAt
    }
}
