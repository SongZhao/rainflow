# ADR-001: iPhone SwiftUI Application Architecture

**Status:** Accepted  
**Date:** 2026-07-26  
**Decision owners:** Product and Engineering

## Context

Rainflow provides a native iPhone client and a separate desktop web interface optimized for Mac. The iPhone code must remain simple enough for a small team while preserving accounting correctness, testability, attachment handling, and safe interaction with the authoritative backend.

Direct `View -> database row` or `View -> backend table` binding would allow UI code to bypass transaction invariants, authorization, stale-revision handling, and attachment workflows.

## Decision

Use SwiftUI for the iPhone presentation layer with this dependency structure:

```text
SwiftUI Views
    |
    v
Screen Models / Presentation State
    |
    v
Application Use Cases
    |
    +--> Authenticated API Client
    |
    +--> GRDB Cache and Draft Repository
    |
    v
Pure Ledger Domain Values and Validation
```

The web client is outside SwiftUI and follows the same API command contract. See [ADR-005](./ADR-005-ClientServer.md).

### Platform scope

- The native app target is iPhone only.
- The minimum deployment target is iOS 26.0.
- Development and submission use the latest stable iOS 26 SDK or later.
- Supporting iOS versions earlier than 26.0 is outside the MVP.
- No iPad or native macOS target is included in the MVP.
- The iPhone app does not expose user-facing multi-window scene creation.
- Mac access is provided by the web client.

### Presentation rules

- Views render state and send user intents.
- Views do not insert postings or mutate calculated balances.
- Views do not depend on GRDB record types or backend-provider SDK records.
- Screen models own transient form state, upload progress, conflict state, and asynchronous UI state.
- Display formatting is separate from stored domain values.
- The iPhone shell uses custom bottom navigation so the center camera control can launch receipt capture without becoming a persistent destination.
- Camera and photo-library paths create drafts; they do not post transactions directly.
- Visual tokens and interaction details are binding in [DESIGN_SPEC.md](../DESIGN_SPEC.md).

### Application rules

- Use cases coordinate local draft validation, authenticated API calls, expected revisions, cache updates, and attachment uploads.
- Every posted mutation goes through an authoritative server command.
- Imports and AI suggestions produce drafts and then call the same commands as manual entry.
- A failed or rejected server mutation never changes the cached posted state as though it succeeded.

### Domain rules

- The Swift domain module has no SwiftUI, GRDB, networking, Supabase, or AI-provider dependency.
- Domain values are `Sendable` where they cross concurrency boundaries.
- Client validation provides immediate feedback but never replaces server validation.

### Concurrency rules

- UI state changes occur on the main actor.
- Parsing, image processing, checksum calculation, and AI requests may run outside the main actor.
- GRDB access uses its supported queue/pool concurrency model behind one adapter.
- API requests carry idempotency keys for creates and expected revisions for updates.
- Thread-confined database records and provider SDK objects do not cross actor boundaries.

## Consequences

### Positive

- Accounting behavior is testable without launching the app.
- SwiftUI changes do not affect ledger rules.
- GRDB and backend-provider changes remain isolated behind adapters.
- AI, imports, and receipt capture cannot bypass the standard write path.
- The app can show cached data and preserve drafts when connectivity is unavailable.

### Negative

- More types and mapping code are required than with direct table binding.
- Posted mutations require connectivity in the MVP.
- Cache invalidation and upload state require explicit implementation.

### Neutral

- This ADR does not require a specific navigation library or global state-management package.
- Browser multi-tab behavior is handled by server revisions, not iPhone window management.

## Rejected Alternatives

### Direct SwiftUI and backend-table binding

Rejected because views could bypass aggregate validation, authorization, idempotency, and stale-revision checks.

### Local SQLite as an independent ledger authority

Rejected because the web client and iPhone would create competing sources of truth and require offline merge logic.

### Global observable application model

Rejected because it centralizes unrelated state, complicates testing, and obscures transaction ownership.

### Full Redux-style architecture

Rejected for the MVP because the product size does not justify the added ceremony. Screen models and use cases provide sufficient separation.

### UIKit-first architecture

Rejected because SwiftUI is the selected native product direction and meets the iPhone interface requirements.

## Implementation Constraints

- No production view may call direct ledger-table mutation APIs.
- No production view may change an account balance property.
- Domain modules must build and test without importing SwiftUI, GRDB, Supabase, or networking frameworks.
- Use cases return typed outcomes rather than raw SQL, HTTP, or provider errors.
- A cached object is never presented as successfully committed until the authoritative server confirms it.

## Validation

Compliance is verified through:

- Module dependency checks.
- Unit tests for screen models and use cases with fake API/cache adapters.
- Code review rules prohibiting direct ledger mutations from views.
- UI tests for critical workflows, offline draft preservation, upload failure, and stale-revision conflicts.

## Related Decisions and Requirements

- [Design Specification](../DESIGN_SPEC.md)
- [Product Requirements](../PRODUCT.md)
- [Architecture](../ARCHITECTURE.md)
- [ADR-002: Double-Entry Ledger](./ADR-002-DoubleEntry.md)
- [ADR-003: Storage Strategy](./ADR-003-StorageStrategy.md)
- [ADR-004: Transaction Boundary](./ADR-004-TransactionBoundary.md)
- [ADR-005: Client-Server and Web Access](./ADR-005-ClientServer.md)
