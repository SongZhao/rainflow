import SwiftUI

struct TransactionsView: View {
    @EnvironmentObject private var ledgerStore: LedgerStore
    @State private var searchText = ""
    @State private var filter: TransactionFilter = .all
    @State private var selectedTransaction: TransactionRecord?
    @State private var deleteCandidate: TransactionRecord?
    @State private var actionError: String?

    private var currencyCode: String { ledgerStore.snapshot?.ledger.currencyCode ?? "USD" }

    private var filteredTransactions: [TransactionSummary] {
        ledgerStore.transactions.filter { transaction in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .expenses: matchesFilter = transaction.kind == .expense
            case .income: matchesFilter = transaction.kind == .income
            case .transfers: matchesFilter = transaction.kind == .transfer
            }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || transaction.payee.localizedCaseInsensitiveContains(query)
                || transaction.category.localizedCaseInsensitiveContains(query)
            return matchesFilter && matchesSearch
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeader(title: "Transactions", trailingSymbol: "arrow.clockwise", trailingAccessibilityLabel: "Refresh") {
                    Task { await ledgerStore.refresh() }
                }
                searchAndFilters

                if filteredTransactions.isEmpty {
                    Spacer()
                    EmptyStateView(
                        symbol: searchText.isEmpty ? "creditcard" : "magnifyingglass",
                        title: searchText.isEmpty ? "No transactions yet" : "No matches",
                        message: searchText.isEmpty
                            ? "Capture a receipt or add a transaction manually."
                            : "Try another payee, category, or filter."
                    )
                    .padding(28)
                    Spacer()
                } else {
                    List {
                        ForEach(groupedDates, id: \.date) { section in
                            Section(section.date.formatted(date: .abbreviated, time: .omitted)) {
                                ForEach(section.transactions) { transaction in
                                    transactionRow(transaction)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .refreshable { await ledgerStore.refresh() }
                }
            }
            .background(RainflowColor.background)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selectedTransaction) { transaction in
                TransactionEditorView(transaction: transaction)
                    .environmentObject(ledgerStore)
            }
            .confirmationDialog(
                "Remove this transaction?",
                isPresented: Binding(
                    get: { deleteCandidate != nil },
                    set: { if !$0 { deleteCandidate = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Remove Transaction", role: .destructive) {
                    guard let transaction = deleteCandidate else { return }
                    Task {
                        await remove(transaction)
                    }
                }
                Button("Cancel", role: .cancel) {
                    deleteCandidate = nil
                }
            } message: {
                Text("Rainflow will soft-delete the complete transaction. Its postings stop affecting balances.")
            }
            .alert("Rainflow", isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("OK", role: .cancel) { actionError = nil }
            } message: {
                Text(actionError ?? "")
            }
        }
    }

    private var searchAndFilters: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(RainflowColor.textSecondary)
                TextField("Search transactions", text: $searchText)
                    .textInputAutocapitalization(.never)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(RainflowColor.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(RainflowColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14).stroke(RainflowColor.border)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(TransactionFilter.allCases) { option in
                        Button(option.rawValue) { filter = option }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(filter == option ? RainflowColor.brand : RainflowColor.surface)
                            .foregroundStyle(filter == option ? Color.white : RainflowColor.textSecondary)
                            .clipShape(Capsule())
                            .overlay {
                                if filter != option {
                                    Capsule().stroke(RainflowColor.border)
                                }
                            }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var groupedDates: [TransactionDaySection] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredTransactions) {
            calendar.startOfDay(for: $0.date)
        }
        return groups
            .map { TransactionDaySection(date: $0.key, transactions: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.date > $1.date }
    }

    private func fullTransaction(for id: UUID) -> TransactionRecord? {
        ledgerStore.snapshot?.activeTransactions.first { $0.id == id }
    }

    @ViewBuilder
    private func transactionRow(_ transaction: TransactionSummary) -> some View {
        let record = fullTransaction(for: transaction.id)
        TransactionRow(transaction: transaction, currencyCode: currencyCode)
            .onTapGesture {
                selectedTransaction = record
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if let record {
                    Button("Remove", role: .destructive) {
                        deleteCandidate = record
                    }
                    Button("Edit") {
                        selectedTransaction = record
                    }
                    .tint(RainflowColor.brand)
                }
            }
            .listRowBackground(RainflowColor.surface)
            .listRowSeparatorTint(RainflowColor.border)
    }

    @MainActor
    private func remove(_ transaction: TransactionRecord) async {
        actionError = nil
        do {
            try await ledgerStore.deleteTransaction(transaction)
            deleteCandidate = nil
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private struct TransactionDaySection: Identifiable {
    var id: Date { date }
    let date: Date
    let transactions: [TransactionSummary]
}

private enum TransactionFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case expenses = "Expenses"
    case income = "Income"
    case transfers = "Transfers"
    var id: String { rawValue }
}
