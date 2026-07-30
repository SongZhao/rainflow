# ADR-004: Transaction Aggregate and Persistence Boundary

**Status:** Accepted  
**Date:** 2026-07-26  
**Decision owners:** Engineering

## Context

A ledger transaction contains a header and two or more postings. Saving these records independently can expose invalid intermediate states, such as:

- A transaction with no postings.
- Only one side of a transfer.
- An edit where old and new postings coexist.
- A deleted header whose postings still affect balances.
- An attachment or import record saved while the accounting entry fails.

The product requires that failures leave the ledger unchanged and that no reader observe a partial transaction.

## Decision

The complete accounting transaction is the aggregate boundary and the authoritative PostgreSQL transaction boundary.

All create, update, soft-delete, restore, and permitted purge operations affecting a ledger transaction execute atomically on the server. Client caches are updated only after success.

## Aggregate Contents

The transaction aggregate includes:

- Transaction header.
- Complete posting collection.
- Revision.
- Soft-deletion state.
- Required transaction-level tag links.
- Required source/import identity.
- Required creation/update metadata written as part of the same operation.
- Active attachment manifests finalized with the transaction.

Large attachment file bytes are managed in private object storage and cannot participate in the PostgreSQL transaction. Their manifest must not become active until the object has been uploaded and verified.

## Create Boundary

Conceptually:

```text
BEGIN
  verify authenticated user owns the ledger
  verify idempotency key is unused
  verify referenced ledger and accounts
  verify accounts are allowed for new postings
  verify currency
  verify at least two postings
  verify posting sum equals zero
  insert transaction header
  insert all postings
  insert required metadata
  activate verified attachment manifests
  perform final aggregate verification
COMMIT
```

On any failure:

```text
ROLLBACK
```

The transaction is not observable before commit.

## Update Boundary

An edit replaces the complete stored representation atomically.

```text
BEGIN
  load current revision
  verify current revision equals expected revision
  validate complete replacement transaction
  update transaction header
  replace complete posting set
  update required metadata
  increment revision
  perform final aggregate verification
COMMIT
```

If the revision does not match, the operation fails with a stale-edit error and makes no changes.

Implementations may delete and reinsert postings or diff them by stable identifier, but the observable result and rollback behavior must be equivalent.

## Soft-Delete Boundary

Soft deletion changes the complete transaction state, not individual postings.

```text
BEGIN
  verify expected revision
  set transaction.deleted_at
  increment revision
COMMIT
```

Queries and reports exclude postings whose parent transaction is soft-deleted.

## Restore Boundary

```text
BEGIN
  verify expected revision
  revalidate referenced accounts and currency
  clear transaction.deleted_at
  increment revision
COMMIT
```

If restoration would violate current invariants, the operation fails without modification and requires a correction workflow.

## Purge Boundary

Permanent purge is a maintenance operation. It must:

- Require explicit confirmation.
- Require a verified backup.
- Delete the transaction and all dependent rows in one database transaction.
- Never leave orphaned postings or metadata.

Normal product flows use soft deletion instead.

## Validation Placement

Validation is layered:

1. **Domain validation** constructs only a valid posted transaction.
2. **Application validation** checks permissions, expected revision, and workflow context.
3. **Persistence validation** checks foreign keys, uniqueness, and final aggregate state inside the database transaction.

No layer may assume that validation in another layer makes atomic persistence unnecessary.

## Read Isolation

Readers must observe either:

- The complete state before a mutation, or
- The complete state after a successful mutation.

Readers must never observe a partially replaced posting set.

The PostgreSQL command layer must use transaction isolation, row locking where needed, and expected-revision predicates that preserve this guarantee.

## Failure Semantics

Any error during the aggregate write results in rollback, including:

- Invalid account.
- Archived account prohibited for the operation.
- Currency mismatch.
- Unbalanced posting set.
- Arithmetic overflow.
- Duplicate posting identifier.
- Duplicate import identifier.
- Stale revision.
- Database constraint failure.
- Storage I/O failure.
- Failure to write required audit metadata.

Optional, nonessential post-commit work such as analytics, cache refresh, object cleanup, or email notification must not be included in the accounting transaction. It may run after commit and fail independently.


