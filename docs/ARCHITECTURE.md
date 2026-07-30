# Rainflow Architecture

**Status:** Active baseline  
**Audience:** Engineering and technical product stakeholders  
**Last updated:** 2026-07-26

## 1. Purpose

This document defines the production architecture for a ledger product serving fewer than 50 users through a native iPhone client and a desktop web interface optimized for Mac. The architecture prioritizes accounting correctness, authorization, recoverability, attachment integrity, and straightforward maintenance over distributed scalability.

Product requirements are defined in [PRODUCT.md](./PRODUCT.md). Binding decisions are recorded in [DECISIONS](./DECISIONS/). UI structure and interaction rules are defined in [DESIGN_SPEC.md](./DESIGN_SPEC.md).

## 2. Architectural Principles

1. **The journal is the source of truth.** Account balances are derived from postings.
2. **The complete transaction is the write boundary.** A transaction and all postings succeed or fail together in the authoritative PostgreSQL transaction.
3. **The server is authoritative.** iPhone and web clients never write ledger tables directly.
4. **Invalid posted states are unrepresentable where practical.** Drafts may be incomplete; posted transactions may not be.
5. **Client presentation does not own accounting rules.** SwiftUI and web forms collect intent and provide fast validation; the backend revalidates every mutation.
6. **Optimistic revisions protect concurrent sessions.** Multiple browser tabs and an iPhone session may coexist without silent last-write-wins behavior.
7. **AI is outside the trusted boundary.** It proposes drafts; deterministic code validates and commits.
8. **Attachments are managed data.** Receipt files are copied into private object storage, checksummed, exported, and integrity-checked.
9. **Recovery beats premature scale.** Backups, migrations, exports, and consistency checks are first-class requirements.
10. **Complexity must be justified by current needs.** Collaboration, offline posting, event sourcing, and multi-currency transactions are deferred.

## 3. System Context

The initial system has two clients and one managed backend.

```text
Native iPhone Client                     Mac Web Client
SwiftUI                                  Responsive Web UI
GRDB cache + local drafts                Browser session state
        |                                       |
        +---------------- HTTPS API ------------+
                                |
                                v
                    Authenticated Ledger API
                    PostgreSQL functions/RPC
                                |
              +-----------------+-----------------+
              |                                   |
              v                                   v
      Authoritative PostgreSQL             Private Object Storage
      ledgers/accounts/transactions         receipt attachments
              |                                   |
              +-----------------+-----------------+
                                |
                                v
                     Backup / Integrity Jobs
                                |
                                v
                    Transactional Email Provider
```

The recommended managed backend for the MVP is Supabase: PostgreSQL as the authoritative database, email authentication, private object storage, and scheduled/server functions. Production email delivery uses a configured SMTP or transactional email provider.

The iPhone GRDB database is a cache and draft store, not an independent ledger authority. Posted mutations require connectivity in the MVP. See [ADR-003](./DECISIONS/ADR-003-StorageStrategy.md) and [ADR-005](./DECISIONS/ADR-005-ClientServer.md).

### 3.1 Native platform baseline

- Native client: iPhone only.
- Minimum deployment target: iOS 26.0.
- Build and submission SDK: latest stable iOS 26 SDK or later.
- iPad, Mac Catalyst, and native macOS targets are excluded from the MVP.
- Earlier iOS versions are not supported in the MVP; this deliberately reduces compatibility branches and QA combinations for the controlled user population.

See [ADR-001](./DECISIONS/ADR-001-SwiftUI.md).

## 4. Layered Architecture

```text
iPhone SwiftUI Views          Web Views
        |                         |
        v                         v
Screen Models / Form State   Web Form State
        |                         |
        +------ API Client -------+
                    |
                    v
          Authenticated API / RPC
                    |
                    v
        Server Application Commands
                    |
                    v
       Ledger Validation + Authorization
                    |
          +---------+---------+
          |                   |
          v                   v
Authoritative PostgreSQL   Private Object Storage
```

The accounting contract is documented once in the ADRs and implemented with defense in depth:

- Client validation gives immediate feedback.
- The authoritative server command repeats validation and authorization.
- PostgreSQL constraints and transaction-scoped verification protect persistence.

### 4.1 Presentation layer

Responsibilities:

