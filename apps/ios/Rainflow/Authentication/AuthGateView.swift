import SwiftUI

struct AuthGateView: View {
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var ledgerStore: LedgerStore

    var body: some View {
        Group {
            switch authStore.phase {
            case .loading:
                launchView
            case .configurationRequired(let message):
                ConfigurationRequiredView(message: message)
            case .signedOut:
                EmailSignInView()
            case .codeSent(let email):
                OTPVerificationView(email: email)
            case .signedIn:
                AuthenticatedRootView()
            }
        }
        .task {
            await authStore.start()
        }
        .onChange(of: authStore.phase) { _, phase in
            if case .signedIn = phase {
                Task { await ledgerStore.refresh() }
            } else if phase == .signedOut {
                ledgerStore.reset()
            }
        }
    }

    private var launchView: some View {
        ZStack {
            RainflowColor.background.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(RainflowColor.brandAccent)
                Text("Rainflow")
                    .font(.largeTitle.weight(.semibold))
                ProgressView()
                    .tint(RainflowColor.brandAccent)
            }
            .foregroundStyle(RainflowColor.textPrimary)
        }
    }
}

private struct EmailSignInView: View {
    @EnvironmentObject private var authStore: AuthStore
    @State private var email = ""

    var body: some View {
        ZStack {
            RainflowColor.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Spacer(minLength: 70)
                    Image(systemName: "drop.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(RainflowColor.brandAccent)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Welcome to Rainflow")
                            .font(.largeTitle.weight(.semibold))
                        Text("Enter your email and we will send a sign-in code.")
                            .foregroundStyle(RainflowColor.textSecondary)
                    }
                    TextField("you@example.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)
                        .padding(16)
                        .background(RainflowColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .submitLabel(.continue)
                        .onSubmit { Task { await authStore.sendCode(to: email) } }

                    if let error = authStore.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(RainflowColor.expense)
                    }

                    Button {
                        Task { await authStore.sendCode(to: email) }
                    } label: {
                        HStack {
                            if authStore.isWorking { ProgressView().tint(.white) }
                            Text(authStore.isWorking ? "Sending…" : "Send code")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(RainflowColor.brand)
                    .disabled(authStore.isWorking)

                    Text("By continuing, you agree to use Rainflow only for your own financial records. Rainflow never asks for a bank password in this MVP.")
                        .font(.caption)
                        .foregroundStyle(RainflowColor.textSecondary)
                    Spacer()
                }
                .padding(24)
            }
        }
    }
}

private struct OTPVerificationView: View {
    @EnvironmentObject private var authStore: AuthStore
    let email: String
    @State private var code = ""

    var body: some View {
        ZStack {
            RainflowColor.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 24) {
                Spacer()
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(RainflowColor.brandAccent)
                Text("Check your email")
                    .font(.largeTitle.weight(.semibold))
                Text("Enter the code sent to \(email).")
                    .foregroundStyle(RainflowColor.textSecondary)

                TextField("00000000", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .padding(16)
                    .background(RainflowColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .onChange(of: code) { _, value in
                        let filtered = String(value.filter(\.isNumber).prefix(8))
                        if filtered != value { code = filtered }
                    }

                if let error = authStore.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(RainflowColor.expense)
                }

                Button {
                    Task { await authStore.verifyCode(code, email: email) }
                } label: {
                    HStack {
                        if authStore.isWorking { ProgressView().tint(.white) }
                        Text(authStore.isWorking ? "Verifying…" : "Verify and sign in")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(RainflowColor.brand)
                .disabled(authStore.isWorking || !(6...8).contains(code.count))

                Button("Use a different email") { authStore.changeEmail() }
                    .foregroundStyle(RainflowColor.brandAccent)
                Spacer()
            }
            .padding(24)
        }
    }
}

private struct ConfigurationRequiredView: View {
    let message: String

    var body: some View {
        ZStack {
            RainflowColor.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(RainflowColor.warning)
                    Text("One-time setup required")
                        .font(.largeTitle.weight(.semibold))
                    Text(message)
                        .foregroundStyle(RainflowColor.textSecondary)
                    FinanceCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("On your Mac")
                                .font(.headline)
                            Text("1. Copy Config/Local.xcconfig.example to Local.xcconfig.")
                            Text("2. Add your public Supabase URL and publishable key.")
                            Text("3. Regenerate the Xcode project and run again.")
                        }
                        .font(.callout)
                    }
                    Text("Do not place a Supabase service-role key in the app.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(RainflowColor.expense)
                }
                .padding(24)
            }
        }
    }
}
