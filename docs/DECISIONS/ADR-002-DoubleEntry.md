# ADR-002: Double-Entry Ledger Model

**Status:** Accepted  
**Date:** 2026-07-26  
**Decision owners:** Product and Engineering

## Context

Rainflow must produce trustworthy balances, transfers, reports, and corrections. A single-entry model with directly editable account balances would be easier to prototype but can silently diverge when transfers, splits, imports, edits, or failures occur.

The application also needs familiar personal-finance language without weakening the underlying accounting model.

## Decision

Use a double-entry journal in which every active posted transaction contains two or more postings whose signed amounts sum exactly to zero.

### Money representation

- Store money as signed `Int64` minor units.
- Store or inherit an explicit currency code.
- Prohibit `Double` for stored monetary values and ledger arithmetic.
- Detect integer overflow.
- Format currency only in the presentation layer.

For USD, `$12.34` is stored as `1234` minor units.

### Currency scope

- Each ledger selects one supported currency at creation.
- The initial allowlist is USD, CAD, EUR, GBP, JPY, and AUD.
- The selected currency is immutable after the first posted transaction.
- Every posting in that ledger uses the same currency and defined minor-unit scale.
- Multi-currency transactions and automatic conversion are deferred and require a new ADR.

### Accounts

Every account has one type:

- Asset.
- Liability.
- Equity.
- Income.
- Expense.

Income and expense categories are accounts in the domain. Tags, payees, and notes are metadata.

### Transactions and postings

An active posted transaction must:

1. Have at least two postings.
2. Reference existing accounts.
3. Use the ledger currency for every posting.
4. Sum to exactly zero in minor units.
5. Contain unique stable posting identifiers.
6. Be committed as one atomic unit.

### Source of truth

Postings are the source of truth for balances and reports.

Account balances are computed from active postings. A mutable balance field is prohibited. A future cache may be added only after profiling and must be rebuildable from postings.

### Transfers

A transfer is one transaction, not two linked transactions.

```text
Assets:Checking  -$500.00
Assets:Savings   +$500.00
```

Credit-card payments and cash withdrawals use the same principle.

### Opening balances

Opening balances are normal transactions against an equity account.

```text
Assets:Checking           +$2,000.00
Equity:Opening Balances   -$2,000.00
```

An `openingBalance` field on an account is prohibited. If the default opening-balances equity account no longer exists, the workflow must select or create another equity account rather than relying on a protected name.

### Editing

The initial release permits direct correction of an existing transaction.

- The complete transaction and posting set are replaced atomically.
- The revision increments.
- A stale revision cannot overwrite a newer version.
- The MVP stores `createdAt`, `updatedAt`, and `revision` without prior-version snapshots.
- Stable identifiers and aggregate update commands permit a future append-only revision-history table.

Reversal-only editing is not required for the initial personal-use product.

### Deletion

Normal deletion is soft deletion of the complete transaction.

- Deleted transactions do not affect balances or reports.
- Individual postings cannot be deleted through product flows.
- Deleted transactions can be restored.
- Permanent purge is a separate maintenance operation requiring a verified backup.

### Archived accounts

Accounts with historical postings cannot be hard-deleted through normal flows. They may be archived and remain available for history and reports.

## Sign Convention

The storage convention is binding:

| Account type | Increase | Decrease |
|---|---:|---:|
| Asset | Positive | Negative |
| Expense | Positive | Negative |
| Liability | Negative | Positive |
| Equity | Negative | Positive |
| Income | Negative | Positive |

Every active transaction sums to exactly zero.

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

Report presentation may transform signs by account type, but storage semantics remain unchanged and centrally tested.

## Consequences

### Positive

- Transfers cannot create or destroy value accidentally.
- Split transactions remain internally consistent.
- Balances can always be rebuilt from the journal.
- Failed writes can roll back without compensating balance updates.
- Reports share one canonical data source.

### Negative

- The domain model is more complex than a list of signed transactions.
- UI flows must translate familiar language into postings.
- Edits affect multiple postings and require aggregate-level persistence.

### Neutral

- Users do not need to see debit and credit terminology in ordinary workflows.

## Rejected Alternatives

### Single-entry transactions with mutable account balances

Rejected because balances can diverge from transaction history and transfers require fragile linking.

### Two linked transactions for transfers

Rejected because one side can fail, be edited, or be deleted independently.

### Categories as unrelated labels

Rejected because category reports would become a second accounting system independent of the journal.

### Floating-point money

Rejected because binary floating-point arithmetic can produce nonzero residuals in values that appear balanced.

### Immutable reversal-only ledger for all edits

Deferred because it adds user and implementation complexity that is not required for the initial small personal-use product. It can be reconsidered if regulatory auditability becomes a requirement.

## Validation

The domain must reject:

- Fewer than two postings.
- Missing accounts.
- Currency mismatches.
- Nonzero posting sum.
- Arithmetic overflow.
- Duplicate posting identifiers.
- New postings to archived accounts outside explicit correction flows.

Persistence and property-based tests must independently verify these invariants.

## Related Decisions and Requirements

- [Product Requirements](../PRODUCT.md)
- [Architecture](../ARCHITECTURE.md)
- [ADR-001: SwiftUI Architecture](./ADR-001-SwiftUI.md)
- [ADR-003: Storage Strategy](./ADR-003-StorageStrategy.md)
- [ADR-004: Transaction Boundary](./ADR-004-TransactionBoundary.md)
- [ADR-005: Client-Server and Web Access](./ADR-005-ClientServer.md)
