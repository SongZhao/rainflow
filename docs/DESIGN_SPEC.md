# Rainflow Product Design Specification

**Status:** Approved implementation baseline  
**Audience:** Product, design, iOS, web, backend, QA  
**Last updated:** 2026-07-26  
**Reference implementation:** `apps/ios`, `apps/web`  
**Visual reference:** [First-pass design board](./assets/rainflow-first-pass.png)

## 1. Purpose

This document translates the Rainflow product and accounting requirements into a consistent user experience for the native iPhone application and the Mac-oriented web application.

Rainflow is a modern personal-finance ledger. It should feel visually rich and approachable while preserving deterministic double-entry accounting underneath. The design is inspired by the information hierarchy, card rhythm, and chart-forward presentation of modern finance products such as Monarch Money, but it must use Rainflow-specific branding, interaction patterns, and components rather than copying another product.

Related documents:

- [Product requirements](./PRODUCT.md)
- [Architecture](./ARCHITECTURE.md)
- [AI rules](./AI_RULES.md)
- [Roadmap](./ROADMAP.md)
- [ADR-001: SwiftUI](./DECISIONS/ADR-001-SwiftUI.md)
- [ADR-005: Client-server authority](./DECISIONS/ADR-005-ClientServer.md)
- [ADR-006: Web application stack](./DECISIONS/ADR-006-WebStack.md)

## 2. Experience Goals

Rainflow should make the following activities feel immediate and trustworthy:

1. Capture an expense or income entry in seconds.
2. Understand current cash position without interpreting accounting terminology.
3. Find and correct a transaction safely.
4. See where money is going through simple visual summaries.
5. Move between iPhone and Mac without learning two different products.

The interface must favor clarity over density on iPhone and productivity over decoration on Mac web.

## 3. Design Principles

### 3.1 Capture first

The primary iPhone action is the center Capture control. It opens a task sheet rather than navigating to a persistent tab.

Available actions:

- Take Photo
- Choose from Library
- Add Manually

A receipt never posts a transaction automatically. It creates or enriches a draft that the user reviews and confirms.

### 3.2 Financial meaning is visually stable

- Income and favorable positive movement use semantic green.
- Expenses and unfavorable negative movement use semantic red.
- Rainflow blue is reserved for navigation, selection, primary actions, and neutral charts.
- Warning amber is used for missing information, attachment integrity problems, and review-required states.
- Color is never the only signal; labels, signs, shapes, and icons accompany it.

### 3.3 Cards summarize; lists operate

Cards are used for dashboard summaries, account groups, and report summaries. Dense operational tasks such as transaction search and editing use lists, forms, or tables.

### 3.4 Accounting complexity stays behind familiar language

Normal screens use Account, Category, Transaction, Transfer, Split, and Balance. Posting, debit, credit, journal, and balancing details appear only in diagnostic or advanced contexts.

### 3.5 Every destructive or conflicting state is recoverable

- Transaction deletion is recoverable.
- Account hard deletion requires the documented two-step challenge.
- Stale edits show a conflict screen rather than overwriting changes.
- Failed uploads preserve the transaction draft.
- Missing authoritative attachments show an in-app incident state.

### 3.6 Reversible product decisions stay isolated

Navigation order, report selection, dashboard card ordering, authentication provider, and web framework must not leak into domain rules or stored accounting semantics.

## 4. Brand Foundation

### 4.1 Name and mark

**Product name:** Rainflow  
**Placeholder mark:** a simplified blue water drop. The implementation may use the SF Symbol `drop.fill` until a final logo is delivered.

Brand voice:

- Calm
- Clear
- Trustworthy
- Modern
- Direct

Suggested tagline for product surfaces: **Modern finance. Clear insights.**

### 4.2 Color tokens

The first implementation uses the following tokens. Components consume semantic tokens rather than hard-coded values.

