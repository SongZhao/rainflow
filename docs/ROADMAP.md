# Rainflow Roadmap

**Status:** Active plan  
**Audience:** Product, design, engineering, QA  
**Last updated:** 2026-07-26

## Approved First-Pass Implementation

The first implementation baseline includes:

- iPhone custom bottom navigation with Dashboard, Accounts, center Capture action, Transactions, and Reports.
- Receipt capture from camera or photo library plus manual entry.
- Dashboard, account, transaction, and report screens using the Rainflow design tokens.
- A Next.js Mac web shell with matching information architecture.
- An iPhone Supabase adapter for authenticated reads and atomic transaction creation.
- A GRDB snapshot cache and durable pending-receipt queue.
- Supabase migrations for authoritative ledger entities, private receipt policies, and atomic transaction commands.
- The Mac web client uses the shared Supabase authority for authentication, ledger reads, transaction writes, and receipt upload/viewing.

This baseline proves the iPhone interaction model and authority boundary in source. It is not declared release-complete until the Xcode build and Supabase migrations pass in real development environments.

## 1. Roadmap Principles

1. Correctness and authorization precede interface breadth.
2. The authoritative server mutation path is implemented before either client can post transactions.
3. The iPhone and web clients share API contracts and acceptance tests.
4. GRDB is a cache and draft store, not a competing ledger authority.
5. Receipt storage, backup, and integrity are product requirements, not optional polish.
6. AI and bank import do not block the first usable release.
7. Work is sized for fewer than 50 users; avoid distributed-system machinery without demonstrated need.

## 2. Phase 0: Decision Baseline — Complete

Decisions now accepted:

- Native target: iPhone only.
- Minimum deployment target: iOS 26.0; development and submission use the latest stable iOS 26 SDK or later.
- Mac experience: responsive web interface.
- Native multi-window scenes: not supported.
- Browser tabs/windows: supported with stale-revision rejection.
- Beta distribution: TestFlight.
- Stable limited distribution: unlisted App Store by default; Apple Business Manager Custom App only when all users fit one organization.
- Authoritative backend: Supabase PostgreSQL.
- Authentication: verified email using OTP or magic link.
- Production email: custom SMTP or transactional provider.
- iPhone local data: GRDB cache, drafts, and pending uploads.
- Ledger writes: authenticated server functions/RPC with PostgreSQL transactions.
- Currency: one selected currency per ledger; initial allowlist USD, CAD, EUR, GBP, JPY, AUD.
- Binding sign convention: [ADR-002](./DECISIONS/ADR-002-DoubleEntry.md).
- Default account template: all accounts in [PRODUCT.md](./PRODUCT.md) Section 6.2 are created automatically.
- Account deletion: empty accounts require two confirmations; accounts with postings are archive-only.
- Receipt images: included in the first usable release, copied to private managed storage, included in exports and backups.
- Audit history: `createdAt`, `updatedAt`, and `revision` in MVP; append-only revision history remains a future-compatible extension.

### Remaining setup choices that do not block implementation

- Hosting integration for the accepted Next.js web client.
- Transactional email vendor.
- Exact supported Safari/browser version matrix.

## 3. Phase 1: Shared Contracts and Pure Ledger Rules

### Scope

- Stable identifiers.
- `Money` using `Int64` minor units and explicit currency metadata.
- Supported currency allowlist and scale table.
- Account types and default account-template specification.
- Draft and posted transaction types.
- Binding sign convention.
- Transfer, split, opening-balance, archive, and soft-delete semantics.
- Public API command and error contracts.

### Required tests

- Balanced and unbalanced construction.
- Overflow and currency mismatch rejection.
- Sign behavior by account type.
- Transfer neutrality for net worth.
- Opening-balance posting behavior.
- Randomized/property-based zero-sum invariants.

### Exit criteria

