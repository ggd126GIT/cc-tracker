# Batch 1: Dashboard Summary + Due Date Alerts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a financial summary strip to the Dashboard and visually alert users to overdue or soon-due transactions on both the card tile and transaction row.

**Architecture:** A new `getDueDateStatus` util drives all alert logic. `DashboardSummary` uses React Query's `useQueries` to aggregate transaction data across all cards (query cache is shared with `CardTile`, so no extra DB calls when both are mounted). `CardTile` and `TransactionTable` import the util directly.

**Tech Stack:** React, @tanstack/react-query (`useQueries`), Vitest, Tailwind CSS, Supabase (existing hooks)

> **Note:** Card deletion was already fully implemented in `CardForm.jsx` (confirmed during planning). No work needed for that feature.

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `src/utils/dates.js` | `getDueDateStatus(dateStr, paymentStatus)` util |
| Create | `src/utils/dates.test.js` | Unit tests for dates util |
| Create | `src/components/cards/DashboardSummary.jsx` | Summary strip: outstanding, limit, utilization |
| Modify | `src/components/cards/CardTile.jsx` | Add due date alert badge |
| Modify | `src/components/tracker/TransactionTable.jsx` | Add due date color in rows |
| Modify | `src/pages/DashboardPage.jsx` | Render DashboardSummary above card grid |

---

### Task 1: Create `getDueDateStatus` utility

**Files:**
- Create: `src/utils/dates.js`
- Create: `src/utils/dates.test.js`

- [ ] **Step 1: Write the failing tests**

Create `src/utils/dates.test.js`:

```js
import { describe, it, expect } from 'vitest'
import { getDueDateStatus } from './dates.js'

describe('getDueDateStatus', () => {
  it('returns null when no date provided', () => {
    expect(getDueDateStatus(null, 'unpaid')).toBe(null)
    expect(getDueDateStatus('', 'partial')).toBe(null)
  })

  it('returns null for paid transactions regardless of date', () => {
    expect(getDueDateStatus('2020-01-01', 'paid')).toBe(null)
    expect(getDueDateStatus('2099-12-31', 'paid')).toBe(null)
  })

  it('returns overdue for dates before today', () => {
    expect(getDueDateStatus('2020-06-15', 'unpaid')).toBe('overdue')
    expect(getDueDateStatus('2020-06-15', 'partial')).toBe('overdue')
  })

  it('returns due-soon for today', () => {
    const today = new Date().toISOString().split('T')[0]
    expect(getDueDateStatus(today, 'unpaid')).toBe('due-soon')
  })

  it('returns due-soon for dates within 7 days', () => {
    const d = new Date()
    d.setDate(d.getDate() + 4)
    const dateStr = d.toISOString().split('T')[0]
    expect(getDueDateStatus(dateStr, 'unpaid')).toBe('due-soon')
  })

  it('returns due-soon for exactly 7 days away', () => {
    const d = new Date()
    d.setDate(d.getDate() + 7)
    const dateStr = d.toISOString().split('T')[0]
    expect(getDueDateStatus(dateStr, 'unpaid')).toBe('due-soon')
  })

  it('returns null for dates more than 7 days away', () => {
    const d = new Date()
    d.setDate(d.getDate() + 30)
    const dateStr = d.toISOString().split('T')[0]
    expect(getDueDateStatus(dateStr, 'unpaid')).toBe(null)
  })
})
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
npx vitest run src/utils/dates.test.js
```

Expected: FAIL — "Cannot find module './dates.js'"

- [ ] **Step 3: Implement `dates.js`**

Create `src/utils/dates.js`:

```js
export function getDueDateStatus(dateStr, paymentStatus) {
  if (!dateStr || paymentStatus === 'paid') return null
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  const due = new Date(dateStr + 'T00:00:00')
  const diffDays = Math.ceil((due - today) / (1000 * 60 * 60 * 24))
  if (diffDays < 0) return 'overdue'
  if (diffDays <= 7) return 'due-soon'
  return null
}
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
npx vitest run src/utils/dates.test.js
```

