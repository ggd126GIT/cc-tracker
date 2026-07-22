# Design Spec: Five Features — Dashboard Summary, Due Date Alerts, Card Deletion, Profile Page, Transaction Filters

**Date:** 2026-04-19  
**Status:** Approved

---

## Overview

Five independent features grouped into two parallel implementation batches based on file ownership to avoid merge conflicts.

- **Batch 1:** Dashboard Financial Summary + Due Date Alerts + Card Deletion
- **Batch 2:** Profile / Settings Page + Transaction Filters

---

## Batch 1

### 1. Dashboard Financial Summary

**Component:** `src/components/cards/DashboardSummary.jsx` (new)  
**Placement:** Above the "My Cards" grid in `DashboardPage`

Displays three stats computed from `ownCards` and their transactions:
- **Total Outstanding** — sum of `getRemainingBalance(t.amount, t.amount_paid)` across all unpaid/partial transactions for all owned cards
- **Total Credit Limit** — sum of `card.spending_limit` for all owned cards
- **Utilization %** — Total Outstanding ÷ Total Credit Limit × 100 (renders "—" if total limit is 0)

Data source: reuses `useTransactions(card.id)` already called by each `CardTile` — no new DB queries. Styled to match existing summary cards (white/dark bg, border, rounded-2xl).

**Error handling:** If no cards exist, component renders nothing (null).

---

### 2. Due Date Alerts

**Utility:** `src/utils/dates.js` (new) — exports `getDueDateStatus(dateStr, paymentStatus)`:
- Returns `null` if `paymentStatus === 'paid'` (paid transactions are never urgent)
- Returns `'overdue'` if date is before today
- Returns `'due-soon'` if date is within 7 calendar days from today
- Returns `null` otherwise (no due date, or due date is far away)

**CardTile** (`src/components/cards/CardTile.jsx`):
- Counts transactions where `getDueDateStatus` returns non-null
- Shows a badge on the tile: red for overdue count, orange for due-soon count
- Badge sits in the top-left of the card, does not overlap the Edit button

**TransactionTable** (`src/components/tracker/TransactionTable.jsx`):
- Due date cell gets conditional text color via `getDueDateStatus`:
  - `overdue` → `text-red-600 dark:text-red-400 font-semibold`
  - `due-soon` → `text-orange-500 dark:text-orange-400`
  - null → existing gray color unchanged

---

### 3. Card Deletion

**Hook:** `useDeleteCard` already exists in `src/hooks/useCards.js`  
**UI change:** Inside `CardForm` (edit mode only), add a Delete section at the bottom with:
- "Delete Card" button (red/destructive styling)
- Clicking reveals inline confirmation text: "This will permanently delete this card and all its transactions."
- Two buttons: "Yes, Delete" (red) and "Cancel"
- On confirm: calls `useDeleteCard`, closes modal, navigates to `/`

**Prerequisite:** Verify Supabase `transactions` table has `ON DELETE CASCADE` on `card_id` FK. If not, add migration before wiring UI.

**Error handling:** Show toast error if deletion fails (e.g. DB constraint).

---

## Batch 2

### 4. Profile / Settings Page

**Route:** `/profile`  
**File:** `src/pages/ProfilePage.jsx` (new)  
**Added to:** `App.jsx` routes + `Navbar.jsx` nav links

**Navbar changes:**
- Desktop: add "Profile" text link between the email display and the dark mode toggle
- Mobile bottom nav: add Profile icon as 5th tab (uses existing `UserIcon` or similar from `icons.jsx`)

**Page sections (each submits independently):**

**Display Name**
- Text input pre-filled from `user.user_metadata?.display_name`
- Save calls `supabase.auth.updateUser({ data: { display_name: value } })`
- On success: update Zustand store user, show success toast
- Navbar shows `display_name` instead of `email` once set

**Change Password**
- Two inputs: New Password + Confirm Password
- Client-side: validate both match before submitting
- Save calls `supabase.auth.updateUser({ password: value })`
- On success: show success toast, clear inputs
- On error: show error toast with Supabase error message

**Error handling:** All errors surface via existing `useToast` / `ToastContainer`.

---

### 5. Transaction Filters

**Location:** `TrackerPage.jsx` — filter bar added between `TrackerSummary` and `TransactionTable`  
**Component:** Inline JSX in `TrackerPage` (no separate file needed — simple enough)

**Controls:**
- **Status pills:** All | Unpaid | Partial | Paid  
  Styled as pill toggles; active pill uses `bg-[#9FE870]/20 text-[#2D6A4F] dark:text-[#9FE870]` (matches existing active nav style)
- **Date range:** Two `<input type="date">` fields labeled "From" and "To", filtering on `transaction_date`

**Filtering logic:** `useMemo` in `TrackerPage` derives `filteredTransactions` from `transactions`:
```js
const filteredTransactions = useMemo(() => {
  return transactions.filter((t) => {
    if (statusFilter !== 'all' && t.payment_status !== statusFilter) return false
    if (dateFrom && t.transaction_date < dateFrom) return false
    if (dateTo && t.transaction_date > dateTo) return false
    return true
  })
}, [transactions, statusFilter, dateFrom, dateTo])
```

`TransactionTable` receives `filteredTransactions` instead of raw `transactions`.  
Filters apply to the active tab only (active transactions). Archived tab is unaffected.

**No new hooks, no new DB calls.**

---

## Implementation Strategy

Two parallel agents, each working a batch independently:

| Batch | Features | Files touched |
|-------|----------|---------------|
| 1 | Dashboard Summary + Due Date Alerts + Card Deletion | `DashboardPage`, `CardTile`, `CardForm`, `TransactionTable`, new `DashboardSummary`, new `dates.js` util |
| 2 | Profile Page + Transaction Filters | `App.jsx`, `Navbar.jsx`, `TrackerPage`, new `ProfilePage` |

Zero file overlap between batches — safe to run in parallel.
