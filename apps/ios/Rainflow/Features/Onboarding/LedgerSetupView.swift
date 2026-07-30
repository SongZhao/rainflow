import RainflowDomain
import SwiftUI

struct AuthenticatedRootView: View {
    @EnvironmentObject private var ledgerStore: LedgerStore

    var body: some View {
        Group {
            switch ledgerStore.phase {
            case .idle, .loading:
                loadingView
            case .needsLedger:
                LedgerSetupView()
            case .ready:
                AppRootView()
            case .failed(let message):
                failureView(message: message)
            }
        }
        .task {
            if ledgerStore.phase == .idle {
                await ledgerStore.refresh()
            }
        }
    }

    private var loadingView: some View {
        ZStack {
            RainflowColor.background.ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .tint(RainflowColor.brandAccent)
                Text("Loading your ledger…")
                    .foregroundStyle(RainflowColor.textSecondary)
            }
        }
    }

    private func failureView(message: String) -> some View {
        ZStack {
            RainflowColor.background.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 44))
                    .foregroundStyle(RainflowColor.warning)
                Text("Rainflow could not load")
                    .font(.title2.weight(.semibold))
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(RainflowColor.textSecondary)
                Button("Try Again") {
                    Task { await ledgerStore.refresh() }
                }
                .buttonStyle(.borderedProminent)
                .tint(RainflowColor.brand)
            }
            .padding(24)
        }
    }
}

struct LedgerSetupView: View {
    @EnvironmentObject private var ledgerStore: LedgerStore
    @State private var ledgerName = "Personal"
    @State private var currency: CurrencyCode = .usd

    var body: some View {
        NavigationStack {
            ZStack {
                RainflowColor.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Spacer(minLength: 32)
                        Image(systemName: "drop.fill")
                            .font(.system(size: 54))
                            .foregroundStyle(RainflowColor.brandAccent)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Create your ledger")
                                .font(.largeTitle.weight(.semibold))
                            Text("Rainflow will create the recommended accounts and categories. You can rename or remove empty accounts later with two confirmations.")
                                .foregroundStyle(RainflowColor.textSecondary)
                        }

                        FinanceCard {
                            VStack(spacing: 16) {
                                TextField("Ledger name", text: $ledgerName)
                                    .textContentType(.name)
                                Divider().overlay(RainflowColor.border)
                                Picker("Currency", selection: $currency) {
                                    ForEach(CurrencyCode.allCases) { option in
                                        Text(option.displayName).tag(option)
                                    }
                                }
                            }
                        }

                        if let error = ledgerStore.errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(RainflowColor.expense)
                        }

                        Button {
                            Task {
                                await ledgerStore.createLedger(name: ledgerName, currency: currency)
                            }
                        } label: {
                            HStack {
                                if ledgerStore.isWorking { ProgressView().tint(.white) }
                                Text(ledgerStore.isWorking ? "Creating…" : "Create Ledger")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(RainflowColor.brand)
                        .disabled(ledgerStore.isWorking || ledgerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Text("The selected currency becomes fixed after the first transaction. Multiple ledgers can be exposed later without changing the schema.")
                            .font(.caption)
                            .foregroundStyle(RainflowColor.textSecondary)
                    }
                    .padding(24)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private extension CurrencyCode {
    var displayName: String {
        switch self {
        case .usd: "USD — US Dollar"
        case .cad: "CAD — Canadian Dollar"
        case .eur: "EUR — Euro"
        case .gbp: "GBP — British Pound"
        case .jpy: "JPY — Japanese Yen"
        case .aud: "AUD — Australian Dollar"
        }
    }
}
