import Foundation
import RainflowDomain
import Testing
@testable import Rainflow

@Test func draftRequiresAmountAndTwoDistinctSelections() {
    var draft = TransactionDraft()
    #expect(!draft.canReview)

    draft.amountMinorUnits = 1_000
    draft.accountID = UUID()
    draft.categoryOrDestinationID = UUID()
    #expect(draft.canReview)
}

@Test func receiptParserFindsMerchantTotalAndLineItems() {
    let result = ReceiptTextExtractor.parse(
        lines: [
            "SAFEWAY",
            "Apples 3.49",
            "Milk 4.29",
            "SUBTOTAL 7.78",
            "TAX 0.45",
            "TOTAL $8.23",
            "VISA 8.23"
        ],
        currency: .usd
    )

    #expect(result.merchantName == "SAFEWAY")
    #expect(result.amountMinorUnits == 823)
    #expect(result.lineItems.contains("Apples 3.49"))
    #expect(result.lineItems.contains("Milk 4.29"))
}

@Test func structuredReceiptLineItemsPreserveAmountsAndQuantityDetails() throws {
    let items = ReceiptLineItemParser.parse(
        lines: [
            "Apples 3.49",
            "Bananas 2 x 1.50 3.00"
        ],
        currency: .usd
    )

    let apples = try #require(items.first)
    #expect(apples.description == "Apples")
    #expect(apples.amountMinorUnits == 349)
    #expect(apples.quantity == nil)
    #expect(apples.unitPriceMinorUnits == nil)

    let bananas = try #require(items.dropFirst().first)
    #expect(bananas.description == "Bananas")
    #expect(bananas.amountMinorUnits == 300)
    #expect(bananas.quantity == 2)
    #expect(bananas.unitPriceMinorUnits == 150)
}

@Test func receiptParserHandlesWholeDollarAndOcrZeroTotals() {
    let result = ReceiptTextExtractor.parse(
        lines: [
            "RAIN MART",
            "Notebook 12",
            "T0TAL $12"
        ],
        currency: .usd
    )

    #expect(result.merchantName == "RAIN MART")
    #expect(result.amountMinorUnits == 1_200)
    #expect(result.lineItems.contains("Notebook 12"))
}

@Test func receiptParserIgnoresRewardsPointsWhenChoosingAmount() throws {
    let result = ReceiptTextExtractor.parse(
        lines: [
            "SpotHero",
            "$28.40",
            "42.60 total rewards points earned",
            "Transaction Details",
            "Type Sale",
            "Transaction date Feb 18, 2026",
            "Description SPOTHERO 844-356-8054",
            "Merchant type Parking lots and garages",
            "Method Online, mail or phone Apple Pay",
            "Card number (...4170)",
            "Reference number 24011346049100119089717"
        ],
        currency: .usd
    )

    #expect(result.merchantName == "SpotHero")
    #expect(result.amountMinorUnits == 2_840)
    let date = try #require(result.accountingDate)
    #expect(try LocalDate(date: date) == LocalDate(year: 2026, month: 2, day: 18))
}

@Test func receiptParserPrefersAmountDueOverSubtotalAndTenderLines() {
    let result = ReceiptTextExtractor.parse(
        lines: [
            "CITY PARKING",
            "Parking 18.00",
            "Service fee 2.50",
            "Subtotal 20.50",
            "Tax 1.64",
            "Amount due $22.14",
            "Visa $22.14"
        ],
        currency: .usd
    )

    #expect(result.merchantName == "CITY PARKING")
    #expect(result.amountMinorUnits == 2_214)
    #expect(result.lineItems.contains("Parking 18.00"))
    #expect(result.lineItems.contains("Service fee 2.50"))
}

@Test func receiptParserExtractsNumericReceiptDate() throws {
    let result = ReceiptTextExtractor.parse(
        lines: [
            "RAIN CAFE",
            "Date 07/14/2026",
            "Coffee 4.25",
            "Total $4.25"
        ],
        currency: .usd
    )

    let date = try #require(result.accountingDate)
    #expect(try LocalDate(date: date) == LocalDate(year: 2026, month: 7, day: 14))
}
