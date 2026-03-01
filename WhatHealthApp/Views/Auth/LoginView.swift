import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @State private var authManager = AuthManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // App logo and title
            VStack(spacing: 16) {
                Image("AppIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 22))

                Text("WhatHealth")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("AI가 만들어주는 맞춤형 운동 플랜")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Sign in buttons
            VStack(spacing: 16) {
                // Sign in with Apple
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        Task {
                            await authManager.handleAppleSignIn(result: authorization)
                        }
                    case .failure(let error):
                        if (error as? ASAuthorizationError)?.code != .canceled {
                            authManager.errorMessage = error.localizedDescription
                        }
                    }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .cornerRadius(10)

                // Google Sign In
                GoogleSignInButton {
                    Task {
                        guard let windowScene = UIApplication.shared.connectedScenes
                            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
                              let window = windowScene.windows.first else { return }
                        await authManager.startGoogleSignIn(anchor: window)
                    }
                }
                .frame(height: 50)
            }
            .padding(.horizontal, 32)
            .disabled(authManager.isLoading)

            // Dev login (DEBUG only)
            #if DEBUG
            Button {
                Task { await authManager.devLogin() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.orange)

                    Text("개발자 로그인 (테스트)")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.5), lineWidth: 1)
                )
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
            .disabled(authManager.isLoading)
            #endif

            // Error message
            if let errorMessage = authManager.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Loading indicator
            if authManager.isLoading {
                ProgressView()
                    .padding(.top, 8)
            }

            Spacer()

            Text("계속하면 이용약관 및 개인정보처리방침에 동의하는 것으로 간주됩니다.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
        }
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.15), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        )
    }
}

// MARK: - Google Sign In Button

private struct GoogleSignInButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)

                Text("Google로 계속하기")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}
