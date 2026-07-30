import SwiftUI
import RainflowDomain

struct AccountsView: View {
    @EnvironmentObject private var ledgerStore: LedgerStore

    private var currencyCode: String { ledgerStore.snapshot?.ledger.currencyCode ?? "USD" }
    private var groups: [String: [AccountSummary]] {
        Dictionary(grouping: ledgerStore.accountSummaries, by: \.group)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ScreenHeader(title: "Accounts", trailingSymbol: "arrow.clockwise", trailingAccessibilityLabel: "Refresh") {
                        Task { await ledgerStore.refresh() }
                    }
                    totalCard

                    if ledgerStore.accountSummaries.isEmpty {
                        FinanceCard {
                            EmptyStateView(
                                symbol: "building.columns",
                                title: "No accounts",
                                message: "The default account template will appear after your ledger is created."
                            )
                        }
                        .padding(.horizontal, 16)
                    } else {
                        ForEach(["Assets", "Liabilities"], id: \.self) { group in
                            if let accounts = groups[group], !accounts.isEmpty {
                                accountGroup(group, accounts: accounts)
                            }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .refreshable { await ledgerStore.refresh() }
            .background(RainflowColor.background)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var totalCard: some View {
        let assets = groups["Assets", default: []].reduce(Int64.zero) { $0 + $1.balanceMinorUnits }
        let liabilities = groups["Liabilities", default: []].reduce(Int64.zero) { $0 + $1.balanceMinorUnits }
        return FinanceCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Net Worth")
                    .font(.headline)
                Text((assets + liabilities).formattedCurrency(code: currencyCode))
                    .font(.largeTitle.weight(.semibold))
                    .monospacedDigit()
                HStack {
                    Label(assets.formattedCurrency(code: currencyCode), systemImage: "arrow.up.right")
                        .foregroundStyle(RainflowColor.income)
                    Spacer()
                    Label(liabilities.formattedCurrency(code: currencyCode), systemImage: "arrow.down.right")
                        .foregroundStyle(RainflowColor.expense)
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
    }

    private func accountGroup(_ name: String, accounts: [AccountSummary]) -> some View {
        FinanceCard {
            VStack(spacing: 0) {
                HStack {
                    Text(name)
                        .font(.headline)
                    Spacer()
                    Text(accounts.reduce(Int64.zero) { $0 + $1.balanceMinorUnits }.formattedCurrency(code: currencyCode))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                .padding(.bottom, 8)

                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                    NavigationLink {
                        AccountDetailView(account: account)
                            .environmentObject(ledgerStore)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: account.symbol)
                                .foregroundStyle(RainflowColor.brandAccent)
                                .frame(width: 40, height: 40)
                                .background(RainflowColor.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(account.name)
                                    .fontWeight(.medium)
                                Text(account.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(RainflowColor.textSecondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(account.balanceMinorUnits.formattedCurrency(code: currencyCode))
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(RainflowColor.textSecondary)
                            }
                        }
                        .foregroundStyle(RainflowColor.textPrimary)
                        .padding(.vertical, 11)
                    }
                    .buttonStyle(.plain)
                    if index < accounts.count - 1 {
                        Divider().overlay(RainflowColor.border)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

private struct AccountDetailView: View {
    @EnvironmentObject private var ledgerStore: LedgerStore
    let account: AccountSummary
    @State private var selectedTransaction: TransactionRecord?

    private var currencyCode: String { ledgerStore.snapshot?.ledger.currencyCode ?? "USD" }
    private var transactionIDs: Set<UUID> {
        let records = ledgerStore.snapshot?.activeTransactions ?? []
        return Set(records.compactMap { transaction in
            transaction.postings.contains { $0.accountID == account.id } ? transaction.id : nil
        })
    }
    private var transactions: [TransactionSummary] {
        ledgerStore.transactions.filter { transactionIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                FinanceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: account.symbol)
                            .font(.title2)
                            .foregroundStyle(RainflowColor.brandAccent)
                            .frame(width: 48, height: 48)
                            .background(RainflowColor.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        Text(account.name)
                            .font(.largeTitle.weight(.semibold))
                            .minimumScaleFactor(0.7)
                        Text(account.subtitle)
                            .foregroundStyle(RainflowColor.textSecondary)
                        Text(account.balanceMinorUnits.formattedCurrency(code: currencyCode))
                            .font(.title.weight(.semibold))
                            .monospacedDigit()
                    }
                }

                transactionList
            }
            .padding(16)
        }
        .background(RainflowColor.background)
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedTransaction) { transaction in
            TransactionEditorView(transaction: transaction)
                .environmentObject(ledgerStore)
        }
    }

    private var transactionList: some View {
        FinanceCard {
            VStack(spacing: 0) {
                HStack {
                    Text("Account Transactions")
                        .font(.headline)
                    Spacer()
                    Text("\(transactions.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RainflowColor.textSecondary)
                }
                .padding(.bottom, 8)

                if transactions.isEmpty {
                    EmptyStateView(
                        symbol: "tray",
                        title: "No transactions",
                        message: "Transactions involving this account will appear here."
                    )
                } else {
                    ForEach(Array(transactions.enumerated()), id: \.element.id) { index, transaction in
                        TransactionRow(transaction: transaction, currencyCode: currencyCode)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedTransaction = fullTransaction(for: transaction.id)
                            }
                            .accessibilityAddTraits(.isButton)
                        if index < transactions.count - 1 {
                            Divider().overlay(RainflowColor.border)
                        }
                    }
                }
            }
        }
    }

    private func fullTransaction(for id: UUID) -> TransactionRecord? {
        ledgerStore.snapshot?.activeTransactions.first { $0.id == id }
    }
}
