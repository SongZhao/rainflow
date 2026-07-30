import Foundation

public enum CurrencyCode: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case usd = "USD"
    case cad = "CAD"
    case eur = "EUR"
    case gbp = "GBP"
    case jpy = "JPY"
    case aud = "AUD"

    public var id: String { rawValue }

    public var minorUnitScale: Int {
        switch self {
        case .jpy: 0
        default: 2
        }
    }
}

public struct Money: Equatable, Hashable, Codable, Sendable {
    public let minorUnits: Int64
    public let currency: CurrencyCode

    public init(minorUnits: Int64, currency: CurrencyCode) {
        self.minorUnits = minorUnits
        self.currency = currency
    }

    public static func + (lhs: Money, rhs: Money) throws -> Money {
        guard lhs.currency == rhs.currency else { throw MoneyError.currencyMismatch }
        let (sum, overflow) = lhs.minorUnits.addingReportingOverflow(rhs.minorUnits)
        guard !overflow else { throw MoneyError.overflow }
        return Money(minorUnits: sum, currency: lhs.currency)
    }

    public func negated() throws -> Money {
        let (value, overflow) = Int64.zero.subtractingReportingOverflow(minorUnits)
        guard !overflow else { throw MoneyError.overflow }
        return Money(minorUnits: value, currency: currency)
    }
}

public enum MoneyError: Error, Equatable, Sendable {
    case currencyMismatch
    case overflow
}

public struct LocalDate: Equatable, Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day

        guard let date = calendar.date(from: components) else {
            throw LocalDateError.invalidDate
        }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else {
            throw LocalDateError.invalidDate
        }

        self.year = year
        self.month = month
        self.day = day
    }

    public init(date: Date, calendar: Calendar = .current) throws {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            throw LocalDateError.invalidDate
        }
        try self.init(year: year, month: month, day: day)
    }

    public init(iso8601: String) throws {
        let parts = iso8601.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            throw LocalDateError.invalidDate
        }
        try self.init(year: year, month: month, day: day)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

public enum LocalDateError: Error, Equatable, Sendable {
    case invalidDate
}

public enum AccountType: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case asset
    case liability
    case equity
    case income
    case expense

    public var id: String { rawValue }

    /// The binding storage convention. A normal increase is positive for
    /// assets/expenses and negative for liabilities/equity/income.
    public var normalIncreaseSign: Int64 {
        switch self {
        case .asset, .expense: 1
        case .liability, .equity, .income: -1
        }
    }
}

public struct Account: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let id: UUID
    public let ledgerID: UUID
    public var name: String
    public let type: AccountType
    public var archivedAt: Date?

    public init(
        id: UUID = UUID(),
        ledgerID: UUID,
        name: String,
        type: AccountType,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.ledgerID = ledgerID
        self.name = name
        self.type = type
        self.archivedAt = archivedAt
    }
}

public struct Posting: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let id: UUID
    public let accountID: UUID
    public let amount: Money
    public var memo: String?

    public init(
        id: UUID = UUID(),
        accountID: UUID,
        amount: Money,
        memo: String? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.amount = amount
        self.memo = memo
    }
}

public struct LedgerTransaction: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let id: UUID
    public let ledgerID: UUID
    public let accountingDate: LocalDate
    public let description: String
    public let payee: String?
    public let note: String?
    public let postings: [Posting]
    public let revision: Int

    public init(
        id: UUID = UUID(),
        ledgerID: UUID,
        accountingDate: LocalDate,
        description: String,
        payee: String? = nil,
        note: String? = nil,
        postings: [Posting],
        revision: Int = 1
    ) throws {
        guard postings.count >= 2 else { throw TransactionValidationError.requiresTwoPostings }
        guard revision >= 1 else { throw TransactionValidationError.invalidRevision }

        let currencies = Set(postings.map(\.amount.currency))
        guard currencies.count == 1 else { throw TransactionValidationError.currencyMismatch }

        var sum: Int64 = 0
        for posting in postings {
            let (next, overflow) = sum.addingReportingOverflow(posting.amount.minorUnits)
            guard !overflow else { throw TransactionValidationError.amountOverflow }
            sum = next
        }
        guard sum == 0 else { throw TransactionValidationError.unbalanced(sum: sum) }

        self.id = id
        self.ledgerID = ledgerID
        self.accountingDate = accountingDate
        self.description = description
        self.payee = payee
        self.note = note
        self.postings = postings
        self.revision = revision
    }
}

