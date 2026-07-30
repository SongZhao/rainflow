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

Receipt OCR is server-side. Phone and desktop web receipt import sends the
selected image to the Supabase `extract-receipt` Edge Function. That function
calls Google Vision only when `GOOGLE_VISION_API_KEY` is configured in Supabase
secrets, then returns editable suggestions for merchant, amount, receipt date,
and line items. The Google key must never be exposed to the browser.

If OCR is not configured or cannot confidently parse a receipt, the image still
stays attached and the user manually reviews or enters the fields before saving.
