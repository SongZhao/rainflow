import Foundation
import RainflowDomain
import Supabase

struct SupabaseLedgerAPI: @unchecked Sendable {
    private let client: SupabaseClient
    private let receiptBucket = "receipts"
    private let pageSize = 500

    init(client: SupabaseClient) {
        self.client = client
    }

    func currentUserID() async throws -> UUID {
        try await client.auth.session.user.id
    }

    func fetchAccessibleLedgers() async throws -> [LedgerRecord] {
        let ledgers: [LedgerRecord] = try await client
            .from("ledgers")
            .select()
            .execute()
            .value

        return ledgers.sorted {
            if $0.createdAt == $1.createdAt { return $0.name < $1.name }
            return $0.createdAt < $1.createdAt
        }
    }

    func fetchPrimarySnapshot() async throws -> LedgerSnapshot? {
        let ledgers = try await fetchAccessibleLedgers()

        guard let ledger = ledgers.first else {
            return nil
        }

        return try await fetchSnapshot(ledgerID: ledger.id)
    }

    func fetchSnapshot(ledgerID: UUID) async throws -> LedgerSnapshot? {
        let ledgers = try await fetchAccessibleLedgers()
        guard let ledger = ledgers.first(where: { $0.id == ledgerID }) else {
            return nil
        }

        let accounts: [AccountRecord] = try await client
            .from("accounts")
            .select()
            .eq("ledger_id", value: ledger.id)
            .execute()
            .value

        let attachments: [AttachmentRecord] = try await client
            .from("attachment_manifests")
            .select()
            .eq("ledger_id", value: ledger.id)
            .execute()
            .value

        let transactions = try await fetchTransactions(ledgerID: ledger.id)

        return LedgerSnapshot(
            ledger: ledger,
            accounts: accounts,
            transactions: transactions,
            attachments: attachments
        )
    }

    func createLedger(
        name: String,
        currency: CurrencyCode,
        kind: LedgerKindOption = .personal
    ) async throws -> LedgerRecord {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let parameters = CreateLedgerWithTypeParameters(
            ledgerName: trimmedName.isEmpty ? "Personal" : trimmedName,
            ledgerCurrency: currency.rawValue,
            ledgerKind: kind.rawValue
        )

        do {
            return try await client
                .rpc("create_ledger_with_type", params: parameters)
                .execute()
                .value
        } catch {
            guard kind == .personal else { throw error }

            let fallbackParameters = CreateLedgerParameters(
                ledgerName: trimmedName.isEmpty ? "Personal" : trimmedName,
                ledgerCurrency: currency.rawValue
            )

            return try await client
                .rpc("create_ledger", params: fallbackParameters)
                .execute()
                .value
        }
    }

    func createTransaction(_ transaction: LedgerTransaction, idempotencyKey: UUID) async throws -> CommandResult {
        let parameters = CreateTransactionParameters(
            ledgerID: transaction.ledgerID,
            transactionID: transaction.id,
            idempotencyKey: idempotencyKey,
            accountingDate: transaction.accountingDate.description,
            description: transaction.description,
            payee: transaction.payee ?? "",
            note: transaction.note ?? "",
            postings: transaction.postings.map { PostingPayload(posting: $0) }
        )

        return try await client
            .rpc("create_transaction", params: parameters)
            .execute()
            .value
    }

    func updateTransaction(_ transaction: LedgerTransaction, expectedRevision: Int) async throws -> CommandResult {
        let parameters = UpdateTransactionParameters(
            ledgerID: transaction.ledgerID,
            transactionID: transaction.id,
            expectedRevision: expectedRevision,
            accountingDate: transaction.accountingDate.description,
            description: transaction.description,
            payee: transaction.payee ?? "",
            note: transaction.note ?? "",
            postings: transaction.postings.map { PostingPayload(posting: $0) }
        )

        return try await client
            .rpc("update_transaction", params: parameters)
            .execute()
            .value
    }

    func softDeleteTransaction(ledgerID: UUID, transactionID: UUID, expectedRevision: Int) async throws -> CommandResult {
        let parameters = TransactionRevisionParameters(
            ledgerID: ledgerID,
            transactionID: transactionID,
            expectedRevision: expectedRevision
        )

        return try await client
            .rpc("soft_delete_transaction", params: parameters)
            .execute()
            .value
    }

    func uploadReceipt(
        _ staged: StagedReceipt,
        userID: UUID,
        ledgerID: UUID,
        transactionID: UUID
    ) async throws -> AttachmentRecord {
        let objectKey = [
            userID.uuidString.lowercased(),
            ledgerID.uuidString.lowercased(),
            transactionID.uuidString.lowercased(),
            "\(staged.id.uuidString.lowercased()).jpg"
        ].joined(separator: "/")

        let fileData = try Data(contentsOf: staged.localURL, options: [.mappedIfSafe])
        let parameters = FinalizeAttachmentParameters(
            ledgerID: ledgerID,
            transactionID: transactionID,
            attachmentID: staged.id,
            objectKey: objectKey,
            originalFileName: staged.originalFileName,
            mimeType: staged.mimeType,
            byteSize: staged.byteSize,
            sha256Hex: staged.sha256Hex
        )

        do {
            _ = try await client.storage
                .from(receiptBucket)
                .upload(
                    objectKey,
                    data: fileData,
                    options: FileOptions(
                        cacheControl: "3600",
                        contentType: staged.mimeType,
                        upsert: false
                    )
                )
        } catch {
            // A retry can find the immutable object already present, or a network
            // response can be lost after Storage accepted the bytes. The manifest
            // finalizer is idempotent for this attachment ID, so try it before
            // treating the receipt as failed.
            return try await finalizeAttachment(parameters)
        }

        // Do not delete the object if this response fails: the RPC may have
        // committed before the network error. The durable retry path will call
        // this method again, tolerate the existing object, and finalize safely.
        return try await finalizeAttachment(parameters)
    }

    func receiptViewURL(objectKey objectPath: String) async throws -> URL {
        try await client.storage
            .from(receiptBucket)
            .createSignedURL(path: objectPath, expiresIn: 300)
    }

    private func finalizeAttachment(
        _ parameters: FinalizeAttachmentParameters
    ) async throws -> AttachmentRecord {
        try await client
            .rpc("finalize_attachment", params: parameters)
            .execute()
            .value
    }

    private func fetchTransactions(ledgerID: UUID) async throws -> [TransactionRecord] {
        var result: [TransactionRecord] = []
        var offset = 0

        while true {
            let page: [TransactionRecord] = try await client
                .from("ledger_transactions")
                .select("*, postings(*)")
                .eq("ledger_id", value: ledgerID)
                .order("accounting_date", ascending: false)
                .range(from: offset, to: offset + pageSize - 1)
                .execute()
                .value

            result.append(contentsOf: page)
            guard page.count == pageSize else { break }
            offset += pageSize
        }

        return result
    }
}