- Render screen state on iPhone and web.
- Collect user intent.
- Format dates, amounts, and labels.
- Display validation, authorization, conflict, upload, and persistence errors.
- Present AI suggestions as untrusted draft fields.

Clients do not:

- Insert or update posting rows directly.
- Update calculated balances.
- Hold service-role credentials.
- Bypass expected-revision checks.
- Reimplement server authorization.

### 4.2 Application and API layer

Server commands coordinate authorization, domain validation, and persistence. Examples:

- `CreateTransaction`.
- `UpdateTransaction`.
- `SoftDeleteTransaction`.
- `RestoreTransaction`.
- `CreateAccount`.
- `ArchiveAccount`.
- `DeleteEmptyAccount`.
- `FinalizeAttachment`.
- `ExportLedger`.
- `RestoreBackup`.

The server application layer owns user-to-ledger authorization, stale-revision checks, transaction orchestration, idempotency, and typed public outcomes.

### 4.3 Domain rules

The domain owns:

- Money representation.
- Account types.
- Transaction and posting invariants.
- The binding ledger sign convention.
- Draft-to-posted validation.
- Transfer and split semantics.
- Archived-account rules.
- Soft-deletion behavior.

The Swift client may implement the same pure rules for immediate feedback, but client validation is never authoritative.

### 4.4 Persistence and storage layer

The backend persistence layer owns:

- PostgreSQL schema and migrations.
- Authorization and row-level security.
- Atomic ledger transactions.
- Query optimization.
- Attachment manifests and private object-storage keys.
- Backup creation and restore staging.
- Consistency and attachment-integrity diagnostics.

The iPhone infrastructure layer owns a GRDB cache, local drafts, pending attachment uploads, and cache invalidation. GRDB types do not escape into presentation or domain values.

The selected strategy is documented in [ADR-003](./DECISIONS/ADR-003-StorageStrategy.md).

## 5. Domain Model

### 5.1 Identifiers

All durable entities use stable, application-generated identifiers.

```swift
struct LedgerID: Hashable, Codable, Sendable { let rawValue: UUID }
struct AccountID: Hashable, Codable, Sendable { let rawValue: UUID }
struct TransactionID: Hashable, Codable, Sendable { let rawValue: UUID }
struct PostingID: Hashable, Codable, Sendable { let rawValue: UUID }
```

Identifiers are not derived from database row numbers or display names.

### 5.2 Money

```swift
struct Money: Equatable, Codable, Sendable {
    let minorUnits: Int64
    let currencyCode: CurrencyCode
}
```

Requirements:

- No `Double` in stored amounts or ledger arithmetic.
- Arithmetic checks overflow.
- Currency equality is required before addition.
- Display formatting occurs at the presentation boundary.

For USD, `$12.34` is represented as `1234` minor units.

### 5.3 Accounting date

The domain distinguishes:

- `accountingDate`: a date-only value used for registers and reports.
- `createdAt`: an absolute timestamp.
- `updatedAt`: an absolute timestamp.
- Optional source timestamps from banks or receipts.

The accounting date must not be represented as an arbitrary midnight `Date` whose meaning changes with timezone. A date-component value or canonical serialized local date is preferred.

### 5.4 Account

```swift
enum AccountType: String, Codable, Sendable {
    case asset
    case liability
    case equity
    case income
    case expense
}

struct Account: Identifiable, Codable, Sendable {
    let id: AccountID
    var name: String
    let type: AccountType
    var parentID: AccountID?
    var archivedAt: Date?
}
```

An account balance is not a mutable field on this entity.

### 5.5 Draft transaction

Drafts may be incomplete and are used by forms, imports, and AI suggestions.

```swift
struct DraftPosting: Sendable {
    var id: PostingID
    var accountID: AccountID?
    var amount: Money?
    var memo: String?
}

struct DraftTransaction: Sendable {
    var id: TransactionID
    var accountingDate: LocalDate?
    var description: String
    var payee: String?
    var postings: [DraftPosting]
    var expectedRevision: Int?
}
```

### 5.6 Posted transaction

Only domain validation creates a posted transaction.

```swift
struct PostedTransaction: Sendable {
    let id: TransactionID
    let accountingDate: LocalDate
    let description: String
    let payee: String?
    let postings: [Posting]
    let revision: Int
}
```

Construction fails unless all invariants pass.

