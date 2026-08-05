"use client";

import Link from "next/link";
import { ArrowUpRight, ChevronRight } from "lucide-react";
import { formatDate, formatMoney } from "@/lib/format";
import type { Transaction } from "@/lib/types";
import { useLedger } from "@/components/LedgerProvider";

type MonthlyCashFlow = {
  key: string;
  label: string;
  income: number;
  expense: number;
};

type SpendingItem = {
  label: string;
  amount: number;
};

export default function DashboardPage() {
  const { transactions, accounts, ledger } = useLedger();
  const currentMonthKey = monthKey(new Date());
  const currentMonthTransactions = transactions.filter((item) => item.date.startsWith(currentMonthKey));
  const income = currentMonthTransactions
    .filter((item) => item.kind === "income")
    .reduce((sum, item) => sum + Math.abs(item.amountMinorUnits), 0);
  const expenses = currentMonthTransactions
    .filter((item) => item.kind === "expense")
    .reduce((sum, item) => sum + Math.abs(item.amountMinorUnits), 0);
  const netCashFlow = income - expenses;
  const assetTotal = accounts
    .filter((account) => account.type === "asset")
    .reduce((sum, account) => sum + account.balanceMinorUnits, 0);
  const liabilityTotal = accounts
    .filter((account) => account.type === "liability")
    .reduce((sum, account) => sum + account.balanceMinorUnits, 0);
  const recordedBalance = assetTotal + liabilityTotal;
  const monthlyCashFlow = buildMonthlyCashFlow(transactions);
  const spending = buildSpendingBreakdown(currentMonthTransactions);
  const monthLabel = new Intl.DateTimeFormat("en", { month: "long", year: "numeric" }).format(new Date());
  const cashFlowRange = `${monthlyCashFlow[0]?.label ?? ""}–${monthlyCashFlow.at(-1)?.label ?? ""}`;

  return (
    <div className="page-stack">
      <PageHeading
        title="Overview"
        subtitle={`${ledger?.name ?? "Current ledger"} · ${monthLabel}`}
      />

      <section className="dashboard-lower-grid">
        <div className="card cash-flow-card">
          <span className="eyebrow">This month</span>
          <strong className={`card-hero-value ${netCashFlow < 0 ? "negative" : "positive"}`}>
            {formatMoney(netCashFlow)}
          </strong>
          <small>Net cash flow for {monthLabel}.</small>
          <div>
            <MetricRow label="Income" value={formatMoney(income)} tone="positive" />
            <MetricRow label="Spending" value={formatMoney(-expenses)} tone="negative" />
            <MetricRow label="Net cash flow" value={formatMoney(netCashFlow)} tone={netCashFlow < 0 ? "negative" : "positive"} />
          </div>
        </div>

        <div className="card accounts-summary-card">
          <CardHeader title="Account balances" meta="Recorded balance" />
          <strong className={`card-hero-value ${recordedBalance < 0 ? "negative" : ""}`}>
            {formatMoney(recordedBalance)}
          </strong>
          <MetricRow label="Assets" value={formatMoney(assetTotal)} tone={assetTotal < 0 ? "negative" : "neutral"} />
          <MetricRow label="Liabilities" value={formatMoney(liabilityTotal)} tone={liabilityTotal < 0 ? "negative" : "neutral"} />
          <p className="form-note">Based on recorded transactions. Accounts start at $0 until an opening balance is entered.</p>
          <Link className="card-link" href="/accounts">View accounts <ChevronRight size={15} /></Link>
        </div>
      </section>

      <section className="dashboard-lower-grid">
        <div className="card spending-card">
          <CardHeader title="Spending by category" meta={monthLabel} />
          <Donut total={expenses} items={spending} />
          <Link className="card-link" href="/reports">View spending report <ChevronRight size={15} /></Link>
        </div>

        <div className="card transaction-card">
          <CardHeader title="Recent transactions" meta="Newest first" />
          <div className="transaction-table compact">
            <div className="transaction-head"><span>Date</span><span>Payee</span><span>Category</span><span>Account</span><span>Amount</span></div>
            {transactions.slice(0, 6).map((transaction) => (
              <Link className="transaction-line transaction-button" href={`/transactions/${transaction.id}`} key={transaction.id}>
                <span>{formatDate(transaction.date)}</span>
                <strong>{transaction.payee}</strong>
                <span>{transaction.category}</span>
                <span>{transaction.account}</span>
                <b className={transaction.amountMinorUnits < 0 ? "negative" : transaction.kind === "transfer" ? "" : "positive"}>{formatMoney(transaction.amountMinorUnits, { sign: transaction.amountMinorUnits > 0 })}</b>
              </Link>
            ))}
            {transactions.length === 0 ? <div className="empty-state compact-empty"><p>No transactions yet.</p></div> : null}
          </div>
          {ledger ? <Link className="card-link" href={`/ledgers/${ledger.id}`}>Open ledger <ChevronRight size={15} /></Link> : null}
        </div>
      </section>

      <section className="card cash-flow-chart-card">
        <CardHeader title="Monthly cash flow" meta={cashFlowRange} />
        <CashFlowBars data={monthlyCashFlow} />
        <Link className="card-link" href="/reports">View full report <ArrowUpRight size={15} /></Link>
      </section>
    </div>
  );
}

