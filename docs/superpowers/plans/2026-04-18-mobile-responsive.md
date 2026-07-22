# Mobile Responsive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the app fully functional on mobile by fixing the overflowing navbar, overlapping TrackerSummary stats, and horizontal-scroll tables.

**Architecture:** Four targeted changes — new mobile bottom nav in Navbar, responsive grid in TrackerSummary, mobile card layouts replacing table rows in TransactionTable and ExpenseTable. Desktop layouts are untouched throughout. All changes use Tailwind responsive prefixes (`md:`) to switch between mobile and desktop views.

**Tech Stack:** React, Tailwind CSS (md: breakpoint = 768px), react-router-dom

---

## File Map

| Action | File | What changes |
|--------|------|-------------|
| Modify | `src/components/ui/icons.jsx` | Add `HomeIcon`, `UsersIcon`, `ShareIcon` |
| Modify | `src/components/layout/Navbar.jsx` | Full rewrite — mobile top bar + bottom nav + desktop nav |
| Modify | `src/App.jsx` | `ProtectedRoute` wraps children in `pb-16 md:pb-0` div |
| Modify | `src/components/tracker/TrackerSummary.jsx` | Responsive grid + font size |
| Modify | `src/components/tracker/TransactionTable.jsx` | Add mobile card layout above hidden desktop table |
| Modify | `src/components/expenses/ExpenseTable.jsx` | Add mobile card layout above hidden desktop table |

---

## Task 1: Add navigation icons to icons.jsx

**Files:**
- Modify: `src/components/ui/icons.jsx`

- [ ] **Step 1: Append three new icons at the end of `src/components/ui/icons.jsx`**

Open the file and append after the last existing icon export:

```jsx
export function HomeIcon({ className, ...props }) {
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
      <path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
      <polyline points="9 22 9 12 15 12 15 22" />
    </svg>
  )
}

export function UsersIcon({ className, ...props }) {
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
      <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
      <circle cx="9" cy="7" r="4" />
      <path d="M23 21v-2a4 4 0 0 0-3-3.87" />
      <path d="M16 3.13a4 4 0 0 1 0 7.75" />
    </svg>
  )
}

export function ShareIcon({ className, ...props }) {
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
      <circle cx="18" cy="5" r="3" />
      <circle cx="6" cy="12" r="3" />
      <circle cx="18" cy="19" r="3" />
      <line x1="8.59" y1="13.51" x2="15.42" y2="17.49" />
      <line x1="15.41" y1="6.51" x2="8.59" y2="10.49" />
    </svg>
  )
}
```

- [ ] **Step 2: Verify no regressions**

```bash
npx vitest run
```

Expected: 67 tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/components/ui/icons.jsx
git commit -m "feat: add HomeIcon, UsersIcon, ShareIcon for mobile bottom nav"
```

---

## Task 2: Rewrite Navbar with mobile top bar + bottom nav

**Files:**
- Modify: `src/components/layout/Navbar.jsx`

- [ ] **Step 1: Replace the entire file**

```jsx
import { useNavigate, useLocation } from 'react-router-dom'
import { supabase } from '../../lib/supabase.js'
import useAppStore from '../../store/useAppStore.js'
import Button from '../ui/Button.jsx'
import { SunIcon, MoonIcon, OwlIcon, ExpensesIcon, HomeIcon, UsersIcon, ShareIcon } from '../ui/icons.jsx'
import { usePendingInvites } from '../../hooks/useShares.js'
import { usePendingBorrowerInvites } from '../../hooks/useBorrowerShares.js'

