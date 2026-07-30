"use client";

import { Download, Filter } from "lucide-react";
import { useMemo, useState } from "react";
import { useLedger } from "@/components/LedgerProvider";
import { cashFlow } from "@/lib/mock-data";
import { formatMoney } from "@/lib/format";

type Report = "Cash Flow" | "Spending" | "Income";

export default function ReportsPage() {
  const { transactions } = useLedger();
  const [report, setReport] = useState<Report>("Cash Flow");

  const totals = useMemo(() => {
    const income = transactions.filter((item) => item.kind === "income").reduce((sum, item) => sum + Math.max(item.amountMinorUnits, 0), 0);
    const expenses = Math.abs(transactions.filter((item) => item.kind === "expense").reduce((sum, item) => sum + item.amountMinorUnits, 0));
    return { income, expenses, net: income - expenses };
  }, [transactions]);

  return (
    <div className="page-stack">
      <div className="page-heading"><div><span className="eyebrow">Analysis</span><h1>Reports</h1><p>Charts are paired with readable totals and drill-downs.</p></div><div className="heading-actions"><button className="secondary-button" type="button"><Filter size={17} />Filters</button><button className="secondary-button" type="button"><Download size={17} />Export</button></div></div>

      <div className="report-tabs" role="tablist">
        {(["Cash Flow", "Spending", "Income"] as Report[]).map((item) => <button role="tab" aria-selected={report === item} className={report === item ? "active" : ""} onClick={() => setReport(item)} key={item}>{item}</button>)}
      </div>

      <section className="report-layout">
        <article className="card report-main-card">
          <div className="report-controls"><label><span>Chart</span><select><option>{report === "Cash Flow" ? "Bar + line" : "Donut"}</option></select></label><label><span>Timeframe</span><select><option>Monthly</option><option>Quarterly</option><option>Yearly</option></select></label></div>
          {report === "Cash Flow" ? <LargeCashChart /> : <LargeDonut report={report} total={report === "Income" ? totals.income : totals.expenses} />}
        </article>

        <aside className="card report-summary">
          <span className="eyebrow">July 2026</span>
          <h2>Summary</h2>
          {report === "Cash Flow" ? <>
            <SummaryRow label="Total income" value={formatMoney(totals.income)} tone="positive" />
            <SummaryRow label="Total expenses" value={formatMoney(-totals.expenses)} tone="negative" />
            <SummaryRow label="Net cash flow" value={formatMoney(totals.net)} tone={totals.net >= 0 ? "positive" : "negative"} />
          </> : <>
            <SummaryRow label={report === "Income" ? "Total income" : "Total spending"} value={formatMoney(report === "Income" ? totals.income : totals.expenses)} tone={report === "Income" ? "positive" : "negative"} />
            <SummaryRow label="Total transactions" value={String(transactions.length)} />
            <SummaryRow label="Largest transaction" value="$5,000.00" />
            <SummaryRow label="Average transaction" value="$612.24" />
          </>}
        </aside>
      </section>
    </div>
  );
}

function SummaryRow({ label, value, tone }: { label: string; value: string; tone?: "positive" | "negative" }) {
  return <div className="summary-row"><span>{label}</span><strong className={tone ?? ""}>{value}</strong></div>;
}

function LargeCashChart() {
  const max = Math.max(...cashFlow.flatMap((item) => [item.income, item.expense]));
  const width = 720;
  const height = 280;
  const points = cashFlow.map((item, index) => `${80 + index * 135},${height - (item.net + 100000) / 700000 * 220}`).join(" ");
  return <div className="large-chart" role="img" aria-label="Income, expenses, and net cash flow from March through July 2026">
    <svg viewBox={`0 0 ${width} ${height}`}>
      {[50, 110, 170, 230].map((y) => <line key={y} x1="50" x2="700" y1={y} y2={y} className="grid-line" />)}
      {cashFlow.map((item, index) => {
        const x = 65 + index * 135;
        const incomeHeight = (item.income / max) * 150;
        const expenseHeight = (item.expense / max) * 150;
        return <g key={item.label}>
          <rect x={x} y={230 - incomeHeight} width="28" height={incomeHeight} rx="5" className="svg-income" />
          <rect x={x + 34} y="230" width="28" height={expenseHeight * .65} rx="5" className="svg-expense" />
          <text x={x + 28} y="272" textAnchor="middle">{item.label}</text>
        </g>;
      })}
      <polyline points={points} className="svg-net-line" />
      {points.split(" ").map((pair) => { const [cx, cy] = pair.split(","); return <circle key={pair} cx={cx} cy={cy} r="4" className="svg-net-dot" />; })}
    </svg>
    <div className="chart-legend"><span><i className="income-dot" />Income</span><span><i className="expense-dot" />Expenses</span><span><i className="net-dot" />Net</span></div>
  </div>;
}

function LargeDonut({ report, total }: { report: Report; total: number }) {
  return <div className="large-donut-layout"><div className={`large-donut ${report === "Income" ? "income-donut" : "spending-donut"}`}><div><strong>{formatMoney(total)}</strong><span>Total</span></div></div><div className="large-legend"><span><i className="legend-blue" /><b>{report === "Income" ? "Business Income" : "Housing"}</b><strong>{formatMoney(total * .63)}</strong></span><span><i className="legend-teal" /><b>{report === "Income" ? "Other Income" : "Food & Dining"}</b><strong>{formatMoney(total * .24)}</strong></span><span><i className="legend-amber" /><b>{report === "Income" ? "Interest" : "Transportation"}</b><strong>{formatMoney(total * .13)}</strong></span></div></div>;
}
