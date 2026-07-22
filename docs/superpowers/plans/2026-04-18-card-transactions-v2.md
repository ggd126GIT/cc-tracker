# Card Transactions V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add transaction editing, bulk pay, CSV/PDF export, and billing cycle history to the TrackerPage.

**Architecture:** TrackerPage gains an Active/History tab layout. Active tab extends the existing transaction table with edit, bulk-select, and export. Closing a cycle stamps a `cycle_id` on paid transactions and permanently stores them in a `billing_cycles` table — nothing is deleted.

**Tech Stack:** React + Vite, Supabase, React Query, react-hook-form + zod, Tailwind CSS, jsPDF + jspdf-autotable

---

## File Map

| Action | File | What changes |
|--------|------|-------------|
| Create | `src/utils/export.js` | `buildCSVContent`, `exportCSV`, `exportPDF` |
| Create | `src/utils/export.test.js` | Unit tests for export utilities |
| Create | `src/components/tracker/TransactionEditModal.jsx` | Edit modal for all transaction fields |
| Create | `src/components/tracker/BulkPayBar.jsx` | Selection bar shown in bulk pay mode |
| Create | `src/components/tracker/ExportButtons.jsx` | CSV + PDF export button pair |
| Create | `src/components/tracker/CloseCycleModal.jsx` | Close cycle form + confirmation |
| Create | `src/components/tracker/CycleHistoryList.jsx` | History tab — expandable cycle cards |
| Modify | `src/hooks/useTransactions.js` | Add `useEditTransaction`, `usePayBulk`, `useBillingCycles`, `useCloseCycle`, `useCycleTransactions`; update `useTransactions` query |
| Modify | `src/lib/zod-schemas.js` | Add `billingCycleSchema` |
| Modify | `src/components/tracker/TransactionTable.jsx` | Add checkbox column + Edit button |
| Modify | `src/components/ui/icons.jsx` | Add `EditIcon` |
| Modify | `src/pages/TrackerPage.jsx` | Add tabs, action bar, bulk pay state, close cycle button |

---

## Task 1: Install dependencies

**Files:**
- Modify: `package.json`

- [ ] **Step 1: Install jsPDF and autoTable plugin**

```bash
npm install jspdf jspdf-autotable
```

Expected output: packages added to `node_modules`, `package.json` updated with both dependencies.

- [ ] **Step 2: Verify install**

```bash
node -e "require('jspdf'); console.log('jspdf ok')"
```

Expected: `jspdf ok`

- [ ] **Step 3: Commit**

```bash
git add package.json package-lock.json
git commit -m "chore: add jspdf and jspdf-autotable for PDF export"
```

---

## Task 2: Supabase migration

**Files:**
- (Run in Supabase SQL Editor — no local file)

- [ ] **Step 1: Create `billing_cycles` table**

Open the Supabase dashboard → SQL Editor, run:

```sql
create table billing_cycles (
  id         uuid primary key default gen_random_uuid(),
  card_id    uuid references cards(id) not null,
  user_id    uuid references auth.users(id) not null,
  label      text not null,
  start_date date not null,
  end_date   date not null,
  closed_at  timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table billing_cycles enable row level security;

create policy "Users can manage their own billing cycles"
  on billing_cycles for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
```

- [ ] **Step 2: Add `cycle_id` to `transactions`**

```sql
alter table transactions
  add column cycle_id uuid references billing_cycles(id) default null;
```

- [ ] **Step 3: Verify in Supabase Table Editor**

Open Supabase → Table Editor → `billing_cycles` should exist. Open `transactions` → `cycle_id` column should appear with type `uuid`, nullable.

---

## Task 3: Export utility + tests

**Files:**
- Create: `src/utils/export.js`
- Create: `src/utils/export.test.js`

- [ ] **Step 1: Write failing tests**

Create `src/utils/export.test.js`:

```js
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { buildCSVContent } from './export.js'

const sampleTransactions = [
  {
    id: '1',
    transaction_date: '2026-04-01',
    amount: 1500,
    payment_due_date: '2026-04-30',
    amount_paid: 500,
    payment_status: 'partial',
    notes: 'Groceries',
  },
  {
    id: '2',
    transaction_date: '2026-04-05',
    amount: 2000,
    payment_due_date: '',
    amount_paid: 2000,
    payment_status: 'paid',
    notes: '',
  },
]

describe('buildCSVContent', () => {
  it('includes a header row', () => {
    const csv = buildCSVContent(sampleTransactions)
    const firstLine = csv.split('\n')[0]
    expect(firstLine).toContain('Date')
    expect(firstLine).toContain('Amount')
    expect(firstLine).toContain('Status')
    expect(firstLine).toContain('Notes')
  })

  it('produces correct number of rows (header + data)', () => {
    const csv = buildCSVContent(sampleTransactions)
    const lines = csv.split('\n')
    expect(lines).toHaveLength(3) // 1 header + 2 data rows
  })

  it('includes transaction date and amount in data rows', () => {
    const csv = buildCSVContent(sampleTransactions)
    expect(csv).toContain('2026-04-01')
    expect(csv).toContain('1500')
  })

  it('computes remaining balance correctly', () => {
    const csv = buildCSVContent(sampleTransactions)
    // transaction 1: 1500 - 500 = 1000 remaining
    expect(csv).toContain('1000')
  })

  it('escapes double quotes in cell values', () => {
    const txWithQuotes = [{ ...sampleTransactions[0], notes: 'Say "hello"' }]
    const csv = buildCSVContent(txWithQuotes)
    expect(csv).toContain('Say ""hello""')
  })

  it('handles empty notes and due date gracefully', () => {
    const csv = buildCSVContent([sampleTransactions[1]])
    expect(csv).not.toContain('undefined')
    expect(csv).not.toContain('null')
  })
})
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
npx vitest run src/utils/export.test.js
```

Expected: FAIL — `export.js` not found.

