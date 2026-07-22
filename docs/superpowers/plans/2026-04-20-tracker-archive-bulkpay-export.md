# Tracker: Archive Tab, Bulk Pay Confirm, Invoice Rename, Export Totals — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an Archive tab with Restore, a Bulk Pay confirmation modal, rename "Files" to "Invoice", and include totals in CSV/PDF exports — all scoped to the card tracker page.

**Architecture:** Five isolated changes touching five files. Hooks added to `useTransactions.js`, new modal component created, `TransactionTable` gets a `mode` prop, `TrackerPage` wires everything together, and `export.js` gains a `calcTotals` helper used by both exporters.

**Tech Stack:** React, TanStack Query v5, Supabase JS v2, jsPDF + jspdf-autotable, Vitest, Tailwind CSS

---

## File Map

| File | Action | What changes |
|------|--------|-------------|
| `src/hooks/useTransactions.js` | Modify | Add `useArchivedTransactions`, `useRestoreTransaction` |
| `src/components/tracker/BulkPayConfirmModal.jsx` | Create | Confirmation modal before bulk pay executes |
| `src/components/tracker/TransactionTable.jsx` | Modify | Add `mode` prop (`'active'`\|`'archived'`), Restore action, rename "Files"→"Invoice" |
| `src/pages/TrackerPage.jsx` | Modify | Add archive tab, `showBulkConfirm` state, wire `BulkPayConfirmModal` |
| `src/utils/export.js` | Modify | Add `calcTotals`, append totals row to CSV and PDF |
| `src/utils/export.test.js` | Modify | Update row-count test, add totals tests |

---

## Task 1: Add `useArchivedTransactions` and `useRestoreTransaction` hooks

**Files:**
- Modify: `src/hooks/useTransactions.js`

- [ ] **Step 1: Add `useArchivedTransactions` hook**

Open `src/hooks/useTransactions.js`. After the `useArchiveTransaction` export (around line 67), add:

```js
export function useArchivedTransactions(cardId) {
  return useQuery({
    queryKey: ['transactions_archived', cardId],
    enabled: !!cardId,
    queryFn: async () => {
      const { data, error } = await supabase
        .from('transactions')
        .select('*')
        .eq('card_id', cardId)
        .eq('is_archived', true)
        .order('transaction_date', { ascending: false })
      if (error) throw error
      return data
    },
  })
}
```

- [ ] **Step 2: Add `useRestoreTransaction` hook**

Immediately after the hook above, add:

```js
export function useRestoreTransaction() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ id, cardId }) => {
      const { error } = await supabase
        .from('transactions')
        .update({ is_archived: false })
        .eq('id', id)
      if (error) throw error
      return { cardId }
    },
    onSuccess: (_data, { cardId }) => {
      qc.invalidateQueries({ queryKey: ['transactions', cardId] })
      qc.invalidateQueries({ queryKey: ['transactions_archived', cardId] })
    },
  })
}
```

Note: `useQuery` and `useMutation` are already imported at the top of this file. `useQueryClient` is also already imported.

- [ ] **Step 3: Commit**

```bash
git add src/hooks/useTransactions.js
git commit -m "feat: add useArchivedTransactions and useRestoreTransaction hooks"
```

---

## Task 2: Create `BulkPayConfirmModal` component

**Files:**
- Create: `src/components/tracker/BulkPayConfirmModal.jsx`

- [ ] **Step 1: Create the file**

```jsx
import { formatPeso } from '../../utils/money.js'
import Modal from '../ui/Modal.jsx'
import Button from '../ui/Button.jsx'

export default function BulkPayConfirmModal({ count, total, onConfirm, onCancel, isPending }) {
  return (
    <Modal title="Confirm Bulk Payment" onClose={onCancel}>
      <div className="flex flex-col gap-4">
        <div className="bg-gray-50 dark:bg-gray-800 rounded-xl p-4 text-sm">
          <p className="text-gray-700 dark:text-gray-200">
            You are about to mark{' '}
            <span className="font-semibold text-gray-900 dark:text-white">{count} transaction{count !== 1 ? 's' : ''}</span>{' '}
            as fully paid.
          </p>
          <p className="mt-2 text-gray-500 dark:text-gray-400">
            Total:{' '}
            <span className="font-mono font-semibold text-gray-900 dark:text-white">{formatPeso(total)}</span>
          </p>
        </div>
        <p className="text-xs text-gray-400 dark:text-gray-500">
          This action cannot be undone.
        </p>
        <div className="flex gap-2">
          <Button variant="ghost" className="flex-1" onClick={onCancel} disabled={isPending}>
            Cancel
          </Button>
          <Button className="flex-1" onClick={onConfirm} disabled={isPending}>
            {isPending ? 'Paying…' : 'Confirm Payment'}
          </Button>
        </div>
      </div>
    </Modal>
  )
}
```