| Token | Dark value | Light value | Purpose |
|---|---:|---:|---|
| `background` | `#071014` | `#F5F8FA` | App canvas |
| `surface` | `#10191D` | `#FFFFFF` | Primary card |
| `surfaceElevated` | `#162126` | `#F0F4F6` | Sheets, selected regions |
| `border` | `#26343A` | `#D8E1E5` | Dividers and outlines |
| `textPrimary` | `#F4F8FA` | `#102027` | Main labels |
| `textSecondary` | `#94A3AA` | `#60727A` | Supporting labels |
| `brand` | `#1E8DFF` | `#0878E8` | Primary action and selection |
| `brandAccent` | `#12C6D7` | `#00A7BC` | Secondary brand highlight |
| `income` | `#27C98B` | `#078B5A` | Income and positive values |
| `expense` | `#FF5C63` | `#D92F3A` | Expense and negative values |
| `warning` | `#FFB020` | `#B86B00` | Review or integrity warning |

Chart palettes should derive from these colors plus accessible tints. Avoid large collections of unrelated saturated colors.

### 4.3 Typography

#### iPhone

Use San Francisco through SwiftUI semantic text styles. Dynamic Type is mandatory.

| Role | Preferred style |
|---|---|
| Screen title | `.title2.weight(.semibold)` |
| Hero balance | `.largeTitle.weight(.semibold)` |
| Card title | `.headline` |
| Body | `.body` |
| Amount row | `.body.monospacedDigit()` |
| Caption | `.caption` or `.footnote` |

#### Web

Use `-apple-system`, BlinkMacSystemFont, and system fallbacks. Monetary values use tabular numerals.

### 4.4 Spacing, shape, and elevation

Base spacing unit: 4 points/pixels.

- Screen horizontal inset: 16 on iPhone; 24–32 on web.
- Card internal padding: 16.
- Card gap: 12–16.
- Primary card radius: 20 on iPhone; 16 on web.
- Input radius: 12.
- Pills and chips: full capsule radius.
- Minimum interactive target: 44 × 44 points.
- Shadows should remain subtle. Dark mode primarily communicates elevation through surface contrast and borders.

### 4.5 Iconography

- iPhone uses SF Symbols.
- Web uses a consistent outline icon set or matching local SVGs.
- Icon meaning must remain consistent across platforms.
- The center iPhone action uses a camera icon in a visually elevated circular control.

## 5. Information Architecture

### 5.1 iPhone navigation

Persistent destinations:

1. Dashboard
2. Accounts
3. Capture action — task launcher, not a destination
4. Transactions
5. Reports

The center Capture button opens a bottom sheet. The previously selected destination remains selected after cancellation. Successful creation opens the saved transaction or returns to Transactions based on user action.

Budget, Recurring, Attachments, Settings, profile, export, and ledger management are reachable through contextual cards or a More/Settings surface rather than additional bottom tabs.

### 5.2 Mac web navigation

Persistent left sidebar:

- Dashboard
- Accounts
- Transactions
- Reports
- Attachments
- Recurring
- Budget — feature-flagged until implemented
- Settings

A global **Add transaction** control is always available in the header. Drag-and-drop receipt upload is supported wherever the add flow is available.

### 5.3 Browser tabs and stale edits

The web interface supports normal multiple tabs and windows. Every edit submits an expected revision. A stale revision opens a conflict surface containing:

- Current server version summary
- User’s unsaved draft
- Reload current version
- Copy unsaved values
- Restart edit

Automatic field merging is outside the MVP.

## 6. Screen Specifications

## 6.1 Authentication

### Email entry

- Rainflow mark and product name
- Email field
- Continue button
- Short privacy statement
- Loading and inline validation states

### OTP verification

- Numeric email code input
- Resend timer
- Change email action
- Trusted-device session established after success

Authentication errors must never discard a locally prepared transaction draft.

## 6.2 Dashboard

Purpose: answer “Where do I stand?” and “What changed recently?”

Card order for the MVP:

1. Net worth or total balance trend
2. This-month cash flow
3. Recent transactions
4. Account balances
5. Spending summary
6. Recurring items

Required behaviors:

- Period selector defaults to current month where appropriate.
- Every card has a single obvious drill-down action.
- Empty cards provide one useful action rather than placeholder charts.
- iPhone should show no more than two large charts before requiring scroll.
- Web may show four summary cards in one row and a wider chart/table layout below.

## 6.3 Accounts

Purpose: browse balances and open account registers.

Content:

- Total balance or net worth header
- Time-range selector for trend display
- Account groups: Cash, Investments, Credit Cards, Loans, and other applicable groups
- Group totals
- Account name, subtype, masked suffix when present, current balance, and last update
- Add account action

Behavior:

- Tapping an account opens its register.
- Archived accounts are hidden by default but available through a filter.
- Negative liability values are presented in familiar liability language; storage signs remain internal.

## 6.4 Capture action

The center action opens a bottom sheet with:

1. **Take Photo** — opens the camera.
2. **Choose from Library** — opens the system photo picker.
3. **Add Manually** — opens the manual transaction flow.
4. Cancel.

### Photo path

```text
Capture or choose image
→ Preview and crop/rotate when needed
→ Copy image into application-managed temporary storage
→ Create receipt-backed draft
→ Run deterministic extraction and optional AI suggestion
→ Review fields and original image
→ Save through the standard transaction command
→ Finalize private attachment manifest
```

If extraction is unavailable, the image remains attached and the user completes fields manually.

### Permission behavior

- Ask for camera permission only after Take Photo is selected.
- Photo library access uses the system picker and should prefer limited access APIs.
- Denied permission shows a concise explanation and a Settings deep link.

## 6.5 Manual transaction flow

The MVP uses a guided four-stage flow that may be displayed as separate screens on iPhone and as one wider form on web.

### Stage 1: amount and type

- Segmented control: Expense, Income, Transfer
- Large amount field with numeric keypad
- Currency indicator from the ledger
- Continue disabled until amount is valid and nonzero

### Stage 2: essential details

Expense:

- Payment account
- Category
- Accounting date
- Optional payee
- Optional note

Income:

- Deposit account
- Income category
- Accounting date
- Optional payer/payee
- Optional note

Transfer:

- From account
- To account
- Accounting date
- Optional note

### Stage 3: receipt and advanced details

- Add or replace receipt
- Tags
- Split transaction
- Additional attachments when enabled

### Stage 4: review and save

Show:

- Signed display amount
- Date
- Payee
- Account and category/destination
- Split rows
- Note and tags
- Receipt thumbnail
- Any AI-suggested fields still requiring review

The save control remains disabled until deterministic validation succeeds.

### Success state

- Confirmation icon
- Saved amount and summary
- View Transaction
- Done

## 6.6 Transactions

Purpose: search, inspect, and correct the ledger.

Content:

- Search field
- Filter chips: All, Income, Expenses, Transfers
- Filter sheet for date range, accounts, categories, merchants/payees, amounts, tags, review state, and deleted state where authorized
- Rows grouped by accounting date
- Daily subtotal in the group header when useful
- Merchant/payee or description
- Category/account subtitle when space allows
- Amount aligned right with tabular numerals

Behavior:

- Tap opens transaction detail.
- Swipe actions may expose Edit and Delete after usability testing; they are not required in the first build.
- Soft-deleted transactions are available through a separate filter and may be restored.
- Search and filtering preserve scroll position when returning from detail.

## 6.7 Transaction detail and edit

- Complete transaction summary
- Account/category rows
- Split allocation list
- Receipt gallery
- Created and updated timestamps
- Edit action
- Recoverable Delete action

Editing replaces the complete posting set atomically. The user interface does not expose partial posting saves.

## 6.8 Reports

Top-level segments:

- Cash Flow
- Spending
- Income

Controls:

- Chart type where multiple representations are useful
- Timeframe: month, quarter, year, custom
- Filter button
- Export/share where supported

### Cash Flow

- Income bars
- Expense bars
- Net line
- Summary: income, expenses, net cash flow

### Spending

- Donut by category by default
- Category legend and values
- Summary: total spending, transaction count, largest transaction, average transaction

### Income

- Donut or bars by category/source
- Summary: total income, transaction count, largest transaction, average transaction

Charts must include accessible text summaries and selectable data values. A chart may never be the only representation of a financial result.

## 6.9 Attachments

Web-first management screen:

- Receipt thumbnail
- Transaction link
- File name and upload date
- Integrity state
- Search and filter
- Retry or replace for failed upload

Missing or corrupt authoritative objects display a warning state. The user receives one deduplicated email per integrity incident as defined by the architecture.

## 6.10 Settings

MVP settings:

- Profile and verified email
- Appearance: System, Light, Dark
- Ledger name and currency display
- Export and backup
- Archived accounts
- Notification preferences
- Sign out
- Account deletion

The ledger currency is disabled after the first posted transaction and explains why.

## 7. Component Inventory

Shared conceptual components:

- App shell
- Navigation item
- Primary, secondary, destructive, and text buttons
- Finance card
- Metric card
- Account row
- Transaction row
- Amount label
- Search field
- Filter chip
- Segmented control
- Form field row
- Date picker row
- Account/category picker
- Receipt thumbnail
- Attachment status badge
- Empty state
- Loading skeleton
- Inline error
- Toast/banner
- Confirmation sheet
- Conflict sheet
- Donut, bar, and trend chart

Components must consume design tokens and semantic values. They must not determine accounting signs or transform ledger amounts independently.

## 8. State and Error Design

Every major screen requires these states:

- Loading
- Loaded
- Empty
- Recoverable error
- Offline cached read
- Permission denied where applicable
- Authentication expired

Mutation-specific states:

- Saving
- Uploading attachment
- Validation blocked
- Stale revision conflict
- Server failure with draft preserved
- Duplicate warning
- Success

Copy should state what happened and what the user can do next. Avoid generic “Something went wrong” messages when a typed failure is available.

## 9. Accessibility

- Support Dynamic Type without clipping essential values.
- Minimum 44-point touch targets.
- Respect Reduce Motion and Increase Contrast.
- Use VoiceOver labels that include amount meaning, not only visual sign or color.
- Provide chart summaries and selectable data points.
- Maintain at least WCAG AA contrast on web.
- Do not rely on red/green distinction alone.
- Preserve logical keyboard and screen-reader focus order.
- Web dialogs trap focus and restore it to the triggering control on close.

## 10. Formatting Rules

- The interface locale is initially en-US.
- Currency formatting follows the ledger currency and its minor-unit scale.
- Monetary values use tabular numerals.
- Dates display in familiar local form while accounting dates remain date-only domain values.
- Positive signs are shown selectively: income and explicit positive movement may use `+`; neutral balances normally omit it.
- Expense entry displays the user-entered amount as positive while the review/transaction representation communicates expense meaning through context and semantic color. Stored sign rules remain domain-owned.

## 11. Responsive Web Behavior

- Primary desktop target: current Safari on Mac.
- Full sidebar at widths of 1100px and above.
- Collapsible sidebar at narrower widths.
- Dashboard changes from four columns to two and then one.
- Transaction table hides lower-priority columns before becoming a card list.
- Forms use two columns when space permits and one column on narrow screens.
- Charts preserve labels and accessible summaries when resized.

## 12. Implementation Mapping

### iPhone

- SwiftUI and Swift Charts
- Custom bottom navigation to support a center task action
- `PhotosPicker` for library selection
- Camera bridge for image capture
- Observable feature stores backed by isolated API and persistence adapters
- GRDB snapshot cache and pending-receipt queue behind the ledger store

### Web

- Next.js with TypeScript
- CSS custom properties for tokens
- Server-authoritative API boundary
- Supabase session adapter isolated from UI components
- Browser-local prototype repository remains temporary and is replaceable by the authenticated server adapter

### Backend

- PostgreSQL is authoritative
- Complete transaction commands are atomic
- Attachments use staged object storage finalization
- Expected revisions protect edits

## 13. MVP Design Acceptance Criteria

The design implementation is acceptable when:

- The five-item iPhone bottom bar includes a functional center Capture action.
- The capture sheet exposes camera, library, and manual entry.
- Dashboard, Accounts, Transactions, and Reports use one coherent token system.
- Manual expense, income, and transfer flows can reach a deterministic review state.
- Receipt-backed drafts retain the selected image through validation failure.
- Transaction rows and report summaries use consistent amount semantics.
- Web navigation, dashboard, account list, transaction table, report view, and add flow are usable with keyboard input.
- Empty, loading, error, and stale-edit states are specified and testable.
- Light and dark appearances are supported, with dark mode as the first visual reference.
- No UI component writes ledger rows directly.

## 14. Deferred but Preserved

The following are deferred without closing the architectural door:

- Full budgeting
- Rich recurring-rule automation
- CSV import until beta
- Bank connections
- Shared ledgers
- Multiple ledgers exposed in the UI
- Append-only transaction revision history
- Native iPad or macOS clients
- Real-time collaborative editing
- Advanced AI categorization and insights

Database identifiers, ledger ownership fields, revision fields, repository boundaries, and feature flags must remain compatible with these future additions.
