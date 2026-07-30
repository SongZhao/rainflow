# Rainflow TestFlight Handoff

This checklist turns the source package into an internal TestFlight build. The final steps require the project owner's Mac, Apple Developer account, App Store Connect access, and Supabase project. Do not share Apple passwords, signing private keys, App Store Connect API secrets, or Supabase service credentials.

## 1. One-time Apple setup

1. Join or use an active Apple Developer Program team.
2. Register the intended bundle identifier in Certificates, Identifiers & Profiles.
3. Create the Rainflow app record in App Store Connect using that same bundle identifier.
4. Start with TestFlight internal testing. Stable limited distribution can be selected later according to the accepted product plan.
5. Prepare the required privacy disclosures and support/contact details before inviting external testers.

## 2. One-time Supabase development setup

1. Create a disposable development Supabase project.
2. Apply `supabase/migrations/202607260001_initial_ledger.sql` and then `202607260002_receipt_storage.sql`.
3. Run the invariant and cross-user authorization tests described in `supabase/README.md`.
4. Configure **Authentication -> Emails -> Magic Link** to include `{{ .Token }}` using `supabase/auth-email-templates.md`. The default link-only email will not work with the iPhone code-entry screen.
5. Configure custom SMTP before testing with the full group.
6. Confirm the `receipts` bucket is private and its owner-scoped policies are active.
7. Keep the service-role key and database password only in trusted server/operations environments.

## 3. Configure the iPhone build

On the Mac:

```bash
cp apps/ios/Config/Local.xcconfig.example apps/ios/Config/Local.xcconfig
```

Enter real values for:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`
- `DEVELOPMENT_TEAM`
- `PRODUCT_BUNDLE_IDENTIFIER`

Then run:

```bash
./scripts/check.sh
./scripts/bootstrap-mac.sh
open apps/ios/Rainflow.xcodeproj
```

In Xcode, confirm:

- the Rainflow target uses the expected Apple team;
- automatic signing resolves without warnings;
- the bundle identifier exactly matches App Store Connect;
- the deployment target is iOS 26.0;
- only iPhone is targeted;
- Release configuration contains no local service credential or debug override.

## 4. Simulator smoke test

Verify:

- app launch and configuration-error screen;
- email entry, OTP code entry, invalid-code error, and sign-out;
- ledger creation in each supported currency used by the test group;
- automatic default accounts;
- Expense, Income, and Transfer validation and save;
- Dashboard, Accounts, Transactions, and Reports refresh;
- photo-library receipt selection;
- Dynamic Type, dark/light appearance, and basic VoiceOver labels.

The simulator does not replace physical camera testing.

## 5. Physical-iPhone smoke test

Run directly from Xcode on an iPhone using a non-production test account.

### Authentication and isolation

- A valid emailed OTP code signs in.
- A second test user cannot read the first user's ledger, postings, manifests, or receipt objects.
- Sign-out removes the local snapshot and staged receipt data.

### Ledger correctness

- Expense decreases the source asset/liability flow and increases an expense category under the binding convention.
- Income increases the destination asset and increases income through a negative income posting.
- Transfer moves value between accounts without changing net worth.
- The server rejects an unbalanced, wrong-currency, archived-account, or cross-ledger posting payload.
- Repeating a create command with one idempotency key does not duplicate the transaction.

### Receipts and recovery

- Camera permission is requested only when camera capture is selected.
- Photo permission is requested only when library selection is selected.
- A successful receipt is private and appears on the transaction after refresh.
- Interrupting receipt upload after transaction commit preserves the transaction and creates a durable local retry entry.
- Reconnecting completes the queued upload and removes the staged local copy.
- A queue-storage failure is shown as “needs attention”; it is not falsely described as safely queued.
- Airplane-mode launch shows the cached snapshot as read-only and clearly states that posting requires connectivity.

## 6. Pre-archive checks

Do not archive until all of these are true:

- Both Supabase migrations completed successfully in the target test project.
- RLS and private Storage isolation passed with two real test users.
- The Release build succeeds on a physical-device destination.
- `./scripts/check.sh` passes.
- `Local.xcconfig` is not committed.
- No service-role key, private key, database password, SMTP secret, or Apple secret appears in source or the built app.
- Transaction creation calls the atomic `create_transaction` RPC rather than direct inserts.
- The privacy manifest and camera/photo purpose strings match actual behavior; reconcile the archive report with [APP_PRIVACY.md](./APP_PRIVACY.md).
- Known incomplete workflows are clearly stated in the TestFlight “What to Test” notes.

## 7. Create the archive

```bash
./scripts/archive-testflight.sh
```

The script validates required local values, regenerates the project, resolves packages, and creates:

```text
build/Rainflow.xcarchive
```

Open it in Xcode Organizer, then:

1. Validate App.
2. Distribute App.
3. Choose App Store Connect and Upload.
4. Complete export-compliance and privacy prompts accurately.
5. Wait for Apple processing.
6. Add internal testers.

## 8. Suggested “What to Test” notes

```text
Rainflow internal smoke alpha. Please test email-code sign-in, first-ledger setup,
expense/income/transfer entry, camera or library receipt attachment, dashboard and
account balances, transaction list, reports, offline cached viewing, and receipt
retry after reconnecting. Transaction edit/delete, export/restore, account deletion,
and the Mac web backend are not complete in this build.
```

## 9. Smoke-alpha versus beta blockers

The following are required before a broader or data-bearing beta, but they need not block a tightly controlled smoke build using disposable test data:

- transaction edit/delete/restore UI;
- account archive and two-confirmation delete challenge;
- combined export and verified restore;
- trusted attachment checksum scanner, orphan cleanup, and email worker;
- complete operational monitoring and support process.

No tester should enter irreplaceable financial records until verified export/restore is implemented and rehearsed.