- [ ] **Step 2: Commit**

```bash
git add src/components/tracker/BulkPayConfirmModal.jsx
git commit -m "feat: add BulkPayConfirmModal component"
```

---

## Task 3: Update `TransactionTable` — mode prop, Restore action, Files→Invoice

**Files:**
- Modify: `src/components/tracker/TransactionTable.jsx`

- [ ] **Step 1: Import `useRestoreTransaction` and add `mode` prop + restore state**

At the top of the file, add `useRestoreTransaction` to the import from `useTransactions`:

```js
import { useArchiveTransaction, useRestoreTransaction } from '../../hooks/useTransactions.js'
```

Update the component signature to accept `mode`:

```js
export default function TransactionTable({
  transactions,
  cardId,
  onPay,
  readOnly = false,
  bulkPayMode = false,
  selectedIds = new Set(),
  onToggleSelect,
  onEdit,
  mode = 'active',
}) {
```

Inside the component body, after `const archive = useArchiveTransaction()`, add:

```js
const restore = useRestoreTransaction()
const [confirmRestoreId, setConfirmRestoreId] = useState(null)
```

- [ ] **Step 2: Rename "Files" → "Invoice" in the desktop table header**

Find line 185 in the desktop `<thead>`:

```jsx
<th className="px-4 py-3 text-center whitespace-nowrap">Files</th>
```

Change to:

```jsx
<th className="px-4 py-3 text-center whitespace-nowrap">Invoice</th>
```

- [ ] **Step 3: Add Restore action to desktop table rows**

In the desktop `<tbody>`, find the `{!readOnly && (` block that contains the Actions `<td>`. Replace the entire `{!readOnly && ( <td>...</td> )}` block with:

```jsx
{!readOnly && (
  <td className="px-4 py-3 text-center">
    {mode === 'archived' ? (
      <div className="flex gap-2 justify-center items-center">
        {confirmRestoreId === t.id ? (
          <span className="flex items-center gap-1">
            <span className="text-xs text-gray-500 dark:text-gray-400 whitespace-nowrap">Restore?</span>
            <button
              onClick={() => { restore.mutate({ id: t.id, cardId }); setConfirmRestoreId(null) }}
              className="text-xs text-[#2D6A4F] dark:text-[#9FE870] font-medium transition-colors"
              disabled={restore.isPending}
              aria-label="Confirm restore"
            >
              Yes
            </button>
            <span className="text-gray-300 dark:text-gray-600">/</span>
            <button
              onClick={() => setConfirmRestoreId(null)}
              className="text-xs text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 transition-colors"
              aria-label="Cancel restore"
            >
              No
            </button>
          </span>
        ) : (
          <button
            onClick={() => setConfirmRestoreId(t.id)}
            className="text-xs text-gray-400 hover:text-[#2D6A4F] dark:hover:text-[#9FE870] transition-colors"
            disabled={restore.isPending}
          >
            Restore
          </button>
        )}
      </div>
    ) : (
      <div className="flex gap-2 justify-center items-center">
        <button
          onClick={() => onEdit?.(t)}
          className="text-gray-400 hover:text-[#2D6A4F] dark:hover:text-[#9FE870] transition-colors"
          title="Edit transaction"
          aria-label="Edit transaction"
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
              aria-label="Confirm archive"
            >
              Yes
            </button>
            <span className="text-gray-300 dark:text-gray-600">/</span>
            <button
              onClick={() => setConfirmArchiveId(null)}
              className="text-xs text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 transition-colors"
              aria-label="Cancel archive"
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
    )}
  </td>
)}
```

- [ ] **Step 4: Add Restore action to mobile card rows**

In the mobile layout, find the `<div className="ml-auto">` block that contains the inline Archive confirm. Replace the entire `<div className="ml-auto">...</div>` block with:

