# ADR-003: Authoritative Storage, GRDB Cache, and Attachments

**Status:** Accepted  
**Date:** 2026-07-26  
**Decision owners:** Engineering

## Context

Rainflow serves fewer than 50 users through an iPhone client and a Mac web interface. Both clients must see one consistent ledger. The product also requires verified-email authentication, private receipt storage, email notifications for authoritative attachment loss, backups that include attachments, and atomic double-entry writes.

A local-only SQLite database cannot be the sole authority once a web client accesses the same ledger. Conversely, making each client an independent authority would require offline merge and distributed conflict-resolution complexity that is not justified for the MVP.

## Decision

Use this storage model:

1. **Supabase PostgreSQL is the authoritative ledger database.**
2. **All ledger mutations execute through authenticated PostgreSQL functions/RPC or an equivalent trusted server command layer.** Clients do not directly write transaction or posting rows.
3. **Supabase Auth provides verified-email identity** using email OTP or magic links for the MVP.
4. **Supabase private Storage holds receipt objects.** PostgreSQL stores attachment manifests and ownership metadata.
5. **GRDB is the iPhone cache and draft store.** It stores cached server data, local drafts, pending uploads, and synchronization metadata, but it is not an independent posted-ledger authority.
6. **Posted mutations require connectivity in the MVP.** Offline users may browse cached data and prepare drafts; automatic offline posting and merge are deferred.
7. **Production email delivery uses configured custom SMTP or another transactional email provider.**

This choice is provider-specific for speed of delivery but isolated behind API, repository, attachment, and authentication adapters so it is not a domain dependency.

## Rationale

- PostgreSQL provides explicit transactions, constraints, functions, indexes, and revision-safe updates.
- Supabase combines PostgreSQL, email authentication, private object storage, and scheduled/server functions without building a custom operations platform.
- GRDB is a mature Swift SQLite toolkit with migrations, transactions, observations, and concurrency support suitable for a local iPhone cache.
- Requiring connectivity for commits removes the hardest offline conflict paths while retaining useful cached reads and drafts.
- The expected user count does not justify microservices, Kafka, CRDTs, or a custom synchronization engine.

## Authoritative Schema Direction

### Users and ledgers

- Auth user identifier.
- Ledger `id`, `owner_user_id`, `name`, and `currency_code`.
- Creation and update timestamps.

### Accounts

- `id`.
- `ledger_id`.
- `name`.
- `type`.
- `parent_id`.
- `archived_at`.
- Creation and update timestamps.

### Transactions

- `id`.
- `ledger_id`.
- `accounting_date`.
- Description, payee, and note.
- Optional source and import identifier.
- `revision`.
- `deleted_at`.
- Creation and update timestamps.

### Postings

- `id`.
- `transaction_id`.
- `account_id`.
- `amount_minor_units`.
- `currency_code`.
- Optional memo.

### Attachment manifests

- `id`.
- `ledger_id` and `transaction_id`.
- Private object-storage key.
- Original file name and MIME type.
- Byte size and SHA-256 checksum.
- Status: temporary, active, missing, corrupt, or deleted.
- Notification incident identifier and notification timestamp.
- Creation and update timestamps.

### Optional future tables

- Tags and transaction-tag links.
- Import batches.
- Append-only transaction revision history.
- Integrity incident history.

The MVP does not store a snapshot of every transaction version.

## Server Mutation Boundary

Every ledger mutation runs in one PostgreSQL transaction and verifies:

- Authenticated user ownership.
- Expected transaction revision where applicable.
- Idempotency key for creates.
- Referenced accounts.
- Account eligibility.
- Ledger currency and minor-unit scale.
- At least two postings.
- Exact zero sum.
- Unique stable identifiers.

A client receives a committed result only after the server transaction succeeds.

## Authorization

- Row-level security denies cross-user reads and writes.
- Clients use publishable credentials and user sessions only.
- Service-role credentials exist only in trusted server or scheduled-job environments.
- Ledger mutation functions independently verify ownership even when row-level security is enabled.
- Private attachment objects are accessed with authenticated or short-lived signed requests.

## GRDB iPhone Cache

GRDB stores:

- Cached ledger, account, transaction, posting, and report projections.
- Local form drafts.
- Pending attachment-upload metadata and local temporary file locations.
- Last fetched revisions and synchronization cursor.
- Retry metadata for idempotent requests.

GRDB does not:

- Authoritatively post transactions.
- Generate a committed revision.
- Resolve server conflicts by last-write-wins.
- Hold service-role credentials.

On successful mutation, the client applies the returned server representation or refetches it. On failure, the posted cache remains unchanged while the user draft is preserved.

## Account Deletion

An empty account may be hard-deleted only through a two-command server flow:

1. `RequestAccountDeletion` verifies ownership and returns a short-lived single-use challenge.
2. `ConfirmAccountDeletion` requires that challenge plus the typed current account name, then rechecks that no postings reference the account before deletion.

A UI-only double dialog is insufficient as the sole enforcement mechanism.

Accounts with postings cannot be hard-deleted and may only be archived.

## Attachment Storage Workflow

1. The client normalizes the image, computes its SHA-256 digest, and writes a protected local staged copy.
2. The client uploads the receipt bytes to a private, owner-scoped, unique object key.
3. The finalization command verifies authentication, ledger and transaction ownership, object path/existence, MIME allowlist, claimed size, and checksum format before activating the manifest.
4. A trusted worker later downloads active objects and verifies their actual size and SHA-256 digest.
5. Objects not finalized within the retention window are deleted by a trusted cleanup job.

Object bytes are outside the PostgreSQL transaction, so manifest status must never claim an active attachment before the finalization checks pass. The PostgreSQL finalizer does not independently hash Storage bytes; actual-byte verification belongs to the trusted worker. Accounting validity does not depend on the continued presence of an attachment.

## Attachment Integrity and Email Notification

A scheduled integrity job and on-demand retrieval failures check active manifests.

When an authoritative object is absent or checksum-invalid:

- Mark the manifest missing or corrupt.
- Create or update one deduplicated integrity incident.
- Show an in-app warning.
- Send one email notification to the verified user email for that incident.
- Do not expose receipt content in the email.
- Do not alter transaction postings or balances.

A missing local GRDB/cache file is repaired by redownload and does not trigger an email.

## Indexes

At minimum:

- `accounts(ledger_id, archived_at)`.
- `transactions(ledger_id, accounting_date)`.
- `transactions(ledger_id, deleted_at)`.
- `postings(account_id)`.
- `postings(transaction_id)`.
- `attachments(transaction_id)`.
- `attachments(status)`.
- Unique source/import identifier where the source guarantees uniqueness.
- Unique idempotency key scoped to user or ledger.

Additional indexes require measured query need.

## Backup and Restore

Provider database backups are not sufficient by themselves because receipt objects are stored separately.

The application export/backup package includes:

- Ledger metadata.
- Accounts, transactions, and postings.
- Attachment manifests.
- Every receipt object.
- Checksums for all files and exported records.
- Schema and application version metadata.

Restore uses staging, validates all checksums and ledger invariants, and does not replace active data until verification passes.

## Migrations

- Every schema change has an ordered migration.
- Migrations are tested against committed fixtures.
- Server migrations and GRDB cache migrations are versioned independently.
- A cache migration failure may rebuild the cache from the server without data loss.
- An authoritative migration failure must preserve a recoverable pre-migration state.
- Migration tests verify transaction counts, posting counts, identifiers, revisions, soft-deletion state, and attachment manifests.

## Consequences

### Positive

- iPhone and web share one consistent authority.
- Atomic accounting writes are explicit and testable.
- Email identity and private attachment storage are available without a custom platform.
- GRDB supports fast iPhone reads and durable drafts.
- Offline merge complexity is deferred.

### Negative

- Posted mutations require network connectivity.
- The product now depends operationally on a managed backend and email provider.
- Database and object-storage backups require an application-level combined export.
- Cache synchronization and attachment staging add implementation work.

### Neutral

- Supabase is an infrastructure choice, not a domain model. Adapters preserve a future migration path.

## Rejected Alternatives

### GRDB or SQLite as the only authority

Rejected because the web interface needs the same ledger and independent client authorities require conflict merging.

### Direct client writes to ledger tables

Rejected because clients could bypass aggregate validation, idempotency, and command-level authorization.

### Full offline mutation synchronization

Deferred because it introduces conflict resolution, tombstones, duplicate handling, and attachment reconciliation disproportionate to the MVP.

### Custom backend from the start

Rejected because the user count and feature set do not justify operating bespoke authentication, database, object storage, and email infrastructure.

### Mutable balance columns

Rejected because balances can diverge from postings.

## Reconsideration Triggers

Revisit this decision if:

- The managed provider cannot satisfy required security or data-residency needs.
- Offline posting becomes a demonstrated requirement.
- Storage or email cost becomes material.
- The app requires shared-ledger concurrent editing.
- Provider limitations prevent verified combined backups or safe migrations.

## Related Decisions and Requirements

- [Product Requirements](../PRODUCT.md)
- [Architecture](../ARCHITECTURE.md)
- [AI Rules](../AI_RULES.md)
- [ADR-001: iPhone SwiftUI Architecture](./ADR-001-SwiftUI.md)
- [ADR-002: Double-Entry Ledger](./ADR-002-DoubleEntry.md)
- [ADR-004: Transaction Boundary](./ADR-004-TransactionBoundary.md)
- [ADR-005: Client-Server and Web Access](./ADR-005-ClientServer.md)