function PageHeading({ title, subtitle }: { title: string; subtitle: string }) {
  return <div className="page-heading"><div><span className="eyebrow">Rainflow</span><h1>{title}</h1><p>{subtitle}</p></div></div>;
}

function CardHeader({ title, meta }: { title: string; meta: string }) {
  return <div className="card-header"><div><h2>{title}</h2><span>{meta}</span></div></div>;
}

function MetricRow({ label, value, tone }: { label: string; value: string; tone: "positive" | "negative" | "neutral" }) {
  return <div className="metric-row"><span>{label}</span><strong className={tone === "neutral" ? "" : tone}>{value}</strong></div>;
}

function Donut({ total, items }: { total: number; items: SpendingItem[] }) {
  if (total <= 0 || items.length === 0) {
    return <div className="empty-state compact-empty"><p>No spending this month.</p></div>;
  }

  const colors = ["var(--brand)", "var(--warning)", "var(--brand-accent)", "var(--expense)"];
  const background = buildConicGradient(items, total, colors);
  return <div className="donut-wrap">
    <div className="donut" style={{ background }}><div><strong>{formatMoney(total)}</strong><span>Total</span></div></div>
    <div className="donut-legend">
      {items.map((item, index) => <span key={item.label}>
        <i style={{ background: colors[index % colors.length] }} />
        {item.label} {Math.round(item.amount / total * 100)}%
      </span>)}
    </div>
  </div>;
}

function CashFlowBars({ data }: { data: MonthlyCashFlow[] }) {
  const hasActivity = data.some((item) => item.income > 0 || item.expense > 0);
  if (!hasActivity) {
    return <div className="empty-state"><div><h3>No cash-flow activity yet</h3><p>Add income or expense transactions to populate this chart.</p></div></div>;
  }

  const max = Math.max(...data.flatMap((item) => [item.income, item.expense]), 1);
  return <div className="cash-chart" role="img" aria-label="Income and expenses for the last six calendar months">
    <div className="chart-grid-lines"><span /><span /><span /><span /></div>
    <div className="bar-groups">
      {data.map((item) => <div className="bar-group" key={item.key}>
        <div className="bar-pair"><i className="income-bar" style={{ height: `${item.income > 0 ? Math.max(4, item.income / max * 150) : 0}px` }} /><i className="expense-bar" style={{ height: `${item.expense > 0 ? Math.max(4, item.expense / max * 150) : 0}px` }} /></div>
        <span>{item.label}</span>
      </div>)}
    </div>
    <div className="chart-legend"><span><i className="income-dot" />Income</span><span><i className="expense-dot" />Expenses</span></div>
  </div>;
}

function buildMonthlyCashFlow(transactions: Transaction[]): MonthlyCashFlow[] {
  const now = new Date();
  const months = Array.from({ length: 6 }, (_, index) => {
    const date = new Date(now.getFullYear(), now.getMonth() - 5 + index, 1);
    return {
      key: monthKey(date),
      label: new Intl.DateTimeFormat("en", { month: "short" }).format(date),
      income: 0,
      expense: 0,
    };
  });
  const lookup = new Map(months.map((item) => [item.key, item]));

  for (const transaction of transactions) {
    const month = lookup.get(transaction.date.slice(0, 7));
    if (!month) continue;
    if (transaction.kind === "income") month.income += Math.abs(transaction.amountMinorUnits);
    if (transaction.kind === "expense") month.expense += Math.abs(transaction.amountMinorUnits);
  }

  return months;
}

function buildSpendingBreakdown(transactions: Transaction[]): SpendingItem[] {
  const totals = new Map<string, number>();
  for (const transaction of transactions) {
    if (transaction.kind !== "expense") continue;
    const label = transaction.category || "Uncategorized";
    totals.set(label, (totals.get(label) ?? 0) + Math.abs(transaction.amountMinorUnits));
  }

  const sorted = [...totals.entries()]
    .map(([label, amount]) => ({ label, amount }))
    .sort((a, b) => b.amount - a.amount);
  if (sorted.length <= 4) return sorted;
  return [
    ...sorted.slice(0, 3),
    { label: "Other", amount: sorted.slice(3).reduce((sum, item) => sum + item.amount, 0) },
  ];
}

function buildConicGradient(items: SpendingItem[], total: number, colors: string[]) {
  let start = 0;
  const segments = items.map((item, index) => {
    const end = start + item.amount / total * 100;
    const segment = `${colors[index % colors.length]} ${start}% ${end}%`;
    start = end;
    return segment;
  });
  return `conic-gradient(${segments.join(", ")})`;
}

function monthKey(date: Date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}