## Attachment Finalization Boundary

Attachment bytes and PostgreSQL rows use a staged consistency protocol:

1. Normalize the image locally, compute its digest, and upload it to a private owner-scoped unique object key.
2. In a separate finalization command, verify authentication, ownership, object path/existence, MIME allowlist, claimed size, and checksum format before marking the attachment manifest active.
3. After finalization, a trusted worker independently verifies the stored bytes against the manifest digest.
4. Clean up unfinalized, superseded, or orphaned objects outside the accounting transaction.

If the database command fails, no active manifest is created and the object is eligible for cleanup. PostgreSQL finalization does not independently hash Storage bytes; the trusted worker owns that check. If an active object later becomes missing or corrupt, the accounting transaction remains valid; the manifest records an integrity incident and notification runs post-commit.

## Import Semantics

Each imported transaction is an independent aggregate and commits atomically.

An import batch may contain successful and failed rows, but:

- No individual transaction may be partial.
- Batch reporting must identify committed, skipped, duplicate, and failed rows.
- Exact duplicate source identifiers are rejected deterministically.

A future all-or-nothing batch mode may wrap multiple aggregates only if explicitly required; it is not the default.

## AI Semantics

AI output is a draft outside the transaction boundary. It gains no persistence authority.

Only after deterministic validation and explicit user confirmation does the standard create or update use case begin the database transaction.

See [AI_RULES.md](../AI_RULES.md).

## Account Creation and Opening Balance

The onboarding UI may appear to create an account and opening balance in one flow. The implementation must define its atomic behavior explicitly.

Preferred behavior:

```text
BEGIN
  create account
  create balanced opening-balance transaction
COMMIT
```

If the opening-balance transaction fails, the flow either rolls back the new account or returns a clearly defined account-without-opening-balance result. The initial implementation should use all-or-nothing behavior to match user expectations.

## Consequences

### Positive

- Partial transfers and split transactions cannot be committed.
- Failed edits leave the previous version intact.
- Balance queries always see complete posting sets.
- Imports and AI use the same integrity boundary as manual entry.
- Recovery and debugging have clear semantics.

### Negative

- Repository operations must handle aggregates rather than individual rows.
- Updates may write more rows than a field-level mutation.
- Required metadata failures can cause the accounting write to roll back.

For the expected scale, these costs are acceptable.

## Rejected Alternatives

### Save the header and postings independently

Rejected because it permits partial and observable invalid states.

### Save each transfer side as a separate transaction

Rejected because the sides can fail, edit, or delete independently.

### Update account balances after saving postings

Rejected because balance-update failure would create conflicting sources of truth.

### Rely only on UI validation

Rejected because imports, migrations, tests, background work, and AI features can bypass a screen.

### Client-side last-write-wins

Rejected because multiple browser tabs and iPhone/web sessions may edit the same transaction. Expected revisions must reject stale writes.

### Fully offline posted mutations

Deferred because safe synchronization would require conflict, tombstone, duplicate, and attachment-merge semantics beyond the MVP.

## Testing Requirements

Inject a failure at every write step and verify:

- No transaction header remains after failed creation.
- No partial posting set remains.
- Failed edits preserve the prior revision and postings.
- Failed soft deletion leaves the transaction active.
- Failed restoration leaves the transaction deleted.
- Duplicate import identifiers commit nothing.
- Readers do not observe intermediate replacement states.
- Retried creates with the same idempotency key do not duplicate a transaction.
- Stale writes from another browser tab commit nothing.
- Failed ledger commits leave uploaded temporary attachments inactive and cleanable.

## Related Decisions and Requirements

- [Product Requirements](../PRODUCT.md)
- [Architecture](../ARCHITECTURE.md)
- [AI Rules](../AI_RULES.md)
- [ADR-001: SwiftUI Architecture](./ADR-001-SwiftUI.md)
- [ADR-002: Double-Entry Ledger](./ADR-002-DoubleEntry.md)
- [ADR-003: Storage Strategy](./ADR-003-StorageStrategy.md)
- [ADR-005: Client-Server and Web Access](./ADR-005-ClientServer.md)