export default function Navbar() {
  const navigate = useNavigate()
  const location = useLocation()
  const { user, isDark, toggleDark } = useAppStore()
  const { data: pendingInvites = [] } = usePendingInvites()
  const { data: pendingBorrowerInvites = [] } = usePendingBorrowerInvites()

  async function signOut() {
    await supabase.auth.signOut()
    navigate('/auth')
  }

  const navLinks = [
    { path: '/', label: 'Dashboard', Icon: HomeIcon, badge: 0 },
    { path: '/shared', label: 'Shared', Icon: ShareIcon, badge: pendingInvites.length },
    { path: '/shared-borrowers', label: 'Borrowers', Icon: UsersIcon, badge: pendingBorrowerInvites.length },
    { path: '/expenses', label: 'Expenses', Icon: ExpensesIcon, badge: 0 },
  ]

  function isActive(path) {
    if (path === '/') return location.pathname === '/'
    return location.pathname === path || location.pathname.startsWith(path + '/')
  }

  return (
    <>
      {/* ── Desktop navbar (md and up) ─────────────────────────────── */}
      <nav className="hidden md:flex sticky top-0 z-40 bg-white/90 dark:bg-gray-900/90 backdrop-blur border-b border-gray-200 dark:border-gray-700 px-4 py-3 items-center gap-3">
        <button
          onClick={() => navigate('/')}
          className="flex items-center gap-2 mr-auto"
          aria-label="Go to dashboard"
        >
          <OwlIcon className="w-7 h-7 text-gray-900 dark:text-white" />
          <span className="text-gray-900 dark:text-white font-bold tracking-tight">
            CC <span className="text-[#9FE870]">Tracker</span>
          </span>
        </button>

        {user && (
          <span className="text-gray-500 dark:text-gray-500 text-sm truncate max-w-[200px]">
            {user.email}
          </span>
        )}

        {user && navLinks.map(({ path, label, badge }) => (
          <button
            key={path}
            onClick={() => navigate(path)}
            className={`relative text-sm px-3 py-1.5 rounded-lg transition-colors ${
              isActive(path)
                ? 'bg-[#9FE870]/20 text-[#2D6A4F] dark:text-[#9FE870] font-semibold'
                : 'text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white hover:bg-gray-100 dark:hover:bg-gray-700'
            }`}
          >
            {label}
            {badge > 0 && (
              <span className="absolute -top-1 -right-1 bg-red-500 text-white text-xs w-4 h-4 rounded-full flex items-center justify-center leading-none">
                {badge}
              </span>
            )}
          </button>
        ))}

        <button
          onClick={toggleDark}
          className="text-gray-500 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
          title="Toggle theme"
          aria-label="Toggle dark mode"
        >
          {isDark ? <SunIcon className="w-5 h-5" /> : <MoonIcon className="w-5 h-5" />}
        </button>

        <Button variant="ghost" onClick={signOut} className="text-sm">
          Sign Out
        </Button>
      </nav>

      {/* ── Mobile top bar (below md) ──────────────────────────────── */}
      <nav className="md:hidden sticky top-0 z-40 bg-white/90 dark:bg-gray-900/90 backdrop-blur border-b border-gray-200 dark:border-gray-700 px-4 py-3 flex items-center justify-between">
        <button
          onClick={() => navigate('/')}
          className="flex items-center gap-2"
          aria-label="Go to dashboard"
        >
          <OwlIcon className="w-7 h-7 text-gray-900 dark:text-white" />
          <span className="text-gray-900 dark:text-white font-bold tracking-tight">
            CC <span className="text-[#9FE870]">Tracker</span>
          </span>
        </button>
        <div className="flex items-center gap-1">
          <button
            onClick={toggleDark}
            className="text-gray-500 dark:text-gray-400 p-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
            aria-label="Toggle dark mode"
          >
            {isDark ? <SunIcon className="w-5 h-5" /> : <MoonIcon className="w-5 h-5" />}
          </button>
          <Button variant="ghost" onClick={signOut} className="text-sm">
            Sign Out
          </Button>
        </div>
      </nav>

      {/* ── Mobile bottom nav (below md) ──────────────────────────── */}
      {user && (
        <nav className="md:hidden fixed bottom-0 left-0 right-0 z-40 bg-white dark:bg-gray-900 border-t border-gray-200 dark:border-gray-700">
          <div className="flex items-stretch">
            {navLinks.map(({ path, label, Icon, badge }) => (
              <button
                key={path}
                onClick={() => navigate(path)}
                className={`relative flex-1 flex flex-col items-center gap-0.5 py-2.5 transition-colors ${
                  isActive(path)
                    ? 'text-[#2D6A4F] dark:text-[#9FE870]'
                    : 'text-gray-400 dark:text-gray-500'
                }`}
              >
                <Icon className="w-5 h-5" />
                <span className="text-[10px] leading-tight">{label}</span>
                {badge > 0 && (
                  <span className="absolute top-1.5 right-[calc(50%-14px)] bg-red-500 text-white text-[9px] w-3.5 h-3.5 rounded-full flex items-center justify-center leading-none">
                    {badge}
                  </span>
                )}
              </button>
            ))}
          </div>
        </nav>
      )}
    </>
  )
}
```

- [ ] **Step 2: Run tests**

```bash
npx vitest run
```

Expected: 67 tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/components/layout/Navbar.jsx
git commit -m "feat: add mobile bottom nav and minimal mobile top bar to Navbar"
```

