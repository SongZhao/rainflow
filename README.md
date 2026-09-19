# Rainflow

Rainflow is a personal-finance ledger for a small private group. The repository contains the deployed web app, the Supabase-backed ledger and receipt pipeline, shared Swift domain code, and the iPhone client source.

**Current source of truth:** the `main` branch. As of 2026-09-18, this README was refreshed against HEAD `c4ab5ef`.

## Current product state

- The web app is a functional deployed alpha, not a browser-local prototype.
- Pushes to `main` that change `apps/web/**` are built, tested with Playwright, bundled with OpenNext, and deployed to Cloudflare Workers by GitHub Actions.
- Supabase is the current authority for authentication, ledger data, transaction RPCs, receipt metadata, and private receipt storage.
- Receipt import supports server-side OCR through the Supabase `extract-receipt` Edge Function.
- OCR results can populate merchant, date, total, and structured line items.
- Receipt line items are persisted with the transaction and shown again in transaction detail.
- Expense categories can be auto-selected from receipt merchant/items or prior merchant history; explicit user choices take precedence.
- The iPhone client source is present, but Apple signing/TestFlight release work is separate from the deployed web app.

## Repository map

```text
docs/                         Product, architecture, design, roadmap, ADRs
packages/RainflowDomain/      Pure Swift money and transaction invariants
apps/ios/                     SwiftUI iPhone app generated with XcodeGen
apps/web/                     Deployed Next.js web app
supabase/                     Schema, RLS, RPCs, Storage policies, Edge Functions, SQL tests
scripts/                      Validation, Mac bootstrap, and archive helpers
.github/workflows/            iOS CI and web build/test/Cloudflare deployment
```

## Implemented in the web app

- Email OTP authentication through Supabase Auth.
- Supabase-backed ledger loading and switching.
- Personal and shared ledger creation.
- Shared-ledger email invitations.
- Dashboard, account, ledger, report, attachment, and transaction-detail flows.
- Expense, income, and transfer creation.
- Transaction create/update/delete flows through the authoritative backend.
- Camera/photo/file receipt import.
- Private receipt upload and later attachment viewing.
- Server-side OCR through `extract-receipt`.
- Merchant, date, total, and structured receipt line-item extraction.
- Transaction line-item persistence and detail rendering.
- Expense-category auto-selection from receipt content and merchant history, with `Other Expenses` fallback.
- Responsive phone and desktop web layouts.
- Cloudflare Workers deployment through OpenNext.

## Implemented in the iPhone source

- iPhone-only SwiftUI application targeting iOS 26.0.
- Email six-digit OTP sign-in through Supabase Auth.
- Live Supabase reads and atomic transaction creation through RPC.
- GRDB cache for the latest authoritative snapshot.
- Durable GRDB queue for receipt uploads that fail after a transaction commits.
- Protected local receipt staging, image resizing, and client-side SHA-256 calculation.
- Immutable private Supabase Storage upload followed by idempotent attachment-manifest finalization.
- Ledger setup with the approved default account template.
- Dashboard, Accounts, Transactions, Reports, and Capture.
- Manual Expense, Income, and Transfer flows using exact `Int64` minor units.
- Camera and photo-library receipt selection.
- Cached read-only launch while offline; posted mutations still require connectivity.

The iPhone source is not an installable `.ipa`. Apple signing, physical-device validation, archive validation, and TestFlight upload still require the project owner's Apple environment.

## Backend and data model

- Pure Swift double-entry domain with exact balancing, currency, date, and overflow checks.
- PostgreSQL ledger schema with authoritative transaction aggregates.
- Row-level security for ledger and receipt access.
- Security-definer RPCs for ledger creation and atomic transaction create/update/delete/restore.
- Idempotent transaction creation and expected-revision conflict protection.
- Private Supabase Storage receipt policies.
- Ledger membership and invitation schema.
- Expanded default expense categories.
- Structured transaction line-item schema.
- Receipt attachment finalization and integrity-incident outbox schema.

Current migrations:

```text
202607260001_initial_ledger.sql
202607260002_receipt_storage.sql
202607270003_rpc_optional_fields_compat.sql
202607280004_ledger_membership_and_invites.sql
202608150005_expand_default_expense_categories.sql
202608150006_transaction_line_items.sql
```

## Web deployment

The web app uses Next.js with OpenNext on Cloudflare Workers.

The `.github/workflows/web.yml` pipeline:

```text
push to main affecting apps/web/**
        ↓
npm ci
        ↓
Next.js build
        ↓
Playwright
        ↓
OpenNext Cloudflare build
        ↓
Cloudflare Workers deploy
```

The Worker configured in `apps/web/wrangler.jsonc` is `rainflow-web`.

## Current engineering priorities

The main product loop is already functional:

```text
sign in
  → select/create ledger
  → capture receipt or enter manually
  → OCR merchant/date/total/line items
  → auto-select category
  → save transaction
  → persist receipt + line items
  → review transaction detail
```

Current work is therefore focused on hardening rather than building that loop from scratch, especially:

1. Receipt image compression and storage-efficiency improvements.
2. OCR and receipt-parser quality across more merchants and layouts.
3. Receipt recovery, orphan cleanup, and integrity-worker hardening.
4. Broader automated coverage and production observability.
5. iPhone device/TestFlight completion.
6. Future storage/database portability without making an unnecessary one-way architecture migration.

## Validate this repository

```bash
./scripts/check.sh
```

For web-specific commands, see [apps/web/README.md](apps/web/README.md). For detailed implementation state and known limits, see [docs/IMPLEMENTATION_STATUS.md](docs/IMPLEMENTATION_STATUS.md).

## Security boundary

Only public/publishable client configuration belongs in browser or iPhone client code. Never commit a Supabase service-role key, database password, Google Vision secret, Cloudflare API token, Apple signing certificate/private key, or App Store Connect API secret.