## 6. Ledger Invariants

For every active posted transaction:

1. It contains at least two postings.
2. Every posting references an existing account.
3. Every posting uses the ledger currency.
4. The sum of posting minor units equals exactly zero.
5. Integer arithmetic does not overflow.
6. The transaction identifier is stable.
7. Posting identifiers are unique within the ledger.
8. An archived account may be referenced by historical postings but is not selectable for new postings without an explicit restoration or correction flow.
9. Soft-deleted transactions do not contribute to balances or reports.

Validation occurs in the domain and is reinforced by persistence constraints where practical.

## 7. Sign Convention

The following storage convention is binding throughout clients, server commands, PostgreSQL functions, reports, imports, and tests:

| Account type | Increase | Decrease |
|---|---:|---:|
| Asset | Positive | Negative |
| Expense | Positive | Negative |
| Liability | Negative | Positive |
| Equity | Negative | Positive |
| Income | Negative | Positive |

Every complete transaction sums to exactly zero in integer minor units.

The domain must not mix debit/credit labels, UI signs, and storage signs ad hoc. Report presentation may transform signs only through one centrally tested mapping component.

Examples:

```text
Expense paid from checking
Assets:Checking       -$40.00
Expenses:Dining  +$40.00
```

```text
Salary deposited into checking
Assets:Checking  +$2,500.00
Income:Salary    -$2,500.00
```

```text
Transfer from checking to savings
Assets:Checking  -$500.00
Assets:Savings   +$500.00
```

## 8. Categories, Tags, and Payees

Income and expense categories are accounts in the domain. The UI may call them categories.

- **Account:** affects balances and accounting reports.
- **Tag:** optional cross-cutting metadata.
- **Payee:** counterparty or merchant.
- **Note:** free-form text.

No reporting path should maintain a second category balance independent of postings.

## 9. Transaction Lifecycle

### 9.1 Create

1. Presentation builds a `DraftTransaction`.
2. The application use case resolves required accounts and context.
3. The domain validates and constructs a `PostedTransaction`.
4. The repository commits the header and all postings in one database transaction.
5. The use case returns the committed revision or an error.

### 9.2 Edit

Initial production behavior permits direct correction rather than reversal-only accounting.

1. The screen loads the transaction and its revision.
2. The user edits a draft.
3. The domain validates the complete replacement.
4. Persistence verifies the expected revision.
5. The header and full posting set are replaced atomically.
6. The revision increments.

A stale revision produces a conflict error and does not overwrite newer data.

The MVP stores `createdAt`, `updatedAt`, and `revision` only. A future append-only revision-history table may be added without changing transaction identifiers or aggregate update commands.

### 9.3 Delete

Deletion sets `deletedAt` on the complete transaction in one atomic write. Postings are not independently deleted through normal application code.

### 9.4 Restore

Restoring clears `deletedAt` after rechecking account and currency constraints. The restored transaction resumes contributing to balances.

### 9.5 Purge

Permanent deletion is a maintenance operation, not a normal user action. It requires explicit confirmation and a verified backup.

## 10. Transaction Boundary

The accounting transaction is the aggregate and persistence boundary.

Conceptually:

```text
BEGIN
  verify authenticated ownership
  verify idempotency key or expected revision
  validate complete transaction
  insert or update transaction
  replace all postings
  activate verified attachment manifests
  perform final aggregate verification
COMMIT
```

On any error:

```text
ROLLBACK
```

No observer, report, or account register may see an intermediate state with a transaction header and a partial posting set.

See [ADR-004](./DECISIONS/ADR-004-TransactionBoundary.md).

## 11. Balance and Reporting Queries

Balances are derived from active postings:

```text
account balance = SUM(posting.amount)
where transaction.deletedAt IS NULL
```

Required indexes include:

- `postings.account_id`.
- `postings.transaction_id`.
- `transactions.accounting_date`.
- `transactions.deleted_at`.
- Optional unique source/import identifiers.

For the expected user and data volume, derived queries are preferred over mutable cached balances. A cache may be introduced only after profiling, and it must be rebuildable from postings.

## 12. Storage Strategy

The authoritative ledger uses managed PostgreSQL. The MVP recommendation is Supabase PostgreSQL behind authenticated server functions or RPC commands. Clients do not directly mutate ledger tables.