```jsx
<div className="ml-auto">
  {mode === 'archived' ? (
    confirmRestoreId === t.id ? (
      <span className="flex items-center gap-1">
        <span className="text-xs text-gray-500 dark:text-gray-400">Restore?</span>
        <button
          onClick={() => { restore.mutate({ id: t.id, cardId }); setConfirmRestoreId(null) }}
          className="text-xs text-[#2D6A4F] dark:text-[#9FE870] font-medium"
          disabled={restore.isPending}
          aria-label="Confirm restore"
        >Yes</button>
        <span className="text-gray-300 dark:text-gray-600">/</span>
        <button onClick={() => setConfirmRestoreId(null)} className="text-xs text-gray-400" aria-label="Cancel restore">No</button>
      </span>
    ) : (
      <button
        onClick={() => setConfirmRestoreId(t.id)}
        className="text-xs text-gray-400 hover:text-[#2D6A4F] dark:hover:text-[#9FE870] transition-colors"
        disabled={restore.isPending}
      >Restore</button>
    )
  ) : (
    confirmArchiveId === t.id ? (
      <span className="flex items-center gap-1">
        <span className="text-xs text-gray-500 dark:text-gray-400">Archive?</span>
        <button
          onClick={() => { archive.mutate({ id: t.id, cardId }); setConfirmArchiveId(null) }}
          className="text-xs text-red-500 font-medium"
          disabled={archive.isPending}
          aria-label="Confirm archive"
        >Yes</button>
        <span className="text-gray-300 dark:text-gray-600">/</span>
        <button onClick={() => setConfirmArchiveId(null)} className="text-xs text-gray-400" aria-label="Cancel archive">No</button>
      </span>
    ) : (
      <button
        onClick={() => setConfirmArchiveId(t.id)}
        className="text-xs text-gray-400 hover:text-red-500 transition-colors"
        disabled={archive.isPending}
      >Archive</button>
    )
  )}
</div>
```

Also, in the mobile layout, the Pay and Edit buttons should be hidden when `mode === 'archived'`. Wrap the Pay button with:

```jsx
{mode !== 'archived' && t.payment_status !== 'paid' && (
  <button
    onClick={() => onPay(t)}
    className="text-xs text-[#2D6A4F] dark:text-[#9FE870] border border-[#2D6A4F]/30 dark:border-[#9FE870]/30 px-2.5 py-1 rounded-lg hover:bg-[#9FE870]/10 transition-colors"
  >
    Pay
  </button>
)}
```

Wrap the Edit button with:

```jsx
{mode !== 'archived' && (
  <button
    onClick={() => onEdit?.(t)}
    className="text-xs text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-gray-700 px-2.5 py-1 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors flex items-center gap-1"
  >
    <EditIcon className="w-3 h-3" /> Edit
  </button>
)}
```

- [ ] **Step 5: Commit**

```bash
git add src/components/tracker/TransactionTable.jsx
git commit -m "feat: add archived mode to TransactionTable, rename Files to Invoice"
```

---

## Task 4: Update `TrackerPage` — Archive tab + Bulk Pay confirm wiring

**Files:**
- Modify: `src/pages/TrackerPage.jsx`

- [ ] **Step 1: Add new imports**

At the top of `TrackerPage.jsx`, add to the existing tracker imports:

```js
import BulkPayConfirmModal from '../components/tracker/BulkPayConfirmModal.jsx'
```

Add to the existing `useTransactions` import line:

```js
import { useTransactions, usePayBulk, useArchivedTransactions } from '../hooks/useTransactions.js'
```

- [ ] **Step 2: Add new state and data**

After the existing `const [dateFrom, setDateFrom] = useState('')` line, add:

```js
const [showBulkConfirm, setShowBulkConfirm] = useState(false)
const { data: archivedTransactions = [], isLoading: isLoadingArchived } = useArchivedTransactions(cardId)
```

- [ ] **Step 3: Update `handlePaySelected` to close the confirm modal**

Replace the existing `handlePaySelected` function:

```js
async function handlePaySelected() {
  if (selectedTransactions.length === 0) return
  try {
    await payBulk.mutateAsync({ cardId, transactions: selectedTransactions })
    toast(`${selectedTransactions.length} transaction${selectedTransactions.length !== 1 ? 's' : ''} marked as paid`, 'success')
    setShowBulkConfirm(false)
    exitBulkPay()
  } catch {
    toast('Payment failed. Please try again.', 'error')
  }
}
```

