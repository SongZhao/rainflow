# Rainflow TODO

**Last updated:** 2026-09-19

This file tracks concrete engineering work that should be picked up later. It is not a source of truth for deployed behavior; current `main` and production data remain authoritative.

## Receipt merchant false-positive hotfix — completed 2026-09-19

- Production transactions incorrectly saved as `Curio/curio` were corrected to `Target` and `Daiso`.
- The Michaels product-title transaction was corrected to merchant `Michaels`.
- Production `extract-receipt` v8 now rejects obvious product descriptions as merchant candidates and cross-checks merchant candidates against parsed line-item descriptions.
- Known recurring merchant headers (`Michaels`, `Daiso`, `Target`, `The UPS Store`) are normalized before weaker candidates.
- A weak single-word header such as `Curio` is no longer accepted on position alone. If stronger merchant evidence is absent, merchant is left blank for review rather than silently saved.
- Regression coverage includes:
  - product title above `MICHAELS`;
  - `Curio` above an explicit `DAISO` header;
  - `Curio` without stronger merchant evidence;
  - single-word `Target`;
  - the existing Ace Hardware receipt.
- Production received the merchant work as narrow v7/v8 backports on top of the previously deployed parser so unfinished line-item changes from `main` were not rolled out accidentally.

**Important deployment note:** while validating the merchant fix, the newer line-item parser currently in `main` incorrectly associated a `3 x $9.99` line with the preceding `Order date ...` line in a synthetic Michaels fixture. Do not wholesale deploy that newer parser until the line-item TODO below is completed and this regression is fixed.

## Receipt category auto-selection — implemented, continue hardening

Current web behavior:

- OCR provides merchant + line-item evidence; category selection happens after extraction in the web client.
- A user's explicit category selection always wins and is never overwritten by later auto-selection.
- Previously confirmed transactions for the same merchant are checked **before** generic keyword rules.
- Merchant history canonicalizes store-number variants, including `MICHAELS STORE #6713` → `Michaels` and `The UPS Store #5833` → `The UPS Store`.
- The currently confirmed production mappings therefore teach future imports:
  - Michaels / Daiso → `Class material supplies`
  - The UPS Store printing → `Office supplies`
  - Target / Pho Tick Tock / Gardenia Los Gatos → `Employee benefits`
- New receipt rules also recognize:
  - art/craft/class-material evidence → `Class material supplies`
  - printing/office evidence → `Office supplies`
  - explicit employee/staff meal wording → `Employee benefits`
  - business-license/accounting/software/hosting evidence → `Business operation`
  - parking/toll/transit evidence → `Transportation`
- New restaurants with no confirmed history remain `Dining`; Rainflow does not assume every restaurant receipt is an employee benefit.
- Playwright regression coverage protects the confirmed merchant-history mappings and the new business-category rules.
- When Rainflow cannot confidently classify an expense, the UI now shows up to **6 frequent expense categories** ranked from the active ledger's transaction history before the full category dropdown.
- Low-confidence fallback no longer silently commits `Other Expenses`; the user must choose one of the quick categories or use the full list.

Remaining category work:

- Move category suggestion into shared domain/server logic so web and iPhone use the same classifier.
- Store category suggestion provenance/confidence (merchant history vs receipt rule vs fallback).
- Add an explicit correction-feedback model so a user's changed category can become durable merchant/category training data rather than relying only on transaction history.
- Support ledger-specific classification profiles if personal and business ledgers need different semantics for the same merchant.
- Never auto-save a low-confidence category without showing it for review.

## Receipt extraction parser hardening

### Context

On 2026-09-19 we re-ran Google Vision OCR against all 31 active production receipt images and audited the resulting transaction line items.

The current `extract-receipt` parser can produce structurally valid but semantically wrong line items when receipt content is split across multiple OCR lines. Examples observed in production included:

- Michaels: `Reg`, `1.0 @`, and `YOU SAVED` were treated as merchandise.
- Product descriptions printed on one line and price/quantity on later lines were not associated reliably.
- Modifiers such as restaurant add-ons can be detached from their parent item.
- Merchant abbreviations and truncated receipt descriptions can be persisted as if they were complete names.
- Receipt summary fields, rewards information, discounts, tax, card/reference numbers, and savings lines need stronger exclusion rules.
- A receipt total is not always equal to the transaction being recorded. One Target receipt totaled $19.99 while the transaction represented only the $10.67 health-item portion, so parser output must not assume the entire receipt belongs to the transaction.

Production line items were manually repaired from the OCR text and, where an exact product identifier was available, authoritative product listings. This data repair does **not** fix the parser for future uploads.

### TODO

- Replace the current same-line-only item matcher with a multi-line receipt item parser.
- Associate description, SKU/UPC/item number, quantity, unit price, extended price, discount, and modifier lines as one logical item block.
- Support common layouts where:
  - description precedes quantity/price by one or more lines;
  - price columns are OCR'd vertically rather than horizontally;
  - quantity is expressed as `QTY @ unit price` or `unit price x quantity`;
  - restaurant modifiers follow the parent item;
  - weighted items have fractional quantities and prices with more precision than currency minor units.
- Explicitly reject summary/non-item lines including total, subtotal, tax, tip, fee, payment, tender, balance, reward/points, savings, discount, card/account/reference/auth numbers, and `YOU SAVED`.
- Do not use rewards/points values as transaction totals.
- Preserve OCR evidence/provenance long enough for review without exposing raw receipt text to clients unnecessarily.
- Add a confidence score or review flag for line items rather than persisting low-confidence guesses as normal items.
- Never overwrite a user's manually edited category or line item with a later automatic suggestion.
- Handle partial-receipt / partial-transaction cases: extracted item totals may legitimately represent only part of the photographed receipt.

### Regression fixtures

Add anonymized fixtures/tests covering at least:

- Michaels multi-line floral receipt with clearance discounts.
- Daiso SKU + description + price layout.
- UPS quantity/unit-price printing services.
- Pho Tick Tock quantity lines and modifiers.
- Gardenia/Toast restaurant item + add-on layout.
- Costco abbreviated SKU descriptions, weighted merchandise, and food-court receipts.
- Target receipt where only a subset of the receipt belongs to the saved transaction.
- Receipt with rewards points that numerically resemble a purchase total.

### Acceptance criteria

- No summary, discount, rewards, payment, card, or reference line is returned as a line item.
- Item description/quantity/unit-price/amount associations match the regression fixtures.
- Quantity × unit price agrees with amount when the receipt provides all three, except documented discount/rounding cases.
- Weighted/fractional items preserve quantity and total even when unit price has sub-cent precision.
- Parser output never silently changes an already-saved transaction amount.
- Low-confidence results require review instead of being presented as confirmed line items.
- New parser behavior is covered by automated tests before production deployment.
