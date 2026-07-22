# Card Transactions V2 — Design Spec

**Date:** 2026-04-18  
**Status:** Approved

## Overview

Four interconnected features for the TrackerPage: transaction editing, bulk pay, export (CSV + PDF), and billing cycle history. The goal is to give users full control over their card transactions and a permanent, browsable record of past billing cycles.

---

## Data Model

### New table: `billing_cycles`

```sql
id          uuid primary key default gen_random_uuid()
card_id     uuid references cards(id) not null
user_id     uuid references auth.users(id) not null
label       text not null          -- e.g. "April 2026"
start_date  date not null
end_date    date not null
closed_at   timestamptz not null default now()
created_at  timestamptz not null default now()
```

RLS: user_id-scoped, same pattern as `transactions`.

### Modified table: `transactions`

Add one nullable column:

```sql
cycle_id    uuid references billing_cycles(id) default null
```

- `NULL` = active transaction (current cycle)
- Non-null = archived into a closed billing cycle

No rows are deleted. Closing a cycle stamps `cycle_id` on paid transactions only.

---

## TrackerPage Layout (Option B: Tabs)

TrackerPage gains two tabs below the back button: **Active** and **History**.

### Active Tab

- `TransactionForm` (unchanged — add transaction)
- Action bar above the table:
  - Left: `[Bulk Pay]` toggle button
  - Right: `[Export CSV]` `[Export PDF]` (exports current active transactions)
- `TransactionTable` (extended):
  - Checkbox column — visible only in Bulk Pay mode; only unpaid/partial rows are selectable
  - Edit button per row — opens `TransactionEditModal`
  - Existing Pay / Archive actions unchanged
- `BulkPayBar` — appears above table when Bulk Pay mode is active
- **Close Cycle** button at bottom — enabled only when ≥1 paid transaction exists

### History Tab

- List of closed `billing_cycles` for this card, newest first
- Each cycle renders as a summary card: label, date range, total charged, total paid, transaction count
- Click to expand → read-only transaction list for that cycle
- Export CSV / Export PDF per expanded cycle

---

## Components

### New components

| Component | Location | Purpose |
|-----------|----------|---------|
| `TransactionEditModal` | `src/components/tracker/` | Edit modal pre-filled with all transaction fields |
| `BulkPayBar` | `src/components/tracker/` | Selection bar: count, total, Pay Selected + Cancel |
| `CloseCycleModal` | `src/components/tracker/` | Cycle label + date range inputs, summary, confirm |
| `CycleHistoryList` | `src/components/tracker/` | History tab: expandable cycle summary cards |
| `ExportButtons` | `src/components/tracker/` | Reusable CSV + PDF export buttons |

### New utilities

| File | Exports |
|------|---------|
| `src/utils/export.js` | `exportCSV(transactions, filename)`, `exportPDF(transactions, filename)` |

- `exportCSV` — native browser Blob API, no dependency
- `exportPDF` — uses `jsPDF` library (~200kb)

### New / modified hooks (`src/hooks/useTransactions.js`)

| Hook | Description |
|------|-------------|
| `useEditTransaction` | Updates all fields on a transaction row |
| `usePayBulk` | Accepts array of transactions; pays remaining balance on each; inserts payment records |
| `useBillingCycles(cardId)` | Fetches all billing_cycles for a card, ordered by closed_at desc |
| `useCloseCycle` | Creates billing_cycle row; stamps cycle_id on all paid transactions for the card |

---

## Feature Flows

### Transaction Editing

1. User clicks Edit on a transaction row
2. `TransactionEditModal` opens pre-filled with all fields (date, amount, due date, notes)
3. Same validation rules as TransactionForm (amount > 0, date not in future, amount ≤ available credit + current transaction amount)
4. On save: `useEditTransaction` patches the row; table refreshes; toast "Transaction updated"

### Bulk Pay

1. User clicks **Bulk Pay** — checkbox column appears; `BulkPayBar` mounts above table
2. Only unpaid/partial transactions are selectable (paid rows show a static checkmark)
3. `BulkPayBar` shows: "X selected · ₱total remaining" + **Pay Selected** + **Cancel**
4. Pay Selected → `usePayBulk` runs: for each selected transaction, inserts a payment record for the remaining balance and sets `payment_status = 'paid'`
5. Toast: "X transactions marked as paid"; Bulk Pay mode exits automatically
6. Installment transactions (partial payments already recorded): bulk pay pays the **remaining balance only**, not the full amount

### Close Cycle

1. User clicks **Close Cycle** at bottom of Active tab
2. `CloseCycleModal` opens:
   - Label input (default: "April 2026" — current month + year)
   - Start date / End date inputs (default: earliest and latest transaction dates)
   - Summary: "X paid transactions will be moved to history"
   - Warning if unpaid transactions exist: "Y transactions are still unpaid and will remain in Active"
3. Confirm → `useCloseCycle`:
   - Inserts `billing_cycles` row
   - Updates all paid transactions for this card (cycle_id = NULL) → sets cycle_id to new cycle
   - Unpaid transactions untouched
4. History tab immediately shows new cycle; toast "Cycle 'April 2026' closed"

### Export

- **Active tab export**: exports all currently visible active transactions
- **History tab export**: exports transactions belonging to the selected cycle
- CSV columns: Date, Amount, Due Date, Paid, Remaining, Status, Notes
- PDF: titled with card name + cycle label (or "Active Transactions"), same columns in a table layout

---

## Dependency

- `jsPDF` — add to package.json for PDF export

---

## Out of Scope

- Auto-close cycles
- Global history page across all cards (deferred to future Reports feature)
- Editing archived (closed-cycle) transactions