- [ ] **Step 3: Create `src/utils/export.js`**

```js
import { getRemainingBalance } from './money.js'
import { jsPDF } from 'jspdf'
import autoTable from 'jspdf-autotable'

const CSV_HEADERS = ['Date', 'Amount (PHP)', 'Due Date', 'Paid (PHP)', 'Remaining (PHP)', 'Status', 'Notes']

export function buildCSVContent(transactions) {
  const rows = transactions.map(t => [
    t.transaction_date || '',
    t.amount,
    t.payment_due_date || '',
    t.amount_paid,
    getRemainingBalance(t.amount, t.amount_paid),
    t.payment_status,
    t.notes || '',
  ])
  return [CSV_HEADERS, ...rows]
    .map(r => r.map(cell => `"${String(cell).replace(/"/g, '""')}"`).join(','))
    .join('\n')
}

export function exportCSV(transactions, filename) {
  const csv = buildCSVContent(transactions)
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `${filename}.csv`
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  URL.revokeObjectURL(url)
}

export function exportPDF(transactions, filename, title = 'Transactions') {
  const doc = new jsPDF()
  doc.setFontSize(14)
  doc.text(title, 14, 16)
  doc.setFontSize(9)
  doc.setTextColor(120)
  doc.text(`Exported ${new Date().toLocaleDateString('en-PH')}`, 14, 23)

  autoTable(doc, {
    startY: 28,
    head: [CSV_HEADERS],
    body: transactions.map(t => [
      t.transaction_date || '—',
      `PHP ${Number(t.amount).toFixed(2)}`,
      t.payment_due_date || '—',
      `PHP ${Number(t.amount_paid).toFixed(2)}`,
      `PHP ${getRemainingBalance(t.amount, t.amount_paid).toFixed(2)}`,
      t.payment_status,
      t.notes || '—',
    ]),
    styles: { fontSize: 8 },
    headStyles: { fillColor: [45, 106, 79] },
  })

  doc.save(`${filename}.pdf`)
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
npx vitest run src/utils/export.test.js
```

Expected: all 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/utils/export.js src/utils/export.test.js
git commit -m "feat: add CSV and PDF export utilities"
```

---

## Task 4: Add billingCycleSchema to zod-schemas

**Files:**
- Modify: `src/lib/zod-schemas.js`

- [ ] **Step 1: Append schema at bottom of `src/lib/zod-schemas.js`**

```js
export const billingCycleSchema = z.object({
  label: z.string().min(1, 'Label is required'),
  start_date: z.string().min(1, 'Start date is required'),
  end_date: z.string().min(1, 'End date is required'),
}).refine(d => d.end_date >= d.start_date, {
  message: 'End date must be on or after start date',
  path: ['end_date'],
})
```

- [ ] **Step 2: Verify no import errors**

```bash
npx vitest run src/utils/export.test.js
```

Expected: still PASS (no regressions).

- [ ] **Step 3: Commit**

```bash
git add src/lib/zod-schemas.js
git commit -m "feat: add billingCycleSchema to zod schemas"
```

---

## Task 5: Add hooks to useTransactions.js

**Files:**
- Modify: `src/hooks/useTransactions.js`

- [ ] **Step 1: Update `useTransactions` to exclude cycle-archived transactions**

Find the existing `useTransactions` query (line 10–16) and add `.is('cycle_id', null)` after the `is_archived` filter:

```js
// existing lines stay the same, add one line:
.eq('is_archived', false)
.is('cycle_id', null)          // ← add this line
.order('transaction_date', { ascending: false })
```

- [ ] **Step 2: Add `useEditTransaction` hook at end of file**

```js
export function useEditTransaction() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ id, cardId, data }) => {
      const { error } = await supabase
        .from('transactions')
        .update({
          transaction_date: data.transaction_date,
          amount: data.amount,
          payment_due_date: data.payment_due_date || null,
          notes: data.notes || '',
        })
        .eq('id', id)
      if (error) throw error
      return { cardId }
    },
    onSuccess: (_data, { cardId }) =>
      qc.invalidateQueries({ queryKey: ['transactions', cardId] }),
  })
}
```

- [ ] **Step 3: Add `usePayBulk` hook**

```js
export function usePayBulk() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ transactions }) => {
      const {
        data: { user },
      } = await supabase.auth.getUser()

      await Promise.all(
        transactions.map(async (t) => {
          const remaining = getRemainingBalance(t.amount, t.amount_paid)
          if (remaining <= 0) return

          const newAmountPaid = addMoney(t.amount_paid, remaining)

          const { error: payErr } = await supabase.from('payments').insert({
            transaction_id: t.id,
            user_id: user.id,
            amount: remaining,
            notes: 'Bulk payment',
          })
          if (payErr) throw payErr

          const { error: txErr } = await supabase
            .from('transactions')
            .update({ amount_paid: newAmountPaid, payment_status: 'paid' })
            .eq('id', t.id)
          if (txErr) throw txErr
        })
      )

      return { cardId: transactions[0].card_id }
    },
    onSuccess: (_data, { transactions }) =>
      qc.invalidateQueries({ queryKey: ['transactions', transactions[0].card_id] }),
  })
}
```

- [ ] **Step 4: Add `useBillingCycles` hook**

```js
export function useBillingCycles(cardId) {
  return useQuery({
    queryKey: ['billing_cycles', cardId],
    enabled: !!cardId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('billing_cycles')
        .select('*, transactions(id, amount, amount_paid, payment_status)')
        .eq('card_id', cardId)
        .order('closed_at', { ascending: false })
      if (error) throw error
      return data
    },
  })
}
```

- [ ] **Step 5: Add `useCloseCycle` hook**

```js
export function useCloseCycle() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ cardId, label, start_date, end_date }) => {
      const {
        data: { user },
      } = await supabase.auth.getUser()

      const { data: cycle, error: cycleErr } = await supabase
        .from('billing_cycles')
        .insert({ card_id: cardId, user_id: user.id, label, start_date, end_date })
        .select()
        .single()
      if (cycleErr) throw cycleErr

      const { error: txErr } = await supabase
        .from('transactions')
        .update({ cycle_id: cycle.id })
        .eq('card_id', cardId)
        .eq('payment_status', 'paid')
        .is('cycle_id', null)
      if (txErr) throw txErr

      return { cardId, cycleId: cycle.id }
    },
    onSuccess: (_data, { cardId }) => {
      qc.invalidateQueries({ queryKey: ['transactions', cardId] })
      qc.invalidateQueries({ queryKey: ['billing_cycles', cardId] })
    },
  })
}
```

- [ ] **Step 6: Add `useCycleTransactions` hook**

```js
export function useCycleTransactions(cycleId) {
  return useQuery({
    queryKey: ['cycle_transactions', cycleId],
    enabled: !!cycleId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('transactions')
        .select('*')
        .eq('cycle_id', cycleId)
        .order('transaction_date', { ascending: false })
      if (error) throw error
      return data
    },
  })
}
```

- [ ] **Step 7: Commit**

```bash
git add src/hooks/useTransactions.js
git commit -m "feat: add useEditTransaction, usePayBulk, useBillingCycles, useCloseCycle, useCycleTransactions hooks"
```

---

## Task 6: Add EditIcon to icons.jsx

**Files:**
- Modify: `src/components/ui/icons.jsx`

- [ ] **Step 1: Add `EditIcon` to `src/components/ui/icons.jsx`**

Open the file and add the following export alongside the other icons (follow the existing pattern — each icon is a functional component accepting `className` and spreading remaining props):

```jsx
export function EditIcon({ className, ...props }) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      {...props}
    >
      <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7" />
      <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z" />
    </svg>
  )
}
```

- [ ] **Step 2: Verify the app still compiles**

```bash
npx vite build --mode development 2>&1 | head -20
```

Expected: no errors mentioning `icons.jsx`.

- [ ] **Step 3: Commit**

```bash
git add src/components/ui/icons.jsx
git commit -m "feat: add EditIcon to icons"
```

---

## Task 7: TransactionEditModal

**Files:**
- Create: `src/components/tracker/TransactionEditModal.jsx`

- [ ] **Step 1: Create the component**

```jsx
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { transactionSchema } from '../../lib/zod-schemas.js'
import { useEditTransaction } from '../../hooks/useTransactions.js'
import { getRemainingBalance } from '../../utils/money.js'
import Modal from '../ui/Modal.jsx'
import Button from '../ui/Button.jsx'

function Field({ label, error, children }) {
  return (
    <div className="flex flex-col gap-1">
      <label className="text-xs text-gray-500 dark:text-gray-400 uppercase tracking-wide">{label}</label>
      {children}
      {error && <p className="text-red-500 dark:text-red-400 text-xs">{error}</p>}
    </div>
  )
}

const inputCls =
  'bg-gray-50 dark:bg-gray-800 border border-gray-300 dark:border-gray-600 rounded-xl px-4 py-2.5 text-gray-900 dark:text-white text-sm placeholder-gray-400 dark:placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-[#9FE870] focus:border-transparent w-full transition-colors'

const today = new Date().toISOString().split('T')[0]

export default function TransactionEditModal({ transaction, card, transactions, onClose, onSuccess }) {
  const editTransaction = useEditTransaction()

  // Compute available credit excluding the transaction being edited
  const outstandingExcludingThis = transactions
    .filter(t => t.id !== transaction.id)
    .reduce((acc, t) => acc + getRemainingBalance(t.amount, t.amount_paid), 0)
  const maxAmount = (card?.spending_limit ?? Infinity) - outstandingExcludingThis

  const schema = transactionSchema.extend({
    amount: z.coerce
      .number({ invalid_type_error: 'Must be a number' })
      .positive('Amount must be greater than 0')
      .max(maxAmount, `Exceeds available credit (₱${maxAmount.toLocaleString('en-PH', { minimumFractionDigits: 2 })})`),
    transaction_date: z.string()
      .min(1, 'Date is required')
      .refine(d => d <= today, 'Transaction date cannot be in the future'),
  })

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm({
    resolver: zodResolver(schema),
    defaultValues: {
      transaction_date: transaction.transaction_date,
      amount: transaction.amount,
      payment_due_date: transaction.payment_due_date || '',
      notes: transaction.notes || '',
    },
  })

  async function onSubmit(data) {
    await editTransaction.mutateAsync({ id: transaction.id, cardId: transaction.card_id, data })
    onSuccess?.()
    onClose()
  }

  return (
    <Modal title="Edit Transaction" onClose={onClose}>
      <form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-3">
        {editTransaction.isError && (
          <p className="bg-red-50 dark:bg-red-900/40 border border-red-300 dark:border-red-700 text-red-600 dark:text-red-300 text-xs rounded-lg px-3 py-2">
            {editTransaction.error?.message}
          </p>
        )}

        <Field label="Date" error={errors.transaction_date?.message}>
          <input type="date" max={today} className={inputCls} {...register('transaction_date')} />
        </Field>

        <Field label="Amount (PHP)" error={errors.amount?.message}>
          <input type="number" step="0.01" min="0" placeholder="0.00" className={inputCls} {...register('amount')} />
        </Field>

        <Field label="Payment Due Date" error={errors.payment_due_date?.message}>
          <input type="date" className={inputCls} {...register('payment_due_date')} />
        </Field>

        <Field label="Notes (optional)" error={errors.notes?.message}>
          <input type="text" placeholder="Groceries, utilities…" className={inputCls} {...register('notes')} />
        </Field>

        <div className="flex gap-2 pt-1">
          <Button type="button" variant="ghost" onClick={onClose} className="flex-1">Cancel</Button>
          <Button type="submit" disabled={editTransaction.isPending} className="flex-1">
            {editTransaction.isPending ? 'Saving…' : 'Save Changes'}
          </Button>
        </div>
      </form>
    </Modal>
  )
}
```

- [ ] **Step 2: Commit**

```bash
git add src/components/tracker/TransactionEditModal.jsx
git commit -m "feat: add TransactionEditModal component"
```

---

## Task 8: BulkPayBar

**Files:**
- Create: `src/components/tracker/BulkPayBar.jsx`

- [ ] **Step 1: Create the component**

```jsx
import { formatPeso } from '../../utils/money.js'
import Button from '../ui/Button.jsx'

export default function BulkPayBar({ selectedCount, selectedTotal, onPaySelected, onCancel, isPending }) {
  return (
    <div className="flex items-center justify-between bg-[#2D6A4F]/10 dark:bg-[#9FE870]/10 border border-[#2D6A4F]/30 dark:border-[#9FE870]/30 rounded-xl px-4 py-2.5 text-sm">
      <span className="text-gray-700 dark:text-gray-200">
        <span className="font-semibold text-[#2D6A4F] dark:text-[#9FE870]">{selectedCount}</span> selected
        {selectedCount > 0 && (
          <span className="ml-2 text-gray-500 dark:text-gray-400">· {formatPeso(selectedTotal)} remaining</span>
        )}
      </span>
      <div className="flex gap-2">
        <Button
          variant="ghost"
          className="text-xs py-1.5 px-3"
          onClick={onCancel}
          disabled={isPending}
        >
          Cancel
        </Button>
        <Button
          className="text-xs py-1.5 px-3"
          onClick={onPaySelected}
          disabled={selectedCount === 0 || isPending}
        >
          {isPending ? 'Paying…' : `Pay ${selectedCount > 0 ? selectedCount : ''} Selected`}
        </Button>
      </div>
    </div>
  )
}
```

- [ ] **Step 2: Commit**

```bash
git add src/components/tracker/BulkPayBar.jsx
git commit -m "feat: add BulkPayBar component"
```

---

## Task 9: ExportButtons

**Files:**
- Create: `src/components/tracker/ExportButtons.jsx`

- [ ] **Step 1: Create the component**

```jsx
import { exportCSV, exportPDF } from '../../utils/export.js'
import Button from '../ui/Button.jsx'

export default function ExportButtons({ transactions, filename, title }) {
  if (!transactions || transactions.length === 0) return null

  return (
    <div className="flex gap-2">
      <Button
        variant="ghost"
        className="text-xs py-1.5 px-3"
        onClick={() => exportCSV(transactions, filename)}
        title="Export as CSV"
      >
        Export CSV
      </Button>
      <Button
        variant="ghost"
        className="text-xs py-1.5 px-3"
        onClick={() => exportPDF(transactions, filename, title)}
        title="Export as PDF"
      >
        Export PDF
      </Button>
    </div>
  )
}
```

- [ ] **Step 2: Commit**

```bash
git add src/components/tracker/ExportButtons.jsx
git commit -m "feat: add ExportButtons component"
```

---

## Task 10: CloseCycleModal

**Files:**
- Create: `src/components/tracker/CloseCycleModal.jsx`

- [ ] **Step 1: Create the component**

```jsx
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { billingCycleSchema } from '../../lib/zod-schemas.js'
import { useCloseCycle } from '../../hooks/useTransactions.js'
import Modal from '../ui/Modal.jsx'
import Button from '../ui/Button.jsx'

function Field({ label, error, children }) {
  return (
    <div className="flex flex-col gap-1">
      <label className="text-xs text-gray-500 dark:text-gray-400 uppercase tracking-wide">{label}</label>
      {children}
      {error && <p className="text-red-500 dark:text-red-400 text-xs">{error}</p>}
    </div>
  )
}

const inputCls =
  'bg-gray-50 dark:bg-gray-800 border border-gray-300 dark:border-gray-600 rounded-xl px-4 py-2.5 text-gray-900 dark:text-white text-sm focus:outline-none focus:ring-2 focus:ring-[#9FE870] focus:border-transparent w-full transition-colors'

function getDefaultLabel() {
  return new Date().toLocaleString('en-PH', { month: 'long', year: 'numeric' })
}

function getEarliestDate(transactions) {
  const dates = transactions.map(t => t.transaction_date).filter(Boolean).sort()
  return dates[0] || new Date().toISOString().split('T')[0]
}

function getLatestDate(transactions) {
  const dates = transactions.map(t => t.transaction_date).filter(Boolean).sort()
  return dates[dates.length - 1] || new Date().toISOString().split('T')[0]
}

export default function CloseCycleModal({ cardId, transactions, onClose, onSuccess }) {
  const closeCycle = useCloseCycle()

  const paidTransactions = transactions.filter(t => t.payment_status === 'paid')
  const unpaidCount = transactions.filter(t => t.payment_status !== 'paid').length

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm({
    resolver: zodResolver(billingCycleSchema),
    defaultValues: {
      label: getDefaultLabel(),
      start_date: getEarliestDate(paidTransactions),
      end_date: getLatestDate(paidTransactions),
    },
  })

  async function onSubmit(data) {
    await closeCycle.mutateAsync({ cardId, ...data })
    onSuccess?.()
    onClose()
  }

  return (
    <Modal title="Close Billing Cycle" onClose={onClose}>
      <div className="bg-gray-50 dark:bg-gray-800 rounded-xl p-3 mb-4 text-sm space-y-1">
        <p className="text-gray-700 dark:text-gray-200">
          <span className="font-semibold text-[#2D6A4F] dark:text-[#9FE870]">{paidTransactions.length}</span> paid transaction{paidTransactions.length !== 1 ? 's' : ''} will be moved to history.
        </p>
        {unpaidCount > 0 && (
          <p className="text-amber-600 dark:text-amber-400 text-xs">
            {unpaidCount} unpaid transaction{unpaidCount !== 1 ? 's' : ''} will remain in Active.
          </p>
        )}
      </div>

      <form onSubmit={handleSubmit(onSubmit)} className="flex flex-col gap-3">
        {closeCycle.isError && (
          <p className="bg-red-50 dark:bg-red-900/40 border border-red-300 dark:border-red-700 text-red-600 dark:text-red-300 text-xs rounded-lg px-3 py-2">
            {closeCycle.error?.message}
          </p>
        )}

        <Field label="Cycle Label" error={errors.label?.message}>
          <input type="text" placeholder="April 2026" className={inputCls} {...register('label')} />
        </Field>

        <div className="grid grid-cols-2 gap-3">
          <Field label="Start Date" error={errors.start_date?.message}>
            <input type="date" className={inputCls} {...register('start_date')} />
          </Field>
          <Field label="End Date" error={errors.end_date?.message}>
            <input type="date" className={inputCls} {...register('end_date')} />
          </Field>
        </div>

        <div className="flex gap-2 pt-1">
          <Button type="button" variant="ghost" onClick={onClose} className="flex-1">Cancel</Button>
          <Button type="submit" disabled={closeCycle.isPending || paidTransactions.length === 0} className="flex-1">
            {closeCycle.isPending ? 'Closing…' : 'Close Cycle'}
          </Button>
        </div>
      </form>
    </Modal>
  )
}
```

- [ ] **Step 2: Commit**

```bash
git add src/components/tracker/CloseCycleModal.jsx
git commit -m "feat: add CloseCycleModal component"
```

---

## Task 11: CycleHistoryList

**Files:**
- Create: `src/components/tracker/CycleHistoryList.jsx`

- [ ] **Step 1: Create the component**

```jsx
import { useState } from 'react'
import { useBillingCycles, useCycleTransactions } from '../../hooks/useTransactions.js'
import { formatPeso } from '../../utils/money.js'
import TransactionTable from './TransactionTable.jsx'
import ExportButtons from './ExportButtons.jsx'

function formatDate(dateStr) {
  if (!dateStr) return '—'
  return new Date(dateStr + 'T00:00:00').toLocaleDateString('en-PH', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  })
}

function CycleCard({ cycle, cardName, isExpanded, onToggle }) {
  const totalCharged = cycle.transactions.reduce((sum, t) => sum + Number(t.amount), 0)
  const totalPaid = cycle.transactions.reduce((sum, t) => sum + Number(t.amount_paid), 0)
  const count = cycle.transactions.length

  const { data: fullTransactions = [], isLoading } = useCycleTransactions(isExpanded ? cycle.id : null)

  const exportFilename = `${cardName}-${cycle.label}`.replace(/\s+/g, '-')
  const exportTitle = `${cardName} — ${cycle.label}`

  return (
    <div className="border border-gray-200 dark:border-gray-700 rounded-2xl overflow-hidden">
      <button
        className="w-full flex items-center justify-between px-5 py-4 bg-white dark:bg-gray-900 hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors text-left"
        onClick={onToggle}
      >
        <div>
          <p className="font-semibold text-gray-900 dark:text-white text-sm">{cycle.label}</p>
          <p className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
            {formatDate(cycle.start_date)} – {formatDate(cycle.end_date)} · {count} transaction{count !== 1 ? 's' : ''}
          </p>
        </div>
        <div className="flex items-center gap-6 text-right">
          <div>
            <p className="text-xs text-gray-400 dark:text-gray-500">Charged</p>
            <p className="text-sm font-mono text-gray-900 dark:text-white">{formatPeso(totalCharged)}</p>
          </div>
          <div>
            <p className="text-xs text-gray-400 dark:text-gray-500">Paid</p>
            <p className="text-sm font-mono text-green-600 dark:text-green-400">{formatPeso(totalPaid)}</p>
          </div>
          <span className="text-gray-400 dark:text-gray-500 text-lg">{isExpanded ? '▲' : '▼'}</span>
        </div>
      </button>

      {isExpanded && (
        <div className="px-5 pb-5 border-t border-gray-100 dark:border-gray-800 bg-white dark:bg-gray-900">
          <div className="flex justify-end pt-3 pb-3">
            <ExportButtons
              transactions={fullTransactions}
              filename={exportFilename}
              title={exportTitle}
            />
          </div>
          {isLoading ? (
            <p className="text-gray-400 text-sm text-center py-8">Loading transactions…</p>
          ) : (
            <TransactionTable
              transactions={fullTransactions}
              cardId={cycle.card_id}
              onPay={null}
              readOnly={true}
            />
          )}
        </div>
      )}
    </div>
  )
}

export default function CycleHistoryList({ cardId, cardName }) {
  const { data: cycles = [], isLoading } = useBillingCycles(cardId)
  const [expandedId, setExpandedId] = useState(null)

  if (isLoading) {
    return <p className="text-gray-400 text-sm text-center py-16">Loading history…</p>
  }

  if (cycles.length === 0) {
    return (
      <div className="text-center py-16 text-gray-500 border border-dashed border-gray-300 dark:border-gray-700 rounded-xl">
        No billing cycles yet. Close your first cycle from the Active tab.
      </div>
    )
  }

  return (
    <div className="flex flex-col gap-3">
      {cycles.map(cycle => (
        <CycleCard
          key={cycle.id}
          cycle={cycle}
          cardName={cardName}
          isExpanded={expandedId === cycle.id}
          onToggle={() => setExpandedId(expandedId === cycle.id ? null : cycle.id)}
        />
      ))}
    </div>
  )
}
```

- [ ] **Step 2: Commit**

```bash
git add src/components/tracker/CycleHistoryList.jsx
git commit -m "feat: add CycleHistoryList component for history tab"
```

---

## Task 12: Extend TransactionTable with edit + bulk select

**Files:**
- Modify: `src/components/tracker/TransactionTable.jsx`

- [ ] **Step 1: Replace the entire file with the updated version**

```jsx
import { useState, useMemo } from 'react'
import { formatPeso, getRemainingBalance } from '../../utils/money.js'
import { useArchiveTransaction } from '../../hooks/useTransactions.js'
import { useTransactionAttachmentCounts } from '../../hooks/useAttachments.js'
import AttachmentModal from '../ui/AttachmentModal.jsx'
import Badge from '../ui/Badge.jsx'
import Button from '../ui/Button.jsx'
import { AttachmentIcon, EditIcon } from '../ui/icons.jsx'

function formatDate(dateStr) {
  if (!dateStr) return '—'
  return new Date(dateStr + 'T00:00:00').toLocaleDateString('en-PH', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  })
}

export default function TransactionTable({
  transactions,
  cardId,
  onPay,
  readOnly = false,
  bulkPayMode = false,
  selectedIds = new Set(),
  onToggleSelect,
  onEdit,
}) {
  const archive = useArchiveTransaction()
  const [confirmArchiveId, setConfirmArchiveId] = useState(null)
  const [attachingTxId, setAttachingTxId] = useState(null)

  const txIds = useMemo(() => transactions.map((t) => t.id), [transactions])
  const { data: attCounts = {} } = useTransactionAttachmentCounts(txIds)

  if (!transactions || transactions.length === 0) {
    return (
      <div className="text-center py-16 text-gray-500 border border-dashed border-gray-300 dark:border-gray-700 rounded-xl">
        No transactions yet. Add your first one above.
      </div>
    )
  }

  return (
    <>
      <div className="overflow-x-auto rounded-2xl border border-gray-200 dark:border-gray-700">
        <table className="w-full text-sm">
          <thead>
            <tr className="bg-gray-100 dark:bg-gray-800 text-gray-500 dark:text-gray-400 text-xs uppercase tracking-wide">
              {bulkPayMode && !readOnly && (
                <th className="px-4 py-3 text-center whitespace-nowrap w-10"></th>
              )}
              <th className="px-4 py-3 text-left whitespace-nowrap">Date</th>
              <th className="px-4 py-3 text-right whitespace-nowrap">Amount</th>
              <th className="px-4 py-3 text-left whitespace-nowrap">Due Date</th>
              <th className="px-4 py-3 text-right whitespace-nowrap">Paid</th>
              <th className="px-4 py-3 text-right whitespace-nowrap">Remaining</th>
              <th className="px-4 py-3 text-center whitespace-nowrap">Status</th>
              <th className="px-4 py-3 text-left">Notes</th>
              <th className="px-4 py-3 text-center whitespace-nowrap">Files</th>
              {!readOnly && (
                <th className="px-4 py-3 text-center whitespace-nowrap">Actions</th>
              )}
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100 dark:divide-gray-800">
            {transactions.map((t) => {
              const count = attCounts[t.id] || 0
              const isSelectable = bulkPayMode && !readOnly && t.payment_status !== 'paid'
              const isSelected = selectedIds.has(t.id)
              return (
                <tr key={t.id} className="hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors text-gray-700 dark:text-gray-200">
                  {bulkPayMode && !readOnly && (
                    <td className="px-4 py-3 text-center">
                      {isSelectable ? (
                        <input
                          type="checkbox"
                          checked={isSelected}
                          onChange={() => onToggleSelect?.(t)}
                          className="accent-[#2D6A4F] dark:accent-[#9FE870] w-4 h-4 cursor-pointer"
                        />
                      ) : (
                        <span className="text-[#2D6A4F] dark:text-[#9FE870] text-xs">✓</span>
                      )}
                    </td>
                  )}
                  <td className="px-4 py-3 whitespace-nowrap">{formatDate(t.transaction_date)}</td>
                  <td className="px-4 py-3 text-right font-mono">{formatPeso(t.amount)}</td>
                  <td className="px-4 py-3 whitespace-nowrap text-gray-500 dark:text-gray-400">
                    {formatDate(t.payment_due_date)}
                  </td>
                  <td className="px-4 py-3 text-right font-mono text-green-600 dark:text-green-400">
                    {formatPeso(t.amount_paid)}
                  </td>
                  <td className="px-4 py-3 text-right font-mono text-red-600 dark:text-red-400">
                    {formatPeso(getRemainingBalance(t.amount, t.amount_paid))}
                  </td>
                  <td className="px-4 py-3 text-center">
                    <Badge status={t.payment_status} />
                  </td>
                  <td className="px-4 py-3 text-gray-500 dark:text-gray-400 max-w-[150px] truncate">
                    {t.notes || '—'}
                  </td>
                  <td className="px-4 py-3 text-center">
                    {(!readOnly || count > 0) && (
                      <button
                        onClick={() => setAttachingTxId(t.id)}
                        className="relative inline-flex items-center gap-1 text-gray-400 hover:text-[#2D6A4F] dark:hover:text-[#9FE870] transition-colors text-xs"
                        title="Attachments"
                      >
                        <AttachmentIcon className="w-4 h-4" />
                        {count > 0 && (
                          <span className="bg-[#9FE870]/20 text-[#2D6A4F] dark:text-[#9FE870] text-xs font-medium px-1.5 py-0.5 rounded-full leading-none">
                            {count}
                          </span>
                        )}
                      </button>
                    )}
                  </td>
                  {!readOnly && (
                    <td className="px-4 py-3 text-center">
                      <div className="flex gap-2 justify-center items-center">
                        <button
                          onClick={() => onEdit?.(t)}
                          className="text-gray-400 hover:text-[#2D6A4F] dark:hover:text-[#9FE870] transition-colors"
                          title="Edit transaction"
                        >
                          <EditIcon className="w-3.5 h-3.5" />
                        </button>
                        {t.payment_status !== 'paid' && (
                          <Button
                            variant="ghost"
                            className="text-xs py-1 px-2"
                            onClick={() => onPay(t)}
                          >
                            Pay
                          </Button>
                        )}
                        {confirmArchiveId === t.id ? (
                          <span className="flex items-center gap-1">
                            <span className="text-xs text-gray-500 dark:text-gray-400 whitespace-nowrap">Archive?</span>
                            <button
                              onClick={() => { archive.mutate({ id: t.id, cardId }); setConfirmArchiveId(null) }}
                              className="text-xs text-red-500 hover:text-red-600 font-medium transition-colors"
                              disabled={archive.isPending}
                            >
                              Yes
                            </button>
                            <span className="text-gray-300 dark:text-gray-600">/</span>
                            <button
                              onClick={() => setConfirmArchiveId(null)}
                              className="text-xs text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 transition-colors"
                            >
                              No
                            </button>
                          </span>
                        ) : (
                          <button
                            onClick={() => setConfirmArchiveId(t.id)}
                            className="text-gray-400 hover:text-red-500 dark:hover:text-red-400 text-xs transition-colors"
                            title="Archive transaction"
                            disabled={archive.isPending}
                          >
                            Archive
                          </button>
                        )}
                      </div>
                    </td>
                  )}
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>

      {attachingTxId && (
        <AttachmentModal
          entityType="transaction"
          entityId={attachingTxId}
          readOnly={readOnly}
          onClose={() => setAttachingTxId(null)}
        />
      )}
    </>
  )
}
```

- [ ] **Step 2: Commit**

```bash
git add src/components/tracker/TransactionTable.jsx
git commit -m "feat: add edit button and bulk-select checkboxes to TransactionTable"
```

---

## Task 13: Update TrackerPage — tabs, action bar, bulk pay state, close cycle

**Files:**
- Modify: `src/pages/TrackerPage.jsx`

- [ ] **Step 1: Replace TrackerPage with the full updated version**

```jsx
import { useState, useMemo } from 'react'
import { useParams, useNavigate, useSearchParams } from 'react-router-dom'
import { useCards } from '../hooks/useCards.js'
import { useTransactions, usePayBulk } from '../hooks/useTransactions.js'
import { getRemainingBalance } from '../utils/money.js'
import Navbar from '../components/layout/Navbar.jsx'
import TrackerSummary from '../components/tracker/TrackerSummary.jsx'
import TransactionTable from '../components/tracker/TransactionTable.jsx'
import TransactionForm from '../components/tracker/TransactionForm.jsx'
import TransactionEditModal from '../components/tracker/TransactionEditModal.jsx'
import PaymentModal from '../components/tracker/PaymentModal.jsx'
import BulkPayBar from '../components/tracker/BulkPayBar.jsx'
import ExportButtons from '../components/tracker/ExportButtons.jsx'
import CloseCycleModal from '../components/tracker/CloseCycleModal.jsx'
import CycleHistoryList from '../components/tracker/CycleHistoryList.jsx'
import { useToast, ToastContainer } from '../components/ui/Toast.jsx'
import Button from '../components/ui/Button.jsx'
import { ReturnIcon } from '../components/ui/icons.jsx'

export default function TrackerPage() {
  const { cardId } = useParams()
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const readOnly = searchParams.get('readOnly') === 'true'

  const { data: cards = [] } = useCards()
  const { data: transactions = [], isLoading } = useTransactions(cardId)
  const payBulk = usePayBulk()
  const { toasts, toast } = useToast()

  const [activeTab, setActiveTab] = useState('active')
  const [payingTransaction, setPayingTransaction] = useState(null)
  const [editingTransaction, setEditingTransaction] = useState(null)
  const [bulkPayMode, setBulkPayMode] = useState(false)
  const [selectedTransactions, setSelectedTransactions] = useState([])
  const [showCloseCycle, setShowCloseCycle] = useState(false)

  const card = cards.find((c) => c.id === cardId)

  const selectedIds = useMemo(() => new Set(selectedTransactions.map(t => t.id)), [selectedTransactions])
  const selectedTotal = useMemo(
    () => selectedTransactions.reduce((sum, t) => sum + getRemainingBalance(t.amount, t.amount_paid), 0),
    [selectedTransactions]
  )

  const hasPaidTransactions = transactions.some(t => t.payment_status === 'paid')

  function handleToggleSelect(transaction) {
    setSelectedTransactions(prev =>
      prev.some(t => t.id === transaction.id)
        ? prev.filter(t => t.id !== transaction.id)
        : [...prev, transaction]
    )
  }

  function exitBulkPay() {
    setBulkPayMode(false)
    setSelectedTransactions([])
  }

  async function handlePaySelected() {
    if (selectedTransactions.length === 0) return
    await payBulk.mutateAsync({ transactions: selectedTransactions })
    toast(`${selectedTransactions.length} transaction${selectedTransactions.length !== 1 ? 's' : ''} marked as paid`, 'success')
    exitBulkPay()
  }

  const exportFilename = card ? `${card.nickname}-active-transactions`.replace(/\s+/g, '-') : 'transactions'
  const exportTitle = card ? `${card.nickname} — Active Transactions` : 'Active Transactions'

  if (cards.length > 0 && !card) {
    return (
      <div className="min-h-screen bg-gray-50 dark:bg-gray-950 flex items-center justify-center">
        <div className="text-center">
          <p className="text-gray-500 dark:text-gray-400 mb-4">Card not found.</p>
          <button onClick={() => navigate('/')} className="text-gray-500 hover:text-gray-900 dark:hover:text-white transition-colors">
            <ReturnIcon className="w-4 h-4 inline mr-1" /> Go back to Dashboard
          </button>
        </div>
      </div>
    )
  }

  if (!card) return null

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-950">
      <Navbar />
      <TrackerSummary card={card} transactions={transactions} />

      <main className="max-w-6xl mx-auto p-6">
        <button
          onClick={() => navigate(readOnly ? '/shared' : '/')}
          className="flex items-center gap-1.5 text-xs text-gray-600 dark:text-gray-300 border border-gray-300 dark:border-gray-600 px-3 py-2 rounded-xl hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors mb-6"
        >
          <ReturnIcon className="w-3.5 h-3.5" />
          Back to {readOnly ? 'Shared with me' : 'Dashboard'}
        </button>

        {readOnly && (
          <div className="mb-4 px-4 py-2 bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-700 rounded-lg text-amber-700 dark:text-amber-400 text-sm">
            Viewing shared card — read only
          </div>
        )}

        {/* Tabs */}
        <div className="flex gap-1 border-b border-gray-200 dark:border-gray-700 mb-6">
          {['active', 'history'].map(tab => (
            <button
              key={tab}
              onClick={() => { setActiveTab(tab); exitBulkPay() }}
              className={`px-4 py-2.5 text-sm font-medium capitalize transition-colors border-b-2 -mb-px ${
                activeTab === tab
                  ? 'border-[#2D6A4F] dark:border-[#9FE870] text-[#2D6A4F] dark:text-[#9FE870]'
                  : 'border-transparent text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300'
              }`}
            >
              {tab}
            </button>
          ))}
        </div>

        {activeTab === 'active' && (
          <>
            {!readOnly && (
              <TransactionForm
                cardId={cardId}
                card={card}
                transactions={transactions}
                onSuccess={() => toast('Transaction added!', 'success')}
              />
            )}

            {/* Action bar */}
            {!readOnly && transactions.length > 0 && (
              <div className="flex items-center justify-between mt-4 mb-3">
                <Button
                  variant={bulkPayMode ? 'primary' : 'ghost'}
                  className="text-xs py-1.5 px-3"
                  onClick={() => { setBulkPayMode(b => !b); setSelectedTransactions([]) }}
                >
                  {bulkPayMode ? 'Exit Bulk Pay' : 'Bulk Pay'}
                </Button>
                <ExportButtons
                  transactions={transactions}
                  filename={exportFilename}
                  title={exportTitle}
                />
              </div>
            )}

            {bulkPayMode && (
              <div className="mb-3">
                <BulkPayBar
                  selectedCount={selectedTransactions.length}
                  selectedTotal={selectedTotal}
                  onPaySelected={handlePaySelected}
                  onCancel={exitBulkPay}
                  isPending={payBulk.isPending}
                />
              </div>
            )}

            {isLoading ? (
              <p className="text-gray-500 text-center py-10 mt-6">Loading transactions…</p>
            ) : (
              <TransactionTable
                transactions={transactions}
                cardId={cardId}
                onPay={setPayingTransaction}
                onEdit={setEditingTransaction}
                readOnly={readOnly}
                bulkPayMode={bulkPayMode}
                selectedIds={selectedIds}
                onToggleSelect={handleToggleSelect}
              />
            )}

            {/* Close Cycle button */}
            {!readOnly && hasPaidTransactions && (
              <div className="mt-6 flex justify-end">
                <button
                  onClick={() => setShowCloseCycle(true)}
                  className="text-xs text-gray-500 dark:text-gray-400 border border-gray-300 dark:border-gray-600 px-4 py-2 rounded-xl hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors"
                >
                  Close Billing Cycle
                </button>
              </div>
            )}
          </>
        )}

        {activeTab === 'history' && (
          <CycleHistoryList cardId={cardId} cardName={card.nickname} />
        )}
      </main>

      {/* Modals */}
      {!readOnly && payingTransaction && (
        <PaymentModal
          transaction={payingTransaction}
          onClose={() => setPayingTransaction(null)}
          onSuccess={() => {
            setPayingTransaction(null)
            toast('Payment recorded!', 'success')
          }}
        />
      )}

      {!readOnly && editingTransaction && (
        <TransactionEditModal
          transaction={editingTransaction}
          card={card}
          transactions={transactions}
          onClose={() => setEditingTransaction(null)}
          onSuccess={() => toast('Transaction updated!', 'success')}
        />
      )}

      {!readOnly && showCloseCycle && (
        <CloseCycleModal
          cardId={cardId}
          transactions={transactions}
          onClose={() => setShowCloseCycle(false)}
          onSuccess={() => {
            setShowCloseCycle(false)
            toast('Billing cycle closed!', 'success')
            setActiveTab('history')
          }}
        />
      )}

      <ToastContainer toasts={toasts} />
    </div>
  )
}
```

- [ ] **Step 2: Run the full test suite to check for regressions**

```bash
npx vitest run
```

Expected: all tests pass.

- [ ] **Step 3: Start the dev server and manually test all features**

```bash
npm run dev
```

Manual test checklist:
- [ ] Navigate to a card → Active and History tabs are visible
- [ ] Add a transaction → appears in Active tab
- [ ] Click Edit on a transaction → modal opens pre-filled, save updates the row
- [ ] Click Bulk Pay → checkboxes appear, paid rows show ✓, BulkPayBar shows selection state
- [ ] Select 2+ transactions, click Pay Selected → both marked paid, toast shown, bulk pay exits
- [ ] Click Export CSV → `.csv` file downloads, opens correctly in Excel/Sheets
- [ ] Click Export PDF → `.pdf` file downloads with correct table
- [ ] Click Close Billing Cycle → CloseCycleModal shows correct paid/unpaid counts
- [ ] Close a cycle → transactions disappear from Active, History tab shows the new cycle card
- [ ] Expand a cycle card in History → transactions listed, Export buttons work for that cycle
- [ ] Verify read-only shared view: no Edit, no Bulk Pay, no Close Cycle visible

- [ ] **Step 4: Commit**

```bash
git add src/pages/TrackerPage.jsx
git commit -m "feat: add tabs, bulk pay, edit, export, and close cycle to TrackerPage"
```

---

## Done

All features shipped. Each can be independently tested via the manual checklist in Task 13 Step 3.