---

## Task 3: Add bottom padding to ProtectedRoute

**Files:**
- Modify: `src/App.jsx`

The mobile bottom nav is `fixed bottom-0 h-16`. Without body padding, page content scrolls behind it. Wrapping `ProtectedRoute` children in a `pb-16 md:pb-0` div fixes all protected pages at once.

- [ ] **Step 1: Update `ProtectedRoute` in `src/App.jsx`**

Find this function (lines 18–21):

```jsx
function ProtectedRoute({ children }) {
  const user = useAppStore((s) => s.user)
  if (!user) return <Navigate to="/auth" replace />
  return children
}
```

Replace with:

```jsx
function ProtectedRoute({ children }) {
  const user = useAppStore((s) => s.user)
  if (!user) return <Navigate to="/auth" replace />
  return <div className="pb-16 md:pb-0">{children}</div>
}
```

- [ ] **Step 2: Run tests**

```bash
npx vitest run
```

Expected: 67 tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/App.jsx
git commit -m "fix: add bottom padding to protected pages to clear mobile nav bar"
```

---

## Task 4: Fix TrackerSummary responsive stats

**Files:**
- Modify: `src/components/tracker/TrackerSummary.jsx`

- [ ] **Step 1: Replace the entire file**

```jsx
import { formatPeso, getRemainingBalance } from '../../utils/money.js'

function calcTotals(transactions = []) {
  return transactions.reduce(
    (acc, t) => ({
      totalSpent: acc.totalSpent + Number(t.amount),
      totalPaid: acc.totalPaid + Number(t.amount_paid),
      totalRemaining:
        acc.totalRemaining + getRemainingBalance(t.amount, t.amount_paid),
    }),
    { totalSpent: 0, totalPaid: 0, totalRemaining: 0 }
  )
}

function StatBox({ label, value, colorClass, className = '' }) {
  return (
    <div className={`flex flex-col gap-1 ${className}`}>
      <p className="text-xs text-gray-500 dark:text-gray-400 uppercase tracking-wide">{label}</p>
      <p className={`text-lg sm:text-2xl font-black font-mono ${colorClass}`}>{formatPeso(value)}</p>
    </div>
  )
}

export default function TrackerSummary({ card, transactions }) {
  const { totalSpent, totalPaid, totalRemaining } = calcTotals(transactions)

  return (
    <div className="sticky top-[57px] z-30 bg-white/95 dark:bg-gray-900/95 backdrop-blur border-b border-gray-200 dark:border-gray-700 px-4 py-4">
      <div className="max-w-6xl mx-auto">
        <div className="flex items-center gap-2 mb-3">
          <div
            className="w-3 h-3 rounded-full flex-shrink-0"
            style={{ backgroundColor: card.color_primary }}
          />
          <h2 className="text-gray-900 dark:text-white font-semibold">{card.nickname}</h2>
          <span className="text-gray-500 dark:text-gray-500 text-sm">· {card.bank_name}</span>
        </div>
        <div className="grid grid-cols-2 sm:grid-cols-3 gap-4">
          <StatBox label="Total Charged" value={totalSpent} colorClass="text-gray-900 dark:text-white" />
          <StatBox label="Total Paid" value={totalPaid} colorClass="text-green-600 dark:text-green-400" />
          <StatBox
            label="Outstanding"
            value={totalRemaining}
            colorClass="text-red-600 dark:text-red-400"
            className="col-span-2 sm:col-span-1"
          />
        </div>
      </div>
    </div>
  )
}
```

- [ ] **Step 2: Run tests**

```bash
npx vitest run
```

Expected: 67 tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/components/tracker/TrackerSummary.jsx
git commit -m "fix: responsive TrackerSummary stats — 2-col mobile, 3-col desktop"
```

---

## Task 5: Add mobile card layout to TransactionTable

**Files:**
- Modify: `src/components/tracker/TransactionTable.jsx`

