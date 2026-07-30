# Rainflow AI Rules

**Status:** Active policy  
**Audience:** Product, engineering, QA, security  
**Last updated:** 2026-07-26

## 1. Purpose

This document defines the allowed role of AI in Rainflow. AI is an assistive drafting tool, not an accounting authority. It may interpret user input and suggest transaction fields, but it must never bypass deterministic validation, user review, or the standard transaction write path.

The surrounding architecture is defined in [ARCHITECTURE.md](./ARCHITECTURE.md). Product requirements are defined in [PRODUCT.md](./PRODUCT.md). AI review states and receipt interactions are specified in [DESIGN_SPEC.md](./DESIGN_SPEC.md).

## 2. Core Policy

AI output is always treated as untrusted input.

```text
User input or receipt
        |
        v
AI suggestion
        |
        v
Draft transaction
        |
        v
Deterministic validation
        |
        v
User confirmation
        |
        v
Standard atomic commit
```

AI has no direct access to persistence repositories or database mutation APIs.

## 3. Allowed AI Capabilities

AI may:

- Extract a possible amount from a receipt or message.
- Suggest an accounting date.
- Suggest a payee or merchant.
- Suggest an income or expense category.
- Suggest a payment or deposit account when context is available.
- Propose split allocations.
- Generate a short transaction description or note.
- Explain why a transaction is unbalanced.
- Identify likely duplicates for user review.
- Summarize spending patterns from already-authorized, minimized data.

Every suggestion remains editable before posting.

## 4. Prohibited AI Capabilities

AI must not:

- Insert, update, delete, restore, or purge ledger records directly.
- Call storage adapters or repository mutation methods.
- Mark an unbalanced transaction as valid.
- Invent an amount when no amount is present or inferable from authorized context.
- Silently change a user-confirmed value.
- Delete an account or transaction.
- Change the ledger currency.
- Create a new category or account without explicit user action.
- Override deterministic duplicate detection.
- Circumvent archived-account restrictions.
- Submit a transaction without explicit user confirmation.
- Use private ledger data for unrelated tasks.
- Transmit full database files, backups, unrelated receipt attachments, or unnecessary transaction history to an AI provider.

## 5. Trust States

Each AI-assisted field should track its origin and confirmation state.

```swift
enum FieldOrigin: Sendable {
    case userEntered
    case imported
    case aiSuggested
    case deterministicRule
}

enum ConfirmationState: Sendable {
    case unreviewed
    case confirmed
    case editedByUser
}

struct SuggestedField<Value: Sendable>: Sendable {
    let value: Value
    let origin: FieldOrigin
    let confidence: Double?
    let evidenceSummary: String?
    var confirmationState: ConfirmationState
}
```

Rules:

- A user edit changes the field origin or state so it is no longer treated as an unreviewed AI value.
- Confidence is advisory only and never replaces validation.
- The UI must make uncertain or missing values visible.
- AI provenance may be retained for debugging or audit only when privacy policy permits it.

## 6. Required Validation

Before posting, deterministic code must verify:

- At least two postings exist.
- All posting accounts exist.
- All posting amounts are present.
- All postings use the ledger currency.
- Posting amounts sum exactly to zero in integer minor units.
- No arithmetic overflow occurs.
- Archived accounts are not selected for new transactions.
- The expected revision still matches for edits.
- Any required duplicate check has completed.

AI confidence cannot waive any rule.

See [ADR-002](./DECISIONS/ADR-002-DoubleEntry.md) and [ADR-004](./DECISIONS/ADR-004-TransactionBoundary.md).

## 7. User Confirmation Rules

A user must review the complete transaction before commit.

The confirmation screen must show:

- Amount.
- Accounting date.
- Payee or description.
- Source and destination accounts or categories.
- Every split posting.
- Remaining unallocated amount, if any.
- Which fields were AI-suggested.

The primary action must not be enabled while deterministic validation fails.

For edits to existing transactions, the screen must clearly indicate that saving will replace the complete posting set atomically.

## 8. Missing and Ambiguous Information

When required information is missing or ambiguous, AI must return an incomplete draft rather than fabricate certainty.

Examples:

- A receipt total is unreadable: leave amount unset.
- The payment account is unknown: leave the account unset.
- Two categories are similarly plausible: show alternatives or mark the category uncertain.
- A split does not add up to the total: preserve the remaining amount and block posting.

The system may ask the user for one targeted clarification at a time.

## 9. Amount Handling

- AI may return textual money values, but conversion to stored money is deterministic application code.
- The parser must use the ledger currency and defined locale rules.
- Stored money uses signed `Int64` minor units.
- Binary floating-point values must not enter ledger arithmetic.
- If the parsed decimal has unsupported precision, deterministic rounding or rejection rules apply before confirmation.
- The original extracted text should remain available during review when useful.

