import Foundation
import RainflowDomain

struct AccountSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let subtitle: String
    let symbol: String
    let balanceMinorUnits: Int64
    let group: String
    let type: AccountType
}

struct TransactionSummary: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case income
        case expense
        case transfer
    }

    let id: UUID
    let date: Date
    let payee: String
    let category: String
    let amountMinorUnits: Int64
    let kind: Kind
    let symbol: String
    let revision: Int
    let hasReceipt: Bool
}

struct CashFlowPoint: Identifiable, Hashable, Sendable {
    var id: String { label }
    let label: String
    let income: Double
    let expense: Double
    let net: Double
}

struct SpendingSlice: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let amountMinorUnits: Int64
}

struct CashFlowSummary: Equatable, Sendable {
    let incomeMinorUnits: Int64
    let expenseMinorUnits: Int64

    var netMinorUnits: Int64 { incomeMinorUnits - expenseMinorUnits }
}

extension LedgerSnapshot {
    var activeTransactions: [TransactionRecord] {
        transactions.filter { $0.deletedAt == nil }
    }

    var activeAccounts: [AccountRecord] {
        accounts.filter { $0.archivedAt == nil }
    }

    var accountSummaries: [AccountSummary] {
        let balances = postingBalancesByAccount
        return activeAccounts
            .filter { $0.type == .asset || $0.type == .liability }
            .map { account in
                AccountSummary(
                    id: account.id,
                    name: account.name,
                    subtitle: account.type.displayName,
                    symbol: account.symbolName,
                    balanceMinorUnits: balances[account.id, default: 0],
                    group: account.type == .asset ? "Assets" : "Liabilities",
                    type: account.type
                )
            }
    }

    var transactionSummaries: [TransactionSummary] {
        let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let attachmentTransactionIDs = Set(attachments.filter { $0.status == "active" }.compactMap(\.transactionID))

        return activeTransactions.compactMap { transaction in
            let classified = transaction.classification(accountMap: accountMap)
            return TransactionSummary(
                id: transaction.id,
                date: transaction.accountingDate.rainflowDate ?? .distantPast,
                payee: transaction.payee?.nilIfBlank ?? transaction.description.nilIfBlank ?? "Transaction",
                category: classified.category,
                amountMinorUnits: classified.displayAmount,
                kind: classified.kind,
                symbol: classified.symbol,
                revision: transaction.revision,
                hasReceipt: attachmentTransactionIDs.contains(transaction.id)
            )
        }
    }

    var netWorthMinorUnits: Int64 {
        let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        return activeTransactions
            .flatMap(\.postings)
            .reduce(into: Int64.zero) { total, posting in
                guard let type = accountMap[posting.accountID]?.type,
                      type == .asset || type == .liability else { return }
                total = total.addingClamped(posting.amountMinorUnits)
            }
    }

    var currentMonthCashFlow: CashFlowSummary {
        cashFlow(for: Date(), calendar: .current)
    }

    var cashFlowPoints: [CashFlowPoint] {
        let calendar = Calendar.current
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: .now)) ?? .now

        let scale = ledger.currency?.minorUnitScale ?? 2
        let divisor = Foundation.pow(10.0, Double(scale))
        return (0..<6).reversed().compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: -offset, to: currentMonth) else { return nil }
            let summary = cashFlow(for: month, calendar: calendar)
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM"
            return CashFlowPoint(
                label: formatter.string(from: month),
                income: Double(summary.incomeMinorUnits) / divisor,
                expense: Double(summary.expenseMinorUnits) / divisor,
                net: Double(summary.netMinorUnits) / divisor
            )
        }
    }

    var currentMonthSpending: [SpendingSlice] {
        let calendar = Calendar.current
        let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        var totals: [UUID: Int64] = [:]

        for transaction in activeTransactions {
            guard let date = transaction.accountingDate.rainflowDate,
                  calendar.isDate(date, equalTo: .now, toGranularity: .month) else { continue }
            for posting in transaction.postings {
                guard accountMap[posting.accountID]?.type == .expense,
                      posting.amountMinorUnits > 0 else { continue }
                totals[posting.accountID, default: 0] = totals[posting.accountID, default: 0]
                    .addingClamped(posting.amountMinorUnits)
            }
        }

        return totals.compactMap { id, amount in
            guard let account = accountMap[id] else { return nil }
            return SpendingSlice(id: id, name: account.name, amountMinorUnits: amount)
        }
        .sorted { $0.amountMinorUnits > $1.amountMinorUnits }
    }

    private var postingBalancesByAccount: [UUID: Int64] {
        activeTransactions
            .flatMap(\.postings)
            .reduce(into: [UUID: Int64]()) { result, posting in
                result[posting.accountID, default: 0] = result[posting.accountID, default: 0]
                    .addingClamped(posting.amountMinorUnits)
            }
    }

    private func cashFlow(for month: Date, calendar: Calendar) -> CashFlowSummary {
        let accountMap = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        var income: Int64 = 0
        var expense: Int64 = 0

        for transaction in activeTransactions {
            guard let date = transaction.accountingDate.rainflowDate,
                  calendar.isDate(date, equalTo: month, toGranularity: .month) else { continue }
            for posting in transaction.postings {
                guard let type = accountMap[posting.accountID]?.type else { continue }
                switch type {
                case .income where posting.amountMinorUnits < 0:
                    income = income.addingClamped(posting.amountMinorUnits.magnitudeAsInt64)
                case .expense where posting.amountMinorUnits > 0:
                    expense = expense.addingClamped(posting.amountMinorUnits)
                default:
                    break
                }
            }
        }
        return CashFlowSummary(incomeMinorUnits: income, expenseMinorUnits: expense)
    }
}

