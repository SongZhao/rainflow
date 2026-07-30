# Rainflow Supabase Boundary

This folder defines the authoritative ledger boundary used by the iPhone client.

## Included

- Ledger, account, transaction, posting, attachment-manifest, idempotency, and integrity-event tables.
- Row-level read policies for authenticated owners.
- Owner-scoped private `receipts` insert/read policies with client overwrite and delete denied.
- Automatic default-account creation.
- Atomic transaction create/update/soft-delete/restore RPCs.
- Exact balance, currency, archived-account, and same-ledger checks.
- Expected-revision and idempotency handling.
- Deferred database triggers that reject invalid committed posting sets.

## Apply in a disposable development project

Install and authenticate the Supabase CLI, then link the development project:

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

Alternatively, execute the migration files in filename order in the Supabase SQL editor. Do not test a first migration run against production data.

For a fully local Supabase environment:

```bash
supabase start
supabase db reset
```

After migration, run the assertions in `tests/invariants.sql` using a controlled test user/session or convert them into the project's automated database test harness.

## Email OTP configuration

The iPhone app requests an email OTP and verifies the numeric token Supabase sends. Supabase's default passwordless email may send only a link, which does not match Rainflow's code-entry screen.

Configure the Supabase **Authentication -> Emails -> Magic Link** template to include `{{ .Token }}`. Use [auth-email-templates.md](./auth-email-templates.md) as the copy-paste source. Configure custom SMTP before production-like testing.

## Client credentials

The iPhone app may contain only:

- the Supabase project URL;
- the Supabase publishable client key.

Never ship or commit the service-role key, database password, signing key, or SMTP credentials.

## Receipt integrity boundary

The current flow is:

1. The iPhone normalizes the selected image, computes a SHA-256 digest, and stores a protected local staged copy.
2. It uploads to an owner-scoped unique key in the private `receipts` bucket.
3. `finalize_attachment` verifies authentication, ledger/transaction ownership, object path, object existence, MIME allowlist, claimed byte size, and checksum format before activating the manifest.
4. If upload or finalization returns an ambiguous network error, the client retains and queues the staged copy. A retry tolerates an already-present immutable object and calls the idempotent finalizer again.

The SQL function does **not** independently download and hash object bytes. A trusted Edge Function or server worker must later download active objects, verify the recorded size and digest, call `report_attachment_integrity_issue` on mismatch/missing data, and send one deduplicated email from the outbox. That worker and email delivery are not included yet.

Unfinalized objects are logically orphaned and require a trusted service-role cleanup job based on age/path; app clients cannot delete or overwrite receipt objects. Accounting transactions remain valid even when an attachment later has an integrity incident.

## Production work still required

- Execute and test both migrations on real Supabase infrastructure.
- Add automated cross-user RLS and RPC tests.
- Implement the trusted object integrity scanner, orphan cleanup, and email outbox worker.
- Add account-deletion challenge RPCs.
- Add combined database-plus-object export and staged restore jobs.
- Define retention, monitoring, and operational alerting.
