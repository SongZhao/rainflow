# Rainflow Product Requirements

**Status:** Active baseline  
**Audience:** Product, design, engineering, QA  
**Last updated:** 2026-07-26

## 1. Product Summary

Rainflow is a private personal-bookkeeping product for a small, known user group of fewer than 50 people. It provides a native iPhone application and a desktop web interface optimized for use on Mac. Both clients operate on one authenticated, server-authoritative double-entry ledger while presenting familiar personal-finance language.

The product prioritizes:

1. Accounting correctness.
2. Fast and understandable transaction entry.
3. Reliable access from iPhone and Mac web browsers.
4. Recoverability, attachment integrity, and user-controlled exports.
5. Maintainable implementation over large-scale infrastructure.
6. Assistive AI that proposes entries but never bypasses deterministic validation or user review.

The technical design is defined in [ARCHITECTURE.md](./ARCHITECTURE.md). Binding implementation decisions are recorded in [DECISIONS](./DECISIONS/). The user experience and visual system are defined in [DESIGN_SPEC.md](./DESIGN_SPEC.md).

## 2. Target Users and Operating Assumptions

- Fewer than 50 total users.
- One person normally owns and edits each ledger.
- Users sign up and verify an email address.
- The supported native client is iPhone only, with a minimum deployment target of iOS 26.0.
- A responsive web client provides the Mac interface and may also function in other supported desktop browsers.
- The authoritative ledger is stored in a managed backend so the iPhone and web clients share one consistent state.
- Real-time collaborative editing is not required.
- Multiple browser tabs or client sessions may be open; optimistic revision checks prevent stale overwrites.
- The iPhone app does not provide a user-facing multi-window feature.
- Each ledger selects one currency at creation. The currency cannot change after the first posted transaction.
- The initial supported currency allowlist is USD, CAD, EUR, GBP, JPY, and AUD. Adding another single-ledger currency is not a schema change when its minor-unit scale is defined.
- The first release uses en-US interface conventions while formatting amounts with the ledger's selected currency.

These constraints favor a small, reliable client-server architecture over distributed collaboration or complex offline conflict resolution.

## 3. Goals

### 3.1 Core goals

- Record balanced transactions without exposing accounting jargon unnecessarily.
- Show trustworthy account balances derived from ledger postings.
- Support common personal-finance workflows: expense, income, transfer, opening balance, and split transaction.
- Permit safe transaction correction and recoverable deletion.
- Allow users to export and restore their data.
- Provide AI-assisted transaction drafting with clear provenance and confirmation.

### 3.2 Quality goals

- No partially saved transaction may become visible.
- No posted transaction may be unbalanced.
- No independently editable balance may exist outside the posting journal.
- A failed write must leave the ledger unchanged.
- A migration or restore must be verifiable before the active store is replaced.
- The domain model must be testable without SwiftUI or a database.

## 4. Non-Goals for the Initial Release

The following are explicitly deferred:

- Real-time collaborative editing of one ledger.
- Shared household or team ledgers.
- Posting ledger mutations while fully offline.
- Automatic bank connections.
- Transactions containing more than one currency.
- Automatic currency conversion or exchange-rate accounting.
- Event sourcing or CQRS.
- Microservices.
- AI-initiated posting without explicit user confirmation.
- Performance optimization for millions of postings.
- A native iPad or Mac application.
- User-facing multi-window support in the iPhone app.

See [ROADMAP.md](./ROADMAP.md) for sequencing and reconsideration criteria.

## 5. Product Language

The interface may use familiar labels while the domain remains accounting-correct.

| UI term | Domain meaning |
|---|---|
| Account | Asset, liability, equity, income, or expense account |
| Category | Presentation name for an income or expense account |
| Transfer | One transaction with postings to two balance-sheet accounts |
| Split | One transaction with three or more postings |
| Balance | Sum of active postings for an account |
| Delete | Recoverable soft deletion of the complete transaction |
| AI suggestion | Untrusted draft data requiring deterministic validation and user review |

Tags, payees, and notes are metadata and do not replace accounts.

## 6. Core Domain Concepts

