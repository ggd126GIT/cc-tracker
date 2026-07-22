# Tracker Page: Archive Tab, Bulk Pay Confirm, Invoice Rename, Export Totals

**Date:** 2026-04-20  
**Scope:** Card Tracker page only (`TrackerPage`, `TransactionTable`, `BulkPayBar`, `export.js`, `useTransactions`)

---

## Overview

Five focused improvements to the card tracker page:

1. Add an **Archive tab** to view archived transactions (with Restore action)
2. Rename tabs to **Active / History / Archive**
3. Add a **Bulk Pay confirmation modal** before executing payment
4. Rename the **"Files" column header to "Invoice"** (tracker only)
5. Include **totals row** in CSV and PDF exports

---

## 1. Active / History / Archive Tabs

**Change:** Tab array in `TrackerPage` changes from `['active', 'history']` to `['active', 'history', 'archive']`.

- Selecting any tab resets filters (`statusFilter`, `dateFrom`, `dateTo`) and exits bulk pay mode — same behavior as today
- The `activeTab` state type effectively gains a third value `'archive'`
- Archive tab does NOT show the filter bar, TransactionForm, BulkPay bar, or Close Cycle button — those are Active-only

---

## 2. Archive Tab — Data + View

### New hook: `useArchivedTransactions(cardId)`

In `useTransactions.js`, add:

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

Note: archived transactions are not tied to cycles, so no `cycle_id` filter needed.

### New mutation: `useRestoreTransaction()`

In `useTransactions.js`, add:

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

### `TransactionTable` mode prop

Add a `mode` prop to `TransactionTable`: `'active'` (default) or `'archived'`.

When `mode='archived'`:
- No Pay button
- No Edit button
- No Archive button
- Action column header label: "Actions" (unchanged)
- Action column content: a **Restore** button per row (`text-xs`, ghost style, green hover)
- BulkPay props are irrelevant and ignored

### TrackerPage wiring

```jsx
{activeTab === 'archive' && (
  <ArchivedTransactionSection cardId={cardId} />
)}
```

Or inline — fetch `useArchivedTransactions` in `TrackerPage` and pass to `TransactionTable` with `mode='archived'`.

---

## 3. Bulk Pay Confirmation Modal

### New component: `BulkPayConfirmModal`

Location: `src/components/tracker/BulkPayConfirmModal.jsx`

Props: `{ count, total, onConfirm, onCancel, isPending }`

UI:
```
┌─────────────────────────────────────────┐
│  Confirm Bulk Payment                   │
│                                         │
│  You are about to mark 3 transactions   │
│  as fully paid.                         │
│                                         │
│  Total: PHP 12,500.00                   │
│                                         │
│  This action cannot be undone.          │
│                                         │
│           [Cancel]  [Confirm Payment]   │
└─────────────────────────────────────────┘
```

Styled as a centered modal with backdrop, consistent with existing `PaymentModal` pattern.

### TrackerPage flow change

Current flow:
```
click "Pay X Selected" → handlePaySelected() → payBulk.mutateAsync()
```

New flow:
```
click "Pay X Selected" → setShowBulkConfirm(true)
→ user sees BulkPayConfirmModal
→ Confirm → handlePaySelected() → payBulk.mutateAsync()
→ Cancel → modal closes, selection preserved
```

New state in `TrackerPage`: `const [showBulkConfirm, setShowBulkConfirm] = useState(false)`

`BulkPayBar`'s `onPaySelected` prop now triggers `setShowBulkConfirm(true)` instead of directly calling `handlePaySelected`.

---

## 4. Files → Invoice (Column Header)

**File:** `src/components/tracker/TransactionTable.jsx` line 185

**Change:** `Files` → `Invoice`

Scope: desktop table header only. Mobile card layout does not have a "Files" label — the attachment icon stands alone, no change needed there.

---

## 5. Export Totals

**File:** `src/utils/export.js`

### CSV totals

After the data rows, append:
- One blank row (visual separator)
- A `TOTALS` row: `["TOTALS", sumAmount, "", sumPaid, sumRemaining, "", ""]`

The blank cells align with Date / Due Date / Status / Notes columns which don't have meaningful totals.

### PDF totals

Use jsPDF-autotable's `foot` option:

```js
foot: [['TOTALS', `PHP ${sumAmount.toFixed(2)}`, '', `PHP ${sumPaid.toFixed(2)}`, `PHP ${sumRemaining.toFixed(2)}`, '', '']],
footStyles: { fillColor: [45, 106, 79], textColor: 255, fontStyle: 'bold' },
```

This renders a green-shaded footer row matching the header, with bold white text.

### Helper (shared by both)

```js
function calcTotals(transactions) {
  return transactions.reduce((acc, t) => {
    acc.amount += Number(t.amount) || 0
    acc.paid += Number(t.amount_paid ?? 0)
    acc.remaining += getRemainingBalance(t.amount, t.amount_paid ?? 0)
    return acc
  }, { amount: 0, paid: 0, remaining: 0 })
}
```

---

## Files Touched

| File | Change |
|------|--------|
| `src/hooks/useTransactions.js` | Add `useArchivedTransactions`, `useRestoreTransaction` |
| `src/pages/TrackerPage.jsx` | Add archive tab, `showBulkConfirm` state, wire modal |
| `src/components/tracker/TransactionTable.jsx` | Add `mode` prop, Restore action, rename "Files" → "Invoice" |
| `src/components/tracker/BulkPayConfirmModal.jsx` | New component |
| `src/utils/export.js` | Add `calcTotals`, append totals to CSV and PDF |

---

## Out of Scope

- Bulk restore (not requested, archive tab is individual-restore only)
- Archive tab on shared/read-only view (read-only users cannot archive, so archive tab is hidden for `readOnly`)
- Unarchive from History (billing cycle transactions are not in the archive flow)
