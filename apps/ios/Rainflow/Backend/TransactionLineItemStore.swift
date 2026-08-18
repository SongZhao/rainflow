import Foundation
import Supabase

protocol TransactionLineItemPersisting: Sendable {
    func replaceLineItems(
        ledgerID: UUID,
        transactionID: UUID,
        items: [ReceiptLineItem]
    ) async throws
}

struct SupabaseTransactionLineItemStore: TransactionLineItemPersisting, @unchecked Sendable {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func replaceLineItems(
        ledgerID: UUID,
        transactionID: UUID,
        items: [ReceiptLineItem]
    ) async throws {
        let payload = items
            .filter { !$0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(50)
            .map {
                ReceiptLineItem(
                    description: String($0.description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240)),
                    amountMinorUnits: $0.amountMinorUnits,
                    quantity: $0.quantity,
                    unitPriceMinorUnits: $0.unitPriceMinorUnits
                )
            }

        let parameters = ReplaceTransactionLineItemsParameters(
            ledgerID: ledgerID,
            transactionID: transactionID,
            items: Array(payload)
        )

        let _: Int = try await client
            .rpc("replace_transaction_line_items", params: parameters)
            .execute()
            .value
    }
}

private struct ReplaceTransactionLineItemsParameters: Encodable, Sendable {
    let ledgerID: UUID
    let transactionID: UUID
    let items: [ReceiptLineItem]

    enum CodingKeys: String, CodingKey {
        case ledgerID = "p_ledger_id"
        case transactionID = "p_transaction_id"
        case items = "p_items"
    }
}