- Rules run without UI, GRDB, Supabase, or web dependencies.
- Swift client fixtures and server fixtures produce matching expected results.
- No unresolved sign or currency semantics remain.

## 4. Phase 2: Authoritative Backend

### Scope

- Supabase project and environment separation.
- Email OTP or magic-link authentication.
- Custom SMTP configuration for non-development environments.
- PostgreSQL schema and ordered migrations.
- Row-level security and ownership tests.
- Ledger mutation functions/RPC.
- Expected-revision and idempotency handling.
- Derived balance and register queries.
- Default account-template creation.
- Empty-account two-confirmation deletion command.

### Required tests

- Cross-user access is denied.
- Partial transaction writes roll back.
- Stale revisions commit nothing.
- Retried idempotent creates do not duplicate transactions.
- Accounts with postings cannot be hard-deleted.
- Soft-deleted transactions are excluded from balances.

### Exit criteria

- A headless test client can create a user, ledger, accounts, and balanced transactions.
- Every mutation is authoritative and atomic.
- No direct client table write is required.

## 5. Phase 3: Receipt Storage and Combined Backup Foundation

### Scope

- Private receipt bucket.
- Temporary upload and finalization protocol.
- Attachment manifest with size, MIME type, and SHA-256 checksum.
- Orphan temporary-object cleanup.
- Missing/corrupt incident state.
- Deduplicated in-app and email notification pipeline.
- Export package format including database records and attachment bytes.

### Required tests

- Failed transaction commit leaves no active attachment manifest.
- Missing local cache re-downloads without email.
- Missing authoritative object creates one incident and one email notification.
- Backup checksum failure blocks restore.
- Export contains every active attachment exactly once.

### Exit criteria

- Receipt bytes and manifests cannot silently diverge without detection.
- A combined export can be verified independently.

## 6. Phase 4: iPhone Internal Alpha

### Scope

- SwiftUI application shell.
- Verified-email sign-in.
- GRDB schema, cache, drafts, and pending uploads.
- Ledger setup and automatic default account creation.
- Account list and balance display.
- Expense, income, transfer, and opening-balance entry.
- Transaction list and details.
- Edit with expected revision.
- Soft delete and restore.
- Receipt capture from camera or photo library.
- Basic export.

### Design goals

- Common entry fits into a short, understandable flow.
- Users do not need debit/credit terminology.
- Offline state preserves drafts and cached reads but clearly labels that posting requires connectivity.
- Negative balances and liability meaning do not rely on color alone.

### Exit criteria

- Critical workflows pass UI tests.
- Upload and network failures preserve user drafts.
- TestFlight build is usable by the internal group.

## 7. Phase 5: Mac Web Internal Alpha

### Scope

- Responsive desktop web shell optimized for current Safari on Mac.
- Shared authentication and ledger selection.
- Account overview and transaction list.
- Expense, income, transfer, and opening-balance entry.
- Edit, soft delete, restore, and receipt upload.
- Receipt images can be imported from the browser and attached to transactions; browser OCR field extraction is deferred.
- Conflict screen for stale revisions.
- Multiple-tab behavior tests.

### Exit criteria

- One user can switch between iPhone and web without inconsistent balances.
- Two tabs cannot silently overwrite one another.
- Core alpha workflows have behavior parity with iPhone.

## 8. First Usable Release: Internal Alpha

The internal alpha is reached when Phases 1 through 5 pass their exit criteria.

It includes:

- TestFlight iPhone app.
- Mac web interface.
- Verified email identity.
- Multiple ledgers, including personal ledgers and shared ledgers with email-based invitations.
- Single-currency ledgers from the supported allowlist.
- Automatic default accounts.
- Expense, income, transfer, and opening balance.
- Transactions are reached through ledger and account detail views rather than a standalone transaction tab.
- Edit, soft delete, and restore.
- Receipt attachments in managed storage.
- Basic combined export.

It intentionally excludes split transactions, advanced reports, CSV import, reconciliation, and AI.

