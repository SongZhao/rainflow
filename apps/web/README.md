# Rainflow Web

Mac-oriented Rainflow web implementation using Next.js, TypeScript, and the
same Supabase backend as the iPhone app.

## Run

```bash
npm install
npm run dev
```

Open `http://localhost:3000`.

The web app reads Supabase settings from `.env.local`:

```text
NEXT_PUBLIC_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

The prototype includes:

- Email sign-in code authentication
- Shared Supabase ledger, account, transaction, and attachment reads
- Atomic transaction creation through the same `create_transaction` RPC used by iPhone
- Responsive sidebar shell
- Dashboard, Accounts, Transactions, Reports, and Attachments
- Functional add-transaction dialog
- Receipt photo/file selection, private upload, manifest finalization, and viewing
- Reusable design tokens and responsive components

Receipt OCR remains iPhone-first. Web receipt import stores the selected image
with the saved transaction and exposes temporary private viewing links from the
Transactions and Attachments screens.
