"use client";

import { Download, Filter } from "lucide-react";
import { useMemo, useState } from "react";
import { useLedger } from "@/components/LedgerProvider";
import { formatMoney } from "@/lib/format";
import type { Transaction } from "@/lib/types";

type Report = "Cash Flow" | "Spending" | "Income";
type MonthlyCashFlow = { key: string; label: string; income: number; expense: number; net: number };
type BreakdownItem = { label: string; amount: number };

export default function ReportsPage() {
  const { transactions } = useLedger();
  const [report, setReport] = useState<Report>("Cash Flow");
  const reportData = useMemo(() => buildReportData(transactions), [transactions]);

  const selectedTransactions = report === "Income"
    ? reportData.currentTransactions.filter((item) => item.kind === "income")
    : report === "Spending"
      ? reportData.currentTransactions.filter((item) => item.kind === "expense")
      : reportData.currentTransactions.filter((item) => item.kind === "income" || item.kind === "expense");
  const selectedTotal = report === "Income" ? reportData.current.income : reportData.current.expense;
  const largest = selectedTransactions.reduce((maximum, item) => Math.max(maximum, Math.abs(item.amountMinorUnits)), 0);
  const average = selectedTransactions.length > 0 ? Math.round(selectedTotal / selectedTransactions.length) : 0;
  const breakdown = report === "Cash Flow" ? [] : buildBreakdown(selectedTransactions);

  return (
    <div className="page-stack">
      <div className="page-heading"><div><span className="eyebrow">Analysis</span><h1>Reports</h1><p>Charts use posted transactions from the current ledger.</p></div><div className="heading-actions"><button className="secondary-button" type="button"><Filter size={17} />Filters</button><button className="secondary-button" type="button"><Download size={17} />Export</button></div></div>

      <div className="report-tabs" role="tablist">
        {(["Cash Flow", "Spending", "Income"] as Report[]).map((item) => <button role="tab" aria-selected={report === item} className={report === item ? "active" : ""} onClick={() => setReport(item)} key={item}>{item}</button>)}
      </div>

      <section className="report-layout">
        <article className="card report-main-card">
          <div className="card-header">
            <div>
              <h2>{report}</h2>
              <span>{report === "Cash Flow" ? "Last 6 calendar months" : `${reportData.currentMonthLabel} by category`} · current ledger</span>
            </div>
          </div>
          {report === "Cash Flow"
            ? <LargeCashChart data={reportData.months} />
            : <LargeDonut report={report} total={selectedTotal} items={breakdown} />}
        </article>

        <aside className="card report-summary">
          <span className="eyebrow">{reportData.currentMonthLabel}</span>
          <h2>Summary</h2>
          {report === "Cash Flow" ? <>
            <SummaryRow label="Total income" value={formatMoney(reportData.current.income)} tone="positive" />
            <SummaryRow label="Total expenses" value={formatMoney(-reportData.current.expense)} tone="negative" />
            <SummaryRow label="Net cash flow" value={formatMoney(reportData.current.net)} tone={reportData.current.net >= 0 ? "positive" : "negative"} />
            <SummaryRow label="Transactions" value={String(selectedTransactions.length)} />
          </> : <>
            <SummaryRow label={report === "Income" ? "Total income" : "Total spending"} value={formatMoney(selectedTotal)} tone={report === "Income" ? "positive" : "negative"} />
            <SummaryRow label="Transactions" value={String(selectedTransactions.length)} />
            <SummaryRow label="Largest transaction" value={formatMoney(largest)} />
            <SummaryRow label="Average transaction" value={formatMoney(average)} />
          </>}
        </aside>
      </section>
    </div>
  );
}

function SummaryRow({ label, value, tone }: { label: string; value: string; tone?: "positive" | "negative" }) {
  return <div className="summary-row"><span>{label}</span><strong className={tone ?? ""}>{value}</strong></div>;
}

