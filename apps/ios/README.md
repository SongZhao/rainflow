# Rainflow iPhone App

This folder contains the build-prepared SwiftUI iPhone client. XcodeGen creates `Rainflow.xcodeproj` from `project.yml`.

## Requirements

- macOS with Xcode 26 and the iOS 26 SDK.
- An Apple Developer team for a physical-device or archive build.
- Homebrew and XcodeGen (`brew install xcodegen`).
- A Supabase project with the migrations in `../../supabase/migrations/` applied.

## 1. Configure Supabase first

Use a disposable development project before production. Apply the migrations in filename order and verify the SQL tests described in `../../supabase/README.md`.

Rainflow uses an email OTP. In Supabase Auth email templates, the sign-in template must include the token variable rather than only a confirmation link. Configure a real SMTP provider before inviting the full test group.

## 2. Create the local build configuration

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Fill in:

```xcconfig
SUPABASE_URL = https:/$()/YOUR_PROJECT_REF.supabase.co
SUPABASE_PUBLISHABLE_KEY = sb_publishable_...
DEVELOPMENT_TEAM = YOUR_APPLE_TEAM_ID
PRODUCT_BUNDLE_IDENTIFIER = your.registered.bundle.identifier
```

`Local.xcconfig` is gitignored. Use only the public project URL and publishable key. Never place a service-role key or database password in an app configuration file.

## 3. Generate, resolve, and compile

From the repository root, either double-click `Prepare-Rainflow.command` in Finder or run:

```bash
./scripts/bootstrap-mac.sh
```

That script:

1. checks for macOS and Xcode;
2. installs XcodeGen through Homebrew when needed;
3. runs the pure domain tests;
4. generates the Xcode project;
5. resolves Supabase Swift and GRDB;
6. builds the Debug app for an iPhone simulator without code signing.

Open the generated project:

```bash
open apps/ios/Rainflow.xcodeproj
```

Select your Apple team in Xcode, run on a connected iPhone, and complete the smoke tests in `../../docs/TESTFLIGHT.md`.

## Implemented runtime behavior

- Email OTP authentication and session-state observation.
- Authenticated Supabase reads and atomic create-transaction RPC calls.
- GRDB snapshot cache and durable pending-receipt queue.
- Camera/photo-library receipt capture.
- Protected local staging, immutable private object upload, and idempotent finalization.
- Expense, income, transfer, ledger setup, dashboard, accounts, transactions, and reports.

Posted mutations require a connection. Cached data can be viewed offline. A receipt upload that fails after the accounting transaction commits is queued locally; a queue failure is shown as an explicit needs-attention state rather than being reported as safely queued.

## Archive for TestFlight

After the simulator and device builds pass and `Local.xcconfig` contains real values:

```bash
./scripts/archive-testflight.sh
```

The script creates `build/Rainflow.xcarchive`. Final validation and upload happen in Xcode Organizer with the project owner's Apple account.

## Current limits

- The app has not been semantically compiled in this Linux packaging environment.
- The Supabase migrations have not been executed here.
- Transaction editing, soft-delete/restore UI, account deletion challenges, combined export/restore, and the server integrity/email worker are not yet exposed as complete product workflows.
