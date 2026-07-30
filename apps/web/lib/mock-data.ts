import type { Account, Transaction } from "./types";

export const accounts: Account[] = [
  { id: "checking", name: "SoFi Checking (…9852)", subtype: "Checking", type: "asset", group: "Assets", balanceMinorUnits: 512045 },
  { id: "savings", name: "SoFi Savings (…1120)", subtype: "Savings", type: "asset", group: "Assets", balanceMinorUnits: 781473 },
  { id: "cash", name: "Cash Wallet", subtype: "Cash", type: "asset", group: "Assets", balanceMinorUnits: 60000 },
  { id: "investments", name: "Robinhood", subtype: "Investments", type: "asset", group: "Assets", balanceMinorUnits: 625012 },
  { id: "credit", name: "Chase Sapphire", subtype: "Credit Card", type: "liability", group: "Liabilities", balanceMinorUnits: -193455 },
  { id: "loan", name: "SoFi Personal Loan", subtype: "Loan", type: "liability", group: "Liabilities", balanceMinorUnits: -200000 },
];

export const initialTransactions: Transaction[] = [
  { id: "t1", date: "2026-07-26", payee: "SoFi", category: "Transfer", account: "Cash", accountId: "cash", categoryId: "checking", amountMinorUnits: 2, kind: "income", revision: 1 },
  { id: "t2", date: "2026-07-25", payee: "Safeway", category: "Groceries", account: "SoFi Checking", accountId: "checking", categoryId: "groceries", amountMinorUnits: -7823, kind: "expense", revision: 1 },
  { id: "t3", date: "2026-07-24", payee: "Shell", category: "Transportation", account: "SoFi Checking", accountId: "checking", categoryId: "transportation", amountMinorUnits: -4631, kind: "expense", revision: 1 },
  { id: "t4", date: "2026-07-23", payee: "Venmo", category: "Transfer", account: "SoFi Checking", accountId: "checking", categoryId: "cash", amountMinorUnits: 12000, kind: "transfer", revision: 1 },
  { id: "t5", date: "2026-07-22", payee: "Netflix", category: "Entertainment", account: "SoFi Checking", accountId: "checking", categoryId: "entertainment", amountMinorUnits: -1549, kind: "expense", revision: 1 },
];

export const cashFlow = [
  { label: "Mar", income: 500000, expense: 180000, net: 320000 },
  { label: "Apr", income: 240000, expense: 330000, net: -90000 },
  { label: "May", income: 210000, expense: 160000, net: 50000 },
  { label: "Jun", income: 185000, expense: 192000, net: -7000 },
  { label: "Jul", income: 540102, expense: 324650, net: 215452 },
];
