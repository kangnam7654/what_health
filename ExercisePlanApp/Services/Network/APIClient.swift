import Foundation

final class APIClient {
    static let shared = APIClient()
    private init() {}

    private var baseURL: String { AppConstants.API.baseURL }

    private var authHeaders: [String: String] {
        get async {
            var headers = ["Content-Type": "application/json"]
            if let token = await AuthManager.shared.jwtToken {
                headers["Authorization"] = "Bearer \(token)"
            }
            return headers
        }
    }

    // MARK: - POST

    func post<T: Decodable>(endpoint: String, body: some Encodable) async throws -> T {
        let url = URL(string: "\(baseURL)\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let headers = await authHeaders
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try JSONEncoder().encode(body)

        return try await perform(request: request)
    }

    // MARK: - GET

    func get<T: Decodable>(endpoint: String) async throws -> T {
        let url = URL(string: "\(baseURL)\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let headers = await authHeaders
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        return try await perform(request: request)
    }

    // MARK: - Private

    private var isRefreshing = false

    private func perform<T: Decodable>(request: URLRequest, retried: Bool = false) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            if !retried, let refreshedRequest = await tryRefreshAndRetry(original: request) {
                return try await perform(request: refreshedRequest, retried: true)
            }
            throw APIError.unauthorized
        case 429:
            let message = extractErrorMessage(from: data) ?? "요청 한도 초과"
            throw APIError.quotaExceeded(message)
        default:
            let message = extractErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw APIError.serverError(httpResponse.statusCode, message)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingError
        }
    }

    private func tryRefreshAndRetry(original: URLRequest) async -> URLRequest? {
        guard !isRefreshing,
              let refreshToken = KeychainHelper.shared.read(for: AppConstants.Keychain.refreshToken) else {
            return nil
        }

        isRefreshing = true
        defer { isRefreshing = false }

        guard let url = URL(string: "\(baseURL)/auth/refresh") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct RefreshBody: Encodable { let refresh_token: String }
        request.httpBody = try? JSONEncoder().encode(RefreshBody(refresh_token: refreshToken))

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        struct RefreshResponse: Decodable {
            let access_token: String
            let refresh_token: String
        }

        guard let refreshResult = try? JSONDecoder().decode(RefreshResponse.self, from: data) else {
            return nil
        }

        _ = KeychainHelper.shared.save(refreshResult.access_token, for: AppConstants.Keychain.jwtToken)
        _ = KeychainHelper.shared.save(refreshResult.refresh_token, for: AppConstants.Keychain.refreshToken)
        await MainActor.run { AuthManager.shared.jwtToken = refreshResult.access_token }

        var retryRequest = original
        retryRequest.setValue("Bearer \(refreshResult.access_token)", forHTTPHeaderField: "Authorization")
        return retryRequest
    }

    private func extractErrorMessage(from data: Data) -> String? {
        struct ErrorBody: Decodable {
            let detail: String?
            let message: String?
        }
        let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
        return body?.detail ?? body?.message
    }
}
