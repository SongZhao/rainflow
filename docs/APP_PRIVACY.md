# Rainflow App Privacy Configuration

This document maps the current iPhone implementation to the bundled privacy manifest and to the App Store Connect privacy questionnaire. It is an engineering disclosure checklist, not a substitute for a reviewed privacy policy.

## Current data collection

Rainflow currently collects the following data only to provide app functionality. All of it is linked to the signed-in user and none of it is used for tracking or advertising.

| Apple category | Rainflow data | Purpose |
|---|---|---|
| Email Address | Verified sign-in email | Authentication, account access, and required service notices |
| User ID | Supabase account identifier | Ownership and authorization |
| Other Financial Info | Ledgers, account names, balances derived from postings, transactions, categories, payees, and reports | Personal-finance functionality |
| Photos or Videos | Receipt images explicitly selected or photographed by the user | Transaction attachments |
| Other User Content | Notes, descriptions, attachment filenames, and similar user-entered text | Transaction and attachment functionality |

The source does not include advertising, cross-app tracking, analytics collection, contact upload, location collection, or bank-link credentials.

## Bundled manifest

`apps/ios/Rainflow/Resources/PrivacyInfo.xcprivacy` declares:

- tracking disabled;
- no tracking domains;
- the five linked data categories above;
- App Functionality as the collection purpose;
- no app-owned required-reason API declarations currently identified in the source.

Third-party SDK manifests are aggregated by Xcode. Generate an archive privacy report and review the Supabase Swift and GRDB declarations before every release.

## App Store Connect checklist

Before uploading a build that will be used beyond a disposable internal smoke test:

1. Generate the privacy report from the archived app in Xcode Organizer.
2. Reconcile the report with this file and the behavior of the configured Supabase project.
3. Complete App Store Connect privacy answers for every collected category.
4. Publish a privacy policy and support contact appropriate to the actual operator of Rainflow.
5. Revisit the declarations whenever analytics, crash reporting, AI processing, email tooling, bank connectivity, or another third-party service is added.

## Data handling commitments in the current design

- Receipt access is user initiated.
- Receipt objects are private, owner scoped, and immutable to app clients after upload.
- Financial writes use authenticated server commands.
- Local cached data and staged receipts are removed on sign-out.
- No service-role key or backend secret is placed in the app.
- Testers must use disposable data until verified export and restore are implemented.