private extension TransactionRecord {
    func classification(accountMap: [UUID: AccountRecord]) -> (
        kind: TransactionSummary.Kind,
        displayAmount: Int64,
        category: String,
        symbol: String
    ) {
        if let expensePosting = postings.first(where: {
            accountMap[$0.accountID]?.type == .expense && $0.amountMinorUnits > 0
        }), let account = accountMap[expensePosting.accountID] {
            return (
                .expense,
                -expensePosting.amountMinorUnits,
                account.name,
                account.symbolName
            )
        }

        if let incomePosting = postings.first(where: {
            accountMap[$0.accountID]?.type == .income && $0.amountMinorUnits < 0
        }), let account = accountMap[incomePosting.accountID] {
            return (
                .income,
                incomePosting.amountMinorUnits.magnitudeAsInt64,
                account.name,
                account.symbolName
            )
        }

        let transferAmount = postings
            .first(where: { accountMap[$0.accountID]?.type == .asset || accountMap[$0.accountID]?.type == .liability })?
            .amountMinorUnits.magnitudeAsInt64 ?? 0
        return (.transfer, transferAmount, "Transfer", "arrow.left.arrow.right")
    }
}

extension AccountType {
    var displayName: String {
        switch self {
        case .asset: "Asset"
        case .liability: "Liability"
        case .equity: "Equity"
        case .income: "Income"
        case .expense: "Expense"
        }
    }
}

extension AccountRecord {
    var symbolName: String {
        let normalized = name.lowercased()
        if normalized.contains("checking") { return "building.columns.fill" }
        if normalized.contains("saving") { return "banknote.fill" }
        if normalized.contains("cash") { return "wallet.pass.fill" }
        if normalized.contains("credit") { return "creditcard.fill" }
        if normalized.contains("grocer") { return "cart.fill" }
        if normalized.contains("dining") { return "fork.knife" }
        if normalized.contains("transport") { return "car.fill" }
        if normalized.contains("housing") { return "house.fill" }
        if normalized.contains("utilit") { return "bolt.fill" }
        if normalized.contains("health") { return "cross.case.fill" }
        if normalized.contains("entertain") { return "play.rectangle.fill" }
        if type == .income { return "arrow.down.circle.fill" }
        if type == .expense { return "tag.fill" }
        return "circle.grid.2x2.fill"
    }
}

extension Int64 {
    func formattedCurrency(code: String = "USD", showPlus: Bool = false) -> String {
        let currency = CurrencyCode(rawValue: code) ?? .usd
        let divisor = Decimal(sign: .plus, exponent: currency.minorUnitScale, significand: 1)
        let decimal = Decimal(self) / divisor
        let number = NSDecimalNumber(decimal: decimal)

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.rawValue
        formatter.locale = .autoupdatingCurrent
        formatter.minimumFractionDigits = currency.minorUnitScale
        formatter.maximumFractionDigits = currency.minorUnitScale

        let base = formatter.string(from: number) ?? "\(currency.rawValue) 0"
        return showPlus && self > 0 ? "+\(base)" : base
    }

    fileprivate var magnitudeAsInt64: Int64 {
        if self == .min { return .max }
        return Swift.abs(self)
    }

    fileprivate func addingClamped(_ other: Int64) -> Int64 {
        let (value, overflow) = addingReportingOverflow(other)
        if !overflow { return value }
        return other >= 0 ? .max : .min
    }
}

private extension String {
    var rainflowDate: Date? {
        let parts = split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
    }

    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

// Preview-only sample data. Production screens read LedgerStore.
enum PreviewData {
    static let accounts: [AccountSummary] = [
        .init(id: UUID(), name: "Checking", subtitle: "Asset", symbol: "building.columns.fill", balanceMinorUnits: 512_045, group: "Assets", type: .asset),
        .init(id: UUID(), name: "Savings", subtitle: "Asset", symbol: "banknote.fill", balanceMinorUnits: 781_473, group: "Assets", type: .asset),
        .init(id: UUID(), name: "Credit Card", subtitle: "Liability", symbol: "creditcard.fill", balanceMinorUnits: -193_455, group: "Liabilities", type: .liability)
    ]

    static let transactions: [TransactionSummary] = [
        .init(id: UUID(), date: .now, payee: "Safeway", category: "Groceries", amountMinorUnits: -7_823, kind: .expense, symbol: "cart.fill", revision: 1, hasReceipt: true),
        .init(id: UUID(), date: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now, payee: "Salary", category: "Salary", amountMinorUnits: 250_000, kind: .income, symbol: "arrow.down.circle.fill", revision: 1, hasReceipt: false)
    ]

    static let cashFlow: [CashFlowPoint] = [
        .init(label: "Mar", income: 5_000, expense: 1_800, net: 3_200),
        .init(label: "Apr", income: 2_400, expense: 3_300, net: -900),
        .init(label: "May", income: 2_100, expense: 1_600, net: 500),
        .init(label: "Jun", income: 1_850, expense: 1_920, net: -70),
        .init(label: "Jul", income: 2_700, expense: 1_100, net: 1_600)
    ]
}
