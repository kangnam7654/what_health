import Foundation
import AuthenticationServices
import Network

/// Result of Google OAuth flow: auth code + the redirect URI used (needed for token exchange)
struct GoogleOAuthResult {
    let code: String
    let redirectURI: String
}

@MainActor
final class GoogleOAuthHelper: NSObject, ASWebAuthenticationPresentationContextProviding {

    private var authSession: ASWebAuthenticationSession?
    private var presentationAnchorWindow: ASPresentationAnchor?
    private var listener: NWListener?

    // Gemini CLI OAuth credentials (public installed-app client, safe to embed per Google's policy)
    private static let geminiClientID = "681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com"

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            presentationAnchorWindow ?? ASPresentationAnchor()
        }
    }

    func startOAuthFlow(anchor: ASPresentationAnchor) async throws -> GoogleOAuthResult {
        presentationAnchorWindow = anchor

        // 1. Start local HTTP server for loopback redirect (Gemini CLI Desktop client requires localhost)
        let port = try await startLoopbackServer()
        let redirectURI = "http://127.0.0.1:\(port)"
        let callbackScheme = AppConstants.OAuth.googleRedirectScheme

        // 2. Build Google OAuth URL with Gemini CLI's client ID
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.geminiClientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile https://www.googleapis.com/auth/cloud-platform"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]

        guard let authURL = components.url else {
            stopLoopbackServer()
            throw AuthError.invalidURL
        }

        // 3. Open ASWebAuthenticationSession
        // Flow: Google → http://127.0.0.1:{port}?code=X → local server → 302 → {appScheme}:/oauth2callback?code=X → ASWebAuthenticationSession intercepts
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

        return GoogleOAuthResult(code: code, redirectURI: redirectURI)
    }

    // MARK: - Loopback HTTP Server

    private func startLoopbackServer() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            do {
                let listener = try NWListener(using: .tcp, on: .any)
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

    private func handleLoopbackConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
            guard let data = data,
                  let request = String(data: data, encoding: .utf8),
                  let firstLine = request.split(separator: "\r\n").first else {
                connection.cancel()
                return
            }

            // Parse "GET /?code=XXX&scope=... HTTP/1.1"
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

enum AuthError: LocalizedError {
    case invalidURL
    case cancelled
    case missingAuthCode
    case invalidToken
    case networkError(String)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid OAuth URL"
        case .cancelled: return "Sign in was cancelled"
        case .missingAuthCode: return "Authorization code not received"
        case .invalidToken: return "Invalid authentication token"
        case .networkError(let msg): return "Network error: \(msg)"
        case .serverError(let msg): return "Server error: \(msg)"
        }
    }
}