public enum TransactionValidationError: Error, Equatable, Sendable {
    case requiresTwoPostings
    case currencyMismatch
    case amountOverflow
    case unbalanced(sum: Int64)
    case invalidRevision
}

public enum TransactionKind: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case expense = "Expense"
    case income = "Income"
    case transfer = "Transfer"

    public var id: String { rawValue }
}

public struct TransactionDraft: Equatable, Sendable {
    public var kind: TransactionKind
    public var amountMinorUnits: Int64?
    public var accountID: UUID?
    public var categoryOrDestinationID: UUID?
    public var accountingDate: Date
    public var payee: String
    public var note: String
    public var receiptLocalURL: URL?

    public init(
        kind: TransactionKind = .expense,
        amountMinorUnits: Int64? = nil,
        accountID: UUID? = nil,
        categoryOrDestinationID: UUID? = nil,
        accountingDate: Date = .now,
        payee: String = "",
        note: String = "",
        receiptLocalURL: URL? = nil
    ) {
        self.kind = kind
        self.amountMinorUnits = amountMinorUnits
        self.accountID = accountID
        self.categoryOrDestinationID = categoryOrDestinationID
        self.accountingDate = accountingDate
        self.payee = payee
        self.note = note
        self.receiptLocalURL = receiptLocalURL
    }

    public var canReview: Bool {
        guard let amountMinorUnits, amountMinorUnits > 0 else { return false }
        return accountID != nil
            && categoryOrDestinationID != nil
            && accountID != categoryOrDestinationID
    }
}

public enum TransactionDraftError: Error, Equatable, Sendable {
    case amountRequired
    case amountMustBePositive
    case accountRequired
    case destinationRequired
    case accountAndDestinationMustDiffer
}

public enum SimpleTransactionBuilder {
    /// Builds a two-posting transaction using Rainflow's binding sign convention:
    /// expense: source -, expense category +
    /// income: destination +, income category -
    /// transfer: source -, destination +
    public static func build(
        id: UUID = UUID(),
        ledgerID: UUID,
        currency: CurrencyCode,
        draft: TransactionDraft
    ) throws -> LedgerTransaction {
        guard let amount = draft.amountMinorUnits else { throw TransactionDraftError.amountRequired }
        guard amount > 0 else { throw TransactionDraftError.amountMustBePositive }
        guard let accountID = draft.accountID else { throw TransactionDraftError.accountRequired }
        guard let destinationID = draft.categoryOrDestinationID else {
            throw TransactionDraftError.destinationRequired
        }
        guard accountID != destinationID else {
            throw TransactionDraftError.accountAndDestinationMustDiffer
        }

        let negativeAmount = Money(minorUnits: -amount, currency: currency)
        let positiveAmount = Money(minorUnits: amount, currency: currency)
        let postings: [Posting]

        switch draft.kind {
        case .expense:
            postings = [
                Posting(accountID: accountID, amount: negativeAmount),
                Posting(accountID: destinationID, amount: positiveAmount)
            ]
        case .income:
            postings = [
                Posting(accountID: accountID, amount: positiveAmount),
                Posting(accountID: destinationID, amount: negativeAmount)
            ]
        case .transfer:
            postings = [
                Posting(accountID: accountID, amount: negativeAmount),
                Posting(accountID: destinationID, amount: positiveAmount)
            ]
        }

        let date = try LocalDate(date: draft.accountingDate)
        let trimmedPayee = draft.payee.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = trimmedPayee.isEmpty ? draft.kind.rawValue : trimmedPayee

        return try LedgerTransaction(
            id: id,
            ledgerID: ledgerID,
            accountingDate: date,
            description: description,
            payee: trimmedPayee.isEmpty ? nil : trimmedPayee,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            postings: postings
        )
    }
}