Expected: all 7 tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/utils/dates.js src/utils/dates.test.js
git commit -m "feat: add getDueDateStatus utility for due date alerts"
```

---

### Task 2: Create `DashboardSummary` component

**Files:**
- Create: `src/components/cards/DashboardSummary.jsx`

- [ ] **Step 1: Create the component**

Create `src/components/cards/DashboardSummary.jsx`:

```jsx
import { useQueries } from '@tanstack/react-query'
import { supabase } from '../../lib/supabase.js'
import { getRemainingBalance, formatPeso } from '../../utils/money.js'

function makeTransactionQuery(cardId) {
  return {
    queryKey: ['transactions', cardId],
    enabled: !!cardId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('transactions')
        .select('*')
        .eq('card_id', cardId)
        .eq('is_archived', false)
        .is('cycle_id', null)
        .order('transaction_date', { ascending: false })
      if (error) throw error
      return data
    },
  }
}

export default function DashboardSummary({ cards }) {
  const results = useQueries({ queries: cards.map((c) => makeTransactionQuery(c.id)) })

  const allTransactions = results.flatMap((r) => r.data ?? [])
  const totalOutstanding = allTransactions.reduce(
    (sum, t) => sum + getRemainingBalance(t.amount, t.amount_paid),
    0
  )
  const totalLimit = cards.reduce((sum, c) => sum + (c.spending_limit || 0), 0)
  const utilization = totalLimit > 0 ? Math.round((totalOutstanding / totalLimit) * 100) : null

  if (cards.length === 0) return null

  return (
    <div className="grid grid-cols-3 gap-4 mb-6">
      <div className="bg-white dark:bg-gray-900 border border-gray-200 dark:border-gray-700 rounded-2xl p-5">
        <p className="text-xs text-gray-400 uppercase tracking-widest font-semibold mb-1">
          Outstanding
        </p>
        <p className="text-2xl font-black font-mono text-red-600 dark:text-red-400">
          {formatPeso(totalOutstanding)}
        </p>
      </div>
      <div className="bg-white dark:bg-gray-900 border border-gray-200 dark:border-gray-700 rounded-2xl p-5">
        <p className="text-xs text-gray-400 uppercase tracking-widest font-semibold mb-1">
          Total Limit
        </p>
        <p className="text-2xl font-black font-mono text-gray-900 dark:text-white">
          {formatPeso(totalLimit)}
        </p>
      </div>
      <div className="bg-white dark:bg-gray-900 border border-gray-200 dark:border-gray-700 rounded-2xl p-5">
        <p className="text-xs text-gray-400 uppercase tracking-widest font-semibold mb-1">
          Utilization
        </p>
        <p className="text-2xl font-black font-mono text-gray-900 dark:text-white">
          {utilization !== null ? `${utilization}%` : '—'}
        </p>
      </div>
    </div>
  )
}
```

- [ ] **Step 2: Commit**

```bash
git add src/components/cards/DashboardSummary.jsx
git commit -m "feat: add DashboardSummary component with outstanding/limit/utilization"
```

---

### Task 3: Add due date badge to `CardTile`

**Files:**
- Modify: `src/components/cards/CardTile.jsx`

Current file imports at top: `useNavigate`, `useTransactions`, `getRemainingBalance`, `SpendingBar`

- [ ] **Step 1: Add getDueDateStatus import and badge logic**

In `src/components/cards/CardTile.jsx`, add the import after existing imports:

```js
import { getDueDateStatus } from '../../utils/dates.js'
```

After the existing `const spent = sumOutstanding(transactions)` line, add:

```js
const overdueCount = transactions.filter(
  (t) => getDueDateStatus(t.payment_due_date, t.payment_status) === 'overdue'
).length
const dueSoonCount = transactions.filter(
  (t) => getDueDateStatus(t.payment_due_date, t.payment_status) === 'due-soon'
).length
const alertCount = overdueCount + dueSoonCount
```

- [ ] **Step 2: Add badge JSX inside the card div**

Inside the outer `<div>` (the card itself), add this as the first child (before the Edit button):

```jsx
{alertCount > 0 && (
  <span
    className={`absolute top-3 left-3 text-white text-xs font-bold px-2 py-0.5 rounded-full ${
      overdueCount > 0 ? 'bg-red-500' : 'bg-orange-400'
    }`}
  >
    {alertCount} {overdueCount > 0 ? 'overdue' : 'due soon'}
  </span>
)}
```

- [ ] **Step 3: Commit**

```bash
git add src/components/cards/CardTile.jsx
git commit -m "feat: add due date alert badge to CardTile"
```

---

### Task 4: Add due date coloring to `TransactionTable`

**Files:**
- Modify: `src/components/tracker/TransactionTable.jsx`

- [ ] **Step 1: Add getDueDateStatus import**

In `src/components/tracker/TransactionTable.jsx`, add after existing imports:

```js
import { getDueDateStatus } from '../../utils/dates.js'
```

- [ ] **Step 2: Update the mobile due date display**

Find the mobile row section (inside the `md:hidden` block) where the due date is rendered:

```jsx
{t.payment_due_date && <span>Due {formatDate(t.payment_due_date)}</span>}
```

Replace with:

```jsx
{t.payment_due_date && (
  <span className={
    getDueDateStatus(t.payment_due_date, t.payment_status) === 'overdue'
      ? 'text-red-600 dark:text-red-400 font-semibold'
      : getDueDateStatus(t.payment_due_date, t.payment_status) === 'due-soon'
      ? 'text-orange-500 dark:text-orange-400'
      : ''
  }>
    Due {formatDate(t.payment_due_date)}
  </span>
)}
```

- [ ] **Step 3: Update the desktop due date cell**

Find the desktop table cell that renders the due date (inside `hidden md:block`):

```jsx
<td className="px-4 py-3 whitespace-nowrap text-gray-500 dark:text-gray-400">
  {formatDate(t.payment_due_date)}
