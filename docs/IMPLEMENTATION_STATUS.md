# Rainflow Implementation Status

**Date:** 2026-07-26  
**Package status:** Build-prepared internal-alpha source; not an installable or signed release

## Implemented and present in this package

### Shared ledger domain

- `Int64` minor-unit money for USD, CAD, EUR, GBP, JPY, and AUD.
- Strict date-only accounting dates.
- Binding posting sign convention.
- Two-posting minimum, single-currency enforcement, overflow protection, and exact zero-sum validation.
- Deterministic two-posting builders for Expense, Income, and Transfer drafts.
- Six passing pure Swift tests.

### iPhone client source

- iPhone-only SwiftUI target with minimum iOS 26.0.
- Rainflow design system, dark/light support, and custom five-position bottom navigation.
- Center Capture action with camera, photo library, and manual-entry paths.
- Email OTP authentication through Supabase Auth.
- Auth-session state listener and sign-out/reset behavior.
- Ledger onboarding and supported-currency selection.
- Live Supabase snapshot reads and atomic create-transaction RPC calls.
- Dashboard, Accounts, Transactions, and Reports backed by the authoritative snapshot or GRDB cache.
- GRDB migrations, latest-snapshot cache, and durable pending-receipt queue.
- Protected local receipt staging, image resizing, and client-side SHA-256 calculation.
- Immutable private Storage upload, idempotent attachment finalization RPC, ambiguous-response-safe retry, and local staged-file cleanup after success.
- Explicit receipt `uploaded`, `queued`, and `needs attention` outcomes.
- Configuration files, a behavior-matched privacy manifest, privacy disclosure checklist, placeholder app icon, XcodeGen project definition, clickable Mac preparation command, archive helper, secret scan, and macOS 26 CI workflow.

### Supabase boundary source

- Authoritative ledger schema and default account template.
- RLS owner-read policies and explicit `owns_ledger` execution grant required by those policies.
- No direct authenticated table-write grants.
- Atomic security-definer RPCs for create/update/soft-delete/restore.
- Idempotent creates and expected-revision checks.
- Deferred transaction-balance constraints, including validation of both old and new aggregates if a posting is moved.
- Same-ledger relational constraints for account parents and transaction attachments.
- Private owner-scoped receipt insert/read policies with client overwrite and delete denied.
- Attachment finalization and integrity-incident outbox schema.

### Mac web source

- Next.js/TypeScript web client matching the approved information architecture.
- Supabase-backed authentication, ledger loading, transaction create/update/delete, and receipt upload/viewing.
- Dashboard, account, transaction, report, attachment, add-entry, transaction-detail, ledger-detail, and account-detail views.
- Direct Transactions navigation is removed; transactions are accessed through ledger/account detail pages and transaction drill-downs.
- Multiple ledger switching, personal/shared ledger creation, and shared-ledger email invitations are implemented in the web shell.
- Browser receipt import stores the selected image with the transaction and supports viewing the attachment later.
- Deferred TODO: browser-side receipt OCR is not implemented yet. Web users must manually enter amount, merchant, date, and line-item details until OCR quality and incorrect-amount handling are validated.

## Validation completed in this environment

- `swift test` passes for `RainflowDomain`.
- Every Swift source file passes Swift parser validation.
- `Info.plist`, asset JSON, dependency pins, deployment target, gitignore rules, Markdown relative links, and required SQL safeguards pass `scripts/validate_project.py`.
- The repository passes the server-secret/private-key scan.
- The release ZIP excludes `.build`, generated Xcode projects, local configuration, node modules, and other machine-specific output.

## Validation that still requires macOS or external services

- Semantic compilation and linking of the iOS app with Xcode 26 and the iOS 26 SDK.
- Resolution and compilation of the pinned Supabase Swift and GRDB packages in Xcode.
- Simulator and physical-iPhone execution.
- Apple code signing, archive validation, and TestFlight upload.
- Execution of the migrations against a local or hosted Supabase/PostgreSQL environment.
- End-to-end email OTP, RLS, RPC, Storage, airplane-mode, and receipt-retry tests.
- Next.js lint, typecheck, production build, and Safari accessibility testing after each web UI change.

## Mandatory work before the first internal TestFlight smoke build

1. Apply and test the migrations in a disposable Supabase project.
2. Configure the OTP email template and SMTP appropriate to the test group.
3. Create the gitignored iOS `Local.xcconfig` with real public values and Apple signing identifiers.
4. Run `scripts/bootstrap-mac.sh` and resolve any real SDK/package compiler findings.
5. Run the app on a physical iPhone and verify the critical smoke matrix in [TESTFLIGHT.md](./TESTFLIGHT.md).
6. Confirm RLS prevents a second test user from reading the first user's ledger or receipt.
7. Confirm all posted writes use RPC and no service credential is present in the app bundle.

## Work after the smoke alpha, before feature-complete beta

- Transaction detail, expected-revision edit, soft-delete, and restore UI.
- Empty-account two-confirmation deletion challenge and account archive UI.
- Opening-balance workflow.
- Combined export/verified restore including attachment bytes.
- Trusted attachment hash scanner, orphan cleanup, integrity warning UI, and deduplicated email worker.
- Full receipt reattachment/recovery screen for a device-side `needs attention` case.
- Browser-side receipt OCR for web receipt import, including protections against rewards points, reference numbers, card numbers, and other non-total amounts being selected as transaction totals.
- Split transactions, search/filter depth, account register, and exact report reconciliation.
- Automated UI, API, RLS, migration, accessibility, and backup/restore test suites.

## Important integrity statement

The client computes and records a SHA-256 digest, and attachment finalization validates ownership, path, object existence, allowed MIME type, claimed size, and digest format. The current SQL does not independently hash the stored bytes. Do not describe server-side byte integrity monitoring or email notification as operational until the trusted worker is implemented and tested.

## Xcode 26 simulator compatibility patch

The camera bridge is explicitly main-actor isolated and imports UIKit with
`@preconcurrency` to prevent Objective-C delegate/sendability mismatches under
Swift 6 complete concurrency checking. `scripts/diagnose-ios-build.sh` records a
full Xcode build log and prints the actual compiler diagnostics if a build fails.