### 6.1 Ledger

A ledger has:

- A stable identifier.
- An owning user identifier.
- A name.
- One selected currency code.
- A schema version.
- Creation and update timestamps.

A ledger contains accounts, transactions, and attachment manifests.

### 6.2 Account

An account belongs to one of these types:

- Asset.
- Liability.
- Equity.
- Income.
- Expense.

Accounts referenced by historical postings cannot be hard-deleted through normal product flows. Users may archive them, which prevents new selection while preserving history.

The setup flow automatically creates this initial template. The top-level labels are account-type groups in the UI; every indented account is created as a posting account:

```text
Assets
  Checking
  Savings
  Cash

Liabilities
  Credit Card

Income
  Salary
  Other Income

Expenses
  Groceries
  Dining
  Transportation
  Housing
  Utilities
  Shopping
  Healthcare
  Entertainment
  Other Expenses

Equity
  Opening Balances
```

No template account is name-protected or permanently system-protected. Stable identifiers, not names, are used for references. An empty account may be hard-deleted only after two distinct confirmations; an account with postings may only be archived.

### 6.3 Transaction

A transaction is the atomic accounting unit. It contains:

- A stable identifier.
- An accounting date.
- A description.
- Optional payee, note, tags, source, and import identifier.
- Two or more postings.
- Zero or more attachment manifests.
- Creation and update timestamps.
- A revision number.
- Optional soft-deletion metadata.

### 6.4 Posting

A posting contains:

- A stable identifier.
- Its parent transaction identifier.
- An account identifier.
- A signed amount in integer minor units.
- The ledger currency code.
- Optional memo metadata.

The sum of all posting amounts in an active transaction must equal zero.

### 6.5 Receipt attachment

A receipt attachment contains:

- A stable identifier.
- Its parent transaction identifier.
- A private managed-storage object key.
- Original file name and MIME type.
- Byte size and SHA-256 checksum.
- Upload and integrity status.
- Creation and update timestamps.

Receipt files are copied into application-managed private storage. The product does not rely on an external file reference remaining available.

## 7. Money and Currency Requirements

- Stored monetary values use signed 64-bit integer minor units.
- `Double` and binary floating-point values are prohibited for stored money and ledger arithmetic.
- Each posting stores or inherits an explicit ISO currency code.
- Every posting in one ledger uses that ledger's selected currency.
- The selected currency becomes immutable after the first posted transaction.
- Currency metadata defines the allowed minor-unit scale; the implementation must not assume every currency has two decimal places.
- Display formatting is presentation-only and must not affect stored values.
- Arithmetic must detect integer overflow and fail safely.
- Rounding occurs only at defined import or conversion boundaries, not during ordinary ledger summation.
- Multi-currency transactions and automatic conversion are deferred.

Example: `$12.34` is stored as `1234` minor units for USD.

See [ADR-002: Double-Entry Ledger](./DECISIONS/ADR-002-DoubleEntry.md).

## 8. Functional Requirements

### 8.1 Ledger setup

Users can:

- Create a ledger.
- Choose its currency before transactions exist.
- Automatically create the complete default account template defined in Section 6.2.
- Add an optional opening balance.

An opening balance is stored as a normal balanced transaction against the default `Equity:Opening Balances` account; it is not stored as an account property. If that empty default account was previously deleted, the flow requires the user to select or create an equity account before posting.

### 8.2 Account management

Users can:

- Create accounts.
- Rename any account, including accounts from the default template.
- Reorder or group accounts for presentation.
- Archive and restore accounts.
- View balances and posting history.
- Hard-delete an account only when it has no postings and after two distinct confirmations.

The two-confirmation hard-delete flow must include:

1. A first request that displays an irreversible-action warning and obtains a short-lived deletion challenge.
2. A second deliberate confirmation that submits the challenge and typed account name.

The server still verifies that the account has no postings at final confirmation time.

Users cannot:

- Hard-delete an account that has postings.
- Directly type or overwrite a calculated balance.
- Change an account type after postings exist unless a validated migration operation supports it.

### 8.3 Expense entry

