# ADR-005: Client-Server Authority and Mac Web Access

**Status:** Accepted  
**Date:** 2026-07-26  
**Decision owners:** Product and Engineering

## Context

The product requires a native iPhone client and a web interface for Mac. Users sign up with email and expect both clients to access the same ledger. A local-only design would either make the web client impossible or create independent copies that can silently diverge.

The product has fewer than 50 users, so the solution should provide correct shared access without building large-scale distributed infrastructure.

## Decision

- Provide one native iPhone client and one responsive desktop web client optimized for current Safari on Mac.
- Use a server-authoritative ledger accessed through authenticated commands.
- Require verified-email authentication.
- Support multiple browser tabs and client sessions through expected revisions and idempotency keys.
- Do not implement real-time collaborative editing or automatic field-level merges.
- Do not expose a user-facing multi-window feature in the iPhone app.
- Require connectivity to commit posted mutations in the MVP; cached reads and local drafts remain available on iPhone.

## Multi-Window Meaning

“Multiple windows” can refer to two different behaviors:

1. **Native Apple multi-window scenes:** creating separate application windows, mainly relevant to iPad and Mac. This is not supported because the native target is iPhone only.
2. **Browser tabs/windows:** opening the web app more than once. This is supported as normal browser behavior, with stale-revision rejection preventing silent overwrites.

The product does not promise synchronized cursor presence, live co-editing, or automatic merging between open sessions.

## API Command Rules

Every mutation command includes:

- Authenticated user identity.
- Ledger identifier.
- Stable aggregate identifier.
- Idempotency key for create operations.
- Expected revision for update, delete, and restore operations.
- Complete replacement posting set for transaction edits.

The server returns the committed representation and new revision. A stale command returns a typed conflict without modifying the ledger.

## Authentication

- Users sign up with an email address.
- The email address must be verified before ledger access.
- Email OTP or magic-link authentication is preferred for the MVP.
- Sessions are revocable.
- Production authentication and notification email uses a configured transactional email provider.

## Distribution

- Internal alpha and beta builds use TestFlight.
- TestFlight is not the permanent production channel because beta builds expire.
- For stable limited-audience distribution, prefer an unlisted App Store release unless all users belong to a specific organization using Apple Business Manager, in which case Custom App private distribution may be used.
- Apple Developer Enterprise distribution is not selected; it is intended for qualifying organizations distributing proprietary apps to their own employees.
- The App Store distribution method must be chosen carefully before approval because changing between public and private distribution generally requires a new app record; public distribution can later request unlisted status.

## Consequences

### Positive

- iPhone and Mac web users see one authoritative ledger.
- Browser tabs cannot silently overwrite newer edits.
- TestFlight provides the fastest controlled path to early users.
- Stable production distribution remains available without making the app publicly discoverable.

### Negative

- A backend and internet connectivity are required for posted mutations.
- Authentication, authorization, session handling, and web security become production responsibilities.
- TestFlight requires periodic new builds during beta.

### Neutral

- The web framework is an implementation detail as long as it follows the API contracts and supported-browser requirements.

## Rejected Alternatives

### Native macOS application in the MVP

Rejected because the requested Mac experience is web-based and a second native target would increase implementation and release overhead.

### Independent local ledgers with manual export between clients

Rejected because it is error-prone and does not provide the requested shared interface.

### Last-write-wins updates

Rejected because concurrent browser tabs or clients could silently discard user changes.

### Enterprise distribution

Rejected because it is unnecessarily restrictive and is intended for qualifying organizations distributing only to their employees.

## Related Decisions and Requirements

- [Product Requirements](../PRODUCT.md)
- [Architecture](../ARCHITECTURE.md)
- [Roadmap](../ROADMAP.md)
- [ADR-001: iPhone SwiftUI Architecture](./ADR-001-SwiftUI.md)
- [ADR-003: Storage Strategy](./ADR-003-StorageStrategy.md)
- [ADR-004: Transaction Boundary](./ADR-004-TransactionBoundary.md)
- [ADR-006: Web Application Stack](./ADR-006-WebStack.md)
