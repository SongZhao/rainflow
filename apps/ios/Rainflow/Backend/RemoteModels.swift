import Foundation
import RainflowDomain

struct LedgerRecord: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let ownerUserID: UUID
    let name: String
    let currencyCode: String
    let ledgerType: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserID = "owner_user_id"
        case name
        case currencyCode = "currency_code"
        case ledgerType = "ledger_type"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var currency: CurrencyCode? { CurrencyCode(rawValue: currencyCode) }
    var displayType: String { ledgerType == "shared" ? "Shared" : "Personal" }
}

enum LedgerKindOption: String, CaseIterable, Identifiable, Codable, Sendable {
    case personal
    case shared

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal: "Personal"
        case .shared: "Shared"
        }
    }

    var subtitle: String {
        switch self {
        case .personal: "Only you can access it"
        case .shared: "You can invite others from the web app"
        }
    }
}

struct AccountRecord: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let ledgerID: UUID
    let name: String
    let type: AccountType
    let parentID: UUID?
    let displayOrder: Int
    let archivedAt: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case ledgerID = "ledger_id"
        case name
        case type
        case parentID = "parent_id"
        case displayOrder = "display_order"
        case archivedAt = "archived_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct PostingRecord: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let transactionID: UUID
    let accountID: UUID
    let amountMinorUnits: Int64
    let currencyCode: String
    let memo: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case transactionID = "transaction_id"
        case accountID = "account_id"
        case amountMinorUnits = "amount_minor_units"
        case currencyCode = "currency_code"
        case memo
        case createdAt = "created_at"
    }
}

struct TransactionRecord: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let ledgerID: UUID
    let accountingDate: String
    let description: String
    let payee: String?
    let note: String?
    let source: String?
    let importIdentifier: String?
    let revision: Int
    let deletedAt: String?
    let createdAt: String
    let updatedAt: String
    let postings: [PostingRecord]

    enum CodingKeys: String, CodingKey {
        case id
        case ledgerID = "ledger_id"
        case accountingDate = "accounting_date"
        case description
        case payee
        case note
        case source
        case importIdentifier = "import_identifier"
        case revision
        case deletedAt = "deleted_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case postings
    }
}

struct AttachmentRecord: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let ledgerID: UUID
    let transactionID: UUID?
    let objectKey: String
    let originalFileName: String
    let mimeType: String
    let byteSize: Int64
    let sha256Hex: String
    let status: String
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case ledgerID = "ledger_id"
        case transactionID = "transaction_id"
        case objectKey = "object_key"
        case originalFileName = "original_file_name"
        case mimeType = "mime_type"
        case byteSize = "byte_size"
        case sha256Hex = "sha256_hex"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct LedgerSnapshot: Codable, Equatable, Sendable {
    let ledger: LedgerRecord
    let accounts: [AccountRecord]
    let transactions: [TransactionRecord]
    let attachments: [AttachmentRecord]
    let cachedAt: Date

    init(
        ledger: LedgerRecord,
        accounts: [AccountRecord],
        transactions: [TransactionRecord],
        attachments: [AttachmentRecord] = [],
        cachedAt: Date = .now
    ) {
        self.ledger = ledger
        self.accounts = accounts.sorted {
            if $0.displayOrder == $1.displayOrder { return $0.name < $1.name }
            return $0.displayOrder < $1.displayOrder
        }
        self.transactions = transactions.sorted {
            if $0.accountingDate == $1.accountingDate { return $0.createdAt > $1.createdAt }
            return $0.accountingDate > $1.accountingDate
        }
        self.attachments = attachments
        self.cachedAt = cachedAt
    }
}

struct CommandResult: Codable, Equatable, Sendable {
    let id: UUID
    let revision: Int
    let deleted: Bool?
}

struct PostingPayload: Codable, Sendable {
    let id: UUID
    let accountID: UUID
    let amountMinorUnits: Int64
    let currencyCode: String
    let memo: String?

    enum CodingKeys: String, CodingKey {
        case id
        case accountID = "account_id"
        case amountMinorUnits = "amount_minor_units"
        case currencyCode = "currency_code"
        case memo
    }

    init(posting: Posting) {
        id = posting.id
        accountID = posting.accountID
        amountMinorUnits = posting.amount.minorUnits
        currencyCode = posting.amount.currency.rawValue
        memo = posting.memo
    }
}

struct CreateLedgerParameters: Codable, Sendable {
    let ledgerName: String
    let ledgerCurrency: String

    enum CodingKeys: String, CodingKey {
        case ledgerName = "ledger_name"
        case ledgerCurrency = "ledger_currency"
    }
}

struct CreateLedgerWithTypeParameters: Codable, Sendable {
    let ledgerName: String
    let ledgerCurrency: String
    let ledgerKind: String

    enum CodingKeys: String, CodingKey {
        case ledgerName = "ledger_name"
        case ledgerCurrency = "ledger_currency"
        case ledgerKind = "ledger_kind"
    }
}

struct CreateTransactionParameters: Codable, Sendable {
    let ledgerID: UUID
    let transactionID: UUID
    let idempotencyKey: UUID
    let accountingDate: String
    let description: String
    let payee: String
    let note: String
    let postings: [PostingPayload]

    enum CodingKeys: String, CodingKey {
        case ledgerID = "p_ledger_id"
        case transactionID = "p_transaction_id"
        case idempotencyKey = "p_idempotency_key"
        case accountingDate = "p_accounting_date"
        case description = "p_description"
        case payee = "p_payee"
        case note = "p_note"
        case postings = "p_postings"
    }
}

struct UpdateTransactionParameters: Codable, Sendable {
    let ledgerID: UUID
    let transactionID: UUID
    let expectedRevision: Int
    let accountingDate: String
    let description: String
    let payee: String
    let note: String
    let postings: [PostingPayload]

    enum CodingKeys: String, CodingKey {
        case ledgerID = "p_ledger_id"
        case transactionID = "p_transaction_id"
        case expectedRevision = "p_expected_revision"
        case accountingDate = "p_accounting_date"
        case description = "p_description"
        case payee = "p_payee"
        case note = "p_note"
        case postings = "p_postings"
    }
}

struct TransactionRevisionParameters: Codable, Sendable {
    let ledgerID: UUID
    let transactionID: UUID
    let expectedRevision: Int

    enum CodingKeys: String, CodingKey {
        case ledgerID = "p_ledger_id"
        case transactionID = "p_transaction_id"
        case expectedRevision = "p_expected_revision"
    }
}

struct FinalizeAttachmentParameters: Codable, Sendable {
    let ledgerID: UUID
    let transactionID: UUID
    let attachmentID: UUID
    let objectKey: String
    let originalFileName: String
    let mimeType: String
    let byteSize: Int64
    let sha256Hex: String

    enum CodingKeys: String, CodingKey {
        case ledgerID = "p_ledger_id"
        case transactionID = "p_transaction_id"
        case attachmentID = "p_attachment_id"
        case objectKey = "p_object_key"
        case originalFileName = "p_original_file_name"
        case mimeType = "p_mime_type"
        case byteSize = "p_byte_size"
        case sha256Hex = "p_sha256_hex"
    }
}
