import Foundation
import AuthenticationServices

@Observable
@MainActor
final class AuthManager: NSObject {

    static let shared = AuthManager()

    var isAuthenticated: Bool = false
    var currentUser: AuthUser?
    var jwtToken: String?
    var isLoading: Bool = false
    var errorMessage: String?
    var isChatGPTConnected: Bool = false
    var isGoogleConnected: Bool = false

    private let googleOAuthHelper = GoogleOAuthHelper()
    private let chatGPTOAuthHelper = ChatGPTOAuthHelper()

    private override init() {
        super.init()
        isChatGPTConnected = KeychainHelper.shared.read(for: AppConstants.Keychain.chatgptConnected) == "true"
        isGoogleConnected = KeychainHelper.shared.read(for: AppConstants.Keychain.googleConnected) == "true"
    }

    // MARK: - Apple Sign In

    func handleAppleSignIn(result: ASAuthorization) async {
        guard let credential = result.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            errorMessage = "Failed to extract Apple identity token"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await postAppleToken(identityToken: identityToken)
            await handleAuthSuccess(response: response)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Google Sign In

    func startGoogleSignIn(anchor: ASPresentationAnchor) async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await googleOAuthHelper.startOAuthFlow(anchor: anchor)
            let response = try await postGoogleCode(authCode: result.code, redirectURI: result.redirectURI)
            await handleAuthSuccess(response: response)
            _ = KeychainHelper.shared.save("true", for: AppConstants.Keychain.googleConnected)
            isGoogleConnected = true
        } catch {
            if (error as? AuthError) != .cancelled {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }

    // MARK: - Google Connect (for Gemini access)

    func connectGoogle(anchor: ASPresentationAnchor) async throws {
        let result = try await googleOAuthHelper.startOAuthFlow(anchor: anchor)
        let _: GoogleConnectResponse = try await APIClient.shared.post(
            endpoint: "/auth/google/connect",
            body: GoogleAuthRequest(authorizationCode: result.code, redirectURI: result.redirectURI)
        )
        _ = KeychainHelper.shared.save("true", for: AppConstants.Keychain.googleConnected)
        isGoogleConnected = true
    }

    // MARK: - ChatGPT Connect

    func connectChatGPT(anchor: ASPresentationAnchor) async throws {
        let result = try await chatGPTOAuthHelper.startOAuthFlow(anchor: anchor)
        let _: ChatGPTConnectResponse = try await APIClient.shared.post(
            endpoint: "/auth/chatgpt/connect",
            body: ChatGPTAuthRequest(
                authorizationCode: result.code,
                redirectURI: result.redirectURI,
                codeVerifier: result.codeVerifier
            )
        )
        _ = KeychainHelper.shared.save("true", for: AppConstants.Keychain.chatgptConnected)
        isChatGPTConnected = true
    }

    // MARK: - Sign Out

    func signOut() {
        _ = KeychainHelper.shared.delete(for: AppConstants.Keychain.jwtToken)
        _ = KeychainHelper.shared.delete(for: AppConstants.Keychain.refreshToken)
        _ = KeychainHelper.shared.delete(for: AppConstants.Keychain.chatgptConnected)
        _ = KeychainHelper.shared.delete(for: AppConstants.Keychain.googleConnected)
        isChatGPTConnected = false
        isGoogleConnected = false
        jwtToken = nil
        currentUser = nil
        isAuthenticated = false
    }

    // MARK: - Check Existing Auth

    func checkExistingAuth() async {
        guard let storedToken = KeychainHelper.shared.read(for: AppConstants.Keychain.jwtToken) else {
            return
        }

        isLoading = true

        do {
            let user = try await validateToken(storedToken)
            jwtToken = storedToken
            currentUser = user
            isAuthenticated = true
        } catch {
            // Token invalid or expired - clear it
            _ = KeychainHelper.shared.delete(for: AppConstants.Keychain.jwtToken)
        }

        isLoading = false
    }

    // MARK: - Dev Login

    #if DEBUG
    func devLogin() async {
        isLoading = true
        errorMessage = nil

        do {
            let url = URL(string: "\(AppConstants.API.baseURL)/auth/dev-login")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw AuthError.serverError("Dev login failed")
            }

            let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
            await handleAuthSuccess(response: authResponse)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
    #endif

    // MARK: - Private helpers

    private func handleAuthSuccess(response: AuthResponse) async {
        _ = KeychainHelper.shared.save(response.accessToken, for: AppConstants.Keychain.jwtToken)
        _ = KeychainHelper.shared.save(response.refreshToken, for: AppConstants.Keychain.refreshToken)
        jwtToken = response.accessToken
        currentUser = response.user
        isAuthenticated = true
    }

    private func postAppleToken(identityToken: String) async throws -> AuthResponse {
        let url = URL(string: "\(AppConstants.API.baseURL)/auth/apple")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["identity_token": identityToken]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.serverError("Apple sign in failed")
        }

        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }

    private func postGoogleCode(authCode: String, redirectURI: String) async throws -> AuthResponse {
        let url = URL(string: "\(AppConstants.API.baseURL)/auth/google")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = GoogleAuthRequest(authorizationCode: authCode, redirectURI: redirectURI)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.serverError("Google sign in failed")
        }

        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }

    private func validateToken(_ token: String) async throws -> AuthUser {
        let url = URL(string: "\(AppConstants.API.baseURL)/auth/me")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AuthError.invalidToken
        }

        return try JSONDecoder().decode(AuthUser.self, from: data)
    }
}

// MARK: - Response models

private struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
    }
}

// MARK: - AuthError Equatable

extension AuthError: Equatable {
    static func == (lhs: AuthError, rhs: AuthError) -> Bool {
        switch (lhs, rhs) {
        case (.cancelled, .cancelled): return true
        case (.invalidURL, .invalidURL): return true
        case (.missingAuthCode, .missingAuthCode): return true
        case (.invalidToken, .invalidToken): return true
        default: return false
        }
    }
}
