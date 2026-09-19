# Rainflow Implementation Status

**Updated:** 2026-09-18  
**Source reviewed:** `main` at `c4ab5ef` (`Make receipt category auto-selection resilient`)  
**Product status:** Deployed functional web alpha; iPhone source is implemented but not yet documented here as a shipped TestFlight release

## Source-of-truth rule

Use the current `main` branch and deployed behavior as the primary source of truth. This file is a snapshot and can become stale. README or roadmap language must not override newer code.

## What is working now

### Web application

The web client is no longer a browser-local prototype. It is a Supabase-backed application with a Cloudflare Workers deployment path.

Implemented:

- Email OTP authentication through Supabase Auth.
- Ledger loading and switching.
- Personal and shared ledger creation.
- Shared-ledger email invitations.
- Dashboard, account, ledger, report, attachment, and transaction-detail views.
- Expense, income, and transfer entry.
- Transaction create/update/delete flows.
- Phone and desktop receipt import.
- Private receipt upload and attachment viewing.
- Server-side receipt OCR through the Supabase `extract-receipt` Edge Function.
- Editable OCR suggestions for merchant, date, amount, and structured line items.
- Receipt line-item persistence in the backend.
- Saved receipt line items displayed again in transaction detail.
- Expense-category auto-selection using receipt merchant/items.
- Merchant-history category reuse when a prior matching transaction exists.
- `Other Expenses` fallback when no stronger category rule matches.
- Manual category selection takes precedence over automatic suggestions.
- Responsive web UI for phone and desktop layouts.

### Web deployment

The repository contains an active automated deployment pipeline in `.github/workflows/web.yml`.

For pushes to `main` affecting `apps/web/**`, the pipeline performs:

1. `npm ci`
2. Next.js production build
3. Playwright tests
4. OpenNext Cloudflare bundle build
5. Cloudflare Workers deployment

The Cloudflare Worker configured by `apps/web/wrangler.jsonc` is `rainflow-web`.

### Supabase backend

Implemented migrations currently include:

- Initial ledger schema.
- Private receipt Storage policies and attachment finalization.
- RPC optional-field compatibility.
- Ledger membership and invitations.
- Expanded default expense categories.
- Structured transaction line items.

Backend capabilities include:

- Authoritative ledger and transaction schema.
- RLS-based access control.
- Security-definer RPCs for ledger creation and transaction mutations.
- Idempotent transaction creation.
- Expected-revision conflict checks.
- Deferred transaction-balance constraints.
- Same-ledger relational safeguards.
- Private owner/member-scoped receipt access.
- Attachment finalization and integrity-incident outbox.
- Transaction line-item persistence.

### Receipt flow

The current web receipt path is functionally end-to-end:

```text
select/capture receipt
  → call extract-receipt
  → parse merchant/date/total/line items
  → derive category suggestion
  → user reviews/overrides fields
  → create transaction
  → upload/finalize receipt attachment
  → persist line items
  → show line items in transaction detail
```

This means structured line-item support is implemented; it is no longer a future milestone.

### Shared Swift ledger domain

- Exact `Int64` minor-unit money model.
- Supported currencies include USD, CAD, EUR, GBP, JPY, and AUD.
- Strict date-only accounting dates.
- Binding posting sign convention.
- Two-posting minimum.
- Single-currency enforcement.
- Overflow protection.
- Exact zero-sum validation.
- Deterministic Expense, Income, and Transfer builders.

### iPhone client source

Implemented in source:

- SwiftUI iPhone target for iOS 26.0.
- Supabase OTP auth and auth-session handling.
- Ledger onboarding.
- Live authoritative snapshot reads.
- Atomic transaction creation.
- Dashboard, Accounts, Transactions, Reports, and Capture.
- GRDB latest-snapshot cache.
- Durable pending-receipt queue.
- Protected local receipt staging.
- Client-side receipt resizing.
- Client-side SHA-256.
- Immutable private Storage upload.
- Idempotent attachment finalization.
- Receipt retry/recovery states.
- Cached read-only offline launch.

The iPhone source should not be described as a shipped TestFlight build until signing, device validation, archive validation, and upload have actually been completed and verified.

## Recent HEAD progression

The latest receipt-related work on `main` shows the current state clearly:

- `b898aab` — Parse structured receipt line items
- `7d43040` — Suggest receipt categories from history and content
- `fd82f6b` — Expand default expense categories
- `11ac315` — Persist receipt line items
- `3e60621` — Add transaction line item data helpers
- `0f54d9b` — Fix receipt category suggestion and save line items
- `7ed6994` — Show saved receipt line items in transaction details
- `c4ab5ef` — Make receipt category auto-selection resilient

## Current priorities

### 1. Receipt image compression and storage efficiency

The receipt workflow works, so the immediate concern is no longer whether images can be attached. The priority is reducing long-term Storage usage without materially hurting OCR or later receipt readability.

For the web path, compression should be evaluated before upload so both network transfer and stored object size benefit. The implementation should preserve enough resolution for OCR and human review.

### 2. OCR/parser robustness

Structured extraction exists, but accuracy still needs continued hardening across varied merchant layouts.

Focus areas include:

- Reliable total selection.
- Merchant normalization.
- Multi-photo receipts.
- Quantity and unit-price parsing.
- Avoiding card/reference/rewards numbers as monetary totals.
- Preserving user review when confidence is low.

### 3. Receipt recovery and integrity hardening

Still important:

- Full reattachment/recovery UX for failed receipt cases.
- Trusted stored-byte hash verification.
- Orphan cleanup.
- Integrity-warning presentation.
- Deduplicated operational notification worker.

### 4. Test and observability depth

Expand:

- Auth/RLS integration coverage.
- Transaction/RPC regression coverage.
- Receipt upload/finalization tests.
- OCR regression fixtures.
- Line-item parsing regressions.
- Phone/desktop Playwright coverage.
- Accessibility testing.
- Backup/restore testing when those features are implemented.

### 5. iPhone release completion

Remaining release-oriented work includes:

- Real Xcode semantic compilation/linking with project-owner signing.
- Simulator and physical-device verification.
- End-to-end Supabase/RLS/Storage checks on device.
- Archive validation.
- TestFlight upload and smoke testing.

## Architecture note

Supabase currently remains the operational backend boundary for Auth, PostgreSQL data, RPCs, and receipt Storage.

A future split such as Supabase Auth plus Cloudflare D1/R2 can remain an option, but there is no need to force that migration before a concrete capacity, cost, or operational reason appears. New code should avoid unnecessary provider coupling where practical so storage/database migration remains reversible.

## Important integrity statement

The client computes and records a SHA-256 digest, and attachment finalization validates ownership, path, object existence, allowed MIME type, claimed size, and digest format. The current SQL does not independently hash stored receipt bytes. Do not describe trusted server-side byte-integrity monitoring or integrity email notification as operational until that worker exists and is tested.
