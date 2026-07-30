import Foundation
import GRDB

struct PendingReceiptUpload: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let userID: UUID
    let ledgerID: UUID
    let transactionID: UUID
    let stagedReceipt: StagedReceipt
    let createdAt: Date
    var attemptCount: Int
    var lastError: String?
}

final class AppDatabase: @unchecked Sendable {
    private let queue: DatabaseQueue
    private init(queue: DatabaseQueue) throws {
        self.queue = queue
        try Self.migrator.migrate(queue)
    }

    static func live() throws -> AppDatabase {
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("Rainflow", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("rainflow.sqlite").path
        return try AppDatabase(queue: DatabaseQueue(path: path))
    }

    func save(snapshot: LedgerSnapshot) throws {
        let data = try Self.makeEncoder().encode(snapshot)
        try queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO cached_snapshots (ledger_id, payload, updated_at)
                VALUES (?, ?, ?)
                ON CONFLICT(ledger_id) DO UPDATE SET
                    payload = excluded.payload,
                    updated_at = excluded.updated_at
                """,
                arguments: [snapshot.ledger.id.uuidString, data, Date().timeIntervalSince1970]
            )
        }
    }

    func latestSnapshot() throws -> LedgerSnapshot? {
        try queue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT payload FROM cached_snapshots ORDER BY updated_at DESC LIMIT 1"
            ) else { return nil }
            let data: Data = row["payload"]
            return try Self.makeDecoder().decode(LedgerSnapshot.self, from: data)
        }
    }

    func enqueue(_ pending: PendingReceiptUpload) throws {
        let data = try Self.makeEncoder().encode(pending)
        try queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO pending_receipt_uploads (id, payload, created_at, attempt_count, last_error)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    payload = excluded.payload,
                    attempt_count = excluded.attempt_count,
                    last_error = excluded.last_error
                """,
                arguments: [
                    pending.id.uuidString,
                    data,
                    pending.createdAt.timeIntervalSince1970,
                    pending.attemptCount,
                    pending.lastError
                ]
            )
        }
    }

    func pendingReceiptUploads() throws -> [PendingReceiptUpload] {
        try queue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT payload FROM pending_receipt_uploads ORDER BY created_at ASC"
            )
            return try rows.map { row in
                let data: Data = row["payload"]
                return try Self.makeDecoder().decode(PendingReceiptUpload.self, from: data)
            }
        }
    }

    func removePendingReceiptUpload(id: UUID) throws {
        try queue.write { db in
            try db.execute(
                sql: "DELETE FROM pending_receipt_uploads WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    func removeAllUserData() throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM cached_snapshots")
            try db.execute(sql: "DELETE FROM pending_receipt_uploads")
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_cache_and_receipts") { db in
            try db.execute(sql: """
                CREATE TABLE cached_snapshots (
                    ledger_id TEXT PRIMARY KEY NOT NULL,
                    payload BLOB NOT NULL,
                    updated_at DOUBLE NOT NULL
                );

                CREATE TABLE pending_receipt_uploads (
                    id TEXT PRIMARY KEY NOT NULL,
                    payload BLOB NOT NULL,
                    created_at DOUBLE NOT NULL,
                    attempt_count INTEGER NOT NULL DEFAULT 0,
                    last_error TEXT
                );

                CREATE INDEX pending_receipt_created_idx
                    ON pending_receipt_uploads(created_at);
                """)
        }
        return migrator
    }
}
