import Combine
import Foundation
import Supabase

@MainActor
final class AuthStore: ObservableObject {
    enum Phase: Equatable {
        case loading
        case configurationRequired(String)
        case signedOut
        case codeSent(email: String)
        case signedIn(email: String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private let client: SupabaseClient?
    private let configurationMessage: String?
    private var listenerTask: Task<Void, Never>?
    private var didStart = false

    init(client: SupabaseClient?, configurationMessage: String?) {
        self.client = client
        self.configurationMessage = configurationMessage
    }

    func start() async {
        guard !didStart else { return }
        didStart = true

        guard let client else {
            phase = .configurationRequired(configurationMessage ?? "Supabase is not configured.")
            return
        }

        listenerTask = Task { [weak self, client] in
            for await (_, session) in await client.auth.authStateChanges {
                guard !Task.isCancelled else { break }
                guard let self else { return }
                if let session {
                    self.phase = .signedIn(email: session.user.email ?? "Signed in")
                } else if case .codeSent = self.phase {
                    // Keep the verification screen while waiting for the code.
                } else {
                    self.phase = .signedOut
                }
            }
        }

        do {
            let session = try await client.auth.session
            phase = .signedIn(email: session.user.email ?? "Signed in")
        } catch {
            phase = .signedOut
        }
    }

    func sendCode(to email: String) async {
        guard let client else { return }
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains("@"), normalized.contains(".") else {
            errorMessage = "Enter a valid email address."
            return
        }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            try await client.auth.signInWithOTP(email: normalized)
            phase = .codeSent(email: normalized)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func verifyCode(_ code: String, email: String) async {
        guard let client else { return }
        let normalizedCode = code.filter(\.isNumber)
        guard (6...8).contains(normalizedCode.count) else {
            errorMessage = "Enter the verification code from your email."
            return
        }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let response = try await client.auth.verifyOTP(
                email: email,
                token: normalizedCode,
                type: .email
            )
            guard let session = response.session else {
                errorMessage = "Verification succeeded, but no session was returned. Request a new code and try again."
                return
            }
            phase = .signedIn(email: session.user.email ?? email)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func changeEmail() {
        errorMessage = nil
        phase = .signedOut
    }

    func signOut() async {
        guard let client else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            try await client.auth.signOut()
            phase = .signedOut
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