The interface collects:

- Amount.
- Payment account.
- Expense category.
- Accounting date.
- Optional payee, note, tags, and one or more receipt attachments.

The application creates one balanced transaction, for example:

```text
Assets:Checking       -$40.00
Expenses:Dining  +$40.00
```

### 8.4 Income entry

The interface collects:

- Amount.
- Deposit account.
- Income category.
- Accounting date.
- Optional payer, note, tags, and source information.

### 8.5 Transfer entry

A transfer is one transaction, not two linked records.

Example:

```text
Assets:Checking  -$500.00
Assets:Savings   +$500.00
```

Credit-card payments and cash withdrawals use the same transfer model, with fees or interest represented by additional expense postings when applicable.

### 8.6 Split transactions

Users can allocate one amount across multiple categories or accounts. The final transaction must balance exactly before posting.

The UI must show:

- Entered total.
- Allocated total.
- Remaining amount.
- Clear validation when the remaining amount is nonzero.

### 8.7 Editing

Users may edit a transaction. Saving an edit must:

- Validate the complete replacement transaction.
- Atomically replace the transaction header and all postings on the authoritative backend.
- Increment the revision.
- Preserve stable import/source identifiers when appropriate.
- Reject a stale edit when the stored revision changed after the screen loaded.

The MVP stores `createdAt`, `updatedAt`, and `revision`; it does not retain a snapshot of every prior transaction version. This is not a one-way architectural decision: stable transaction identifiers, aggregate update commands, and explicit revisions allow a future append-only revision-history table to be added without changing the journal model.

### 8.8 Deletion and recovery

Deleting a transaction must soft-delete the entire transaction. Individual postings cannot be deleted through product flows.

A deleted transaction:

- No longer affects balances or reports.
- Remains recoverable.
- Retains its source and audit metadata.

A maintenance operation may permanently purge deleted records after a documented retention period and confirmed backup.

### 8.9 Search and filtering

Users can filter transaction history by:

- Date range.
- Account.
- Category.
- Payee.
- Tag.
- Amount range.
- Source or import status.

### 8.10 Reports

Initial reports include:

- Account balances.
- Net worth.
- Income and expenses by period.
- Spending by category.
- Account register.

Reports must use postings as the canonical source and exclude soft-deleted transactions.

### 8.11 Import

The application may import CSV or structured files after the core ledger is stable.

Imports must:

- Parse outside the trusted ledger boundary.
- Produce draft transactions.
- Detect likely duplicates using source identifiers and deterministic matching rules.
- Require validation before commit.
- Commit each transaction atomically.
- Return a clear import summary with accepted, skipped, duplicate, and failed rows.

### 8.12 Receipt attachments

Receipt images are included in the initial release.

Requirements:

- The selected image is copied into private application-managed object storage.
- The original external file reference is not the durable source.
- Each stored object has a manifest with size, MIME type, and SHA-256 checksum.
- Attachment upload and ledger commit follow the consistency workflow in [ADR-004](./DECISIONS/ADR-004-TransactionBoundary.md).
- A missing local iPhone cache is silently re-downloaded and is not considered data loss.
- A missing or checksum-invalid authoritative object creates an integrity incident, shows an in-app warning, and sends one deduplicated email notification to the verified account email.
- Attachment failure must not make a balanced ledger transaction unbalanced or partially written.

### 8.13 Export, backup, and restore

Users can export a portable package containing documented data representations, including:

- `metadata.json`.
- `accounts.csv`.
- `transactions.csv`.
- `postings.csv`.
- `attachments.json`.
- All receipt attachment files.
- Checksums covering the database export and every attachment.

Before schema migration or restore, the system creates a backup.

Restore must:

1. Validate package structure, checksums, and schema compatibility.
2. Import into staging storage.
3. Run ledger and attachment consistency checks.
4. Replace or merge into the authoritative store only after successful validation.
5. Preserve the previous recoverable state until post-restore verification succeeds.

### 8.14 AI-assisted entry

AI may suggest fields from a receipt, message, or user instruction. It may not directly mutate the ledger.

