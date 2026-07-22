# Expenses Tracker — Design Spec
**Date:** 2026-04-14
**Status:** Approved

---

## Overview

Add a dedicated **Expenses** section to CC Tracker for logging all non-card spending — cash payments, utilities, rent, food, travel, etc. This is pure expense logging with no budget limits, keeping it simple enough to build a daily habit.

---

## Data Model

New Supabase table: `expenses`

| Field | Type | Constraints |
|-------|------|-------------|
| `id` | uuid | PK, default gen_random_uuid() |
| `user_id` | uuid | FK auth.users, not null |
| `category` | text (enum) | not null — see values below |
| `description` | text | not null |
| `amount` | numeric(12,2) | not null, > 0 |
| `expense_date` | date | not null |
| `payment_method` | text (enum) | not null — see values below |
| `notes` | text | nullable |
| `archived` | boolean | default false |
| `created_at` | timestamptz | default now() |

**Category values:**
`utilities`, `food`, `transportation`, `rent`, `healthcare`, `shopping`, `entertainment`, `subscriptions`, `education`, `personal_care`, `insurance`, `others`

**Payment method values:**
`cash`, `gcash`, `maya`, `bank_transfer`, `others`

**RLS Policy:** Users can only SELECT/INSERT/UPDATE/DELETE their own rows (`user_id = auth.uid()`).

---

## UI — Dashboard

The existing dashboard (`DashboardPage.jsx`) gets a third section below "My Borrowers":

- Heading: "My Expenses" with subtitle showing this month's total (e.g., "₱12,400 this April")
- "View All" ghost button → navigates to `/expenses`
- "+ Add Expense" primary button → opens `ExpenseForm` modal
- Empty state with icon + prompt if no expenses this month

---

## UI — Expenses Page (`/expenses`)

### 1. Sticky Summary Header (`ExpenseSummary.jsx`)
Mirrors `TrackerSummary`. Shows:
- **This Month Total** — large `font-black font-mono` number
- **Breakdown row** — Cash / GCash / Maya / Bank Transfer totals for the month

### 2. Category Tiles Row (`CategoryTiles.jsx`)
One tile per category. Each tile shows:
- Category icon (SVG, added to `icons.jsx`)
- Category label
- Total spent this month
- Muted/gray if ₱0, colored if has activity

### 3. Filter Bar
- Month/year selector (left-right arrow navigation, defaults to current month)
- Category dropdown filter (All + each category)
- Payment method filter (All + each method)

Filtering is client-side on already-fetched data.

### 4. Expenses Table (`ExpenseTable.jsx`)
Columns: Date | Category | Description | Amount | Payment | Notes | Actions

- Amount: right-aligned, `font-mono`, red tint (it's spending)
- Category: colored badge matching design system
- Actions: Edit (opens `ExpenseForm` pre-filled) | Archive (confirm inline, same pattern as TransactionTable)

Empty state: "No expenses for this period."

---

## UI — Expense Form (`ExpenseForm.jsx`)

Modal form (same pattern as `LoanForm`, `TransactionForm`):

Fields:
1. **Date** — date input, defaults to today
2. **Category** — select dropdown with all 12 categories
3. **Description** — text input, required
4. **Amount** — numeric input, required
5. **Payment Method** — select dropdown
6. **Notes** — textarea, optional

Supports both **add** and **edit** modes (passed via `expense` prop).

---

## Navigation

- Add "Expenses" link to `Navbar.jsx` alongside "Shared" and "Borrowers"
- Active state follows existing green pill pattern
- New protected route in `App.jsx`: `/expenses` → `<ExpensesPage />`

---

## New Files

| File | Purpose |
|------|---------|
| `src/pages/ExpensesPage.jsx` | Main expenses page |
| `src/components/expenses/ExpenseSummary.jsx` | Sticky summary header |
| `src/components/expenses/CategoryTiles.jsx` | Category overview tiles |
| `src/components/expenses/ExpenseTable.jsx` | Filterable expense table |
| `src/components/expenses/ExpenseForm.jsx` | Add/edit modal |
| `src/hooks/useExpenses.js` | React Query hooks (fetch, add, edit, archive) |

---

## Architecture Notes

- All data fetching via React Query + Supabase — same pattern as `useTransactions`, `useLoans`
- Mutations: `useAddExpense`, `useEditExpense`, `useArchiveExpense`
- Month filtering: client-side on fetched data (no pagination needed at personal use scale)
- No new global store — React Query handles all server state
- Category icons: extend existing `icons.jsx` with one SVG per category

---

## Out of Scope

- Budget limits per category (intentionally excluded — pure logging)
- Recurring expense scheduling
- Expense sharing with other users
- Export / reports (future feature)
