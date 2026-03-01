import Foundation

enum YouTubeURLValidator {
    /// YouTube 검색 URL 생성
    static func searchURL(for exerciseName: String) -> URL? {
        var components = URLComponents(string: "https://www.youtube.com/results")
        components?.queryItems = [URLQueryItem(name: "search_query", value: "\(exerciseName) 운동 자세")]
        return components?.url
    }

    /// YouTube URL 유효성 검사
    /// youtube.com/watch, youtu.be, youtube.com/shorts, youtube.com/embed 지원
    static func isValid(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased() else { return false }

        let validHosts = ["youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"]
        guard validHosts.contains(host) else { return false }

        if host == "youtu.be" {
            return url.pathComponents.count >= 2 // youtu.be/{videoId}
        }

        let path = url.path.lowercased()
        if path.hasPrefix("/watch") { return true }
        if path.hasPrefix("/shorts/") { return true }
        if path.hasPrefix("/embed/") { return true }
        if path.hasPrefix("/live/") { return true }

        return false
    }
}