Example: AI may read `$12.34`; deterministic code converts it to `1234` USD minor units.

## 10. Category and Account Suggestions

AI may suggest only from the currently allowed account set unless the user explicitly starts an account-creation flow.

Selection priority:

1. User-confirmed merchant rules.
2. Deterministic import mappings.
3. Previously confirmed local patterns.
4. AI suggestion.
5. User selection.

AI must not silently create duplicate categories with slightly different names.

## 11. Duplicate Detection

AI may identify possible duplicates, but deterministic identifiers and matching rules decide whether an import is automatically rejected as an exact duplicate.

A likely-duplicate explanation should include the matching factors, such as:

- Same source identifier.
- Same date and amount.
- Same payee and account.

The user may override a non-exact duplicate warning. Exact source-identifier collisions require an explicit exceptional workflow.

## 12. Privacy and Data Minimization

Before sending data to an AI provider:

- Include only fields needed for the current task.
- Remove unrelated account history.
- Do not send credentials, backup files, or database files.
- Avoid sending internal identifiers unless required for local correlation.
- Avoid sending notes or attachments unrelated to the requested suggestion.
- Follow the configured retention and provider settings.

For receipt processing, send only the user-selected receipt image or extracted receipt content plus the minimal allowed account/category context. The durable receipt remains in private application-managed storage; any provider copy must follow configured retention and deletion controls.

## 13. Logging and Diagnostics

Allowed logs:

- Request type.
- Model or provider identifier.
- Latency.
- Token or usage count when available.
- Success or error category.
- Whether the user accepted, edited, or rejected a suggestion.

Disallowed logs:

- Receipt image bytes or extracted receipt text in application logs, even though the product retains the original receipt in private attachment storage.
- Full prompts containing private transaction history.
- Account numbers.
- Raw database records.
- Authentication secrets.

Debug logging containing user content must be disabled in production by default.

## 14. Failure Behavior

AI failure must not block manual bookkeeping.

When AI is unavailable, slow, or returns invalid output:

- Preserve the user's current draft.
- Explain that suggestions are unavailable.
- Allow normal manual entry.
- Do not partially write any transaction.
- Do not repeatedly retry without a bounded policy and visible state.

Malformed model output is treated as a recoverable suggestion failure, not an application crash.

## 15. Provider Independence

AI integration is behind an application protocol.

```swift
protocol TransactionSuggestionService: Sendable {
    func suggestTransaction(from input: SuggestionInput) async throws -> SuggestedTransaction
}
```

Domain types must not depend on provider SDK types. Replacing or disabling an AI provider must not require changes to ledger validation or persistence.

## 16. Testing Requirements

Tests must verify that:

- AI output cannot directly reach repository mutation APIs.
- Unbalanced AI drafts cannot be posted.
- Missing amounts remain missing rather than becoming zero.
- Unsupported currencies are rejected.
- User edits supersede AI suggestions.
- Archived accounts are excluded from suggestions.
- AI failure preserves manual entry.
- Sensitive and unrelated fields are removed from provider payloads.
- A receipt sent to AI must be the user-selected attachment and must not expose another user's storage object.
- Every accepted AI draft passes the same use case as a manual draft.

Adversarial tests should include malformed JSON, contradictory totals, prompt injection in receipt text, unexpected currencies, extremely large amounts, and attempts to request destructive actions.

## 17. Product Copy Guidance

Use language such as:

- "Suggested from receipt"
- "Review before saving"
- "Could not determine payment account"
- "Split is short by $5.00"

Avoid language such as:

- "Verified by AI"
- "Automatically reconciled" when no deterministic reconciliation occurred
- "Guaranteed correct"

## 18. Change Control

Any feature that allows AI to initiate a write, operate without confirmation, or access broader ledger history requires:

1. A new or amended ADR.
2. Updated privacy review.
3. Updated threat analysis.
4. New deterministic safeguards.
5. Explicit product approval.

## 19. Related Documents

- [Product Requirements](./PRODUCT.md)
- [Architecture](./ARCHITECTURE.md)
- [Roadmap](./ROADMAP.md)
- [ADR-002: Double-Entry Ledger](./DECISIONS/ADR-002-DoubleEntry.md)
- [ADR-003: Storage Strategy](./DECISIONS/ADR-003-StorageStrategy.md)
- [ADR-004: Transaction Boundary](./DECISIONS/ADR-004-TransactionBoundary.md)
- [ADR-005: Client-Server and Web Access](./DECISIONS/ADR-005-ClientServer.md)