The iPhone app uses GRDB for:

- Read-through cached accounts, transactions, and reports.
- Local form drafts.
- Pending receipt uploads.
- Last-known server revisions and synchronization cursors.

GRDB is not the authoritative source for posted transactions. The MVP requires connectivity to commit ledger mutations, which avoids offline merge and conflict complexity while preserving cached read access and draft entry.

Receipt files use private managed object storage with a PostgreSQL attachment manifest. Backup packages must include both database data and object bytes because database-provider backups do not necessarily include object storage.

See [ADR-003](./DECISIONS/ADR-003-StorageStrategy.md).

## 13. Concurrency and Multi-Session Model

### 13.1 iPhone window behavior

The native target is iPhone only and does not expose multi-window scene creation. There is one foreground app session per device, although normal background tasks may continue within platform limits.

### 13.2 Web windows and tabs

Users may open multiple browser tabs or windows. Each edit loads an expected revision and sends it with the mutation. The server rejects stale revisions instead of silently overwriting newer data.

```text
Client A loads revision 7
Client B loads revision 7
Client A saves -> revision 8
Client B saves with expected 7 -> conflict, no write
```

The conflict UI reloads the current server version and lets the user reapply the intended changes. Real-time co-editing and automatic field-level merging are not required.

### 13.3 Server writes

- PostgreSQL is the serialization authority for ledger mutations.
- Every mutation runs in a database transaction.
- Idempotency keys protect retried create requests.
- Reads may execute concurrently.
- Parsing, file processing, and AI calls occur outside the ledger transaction.
- Clients update local caches only after a successful server response or subsequent refetch.

## 14. Import Architecture

```text
External File
    |
    v
Parser
    |
    v
Normalized Import Rows
    |
    v
Duplicate Detection
    |
    v
Draft Transactions
    |
    v
User Review / Deterministic Validation
    |
    v
Serialized Atomic Commits
```

Import identifiers should be unique within a source when available. Duplicate detection must be idempotent and tested.

A large import must not block SwiftUI rendering. Parsing occurs off the main actor; commits use bounded batches while preserving one-transaction atomicity.

## 15. Receipt Attachment Architecture

Receipt attachments use a staged workflow because database rows and object bytes cannot share one physical transaction:

1. The client normalizes the image, computes a SHA-256 digest, and writes a protected local staged copy.
2. The client uploads the bytes to a private, owner-scoped, unique object key.
3. A server finalization command verifies authentication, ledger/transaction ownership, object path and existence, MIME allowlist, claimed byte size, and checksum format before activating the manifest.
4. A trusted integrity worker independently downloads active objects and verifies their actual byte size and SHA-256 digest.
5. Unfinalized/orphaned objects are removed by a trusted cleanup job.

The finalization command does not claim to hash object bytes inside PostgreSQL. Server-side byte verification, incident email delivery, and orphan cleanup are operational only after the trusted worker is implemented and tested.

A transaction remains accounting-valid if a later storage incident affects an attachment. The manifest is marked missing or corrupt, the UI displays an integrity warning, and a deduplicated email notification is sent to the verified user email by the trusted worker.

A missing iPhone cache file is not an incident; the client redownloads the authoritative object.

Backups include attachment manifests, object bytes, and checksums.

## 16. AI Trust Boundary

```text
Receipt, text, or image
        |
        v
AI Provider
        |
        v
Untrusted Suggested Fields
        |
        v
Draft Transaction
        |
        v
Deterministic Validation
        |
        v
User Confirmation
        |
        v
Standard Create/Update Use Case
```

AI output never receives direct repository access. See [AI_RULES.md](./AI_RULES.md).

## 17. Backup, Restore, and Migration

### 17.1 Schema versioning

Every database has an explicit schema version. Each migration is:

- Ordered.
- Idempotent where practical.
- Tested against a committed fixture from the previous version.
- Preceded by a backup.
- Followed by consistency checks.

### 17.2 Backup

A backup must capture a consistent authoritative database export plus every attachment object. The package includes a manifest and checksums that detect missing, substituted, or corrupted files.

### 17.3 Restore

Restores use per-ledger staging rather than replacing the shared backend database:

1. Upload the candidate package to private staging storage.
2. Validate file integrity, checksums, ownership, and supported schema.
3. Migrate the staged representation if required.
4. Run ledger and attachment consistency checks.
5. In one controlled server operation, either create a restored ledger or replace the owner's selected ledger records.
6. Preserve the prior ledger and attachment set as a rollback snapshot until post-restore verification succeeds.
7. Remove staging data after the retention window.

### 17.4 Consistency checks

At minimum:

- Every posting references an existing transaction and account.
- Every active transaction has at least two postings.
- Every active transaction sums to zero.
- Currency codes match the ledger.
- Stable identifiers are unique.
- Revisions are nonnegative.
- Attachment manifests resolve to present objects with matching size and checksum, or are explicitly marked with an integrity incident.

## 18. Error Model

Domain errors should be explicit and actionable:

```swift
enum LedgerError: Error, Sendable {
    case insufficientPostings
    case missingAccount(PostingID)
    case currencyMismatch
    case unbalanced(remainingMinorUnits: Int64)
    case arithmeticOverflow
    case archivedAccount(AccountID)
    case staleRevision(expected: Int, actual: Int)
    case duplicateImportIdentifier
    case unauthorized
    case idempotencyConflict
    case attachmentIntegrityFailure
    case persistenceFailure
}
```

Raw database errors must not leak directly into user-facing strings.

## 19. Observability

For a small private application, observability remains minimal and privacy-preserving.

Allowed operational signals:

- Migration start, success, and failure without ledger contents.
- Backup and restore success or failure.
- Error categories.
- Performance timing for slow queries without account names, payees, notes, or amounts.

Prohibited telemetry:

- Full transaction descriptions.
- Payees.
- Notes.
- Raw receipt contents.
- Database files.
- Authentication secrets.

## 20. Testing Strategy

### 20.1 Domain tests

- Balanced and unbalanced transaction construction.
- Currency mismatch rejection.
- Overflow rejection.
- Transfer neutrality for net worth.
- Expense and income sign behavior.
- Archived-account rules.
- Soft-delete inclusion and exclusion.

### 20.2 Property-based tests

Generate valid random transactions and verify:

- Posting sums remain zero.
- Create-edit-delete-restore cycles preserve expected balances.
- Ordering does not affect final balances.
- Export-import round trips preserve identifiers and amounts.

### 20.3 Persistence tests

- Partial write failure rolls back the complete transaction.
- Stale revision writes fail.
- Unique import identifiers reject duplicates.
- Queries exclude soft-deleted transactions.
- Backup snapshots are internally consistent.

### 20.4 Migration tests

Maintain fixtures for every supported schema version. Verify transaction count, posting count, identifiers, balance totals, and soft-deletion state before and after migration.

### 20.5 UI tests

Focus on critical workflows:

- Expense.
- Income.
- Transfer.
- Split transaction.
- Edit conflict handling.
- Delete and restore.
- Backup and restore.
- AI draft confirmation, when enabled.

## 21. Security Boundaries

- The backend verifies email-authenticated identity for every request.
- Row-level security and server commands enforce ledger ownership.
- The iPhone GRDB cache is limited to the application sandbox and protected with platform file security.
- Receipt storage is private and accessed with scoped, short-lived authorization.
- AI integrations receive the minimum necessary data.
- Destructive maintenance requires explicit confirmation.
- Import content is treated as untrusted input.
- All external text is escaped or safely rendered.

## 22. Deferred Architecture

The following require new ADRs before implementation:

- Fully offline posting and automatic offline conflict merging.
- Shared ledgers.
- Multi-currency transactions.
- Bank aggregation.
- Collaborative conflict resolution.
- Cached materialized balances.

## 23. Related Documents

- [Product Requirements](./PRODUCT.md)
- [AI Rules](./AI_RULES.md)
- [Roadmap](./ROADMAP.md)
- [ADR-001: SwiftUI Architecture](./DECISIONS/ADR-001-SwiftUI.md)
- [ADR-002: Double-Entry Ledger](./DECISIONS/ADR-002-DoubleEntry.md)
- [ADR-003: Storage Strategy](./DECISIONS/ADR-003-StorageStrategy.md)
- [ADR-004: Transaction Boundary](./DECISIONS/ADR-004-TransactionBoundary.md)
- [ADR-005: Client-Server and Web Access](./DECISIONS/ADR-005-ClientServer.md)