- [ ] **Step 4: Update tab array and tab switch handler**

Find the tabs map:

```jsx
{['active', 'history'].map(tab => (
```

Change to (archive tab is hidden for read-only shared views since those users cannot archive transactions):

```jsx
{(readOnly ? ['active', 'history'] : ['active', 'history', 'archive']).map(tab => (
```

- [ ] **Step 5: Wire BulkPayBar to open confirm modal instead of paying directly**

Find the `<BulkPayBar` usage and change `onPaySelected={handlePaySelected}` to:

```jsx
<BulkPayBar
  selectedCount={selectedTransactions.length}
  selectedTotal={selectedTotal}
  onPaySelected={() => setShowBulkConfirm(true)}
  onCancel={exitBulkPay}
  isPending={payBulk.isPending}
/>
```

- [ ] **Step 6: Add Archive tab content block**

After the closing `)}` of the `{activeTab === 'history' && ...}` block, add:

```jsx
{activeTab === 'archive' && (
  <>
    {isLoadingArchived ? (
      <p className="text-gray-500 text-center py-10 mt-6">Loading archived transactions…</p>
    ) : (
      <TransactionTable
        transactions={archivedTransactions}
        cardId={cardId}
        onPay={() => {}}
        onEdit={() => {}}
        readOnly={false}
        mode="archived"
      />
    )}
  </>
)}
```

- [ ] **Step 7: Add `BulkPayConfirmModal` to the modals section**

In the modals section at the bottom (alongside `PaymentModal`, `TransactionEditModal`, etc.), add:

```jsx
{!readOnly && showBulkConfirm && (
  <BulkPayConfirmModal
    count={selectedTransactions.length}
    total={selectedTotal}
    onConfirm={handlePaySelected}
    onCancel={() => setShowBulkConfirm(false)}
    isPending={payBulk.isPending}
  />
)}
```

- [ ] **Step 8: Commit**

```bash
git add src/pages/TrackerPage.jsx
git commit -m "feat: add archive tab and bulk pay confirmation to TrackerPage"
```

---

## Task 5: Add export totals to CSV and PDF

**Files:**
- Modify: `src/utils/export.js`
- Modify: `src/utils/export.test.js`

- [ ] **Step 1: Write the failing test for totals in CSV**

Open `src/utils/export.test.js`. The existing test `'produces correct number of rows (header + data)'` checks for 3 lines — it will need updating. First add the new totals tests, then update the row-count test.

Add a new `describe` block after the existing one:

```js
describe('buildCSVContent totals row', () => {
  it('includes a TOTALS row after the data', () => {
    const csv = buildCSVContent(sampleTransactions)
    expect(csv).toContain('TOTALS')
  })

  it('produces correct number of rows (header + data + blank + totals)', () => {
    const csv = buildCSVContent(sampleTransactions)
    const lines = csv.split('\n')
    // 1 header + 2 data + 1 blank + 1 totals = 5
    expect(lines).toHaveLength(5)
  })

  it('totals row contains correct summed amount', () => {
    const csv = buildCSVContent(sampleTransactions)
    // total amount: 1500 + 2000 = 3500
    expect(csv).toContain('3500')
  })

  it('totals row contains correct summed paid', () => {
    const csv = buildCSVContent(sampleTransactions)
    // total paid: 500 + 2000 = 2500
    expect(csv).toContain('2500')
  })

  it('totals row contains correct summed remaining', () => {
    const csv = buildCSVContent(sampleTransactions)
    // remaining: (1500-500) + (2000-2000) = 1000
    expect(csv).toContain('1000')
  })
})
```

Also update the existing row-count test (inside the first `describe`) to the new expected count — but wait, don't change it yet. Run the tests first to confirm current behavior, then update after implementation.

- [ ] **Step 2: Run tests to verify they fail**

```bash
npx vitest run src/utils/export.test.js
```

Expected output: the new totals tests FAIL with "expected ... to contain 'TOTALS'" and the row-count test in the new describe FAIL.

- [ ] **Step 3: Implement `calcTotals` and update `buildCSVContent`**

Open `src/utils/export.js`. After the `import` lines, add the helper:

```js
function calcTotals(transactions) {
  return transactions.reduce(
    (acc, t) => {
      acc.amount += Number(t.amount) || 0
      acc.paid += Number(t.amount_paid ?? 0)
      acc.remaining += getRemainingBalance(t.amount, t.amount_paid ?? 0)
      return acc
    },
    { amount: 0, paid: 0, remaining: 0 }
  )
}
```

Replace `buildCSVContent`:

```js
export function buildCSVContent(transactions) {
  const { amount, paid, remaining } = calcTotals(transactions)
  const rows = transactions.map(t => [
    t.transaction_date || '',
    t.amount,
    t.payment_due_date || '',
    t.amount_paid ?? 0,
    getRemainingBalance(t.amount, t.amount_paid ?? 0),
    t.payment_status,
    t.notes || '',
  ])
  const totalsRow = ['TOTALS', amount, '', paid, remaining, '', '']
  const blankRow = ['', '', '', '', '', '', '']
  return [CSV_HEADERS, ...rows, blankRow, totalsRow]
    .map(r => r.map(cell => `"${String(cell).replace(/"/g, '""')}"`).join(','))
    .join('\n')
}
```

- [ ] **Step 4: Update `exportPDF` to include totals footer**

Replace the `exportPDF` function:

```js
export function exportPDF(transactions, filename, title = 'Transactions') {
  const { amount, paid, remaining } = calcTotals(transactions)
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
      `PHP ${Number(t.amount_paid ?? 0).toFixed(2)}`,
      `PHP ${getRemainingBalance(t.amount, t.amount_paid ?? 0).toFixed(2)}`,
      t.payment_status,
      t.notes || '—',
    ]),
    foot: [['TOTALS', `PHP ${amount.toFixed(2)}`, '', `PHP ${paid.toFixed(2)}`, `PHP ${remaining.toFixed(2)}`, '', '']],
    styles: { fontSize: 8 },
    headStyles: { fillColor: [45, 106, 79] },
    footStyles: { fillColor: [45, 106, 79], textColor: 255, fontStyle: 'bold' },
  })

  doc.save(`${filename}.pdf`)
}
```

- [ ] **Step 5: Update the existing row-count test**

In the first `describe('buildCSVContent')` block, find:

```js
it('produces correct number of rows (header + data)', () => {
  const csv = buildCSVContent(sampleTransactions)
  const lines = csv.split('\n')
  expect(lines).toHaveLength(3) // 1 header + 2 data rows
})
```

Change to:

```js
it('produces correct number of rows (header + data + blank + totals)', () => {
  const csv = buildCSVContent(sampleTransactions)
  const lines = csv.split('\n')
  expect(lines).toHaveLength(5) // 1 header + 2 data + 1 blank + 1 totals
})
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
npx vitest run src/utils/export.test.js
```

Expected output: all tests PASS.

- [ ] **Step 7: Commit**

```bash
git add src/utils/export.js src/utils/export.test.js
git commit -m "feat: add totals row to CSV and PDF exports"
```

---

## Task 6: Manual verification on localhost

- [ ] **Step 1: Start dev server**

```bash
npm run dev
```

- [ ] **Step 2: Verify Archive tab**

1. Open any card's tracker page
2. Confirm tabs now show: **Active · History · Archive**
3. Archive a transaction from Active tab (click Archive → Yes)
4. Switch to Archive tab — transaction appears there
5. Click Restore → Yes on that transaction — it disappears from Archive and reappears in Active

- [ ] **Step 3: Verify Bulk Pay confirmation**

1. On Active tab, click **Bulk Pay**
2. Select one or more unpaid transactions
3. Click **Pay X Selected**
4. Confirm the modal appears with correct count and total
5. Click Cancel — modal closes, selections preserved, nothing paid
6. Click Pay X Selected again → Confirm Payment — transactions marked as paid, toast appears

- [ ] **Step 4: Verify Invoice column rename**

1. On desktop (≥ md breakpoint), confirm the attachment column header reads **Invoice** not **Files**

- [ ] **Step 5: Verify export totals**

1. On Active tab with transactions, click **Export CSV** — open the file and confirm a TOTALS row at the bottom
2. Click **Export PDF** — open the PDF and confirm a green-shaded TOTALS footer row

- [ ] **Step 6: Final commit if all looks good**

```bash
git add -A
git status  # confirm nothing unexpected
```

Only commit if you find stray changes. Otherwise all commits were made per-task.