function LargeCashChart({ data }: { data: MonthlyCashFlow[] }) {
  const hasActivity = data.some((item) => item.income > 0 || item.expense > 0);
  if (!hasActivity) {
    return <div className="empty-state"><div><h3>No cash-flow activity yet</h3><p>Add income or expense transactions to populate this chart.</p></div></div>;
  }

  const width = 720;
  const height = 280;
  const baseline = 138;
  const amplitude = 88;
  const maxMagnitude = Math.max(...data.flatMap((item) => [item.income, item.expense, Math.abs(item.net)]), 1);
  const xStep = data.length > 1 ? 590 / (data.length - 1) : 0;
  const positions = data.map((item, index) => ({
    item,
    x: 65 + index * xStep,
    incomeHeight: item.income / maxMagnitude * amplitude,
    expenseHeight: item.expense / maxMagnitude * amplitude,
    netY: baseline - item.net / maxMagnitude * amplitude,
  }));
  const points = positions.map((item) => `${item.x},${item.netY}`).join(" ");

  return <div className="large-chart" role="img" aria-label="Real income, expenses, and net cash flow for the last six months">
    <svg viewBox={`0 0 ${width} ${height}`}>
      {[baseline - amplitude, baseline - amplitude / 2, baseline, baseline + amplitude / 2, baseline + amplitude].map((y) => <line key={y} x1="35" x2="690" y1={y} y2={y} className="grid-line" />)}
      {positions.map(({ item, x, incomeHeight, expenseHeight }) => <g key={item.key}>
        <rect x={x - 25} y={baseline - incomeHeight} width="22" height={incomeHeight} rx="5" className="svg-income" />
        <rect x={x + 3} y={baseline} width="22" height={expenseHeight} rx="5" className="svg-expense" />
        <text x={x} y="266" textAnchor="middle">{item.label}</text>
      </g>)}
      <polyline points={points} className="svg-net-line" />
      {positions.map(({ item, x, netY }) => <circle key={item.key} cx={x} cy={netY} r="4" className="svg-net-dot" />)}
    </svg>
    <div className="chart-legend"><span><i className="income-dot" />Income</span><span><i className="expense-dot" />Expenses</span><span><i className="net-dot" />Net</span></div>
  </div>;
}

function LargeDonut({ report, total, items }: { report: Report; total: number; items: BreakdownItem[] }) {
  if (items.length === 0 || total <= 0) {
    return <div className="empty-state"><div><h3>No {report.toLowerCase()} activity this month</h3><p>Transactions will appear here after they are posted.</p></div></div>;
  }

  const colors = ["var(--brand)", "var(--income)", "var(--warning)", "var(--expense)"];
  const background = buildConicGradient(items, total, colors);
  return <div className="large-donut-layout">
    <div className="large-donut" style={{ background }}><div><strong>{formatMoney(total)}</strong><span>Total</span></div></div>
    <div className="large-legend">
      {items.map((item, index) => <span key={item.label}>
        <i style={{ background: colors[index % colors.length] }} />
        <b>{item.label}</b>
        <strong>{formatMoney(item.amount)}</strong>
      </span>)}
    </div>
  </div>;
}

function buildReportData(transactions: Transaction[]) {
  const now = new Date();
  const months: MonthlyCashFlow[] = Array.from({ length: 6 }, (_, index) => {
    const date = new Date(now.getFullYear(), now.getMonth() - 5 + index, 1);
    return {
      key: `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`,
      label: new Intl.DateTimeFormat("en", { month: "short" }).format(date),
      income: 0,
      expense: 0,
      net: 0,
    };
  });
  const byMonth = new Map(months.map((item) => [item.key, item]));

  for (const transaction of transactions) {
    const month = byMonth.get(transaction.date.slice(0, 7));
    if (!month) continue;
    if (transaction.kind === "income") month.income += Math.abs(transaction.amountMinorUnits);
    if (transaction.kind === "expense") month.expense += Math.abs(transaction.amountMinorUnits);
  }
  for (const month of months) month.net = month.income - month.expense;

  const current = months[months.length - 1];
  return {
    months,
    current,
    currentTransactions: transactions.filter((item) => item.date.startsWith(current.key)),
    currentMonthLabel: new Intl.DateTimeFormat("en", { month: "long", year: "numeric" }).format(now),
  };
}

function buildBreakdown(transactions: Transaction[]): BreakdownItem[] {
  const amounts = new Map<string, number>();
  for (const transaction of transactions) {
    const label = transaction.category || "Uncategorized";
    amounts.set(label, (amounts.get(label) ?? 0) + Math.abs(transaction.amountMinorUnits));
  }
  const sorted = [...amounts.entries()]
    .map(([label, amount]) => ({ label, amount }))
    .sort((a, b) => b.amount - a.amount);
  if (sorted.length <= 4) return sorted;
  return [
    ...sorted.slice(0, 3),
    { label: "Other", amount: sorted.slice(3).reduce((sum, item) => sum + item.amount, 0) },
  ];
}

function buildConicGradient(items: BreakdownItem[], total: number, colors: string[]) {
  let start = 0;
  const segments = items.map((item, index) => {
    const end = start + item.amount / total * 100;
    const segment = `${colors[index % colors.length]} ${start}% ${end}%`;
    start = end;
    return segment;
  });
  return `conic-gradient(${segments.join(", ")})`;
}