</td>
```

Replace with:

```jsx
<td className={`px-4 py-3 whitespace-nowrap ${
  getDueDateStatus(t.payment_due_date, t.payment_status) === 'overdue'
    ? 'text-red-600 dark:text-red-400 font-semibold'
    : getDueDateStatus(t.payment_due_date, t.payment_status) === 'due-soon'
    ? 'text-orange-500 dark:text-orange-400'
    : 'text-gray-500 dark:text-gray-400'
}`}>
  {formatDate(t.payment_due_date)}
</td>
```

- [ ] **Step 4: Commit**

```bash
git add src/components/tracker/TransactionTable.jsx
git commit -m "feat: highlight overdue and due-soon dates in TransactionTable"
```

---

### Task 5: Wire `DashboardSummary` into `DashboardPage`

**Files:**
- Modify: `src/pages/DashboardPage.jsx`

- [ ] **Step 1: Add import**

In `src/pages/DashboardPage.jsx`, add after the existing imports:

```js
import DashboardSummary from '../components/cards/DashboardSummary.jsx'
```

- [ ] **Step 2: Render DashboardSummary above the card grid**

Find the block:

```jsx
<div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
```

Insert `DashboardSummary` immediately before it (after the error/loading/empty-state blocks):

```jsx
{!isLoading && !error && ownCards.length > 0 && (
  <DashboardSummary cards={ownCards} />
)}
```

- [ ] **Step 3: Smoke test in browser**

Start the dev server:
```bash
npm run dev
```

Verify:
1. Dashboard shows the 3-stat summary strip above the card grid when cards exist
2. Summary strip is absent when no cards
3. CardTile shows a red badge if any transactions are overdue, orange if due within 7 days
4. Open a card → transaction rows show red/orange on due date column for relevant transactions

- [ ] **Step 4: Commit**

```bash
git add src/pages/DashboardPage.jsx
git commit -m "feat: render DashboardSummary on Dashboard above card grid"
```