## 9. Phase 6: Beta Feature Completion

### Scope

- Split transactions.
- Search and filtering.
- Account register.
- Net worth, income/expense, and spending-by-category reports.
- Verified backup and restore.
- Attachment integrity dashboard.
- Accessibility review.
- Production email delivery and templates.
- Provider-ready TODO: live-test server-side Google Vision OCR for the phone and Mac web interfaces. Web receipt import can prefill merchant, amount, receipt date, and likely line items after `GOOGLE_VISION_API_KEY` is configured in Supabase secrets; the alpha still requires user review before saving.

### Exit criteria

- Reports reconcile exactly with posting queries.
- Backup and restore drills preserve every attachment and identifier.
- iPhone and web critical workflows meet accessibility requirements.

## 10. Phase 7: Import and Reconciliation Support

### Scope

- CSV or structured-file import.
- Source profiles and mappings.
- Deterministic duplicate detection.
- Import review workflow.
- Reconciliation support.

### Exit criteria

- Each imported transaction commits atomically.
- Re-importing the same source is idempotent.
- Import errors never alter previously committed transactions.

## 11. Phase 8: AI-Assisted Drafting

### Scope

- Receipt/text suggestion protocol.
- Minimal provider payloads.
- Suggested-field provenance.
- User confirmation screen.
- Manual fallback.
- Adversarial tests from [AI_RULES.md](./AI_RULES.md).

### Exit criteria

- Every AI draft uses the standard server mutation path.
- Unbalanced or incomplete suggestions cannot post.
- AI failure never blocks manual entry.

AI may be omitted from the production release without blocking the core ledger product.

## 12. Phase 9: Production Distribution and Hardening

### Scope

- Choose stable distribution channel before App Store approval:
  - unlisted App Store by default; or
  - private Custom App for a specific Apple Business Manager organization.
- Privacy and security review.
- Migration rehearsal.
- Backup/restore drill.
- Browser compatibility verification.
- Performance profiling with representative data.
- Operational support and incident documentation.

### Exit criteria

- Production acceptance criteria in [PRODUCT.md](./PRODUCT.md) pass.
- No known issue can create a partial or unbalanced committed transaction.
- Authorization tests and attachment-recovery procedures pass.
- Distribution choice is documented and irreversible implications are accepted.

## 13. Deferred Tracks

These require demonstrated demand and an amended or new ADR:

- Fully offline posting and automatic conflict merge.
- Shared or collaborative ledgers.
- Multi-currency transactions and exchange-rate accounting.
- Native iPad or macOS clients.
- Automatic bank connectivity.
- Cached authoritative balance columns.
- Full append-only transaction revision history.
- Real-time presence or live co-editing.

## 14. Release Gates

A release may not proceed when any of these are unresolved:

- A mutation path can bypass authoritative validation.
- A user can access another user's ledger or receipt.
- A transaction can commit partially or unbalanced.
- Stale revisions can overwrite newer data.
- An attachment can be marked active before verification.
- A backup omits attachments or cannot verify checksums.
- A migration can destroy authoritative data without recovery.
- AI can directly call a mutation command without user confirmation.

## 15. Related Documents

- [Product Requirements](./PRODUCT.md)
- [Architecture](./ARCHITECTURE.md)
- [AI Rules](./AI_RULES.md)
- [ADR-001: iPhone SwiftUI Architecture](./DECISIONS/ADR-001-SwiftUI.md)
- [ADR-002: Double-Entry Ledger](./DECISIONS/ADR-002-DoubleEntry.md)
- [ADR-003: Storage Strategy](./DECISIONS/ADR-003-StorageStrategy.md)
- [ADR-004: Transaction Boundary](./DECISIONS/ADR-004-TransactionBoundary.md)
- [ADR-005: Client-Server and Web Access](./DECISIONS/ADR-005-ClientServer.md)
