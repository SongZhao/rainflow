"use client";

import Link from "next/link";
import { ArrowUpRight, CalendarDays, ChevronRight, MoreHorizontal } from "lucide-react";
import { cashFlow } from "@/lib/mock-data";
import { formatDate, formatMoney } from "@/lib/format";
import { useLedger } from "@/components/LedgerProvider";

export default function DashboardPage() {
  const { transactions, accounts, ledger } = useLedger();
  const income = transactions.filter((item) => item.kind === "income").reduce((sum, item) => sum + Math.max(item.amountMinorUnits, 0), 0);
  const expenses = Math.abs(transactions.filter((item) => item.kind === "expense").reduce((sum, item) => sum + item.amountMinorUnits, 0));
  const netWorth = accounts.reduce((sum, account) => sum + account.balanceMinorUnits, 0);

  return (
    <div className="page-stack">
      <PageHeading title="Dashboard" subtitle="Your financial position at a glance." />

      <section className="metric-grid">
        <MetricCard title="Net Worth" value={formatMoney(netWorth)} delta="+$1,250.50 (5.44%)" positive>
          <Sparkline values={[18, 24, 20, 31, 28, 39, 35, 48, 43, 57, 52, 68]} />
        </MetricCard>
        <div className="card cash-flow-card">
          <CardHeader title="Cash Flow" meta="This month" />
          <MetricRow label="Income" value={formatMoney(income)} tone="positive" />
          <MetricRow label="Expenses" value={formatMoney(-expenses)} tone="negative" />
          <MetricRow label="Net" value={formatMoney(income - expenses)} tone={income >= expenses ? "positive" : "negative"} />
          <div className="balance-bar"><span style={{ width: `${Math.min(75, (income / Math.max(income + expenses, 1)) * 100)}%` }} /><i /></div>
        </div>
        <div className="card accounts-summary-card">
          <CardHeader title="Accounts" meta="Total balance" />
          <strong className="card-hero-value">{formatMoney(netWorth)}</strong>
          {Object.entries(groupTotals(accounts)).map(([group, total]) => <MetricRow key={group} label={group} value={formatMoney(total)} tone={total < 0 ? "negative" : "neutral"} />)}
          <Link className="card-link" href="/accounts">View all accounts <ChevronRight size={15} /></Link>
        </div>
        <div className="card spending-card">
          <CardHeader title="Spending" meta="This month" />
          <Donut total={expenses} />
          <Link className="card-link" href="/reports">View full report <ChevronRight size={15} /></Link>
        </div>
      </section>

      <section className="dashboard-lower-grid">
        <div className="card transaction-card">
          <CardHeader title="Recent Transactions" meta="Most recent" />
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
          </div>
          {ledger ? <Link className="card-link" href={`/ledgers/${ledger.id}`}>Open ledger <ChevronRight size={15} /></Link> : null}
        </div>

        <div className="card cash-flow-chart-card">
          <CardHeader title="Cash Flow" meta="Mar–Jul 2026" />
          <CashFlowBars />
          <Link className="card-link" href="/reports">View full report <ArrowUpRight size={15} /></Link>
        </div>
      </section>

      <section className="card recurring-strip">
        <div><span className="eyebrow">Recurring</span><h2>Upcoming this month</h2><p>Keep lightweight reminders here until full recurring rules are enabled.</p></div>
        <div className="recurring-item"><CalendarDays size={20} /><span><strong>Netflix</strong><small>Due tomorrow</small></span><b>{formatMoney(1549)}</b></div>
      </section>
    </div>
  );
}

function PageHeading({ title, subtitle }: { title: string; subtitle: string }) {
  return <div className="page-heading"><div><span className="eyebrow">Rainflow</span><h1>{title}</h1><p>{subtitle}</p></div><button className="icon-button" type="button" aria-label="Dashboard options"><MoreHorizontal /></button></div>;
}

function CardHeader({ title, meta }: { title: string; meta: string }) {
  return <div className="card-header"><div><h2>{title}</h2><span>{meta}</span></div><button className="icon-button subtle" type="button" aria-label={`${title} options`}><MoreHorizontal size={18} /></button></div>;
}

function MetricCard({ title, value, delta, positive, children }: { title: string; value: string; delta: string; positive?: boolean; children: React.ReactNode }) {
  return <div className="card metric-card"><span className="eyebrow">{title}</span><strong className="card-hero-value">{value}</strong><span className={positive ? "positive" : "negative"}>{delta} <small>vs. last month</small></span>{children}</div>;
}

function MetricRow({ label, value, tone }: { label: string; value: string; tone: "positive" | "negative" | "neutral" }) {
  return <div className="metric-row"><span>{label}</span><strong className={tone === "neutral" ? "" : tone}>{value}</strong></div>;
}

function Sparkline({ values }: { values: number[] }) {
  const width = 280;
  const height = 90;
  const max = Math.max(...values);
  const min = Math.min(...values);
  const points = values.map((value, index) => `${(index / (values.length - 1)) * width},${height - ((value - min) / (max - min)) * height}`).join(" ");
  return <svg className="sparkline" viewBox={`0 0 ${width} ${height}`} role="img" aria-label="Net worth increased over the displayed period"><polyline points={points} /></svg>;
}

function groupTotals(accounts: Array<{ group: string; balanceMinorUnits: number }>) {
  return accounts.reduce<Record<string, number>>((result, account) => {
    result[account.group] = (result[account.group] ?? 0) + account.balanceMinorUnits;
    return result;
  }, {});
}

function Donut({ total }: { total: number }) {
  return <div className="donut-wrap"><div className="donut"><div><strong>{formatMoney(total)}</strong><span>Total</span></div></div><div className="donut-legend"><span><i className="legend-blue" />Housing 37%</span><span><i className="legend-amber" />Food 21%</span><span><i className="legend-teal" />Transport 17%</span><span><i className="legend-red" />Other 25%</span></div></div>;
}

function CashFlowBars() {
  const max = Math.max(...cashFlow.flatMap((item) => [item.income, item.expense]));
  return <div className="cash-chart" role="img" aria-label="Cash flow chart from March through July 2026">
    <div className="chart-grid-lines"><span /><span /><span /><span /></div>
    <div className="bar-groups">
      {cashFlow.map((item) => <div className="bar-group" key={item.label}>
        <div className="bar-pair"><i className="income-bar" style={{ height: `${Math.max(4, (item.income / max) * 150)}px` }} /><i className="expense-bar" style={{ height: `${Math.max(4, (item.expense / max) * 150)}px` }} /></div>
        <span>{item.label}</span>
      </div>)}
    </div>
    <div className="chart-legend"><span><i className="income-dot" />Income</span><span><i className="expense-dot" />Expenses</span></div>
  </div>;
}
