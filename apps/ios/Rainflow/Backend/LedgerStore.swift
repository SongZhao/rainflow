import Combine
import Foundation
import RainflowDomain

enum ReceiptSaveStatus: Equatable, Sendable {
    case none
    case uploaded
    case queuedForRetry
    case needsAttention
}

struct TransactionSaveOutcome: Equatable, Sendable {
    let transactionID: UUID
    let receiptStatus: ReceiptSaveStatus

    var receiptQueuedForRetry: Bool { receiptStatus == .queuedForRetry }
    var receiptNeedsAttention: Bool { receiptStatus == .needsAttention }
}

enum LedgerStoreError: LocalizedError {
    case backendUnavailable
    case ledgerRequired
    case unsupportedCurrency
    case receiptUploadDeferred
    case receiptNeedsAttention
    case receiptNotFound

    var errorDescription: String? {
        switch self {
        case .backendUnavailable:
            "Rainflow cannot reach the configured backend."
        case .ledgerRequired:
            "Create your ledger before adding transactions."
        case .unsupportedCurrency:
            "This ledger uses an unsupported currency."
        case .receiptUploadDeferred:
            "The transaction was saved, but its receipt will retry when you are online."
        case .receiptNeedsAttention:
            "The transaction was saved, but Rainflow could not queue the receipt. Keep the original image and attach it again when the device has storage and a connection."
        case .receiptNotFound:
            "No active receipt is attached to this transaction."
        }
    }
}

