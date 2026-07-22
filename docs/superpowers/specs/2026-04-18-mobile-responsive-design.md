# Mobile Responsive Design Spec

**Date:** 2026-04-18  
**Status:** Approved

## Overview

Three targeted fixes to make the app fully functional on mobile devices. No new pages or routes. Desktop layouts are unchanged throughout.

Breakpoint convention (Tailwind defaults):
- Mobile: `< 768px` (below `md`)
- Desktop: `≥ 768px` (`md` and up)

---

## Fix 1: Navbar — Bottom Navigation on Mobile

### Problem
All nav items render in one horizontal row. On mobile (~430px wide), the row overflows and "Sign Out" gets clipped.

### Solution

**Mobile layout (`md:hidden`):**
- **Top bar:** owl logo (left) · dark mode toggle + Sign Out button (right). No nav links. Single minimal row.
- **Bottom bar:** Fixed to bottom of viewport (`fixed bottom-0`), full width, 4 tabs:
  - Dashboard (home icon)
  - Shared (share icon) — red badge dot if `pendingInvites.length > 0`
  - Borrowers (people icon) — red badge dot if `pendingBorrowerInvites.length > 0`
  - Expenses (expenses icon)
- Active tab: brand green text + icon (`text-[#2D6A4F] dark:text-[#9FE870]`), inactive: gray
- Background: `bg-white dark:bg-gray-900`, top border, safe area padding for iPhone home indicator

**Desktop layout (`hidden md:flex`):**
- Current navbar row unchanged — logo, email, Shared, Borrowers, Expenses, dark mode, Sign Out

**Icons needed (already in icons.jsx or add):**
- Dashboard: use existing `OwlIcon` or a home icon
- Shared: existing share/link icon
- Borrowers: people/users icon
- Expenses: existing `ExpensesIcon`

**Body padding:**
- On mobile, add `pb-16` to the page wrapper so content isn't hidden behind the fixed bottom bar. Applied in `App.jsx` or via a layout wrapper.

---

## Fix 2: TrackerSummary — Responsive Stats

### Problem
`grid-cols-3` with `text-2xl font-mono` values. On narrow screens, long peso amounts (e.g. ₱806,123.78) overflow their columns and visually overlap adjacent values.

### Solution

**Mobile:** `grid-cols-2` — Total Charged (top-left), Total Paid (top-right), Outstanding spans full width below (`col-span-2`). Font size `text-lg` on mobile.

**Desktop (`sm:` and up):** `grid-cols-3`, font size `text-2xl` — unchanged from today.

Tailwind classes on the grid: `grid grid-cols-2 sm:grid-cols-3 gap-4`

StatBox value: `text-lg sm:text-2xl font-black font-mono`

Outstanding StatBox: `col-span-2 sm:col-span-1` so it spans full width on mobile only.

---

## Fix 3: Transaction Table — Mobile Card Layout

### Problem
TransactionTable has 9 columns. Even with `overflow-x-auto`, horizontal swiping is frustrating on mobile — users can't see all data without scrolling, and action buttons (Pay, Edit, Archive) are hard to tap.

### Solution

**Mobile (`md:hidden`):** Replace `<table>` with stacked card rows. Each transaction card shows:

```
┌─────────────────────────────────────┐
│ Apr 14, 2026              [Unpaid]  │  ← date + status badge
│ ₱26,417.83        Remaining: ₱26,417│  ← amount + remaining (red)
│ Due: Apr 30, 2026  · Groceries…     │  ← due date + notes truncated
│ [📎 2]  [Edit]  [Pay]  [Archive]    │  ← actions row
└─────────────────────────────────────┘
```

- Cards separated by a divider, rounded border, white bg
- Bulk pay mode: checkbox appears top-left of each card; paid cards show ✓
- Attachment button shows file count badge if > 0

**Desktop (`hidden md:block`):** Full table as today — unchanged.

---

## Fix 4: Expense Table — Mobile Card Layout

### Problem
ExpenseTable also has many columns (Date, Category, Description, Amount, Method, Notes, Actions) causing horizontal scroll on mobile.

### Solution

**Mobile (`md:hidden`):** Card rows per expense:

```
┌─────────────────────────────────────┐
│ Apr 14, 2026           [Utilities]  │  ← date + category badge
│ Meralco                  ₱2,000.00  │  ← description + amount
│ GCash · Electric bill…              │  ← payment method + notes
│                    [Edit]  [Archive] │  ← actions
└─────────────────────────────────────┘
```

**Desktop:** Full table unchanged.

---

## Files Modified

| File | Change |
|------|--------|
| `src/components/layout/Navbar.jsx` | Add mobile top bar + bottom nav; wrap desktop nav in `hidden md:flex` |
| `src/components/tracker/TrackerSummary.jsx` | Responsive grid + font sizes |
| `src/components/tracker/TransactionTable.jsx` | Add mobile card layout alongside existing table |
| `src/components/expenses/ExpenseTable.jsx` | Add mobile card layout alongside existing table |
| `src/App.jsx` or layout wrapper | Add `pb-16 md:pb-0` to page body to clear bottom nav |

---

## New Icons Needed

Add to `src/components/ui/icons.jsx` if not already present:
- `HomeIcon` — for Dashboard tab in bottom nav
- `UsersIcon` — for Borrowers tab in bottom nav

(`ExpensesIcon` and a share-style icon already exist)

---

## Out of Scope

- Mobile-specific pages or routes
- Touch gestures (swipe to delete, etc.)
- Any desktop layout changes
