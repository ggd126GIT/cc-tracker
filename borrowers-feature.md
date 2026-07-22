## Borrowers & Lending Feature Specification

### Overview
A complementary system to the credit card tracker that allows users to track money they lend to other people. This feature mirrors the CC tracker but in reverse (others owe the user).

---

### Core Concepts
- A **Borrower** = a person who owes money
- A **Loan** = a specific obligation under a borrower
- A **Payment Ledger** = history of payments made toward a loan

---

### Borrower Management

#### Required Fields
- Full Name (required)
- Address (required)
- Phone Number (required)
- Email (required for sharing)

#### Behavior
- A borrower can have **multiple loans**
- Display borrower summary:
  - Total Loaned
  - Total Paid
  - Total Outstanding

---

### Loan Management

#### Required Fields
- Loan Amount
- Loan Date

#### Additional Fields
- Loan Description (e.g., iPhone, Cash, Tablet)
- Payment Frequency:
  - One-time
  - Weekly
  - Monthly
- Next Payment Date
- Interest (optional toggle)

#### Notarization
- Notarized: YES / NO
- If YES:
  - Lawyer Name
  - PTR Number
  - Date Notarized

#### Loan Status
- Active
- Completed
- Overdue
- Defaulted

---

### Payment Ledger (Critical)

Each loan must have a **transaction history table**:

Fields:
- Payment ID
- Date
- Amount Paid
- Remaining Balance (auto-calculated)
- Notes
- Created By (Owner / Borrower)
- Created At / Updated At

#### Behavior
- Supports partial payments
- Automatically updates:
  - Loan balance
  - Borrower summary
  - Progress bars

---

### Progress Tracking

#### Per Loan
- Progress bar:
  - Paid vs Total Loan

#### Per Borrower
- Aggregated progress across all loans

---

### Overdue Logic

Automatically mark loan as **Overdue** if:
- Current date > Next Payment Date
- Remaining balance > 0

UI Indicators:
- Red badge
- Warning label

---

### Sharing System

#### Flow
- Owner sends invite via email
- Borrower must:
  - Create account
  - Accept invite

#### Roles

**Owner**
- Full control
- Manage loans, payments, permissions

**Borrower**
- View loans
- Optional: suggest payment entries (requires owner confirmation)

#### Security
- Tokenized invite links
- Expiration support

---

### UI / UX Requirements

#### Dashboard Integration
- "My Borrowers" section under cards

#### Borrower Card
- Name / Initial Avatar
- Summary (Total Loaned, Paid, Balance)
- Progress bar

#### Loan View
- Loan summary card
- Payment ledger table
- Status indicators

---

### Data Integrity & Audit

- No hard deletes (archive only)
- Maintain activity logs:
  - Payment creation
  - Edits
  - Status changes

---

### Reuse from CC Tracker

- Transaction system → Payment ledger
- Progress bar logic
- Sharing system
- Real-time updates

---

### Future Enhancements

- File upload for notarized documents
- Payment reminders
- SMS notifications
- Interest calculation engine

---

## Summary
This product is a **secure, minimal, and high-performance credit card tracking system** that prioritizes:
- Data privacy
- Financial accuracy
- Clean UX
- Real-time updates

The goal is to deliver a tool that feels **trustworthy, fast, and intentional**, not experimental or bloated.