@MainActor
final class LedgerStore: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case needsLedger
        case ready(isOffline: Bool)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var snapshot: LedgerSnapshot?
    @Published private(set) var ledgers: [LedgerRecord] = []
    @Published private(set) var activeLedgerID: UUID?
    @Published private(set) var isWorking = false
    @Published var noticeMessage: String?
    @Published var errorMessage: String?

    private let api: SupabaseLedgerAPI?
    private let database: AppDatabase?
    private let receiptStore: ReceiptStore

    init(api: SupabaseLedgerAPI?, database: AppDatabase?, receiptStore: ReceiptStore) {
        self.api = api
        self.database = database
        self.receiptStore = receiptStore
    }

    var currency: CurrencyCode {
        snapshot?.ledger.currency ?? .usd
    }

    var accounts: [AccountRecord] {
        snapshot?.activeAccounts ?? []
    }

    var accountSummaries: [AccountSummary] {
        snapshot?.accountSummaries ?? []
    }

    var transactions: [TransactionSummary] {
        snapshot?.transactionSummaries ?? []
    }

    var cashFlow: CashFlowSummary {
        snapshot?.currentMonthCashFlow ?? CashFlowSummary(incomeMinorUnits: 0, expenseMinorUnits: 0)
    }

    func refresh() async {
        await refresh(retryReceipts: true)
    }

    @discardableResult
    func createLedger(
        name: String,
        currency: CurrencyCode,
        kind: LedgerKindOption = .personal
    ) async -> Bool {
        guard let api else {
            errorMessage = LedgerStoreError.backendUnavailable.localizedDescription
            return false
        }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let created = try await api.createLedger(name: name, currency: currency, kind: kind)
            activeLedgerID = created.id
            await refresh()
            return errorMessage == nil
        } catch {
            if kind == .shared,
               error.localizedDescription.localizedCaseInsensitiveContains("create_ledger_with_type") {
                errorMessage = "Shared ledger setup is not active in Supabase yet. Apply the latest Supabase setup, then try again."
            } else {
                errorMessage = error.localizedDescription
            }
            return false
        }
    }

    func switchLedger(_ ledger: LedgerRecord) async {
        guard activeLedgerID != ledger.id || snapshot?.ledger.id != ledger.id else { return }
        activeLedgerID = ledger.id
        await refresh(retryReceipts: true)
    }

    func saveTransaction(draft: TransactionDraft, receiptData: Data?) async throws -> TransactionSaveOutcome {
        guard let api else { throw LedgerStoreError.backendUnavailable }
        guard let snapshot else { throw LedgerStoreError.ledgerRequired }
        guard let currency = snapshot.ledger.currency else { throw LedgerStoreError.unsupportedCurrency }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        // Resolve the authenticated owner before the authoritative transaction is
        // created. If receipt upload later fails, the durable retry record already
        // has every path component it needs and does not depend on another auth call.
        let currentUserID = try await api.currentUserID()

        let transaction = try SimpleTransactionBuilder.build(
            ledgerID: snapshot.ledger.id,
            currency: currency,
            draft: draft
        )

        let stagedReceipt: StagedReceipt?
        if let receiptData {
            stagedReceipt = try await receiptStore.stage(imageData: receiptData)
        } else {
            stagedReceipt = nil
        }

        do {
            _ = try await api.createTransaction(transaction, idempotencyKey: UUID())
        } catch {
            if let stagedReceipt { await receiptStore.delete(stagedReceipt) }
            throw error
        }

        var receiptStatus: ReceiptSaveStatus = .none
        if let stagedReceipt {
            do {
                _ = try await api.uploadReceipt(
                    stagedReceipt,
                    userID: currentUserID,
                    ledgerID: transaction.ledgerID,
                    transactionID: transaction.id
                )
                await receiptStore.delete(stagedReceipt)
                receiptStatus = .uploaded
            } catch let uploadError {
                var pending = PendingReceiptUpload(
                    id: stagedReceipt.id,
                    userID: currentUserID,
                    ledgerID: transaction.ledgerID,
                    transactionID: transaction.id,
                    stagedReceipt: stagedReceipt,
                    createdAt: .now,
                    attemptCount: 1,
                    lastError: uploadError.localizedDescription
                )

                do {
                    guard let database else { throw LedgerStoreError.receiptNeedsAttention }
                    try database.enqueue(pending)
                    receiptStatus = .queuedForRetry
                    noticeMessage = LedgerStoreError.receiptUploadDeferred.localizedDescription
                } catch let queueError {
                    pending.lastError = "Upload: \(uploadError.localizedDescription); queue: \(queueError.localizedDescription)"
                    receiptStatus = .needsAttention
                    noticeMessage = LedgerStoreError.receiptNeedsAttention.localizedDescription
                }
            }
        }

        // Pull the authoritative transaction without immediately retrying the same
        // receipt. This keeps the success screen truthful about the outcome above.
        await refresh(retryReceipts: false)
        return TransactionSaveOutcome(
            transactionID: transaction.id,
            receiptStatus: receiptStatus
        )
    }

    func updateTransaction(_ existing: TransactionRecord, draft: TransactionDraft) async throws {
        guard let api else { throw LedgerStoreError.backendUnavailable }
        guard let snapshot else { throw LedgerStoreError.ledgerRequired }
        guard let currency = snapshot.ledger.currency else { throw LedgerStoreError.unsupportedCurrency }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        let transaction = try SimpleTransactionBuilder.build(
            id: existing.id,
            ledgerID: snapshot.ledger.id,
            currency: currency,
            draft: draft
        )

        _ = try await api.updateTransaction(transaction, expectedRevision: existing.revision)
        await refresh(retryReceipts: false)
    }

    func deleteTransaction(_ transaction: TransactionRecord) async throws {
        guard let api else { throw LedgerStoreError.backendUnavailable }
        guard let snapshot else { throw LedgerStoreError.ledgerRequired }

        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        _ = try await api.softDeleteTransaction(
            ledgerID: snapshot.ledger.id,
            transactionID: transaction.id,
            expectedRevision: transaction.revision
        )
        await refresh(retryReceipts: false)
    }

    func activeReceiptAttachment(for transactionID: UUID) -> AttachmentRecord? {
        snapshot?.attachments.first {
            $0.transactionID == transactionID && $0.status == "active"
        }
    }

    func receiptViewURL(for transactionID: UUID) async throws -> URL {
        guard let api else { throw LedgerStoreError.backendUnavailable }
        guard let attachment = activeReceiptAttachment(for: transactionID) else {
            throw LedgerStoreError.receiptNotFound
        }

        return try await api.receiptViewURL(objectKey: attachment.objectKey)
    }

    func reset() {
        snapshot = nil
        ledgers = []
        activeLedgerID = nil
        phase = .idle
        noticeMessage = nil
        errorMessage = nil
        try? database?.removeAllUserData()
        Task { await receiptStore.removeAll() }
    }

    private func refresh(retryReceipts shouldRetryReceipts: Bool) async {
        guard let api else {
            phase = .failed(LedgerStoreError.backendUnavailable.localizedDescription)
            return
        }

        if snapshot == nil { phase = .loading }
        errorMessage = nil

        do {
            let remoteLedgers = try await api.fetchAccessibleLedgers()
            ledgers = remoteLedgers

            guard !remoteLedgers.isEmpty else {
                snapshot = nil
                activeLedgerID = nil
                phase = .needsLedger
                return
            }

            let currentSnapshotID = snapshot?.ledger.id
            let targetID = activeLedgerID.flatMap { requestedID in
                remoteLedgers.contains { $0.id == requestedID } ? requestedID : nil
            } ?? currentSnapshotID.flatMap { currentID in
                remoteLedgers.contains { $0.id == currentID } ? currentID : nil
            } ?? remoteLedgers[0].id

            guard let remote = try await api.fetchSnapshot(ledgerID: targetID) else {
                throw LedgerStoreError.ledgerRequired
            }

            snapshot = remote
            activeLedgerID = remote.ledger.id
            phase = .ready(isOffline: false)
            try? database?.save(snapshot: remote)
            if shouldRetryReceipts {
                await retryPendingReceipts()
            }
        } catch {
            do {
                if let cached = try database?.latestSnapshot() {
                    snapshot = cached
                    if ledgers.isEmpty { ledgers = [cached.ledger] }
                    activeLedgerID = cached.ledger.id
                    phase = .ready(isOffline: true)
                    noticeMessage = "Showing the latest saved copy. New transactions require a connection."
                } else {
                    throw error
                }
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func retryPendingReceipts() async {
        guard let api, let database else { return }
        guard let pending = try? database.pendingReceiptUploads(), !pending.isEmpty else { return }

        var uploadedAny = false
        for var item in pending {
            guard await receiptStore.exists(item.stagedReceipt) else {
                try? database.removePendingReceiptUpload(id: item.id)
                noticeMessage = "A pending receipt is no longer available on this device. Its transaction is safe, but the original image must be attached again."
                continue
            }

            do {
                _ = try await api.uploadReceipt(
                    item.stagedReceipt,
                    userID: item.userID,
                    ledgerID: item.ledgerID,
                    transactionID: item.transactionID
                )
                await receiptStore.delete(item.stagedReceipt)
                try database.removePendingReceiptUpload(id: item.id)
                uploadedAny = true
            } catch {
                item.attemptCount += 1
                item.lastError = error.localizedDescription
                try? database.enqueue(item)
            }
        }

        guard uploadedAny else { return }

        // Refresh the attachment manifest after retry completion without calling
        // refresh() recursively (which would start another retry pass).
        do {
            if let ledgerID = activeLedgerID ?? snapshot?.ledger.id,
               let remote = try await api.fetchSnapshot(ledgerID: ledgerID) {
                snapshot = remote
                phase = .ready(isOffline: false)
                try? database.save(snapshot: remote)
            }
            noticeMessage = "A pending receipt finished uploading."
        } catch {
            noticeMessage = "A pending receipt finished uploading. Rainflow will refresh the attachment list next time."
        }
    }
}