- [ ] **Step 1: Replace the entire file**

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
        {readOnly ? 'No transactions.' : 'No transactions yet. Add your first one above.'}
      </div>
    )
  }

  return (
    <>
      {/* ── Mobile card list (below md) ──────────────────────────────── */}
      <div className="md:hidden flex flex-col divide-y divide-gray-100 dark:divide-gray-800 border border-gray-200 dark:border-gray-700 rounded-2xl overflow-hidden">
        {transactions.map((t) => {
          const count = attCounts[t.id] || 0
          const isSelectable = bulkPayMode && !readOnly && t.payment_status !== 'paid'
          const isSelected = selectedIds.has(t.id)
          return (
            <div key={t.id} className="bg-white dark:bg-gray-900 px-4 py-3">
              {/* Row 1: date + status */}
              <div className="flex items-center justify-between gap-2 mb-1.5">
                <div className="flex items-center gap-2">
                  {bulkPayMode && !readOnly && (
                    isSelectable ? (
                      <input
                        type="checkbox"
                        checked={isSelected}
                        onChange={() => onToggleSelect?.(t)}
                        className="accent-[#2D6A4F] dark:accent-[#9FE870] w-4 h-4 cursor-pointer flex-shrink-0"
                      />
                    ) : (
                      <span className="text-[#2D6A4F] dark:text-[#9FE870] text-xs w-4 flex-shrink-0">✓</span>
                    )
                  )}
                  <span className="text-xs text-gray-500 dark:text-gray-400">{formatDate(t.transaction_date)}</span>
                </div>
                <Badge status={t.payment_status} />
              </div>
              {/* Row 2: amount + remaining */}
              <div className="flex items-baseline justify-between mb-1">
                <span className="text-base font-mono font-bold text-gray-900 dark:text-white">{formatPeso(t.amount)}</span>
                <span className="text-sm font-mono text-red-600 dark:text-red-400">
                  {formatPeso(getRemainingBalance(t.amount, t.amount_paid))} left
                </span>
              </div>
              {/* Row 3: due date + notes */}
              <div className="flex items-center gap-1.5 text-xs text-gray-400 dark:text-gray-500 mb-2.5 flex-wrap">
                {t.payment_due_date && <span>Due {formatDate(t.payment_due_date)}</span>}
                {t.payment_due_date && t.notes && <span>·</span>}
                {t.notes && <span className="truncate max-w-[160px]">{t.notes}</span>}
              </div>
              {/* Row 4: actions */}
              {!readOnly && (
                <div className="flex gap-2 items-center flex-wrap">
                  {count > 0 && (
                    <button
                      onClick={() => setAttachingTxId(t.id)}
                      className="flex items-center gap-1 text-gray-400 hover:text-[#2D6A4F] dark:hover:text-[#9FE870] text-xs transition-colors"
                    >
                      <AttachmentIcon className="w-4 h-4" />
                      <span>{count}</span>
                    </button>
                  )}
                  <button
                    onClick={() => onEdit?.(t)}
                    className="text-xs text-gray-500 dark:text-gray-400 border border-gray-200 dark:border-gray-700 px-2.5 py-1 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors flex items-center gap-1"
                  >
                    <EditIcon className="w-3 h-3" /> Edit
                  </button>
                  {t.payment_status !== 'paid' && (
                    <button
                      onClick={() => onPay(t)}
                      className="text-xs text-[#2D6A4F] dark:text-[#9FE870] border border-[#2D6A4F]/30 dark:border-[#9FE870]/30 px-2.5 py-1 rounded-lg hover:bg-[#9FE870]/10 transition-colors"
                    >
                      Pay
                    </button>
                  )}
                  <div className="ml-auto">
                    {confirmArchiveId === t.id ? (
                      <span className="flex items-center gap-1">
                        <span className="text-xs text-gray-500 dark:text-gray-400">Archive?</span>
                        <button
                          onClick={() => { archive.mutate({ id: t.id, cardId }); setConfirmArchiveId(null) }}
                          className="text-xs text-red-500 font-medium"
                          disabled={archive.isPending}
                        >Yes</button>
                        <span className="text-gray-300 dark:text-gray-600">/</span>
                        <button onClick={() => setConfirmArchiveId(null)} className="text-xs text-gray-400">No</button>
                      </span>
                    ) : (
                      <button
                        onClick={() => setConfirmArchiveId(t.id)}
                        className="text-xs text-gray-400 hover:text-red-500 transition-colors"
                        disabled={archive.isPending}
                      >Archive</button>
                    )}
                  </div>
                </div>
              )}
              {readOnly && count > 0 && (
                <button
                  onClick={() => setAttachingTxId(t.id)}
                  className="flex items-center gap-1 text-gray-400 text-xs"
                >
                  <AttachmentIcon className="w-4 h-4" />
                  <span>{count}</span>
                </button>
              )}
            </div>
          )
        })}
      </div>

      {/* ── Desktop table (md and up) ─────────────────────────────────── */}
      <div className="hidden md:block overflow-x-auto rounded-2xl border border-gray-200 dark:border-gray-700">
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

- [ ] **Step 2: Run tests**

```bash
npx vitest run
```

Expected: 67 tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/components/tracker/TransactionTable.jsx
git commit -m "feat: add mobile card layout to TransactionTable"
```

---

## Task 6: Add mobile card layout to ExpenseTable

**Files:**
- Modify: `src/components/expenses/ExpenseTable.jsx`

- [ ] **Step 1: Replace the entire file**

```jsx
import { useState } from 'react'
import { formatPeso } from '../../utils/money.js'
import { getCategoryLabel, getPaymentMethodLabel, CATEGORIES } from '../../utils/expenses.js'
import { useArchiveExpense } from '../../hooks/useExpenses.js'
import Button from '../ui/Button.jsx'

function formatDate(dateStr) {
  if (!dateStr) return '—'
  return new Date(dateStr + 'T00:00:00').toLocaleDateString('en-PH', {
    month: 'short', day: 'numeric', year: 'numeric',
  })
}

function CategoryBadge({ category }) {
  const cat = CATEGORIES.find((c) => c.value === category)
  return (
    <span
      className="text-xs font-semibold px-2.5 py-1 rounded-full"
      style={{
        backgroundColor: cat ? cat.color + '22' : '#9CA3AF22',
        color: cat ? cat.color : '#9CA3AF',
      }}
    >
      {getCategoryLabel(category)}
    </span>
  )
}

export default function ExpenseTable({ expenses, onEdit }) {
  const archive = useArchiveExpense()
  const [confirmArchiveId, setConfirmArchiveId] = useState(null)

  if (!expenses || expenses.length === 0) {
    return (
      <div className="text-center py-16 text-gray-500 border border-dashed border-gray-300 dark:border-gray-700 rounded-xl">
        No expenses for this period.
      </div>
    )
  }

  return (
    <>
      {/* ── Mobile card list (below md) ──────────────────────────────── */}
      <div className="md:hidden flex flex-col divide-y divide-gray-100 dark:divide-gray-800 border border-gray-200 dark:border-gray-700 rounded-2xl overflow-hidden">
        {expenses.map((e) => (
          <div key={e.id} className="bg-white dark:bg-gray-900 px-4 py-3">
            {/* Row 1: date + category badge */}
            <div className="flex items-center justify-between gap-2 mb-1.5">
              <span className="text-xs text-gray-500 dark:text-gray-400">{formatDate(e.expense_date)}</span>
              <CategoryBadge category={e.category} />
            </div>
            {/* Row 2: description + amount */}
            <div className="flex items-baseline justify-between mb-1">
              <span className="text-sm font-medium text-gray-900 dark:text-white truncate max-w-[180px]">{e.description}</span>
              <span className="text-base font-mono font-bold text-red-600 dark:text-red-400 ml-2 flex-shrink-0">{formatPeso(e.amount)}</span>
            </div>
            {/* Row 3: payment method + notes */}
            <p className="text-xs text-gray-400 dark:text-gray-500 mb-2.5">
              {getPaymentMethodLabel(e.payment_method)}{e.notes ? ` · ${e.notes}` : ''}
            </p>
            {/* Row 4: actions */}
            <div className="flex gap-2 items-center">
              <Button
                variant="ghost"
                className="text-xs py-1 px-2.5"
                onClick={() => onEdit(e)}
              >
                Edit
              </Button>
              {confirmArchiveId === e.id ? (
                <span className="flex items-center gap-1">
                  <span className="text-xs text-gray-500 dark:text-gray-400">Archive?</span>
                  <button
                    onClick={() => { archive.mutate(e.id); setConfirmArchiveId(null) }}
                    className="text-xs text-red-500 font-medium"
                    disabled={archive.isPending}
                  >Yes</button>
                  <span className="text-gray-300 dark:text-gray-600">/</span>
                  <button onClick={() => setConfirmArchiveId(null)} className="text-xs text-gray-400">No</button>
                </span>
              ) : (
                <button
                  onClick={() => setConfirmArchiveId(e.id)}
                  className="text-xs text-gray-400 hover:text-red-500 ml-auto transition-colors"
                  disabled={archive.isPending}
                >
                  Archive
                </button>
              )}
            </div>
          </div>
        ))}
      </div>

      {/* ── Desktop table (md and up) ─────────────────────────────────── */}
      <div className="hidden md:block overflow-x-auto rounded-2xl border border-gray-200 dark:border-gray-700">
        <table className="w-full text-sm">
          <thead>
            <tr className="bg-gray-100 dark:bg-gray-800 text-gray-500 dark:text-gray-400 text-xs uppercase tracking-wide">
              <th className="px-4 py-3 text-left whitespace-nowrap">Date</th>
              <th className="px-4 py-3 text-left whitespace-nowrap">Category</th>
              <th className="px-4 py-3 text-left">Description</th>
              <th className="px-4 py-3 text-right whitespace-nowrap">Amount</th>
              <th className="px-4 py-3 text-left whitespace-nowrap">Payment</th>
              <th className="px-4 py-3 text-left">Notes</th>
              <th className="px-4 py-3 text-center whitespace-nowrap">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100 dark:divide-gray-800">
            {expenses.map((e) => (
              <tr key={e.id} className="hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors text-gray-700 dark:text-gray-200">
                <td className="px-4 py-3 whitespace-nowrap text-gray-500 dark:text-gray-400">
                  {formatDate(e.expense_date)}
                </td>
                <td className="px-4 py-3 whitespace-nowrap">
                  <CategoryBadge category={e.category} />
                </td>
                <td className="px-4 py-3 max-w-[180px] truncate">{e.description}</td>
                <td className="px-4 py-3 text-right font-mono text-red-600 dark:text-red-400">
                  {formatPeso(e.amount)}
                </td>
                <td className="px-4 py-3 whitespace-nowrap text-gray-500 dark:text-gray-400">
                  {getPaymentMethodLabel(e.payment_method)}
                </td>
                <td className="px-4 py-3 text-gray-500 dark:text-gray-400 max-w-[120px] truncate">
                  {e.notes || '—'}
                </td>
                <td className="px-4 py-3 text-center">
                  <div className="flex gap-2 justify-center items-center">
                    <Button
                      variant="ghost"
                      className="text-xs py-1 px-2"
                      onClick={() => onEdit(e)}
                    >
                      Edit
                    </Button>
                    {confirmArchiveId === e.id ? (
                      <span className="flex items-center gap-1">
                        <span className="text-xs text-gray-500 dark:text-gray-400 whitespace-nowrap">Archive?</span>
                        <button
                          onClick={() => { archive.mutate(e.id); setConfirmArchiveId(null) }}
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
                        onClick={() => setConfirmArchiveId(e.id)}
                        className="text-gray-400 hover:text-red-500 dark:hover:text-red-400 text-xs transition-colors"
                        disabled={archive.isPending}
                      >
                        Archive
                      </button>
                    )}
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  )
}
```

- [ ] **Step 2: Run full test suite**

```bash
npx vitest run
```

Expected: 67 tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/components/expenses/ExpenseTable.jsx
git commit -m "feat: add mobile card layout to ExpenseTable"
```

---

## Done

Manual test checklist (mobile viewport, ~430px wide):
- [ ] Navbar: top bar shows logo + dark mode + Sign Out; bottom bar shows 4 tabs with icons and labels
- [ ] Active tab highlighted in green on bottom nav
- [ ] Pending invite badge appears on Shared/Borrowers tabs when invites exist
- [ ] Desktop (≥768px): original full navbar, no bottom bar
- [ ] TrackerSummary: 2-col grid on mobile (Charged + Paid top row, Outstanding full-width below), no overflow
- [ ] TransactionTable: card rows on mobile with date, status badge, amount, remaining, due date, notes, action buttons
- [ ] Bulk pay checkboxes appear on mobile cards when Bulk Pay is active
- [ ] ExpenseTable: card rows on mobile with date, category badge, description, amount, payment method
- [ ] Edit and Archive actions accessible on all mobile cards
- [ ] No horizontal scrollbars anywhere on mobile
- [ ] Page content not hidden behind bottom nav (bottom padding clears it)