The UI must distinguish:

- AI-suggested values.
- User-confirmed values.
- Missing or uncertain values.

Every AI-generated draft passes deterministic validation and user confirmation before commit. Full rules are in [AI_RULES.md](./AI_RULES.md).


## 9. Data Integrity Requirements

For every active transaction:

- It contains at least two postings.
- Every account exists.
- Every posting uses the ledger currency.
- Posting amounts sum exactly to zero in integer minor units.
- No posting amount overflows supported integer arithmetic.
- The transaction and all postings are written or replaced atomically.

For every displayed account balance:

- The value is derived from active postings.
- Archived accounts remain included in historical reporting.
- Soft-deleted transactions are excluded.

See [ADR-004: Transaction Boundary](./DECISIONS/ADR-004-TransactionBoundary.md).

## 10. Privacy and Security

- Every user authenticates with a verified email address.
- Email one-time-code or magic-link authentication is preferred for the initial release.
- Each ledger and attachment is private to its owner unless a future sharing feature is explicitly introduced.
- Server authorization and row-level policies must prevent cross-user access.
- Receipt objects are stored in private buckets and accessed with short-lived authorization.
- The application minimizes collection of personal data.
- AI requests use only the data required for the current suggestion.
- Secrets, credentials, raw database files, and unrelated receipts must not be included in telemetry.
- Backups are protected in transit and at rest.
- Destructive maintenance actions require explicit confirmation.
- Production email delivery uses a configured transactional email provider rather than development-only email service.

## 11. Accessibility and Usability

- Core workflows must support Dynamic Type.
- Controls require accessible labels and logical focus order.
- Amount meaning cannot depend on color alone.
- Positive and negative values must use consistent labels and signs.
- Transaction validation errors must explain how to resolve the problem.
- Common entry flows should be usable without knowledge of debits and credits.

## 12. Release Boundaries and Acceptance Criteria

### 12.1 First usable release: internal alpha

The first usable release includes:

- Verified-email sign-up and sign-in.
- Native iPhone client distributed through TestFlight.
- Mac web interface for the same ledger.
- Automatic creation of the complete default account template.
- Ledger creation with a supported single currency.
- Expense, income, transfer, and opening-balance entry.
- Transaction list, details, editing, soft deletion, and restoration.
- Optimistic revision conflict handling across tabs and clients.
- Receipt image capture/upload into private application storage.
- A basic export containing ledger data and attachments.
- Domain invariant, authorization, atomic-write, and rollback tests.

### 12.2 Beta release

Beta adds:

- Split transactions.
- Search and filtering.
- Account register and initial reports.
- Verified backup and restore.
- Attachment integrity scans and deduplicated email notifications.
- Accessibility and production email-delivery review.

### 12.3 Production release gate

The production release is ready when:

- Domain invariant tests pass.
- Server-side atomic write and rollback tests pass.
- Authorization tests prove one user cannot access another user's ledger or attachments.
- Migration fixtures pass from every supported schema version.
- Users can create, edit, delete, restore, and search transactions on supported clients.
- Expense, income, transfer, opening balance, and split workflows are complete.
- Account balances and reports reconcile with posting totals.
- Export and verified restore include all receipt attachments.
- Attachment integrity incidents create in-app and email notifications without exposing file contents.
- AI, if included, only produces reviewable drafts.
- No client directly writes posting rows or mutable balances.

## 13. Related Documents

- [Architecture](./ARCHITECTURE.md)
- [AI Rules](./AI_RULES.md)
- [Roadmap](./ROADMAP.md)
- [ADR-001: SwiftUI Architecture](./DECISIONS/ADR-001-SwiftUI.md)
- [ADR-002: Double-Entry Ledger](./DECISIONS/ADR-002-DoubleEntry.md)
- [ADR-003: Storage Strategy](./DECISIONS/ADR-003-StorageStrategy.md)
- [ADR-004: Transaction Boundary](./DECISIONS/ADR-004-TransactionBoundary.md)
- [ADR-005: Client-Server and Web Access](./DECISIONS/ADR-005-ClientServer.md)
