import Foundation
import Combine
import FirebaseAuth
import FirebaseCore

final class AuthViewModel: ObservableObject {
    static let shared = AuthViewModel()

    @Published private(set) var currentUser: User?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var authStateListener: AuthStateDidChangeListenerHandle?
    private var auth: Auth?
    private let authManager: AuthManager

    private init() {
        authManager = .shared
        if FirebaseApp.app() != nil {
            let auth = Auth.auth()
            self.auth = auth
            currentUser = auth.currentUser
        } else {
            currentUser = nil
        }
    }

    deinit {
        if let authStateListener, let auth {
            auth.removeStateDidChangeListener(authStateListener)
        }
    }

    var isLoggedIn: Bool {
        currentUser != nil
    }

    var isAuthenticated: Bool {
        isLoggedIn
    }

    var isSignedIn: Bool {
        isLoggedIn
    }

    var user: User? {
        currentUser
    }

    var currentUserEmail: String {
        currentUser?.email ?? ""
    }

    func startListeningIfNeeded() {
        guard authStateListener == nil else { return }
        guard FirebaseApp.app() != nil else { return }
        guard let auth = try? currentAuth() else { return }
        currentUser = auth.currentUser
        listen(using: auth)
    }

    private func listen(using auth: Auth) {
        authStateListener = auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.currentUser = user
            }
        }
    }

    @MainActor
    func signInWithGoogle() async throws {
        try await performAuthFlow {
            _ = try await authManager.signInWithGoogle()
        }
    }

    @MainActor
    func signInWithGitHub() async throws {
        try await performAuthFlow {
            _ = try await authManager.signInWithGitHub()
        }
    }

    @MainActor
    func signUpWithEmail(email: String, password: String) async throws {
        try await signInWithEmail(email: email, password: password)
    }

    @MainActor
    func signInWithEmail(email: String, password: String) async throws {
        try await performAuthFlow {
            let sanitizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sanitizedEmail.isEmpty else {
                throw AuthViewModelError.invalidEmail
            }
            guard !password.isEmpty else {
                throw AuthViewModelError.invalidPassword
            }
            do {
                _ = try await signIn(email: sanitizedEmail, password: password)
            } catch {
                let nsError = error as NSError
                let authCode = AuthErrorCode(rawValue: nsError.code)

                if authCode == .userNotFound {
                    print("[Auth] Email sign-in user not found, creating account for \(sanitizedEmail)")
                    _ = try await createUser(email: sanitizedEmail, password: password)
                    return
                }

                throw mapEmailAuthError(error)
            }
        }
    }

    @MainActor
    func getValidIDToken() async throws -> String {
        startListeningIfNeeded()
        let auth = try currentAuth()
        guard let user = auth.currentUser else {
            throw AuthViewModelError.notAuthenticated
        }

        do {
            let tokenResult = try await getIDTokenResult(for: user, forceRefresh: false)
            let expirationDate = tokenResult.expirationDate
            if expirationDate.timeIntervalSinceNow > 60 {
                return tokenResult.token
            }

            return try await getIDToken(for: user, forceRefresh: true)
        } catch {
            let nsError = error as NSError
            if nsError.domain == AuthErrorDomain,
               nsError.code == AuthErrorCode.userTokenExpired.rawValue {
                return try await getIDToken(for: user, forceRefresh: true)
            }
            throw error
        }
    }

    func signOut() {
        authManager.signOut()
        currentUser = authManager.currentUser()
        errorMessage = nil
    }

    @MainActor
    func clearError() {
        errorMessage = nil
    }

    @MainActor
    private func performAuthFlow(_ operation: () async throws -> Void) async throws {
        startListeningIfNeeded()
        let auth = try currentAuth()

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await operation()
            currentUser = auth.currentUser
            errorMessage = nil
        } catch {
            errorMessage = (error as NSError).localizedDescription
            throw error
        }
    }

    private func createUser(email: String, password: String) async throws -> AuthDataResult {
        let auth = try currentAuth()
        return try await withCheckedThrowingContinuation { continuation in
            auth.createUser(withEmail: email, password: password) { result, error in
                if let error {
                    let nsError = error as NSError
                    print("[Auth] Email registration error: \(nsError.localizedDescription) [\(nsError.domain):\(nsError.code)]")
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else {
                    continuation.resume(throwing: AuthViewModelError.missingResult)
                    return
                }
                continuation.resume(returning: result)
            }
        }
    }

    private func mapEmailAuthError(_ error: Error) -> Error {
        let nsError = error as NSError
        guard nsError.domain == AuthErrorDomain,
              let code = AuthErrorCode(rawValue: nsError.code) else {
            return error
        }

        switch code {
        case .wrongPassword, .invalidCredential:
            return AuthViewModelError.incorrectPassword
        case .weakPassword:
            return AuthViewModelError.weakPassword
        case .invalidEmail:
            return AuthViewModelError.invalidEmailAddress
        default:
            return error
        }
    }

    private func signIn(email: String, password: String) async throws -> AuthDataResult {
        let auth = try currentAuth()
        return try await withCheckedThrowingContinuation { continuation in
            auth.signIn(withEmail: email, password: password) { result, error in
                if let error {
                    let nsError = error as NSError
                    print("[Auth] Email sign-in error: \(nsError.localizedDescription) [\(nsError.domain):\(nsError.code)]")
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else {
                    continuation.resume(throwing: AuthViewModelError.missingResult)
                    return
                }
                continuation.resume(returning: result)
            }
        }
    }

    private func currentAuth() throws -> Auth {
        guard FirebaseApp.app() != nil else {
            throw AuthViewModelError.firebaseNotConfigured
        }
        if let auth {
            return auth
        }
        let initializedAuth = Auth.auth()
        auth = initializedAuth
        return initializedAuth
    }

    private func getIDToken(for user: User, forceRefresh: Bool) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            user.getIDTokenForcingRefresh(forceRefresh) { token, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let token, !token.isEmpty else {
                    continuation.resume(throwing: AuthViewModelError.missingToken)
                    return
                }
                continuation.resume(returning: token)
            }
        }
    }

    private func getIDTokenResult(for user: User, forceRefresh: Bool) async throws -> AuthTokenResult {
        try await withCheckedThrowingContinuation { continuation in
            user.getIDTokenResult(forcingRefresh: forceRefresh) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else {
                    continuation.resume(throwing: AuthViewModelError.missingToken)
                    return
                }
                continuation.resume(returning: result)
            }
        }
    }

    enum AuthViewModelError: LocalizedError {
        case firebaseNotConfigured
        case missingResult
        case invalidEmail
        case invalidPassword
        case incorrectPassword
        case weakPassword
        case invalidEmailAddress
        case notAuthenticated
        case missingToken

        var errorDescription: String? {
            switch self {
            case .firebaseNotConfigured:
                return LocalizationManager.shared.text("auth.error.firebase_not_configured")
            case .missingResult:
                return LocalizationManager.shared.text("auth.error.sign_in_failed")
            case .invalidEmail:
                return LocalizationManager.shared.text("auth.error.invalid_email")
            case .invalidPassword:
                return LocalizationManager.shared.text("auth.error.invalid_password")
            case .incorrectPassword:
                return LocalizationManager.shared.text("auth.error.incorrect_password")
            case .weakPassword:
                return LocalizationManager.shared.text("auth.error.weak_password")
            case .invalidEmailAddress:
                return LocalizationManager.shared.text("auth.error.invalid_email_address")
            case .notAuthenticated:
                return LocalizationManager.shared.text("auth.error.authentication_required")
            case .missingToken:
                return LocalizationManager.shared.text("auth.error.missing_firebase_id_token")
            }
        }
    }
}
