import Foundation
import AuthenticationServices
import CryptoKit
import Network

/// Result of ChatGPT OAuth PKCE flow
struct ChatGPTOAuthResult {
    let code: String
    let redirectURI: String
    let codeVerifier: String
}

@MainActor
final class ChatGPTOAuthHelper: NSObject, ASWebAuthenticationPresentationContextProviding {

    private var authSession: ASWebAuthenticationSession?
    private var presentationAnchorWindow: ASPresentationAnchor?
    private var listener: NWListener?

    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            presentationAnchorWindow ?? ASPresentationAnchor()
        }
    }

    func startOAuthFlow(anchor: ASPresentationAnchor) async throws -> ChatGPTOAuthResult {
        presentationAnchorWindow = anchor

        // 1. Generate PKCE code verifier + challenge
        let codeVerifier = Self.generateCodeVerifier()
        let codeChallenge = Self.generateCodeChallenge(from: codeVerifier)

        // 2. Start local HTTP server on port 1455 (matching Codex CLI's registered redirect_uri)
        let port = try await startLoopbackServer(preferredPort: 1455)
        let redirectURI = "http://localhost:\(port)/auth/callback"
        let callbackScheme = AppConstants.OAuth.googleRedirectScheme

        // 3. Generate state for CSRF protection
        let state = UUID().uuidString

        // 4. Build OpenAI OAuth URL with PKCE (matches Codex CLI parameters)
        var components = URLComponents(string: "https://auth.openai.com/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "openid profile email offline_access"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
        ]

        guard let authURL = components.url else {
            stopLoopbackServer()
            throw AuthError.invalidURL
        }

        // 4. Open ASWebAuthenticationSession
        defer { stopLoopbackServer() }

        let code: String = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error = error {
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        continuation.resume(throwing: AuthError.cancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                guard let callbackURL = callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: AuthError.missingAuthCode)
                    return
                }

                continuation.resume(returning: code)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }

        return ChatGPTOAuthResult(code: code, redirectURI: redirectURI, codeVerifier: codeVerifier)
    }

    // MARK: - PKCE Helpers

    private static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Loopback HTTP Server

    private func startLoopbackServer(preferredPort: UInt16 = 0) async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            do {
                let nwPort: NWEndpoint.Port = preferredPort > 0
                    ? NWEndpoint.Port(rawValue: preferredPort) ?? .any
                    : .any
                let listener = try NWListener(using: .tcp, on: nwPort)
                self.listener = listener

                listener.stateUpdateHandler = { state in
                    guard !hasResumed else { return }
                    switch state {
                    case .ready:
                        if let port = listener.port {
                            hasResumed = true
                            continuation.resume(returning: port.rawValue)
                        }
                    case .failed(let error):
                        hasResumed = true
                        continuation.resume(throwing: AuthError.networkError(error.localizedDescription))
                    default:
                        break
                    }
                }

                listener.newConnectionHandler = { [weak self] connection in
                    self?.handleLoopbackConnection(connection)
                }

                listener.start(queue: .main)
            } catch {
                if !hasResumed {
                    hasResumed = true
                    continuation.resume(throwing: AuthError.networkError(error.localizedDescription))
                }
            }
        }
    }

    private func stopLoopbackServer() {
        listener?.cancel()
        listener = nil
    }

    private nonisolated func handleLoopbackConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
            guard let data = data,
                  let request = String(data: data, encoding: .utf8),
                  let firstLine = request.split(separator: "\r\n").first else {
                connection.cancel()
                return
            }

            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2 else {
                connection.cancel()
                return
            }

            let path = String(parts[1])
            let urlComponents = URLComponents(string: path)
            let code = urlComponents?.queryItems?.first(where: { $0.name == "code" })?.value ?? ""

            // Redirect to app's custom URL scheme so ASWebAuthenticationSession can intercept it
            let scheme = AppConstants.OAuth.googleRedirectScheme
            let redirectTarget = "\(scheme):/oauth2callback?code=\(code)"

            let body = "<html><body><p>Authentication successful. You can close this window.</p></body></html>"
            let response = "HTTP/1.1 302 Found\r\nLocation: \(redirectTarget)\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"

            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}
