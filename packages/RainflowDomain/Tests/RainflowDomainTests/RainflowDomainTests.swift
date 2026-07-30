import Foundation
import Testing
@testable import RainflowDomain

@Test func balancedTransactionIsAccepted() throws {
    let ledgerID = UUID()
    let checking = UUID()
    let groceries = UUID()
    let date = try LocalDate(year: 2026, month: 7, day: 26)

    let transaction = try LedgerTransaction(
        ledgerID: ledgerID,
        accountingDate: date,
        description: "Groceries",
        postings: [
            Posting(accountID: checking, amount: Money(minorUnits: -7_823, currency: .usd)),
            Posting(accountID: groceries, amount: Money(minorUnits: 7_823, currency: .usd))
        ]
    )

    #expect(transaction.postings.count == 2)
}

@Test func unbalancedTransactionIsRejected() throws {
    let date = try LocalDate(year: 2026, month: 7, day: 26)

    #expect(throws: TransactionValidationError.unbalanced(sum: -1)) {
        try LedgerTransaction(
            ledgerID: UUID(),
            accountingDate: date,
            description: "Broken",
            postings: [
                Posting(accountID: UUID(), amount: Money(minorUnits: -100, currency: .usd)),
                Posting(accountID: UUID(), amount: Money(minorUnits: 99, currency: .usd))
            ]
        )
    }
}

@Test func mixedCurrenciesAreRejected() throws {
    let date = try LocalDate(year: 2026, month: 7, day: 26)

    #expect(throws: TransactionValidationError.currencyMismatch) {
        try LedgerTransaction(
            ledgerID: UUID(),
            accountingDate: date,
            description: "Mixed",
            postings: [
                Posting(accountID: UUID(), amount: Money(minorUnits: -100, currency: .usd)),
                Posting(accountID: UUID(), amount: Money(minorUnits: 100, currency: .eur))
            ]
        )
    }
}

@Test func invalidCalendarDateIsRejected() {
    #expect(throws: LocalDateError.invalidDate) {
        try LocalDate(year: 2026, month: 2, day: 31)
    }
}

@Test func expenseDraftBuildsBindingSigns() throws {
    let ledgerID = UUID()
    let checking = UUID()
    let dining = UUID()
    var draft = TransactionDraft(kind: .expense)
    draft.amountMinorUnits = 2_500
    draft.accountID = checking
    draft.categoryOrDestinationID = dining
    draft.payee = "Cafe"

    let transaction = try SimpleTransactionBuilder.build(
        ledgerID: ledgerID,
        currency: .usd,
        draft: draft
    )

    #expect(transaction.postings[0].amount.minorUnits == -2_500)
    #expect(transaction.postings[1].amount.minorUnits == 2_500)
    #expect(transaction.payee == "Cafe")
}

@Test func incomeDraftBuildsBindingSigns() throws {
    let checking = UUID()
    let salary = UUID()
    var draft = TransactionDraft(kind: .income)
    draft.amountMinorUnits = 100_000
    draft.accountID = checking
    draft.categoryOrDestinationID = salary

    let transaction = try SimpleTransactionBuilder.build(
        ledgerID: UUID(),
        currency: .usd,
        draft: draft
    )

    #expect(transaction.postings[0].amount.minorUnits == 100_000)
    #expect(transaction.postings[1].amount.minorUnits == -100_000)
}
