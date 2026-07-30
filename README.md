# Rainflow

Rainflow is a modern personal-finance ledger for a private group of fewer than 50 users. This repository is a **build-prepared internal-alpha source package** for the iPhone app, shared Swift domain, Supabase authority boundary, and Mac web prototype.

It is **not an installable `.ipa`**. Apple signing, a real Supabase project, a successful Xcode build, and an App Store Connect/TestFlight upload must still be completed on macOS with the project owner's accounts.

## Repository map

```text
docs/                         Product, architecture, design, roadmap, ADRs
packages/RainflowDomain/      Pure Swift money and transaction invariants
apps/ios/                     SwiftUI iPhone app generated with XcodeGen
apps/web/                     Next.js Mac web prototype
supabase/                     Authoritative schema, RLS, RPCs, and SQL tests
scripts/                      Static checks, Mac bootstrap, and archive helper
```

## Implemented in the iPhone source

- iPhone-only SwiftUI application targeting iOS 26.0.
- Email six-digit OTP sign-in through Supabase Auth.
- Live Supabase reads and atomic transaction creation through RPC.
- GRDB cache for the latest authoritative snapshot.
- Durable GRDB queue for receipt uploads that fail after a transaction commits.
- Protected local receipt staging, image resizing, and client-side SHA-256 calculation.
- Immutable private Supabase Storage upload followed by idempotent attachment-manifest finalization.
- Ledger setup with the approved default account template.
- Dashboard, Accounts, Transactions, Reports, and the center Capture action.
- Manual Expense, Income, and Transfer flows using exact `Int64` minor units.
- Camera and photo-library receipt selection.
- Cached read-only launch while offline; posted mutations still require connectivity.

## Implemented in the shared/backend source

- Pure Swift double-entry domain with exact balancing, currency, date, and overflow checks.
- PostgreSQL ledger schema with one authoritative transaction aggregate.
- Deferred database balance constraints as defense in depth.
- Row-level read policies and owner-scoped private receipt insert/read policies; app clients cannot overwrite or delete stored receipt bytes.
- Security-definer RPCs for ledger creation and atomic transaction create/update/delete/restore.
- Idempotent transaction creation and expected-revision conflict protection.
- Same-ledger foreign-key constraints for account parents and attachment manifests.
- Attachment integrity incident outbox schema.

## Still required before a useful TestFlight build

1. Create a Supabase development project and execute both migrations successfully.
2. Configure the Supabase email template to send the OTP token, then configure production SMTP before broader testing.
3. Put the project URL, publishable key, Apple Team ID, and registered bundle identifier in the gitignored `Local.xcconfig`.
4. Run the real Xcode 26 simulator and device builds on a Mac.
5. Exercise authentication, RLS, transaction RPCs, receipt upload/finalization, and offline recovery against the real project.
6. Archive, validate, and upload through Xcode Organizer.

The Mac web client remains a browser-local UI prototype and is not yet connected to the authoritative backend. Export/restore, account deletion challenges, transaction edit/delete UI, and the trusted attachment-integrity/email worker remain later implementation work.

## Validate this package

```bash
./scripts/check.sh
```

The command runs the pure Swift tests, parser-validates all Swift source, validates project metadata and Markdown links, checks required SQL safeguards, and scans for server credentials.

## Prepare the Xcode project on a Mac

```bash
./scripts/bootstrap-mac.sh
```

On a Mac, you can also double-click `Prepare-Rainflow.command`. Then follow [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md). Detailed status and known limits are in [docs/IMPLEMENTATION_STATUS.md](docs/IMPLEMENTATION_STATUS.md), and the current privacy mapping is in [docs/APP_PRIVACY.md](docs/APP_PRIVACY.md).

## Security boundary

Only the Supabase project URL and **publishable** client key belong in the iPhone app. Never add a service-role key, database password, Apple signing certificate, private key, or App Store Connect API secret to this repository.
