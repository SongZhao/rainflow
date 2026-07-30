"use client";

import Link from "next/link";
import { ArrowLeft, CalendarDays, ChevronLeft, ChevronRight } from "lucide-react";
import { useParams } from "next/navigation";
import { useEffect, useMemo, useState } from "react";
import { useLedger } from "@/components/LedgerProvider";
import { formatDate, formatMoney } from "@/lib/format";
import type { Transaction } from "@/lib/types";

export default function LedgerDetailPage() {
  const params = useParams<{ id: string }>();
  const { ledger, ledgers, accounts, transactions, switchLedger } = useLedger();
  const total = accounts.reduce((sum, account) => sum + account.balanceMinorUnits, 0);
  const requestedLedger = ledgers.find((item) => item.id === params.id);
  const [visibleMonth, setVisibleMonth] = useState(currentMonthValue);
  const [selectedDate, setSelectedDate] = useState<string | null>(null);
  const calendarMonth = useMemo(() => buildLedgerCalendar(visibleMonth, transactions), [visibleMonth, transactions]);
  const selectedDay = selectedDate ? calendarMonth.days.find((day) => day.date === selectedDate) ?? null : null;

  useEffect(() => {
    if (requestedLedger && ledger?.id !== requestedLedger.id) {
      void switchLedger(requestedLedger.id);
    }
  }, [ledger?.id, requestedLedger, switchLedger]);

  if (requestedLedger && ledger?.id !== requestedLedger.id) {
    return (
      <div className="page-stack">
        <Link className="inline-link" href="/accounts"><ArrowLeft size={14} /> Back to accounts</Link>
        <section className="card detail-card">
          <div className="empty-state"><h3>Loading ledger</h3><p>Rainflow is switching to {requestedLedger.name}.</p></div>
        </section>
      </div>
    );
  }

  if (!ledger || ledger.id !== params.id) {
    return (
      <div className="page-stack">
        <Link className="inline-link" href="/accounts"><ArrowLeft size={14} /> Back to accounts</Link>
        <section className="card detail-card">
          <div className="empty-state"><h3>Ledger not found</h3><p>Refresh the ledger or return to accounts.</p></div>
        </section>
      </div>
    );
  }

  return (
    <div className="page-stack">
      <div className="page-heading">
        <div>
          <span className="eyebrow">Ledger</span>
          <h1>{ledger.name}</h1>
          <p>{ledger.currencyCode} · {accounts.length} account{accounts.length === 1 ? "" : "s"} · {transactions.length} transaction{transactions.length === 1 ? "" : "s"}</p>
        </div>
        <Link className="secondary-button" href="/accounts"><ArrowLeft size={17} />Back</Link>
      </div>

      <section className="detail-layout">
        <article className="card detail-card">
          <span className="eyebrow">Ledger Balance</span>
          <strong className={total < 0 ? "detail-amount negative" : "detail-amount"}>{formatMoney(total)}</strong>
          <div className="detail-grid">
            <DetailItem label="Currency" value={ledger.currencyCode} />
            <DetailItem label="Accounts" value={`${accounts.length}`} />
            <DetailItem label="Transactions" value={`${transactions.length}`} />
            <DetailItem label="Scope" value={ledger.kind === "shared" ? "Shared" : "Personal"} />
          </div>
        </article>

        <article className="card detail-card ledger-calendar-card">
          <div className="card-header calendar-card-header">
            <div>
              <h2>Calendar</h2>
              <span>Daily cash flow in this ledger</span>
            </div>
            <div className="month-controls">
              <button className="icon-button" type="button" onClick={() => setVisibleMonth(addMonths(visibleMonth, -1))} aria-label="Previous month">
                <ChevronLeft size={16} />
              </button>
              <label className="month-field">
                <CalendarDays size={15} />
                <input
                  aria-label="Choose month"
                  type="month"
                  value={visibleMonth}
                  onInput={(event) => {
                    setVisibleMonth(event.currentTarget.value);
                    setSelectedDate(null);
                  }}
                  onChange={(event) => {
                    setVisibleMonth(event.currentTarget.value);
                    setSelectedDate(null);
                  }}
                />
              </label>
              <button className="icon-button" type="button" onClick={() => setVisibleMonth(addMonths(visibleMonth, 1))} aria-label="Next month">
                <ChevronRight size={16} />
              </button>
            </div>
          </div>

          <div className="ledger-calendar-title">{calendarMonth.label}</div>
          <div className="ledger-calendar-weekdays">
            {WEEKDAYS.map((weekday) => <span key={weekday}>{weekday}</span>)}
          </div>
          <div className="ledger-calendar-grid">
            {Array.from({ length: calendarMonth.leadingBlankDays }).map((_, index) => (
              <span className="ledger-calendar-empty" key={`blank-${index}`} />
            ))}
            {calendarMonth.days.map((day) => (
              <button
                type="button"
                className={`ledger-calendar-day${day.transactions.length > 0 ? " has-transactions" : ""}${selectedDate === day.date ? " selected" : ""}`}
                key={day.date}
                onClick={() => setSelectedDate(day.date)}
                disabled={day.transactions.length === 0}
              >
                <span>{day.dayNumber}</span>
                <strong className={day.netMinorUnits > 0 ? "positive" : day.netMinorUnits < 0 ? "negative" : ""}>
                  {day.transactions.length > 0 ? formatMoney(day.netMinorUnits, { sign: day.netMinorUnits > 0 }) : "—"}
                </strong>
                <small>{day.transactions.length > 0 ? `${day.transactions.length} tx` : "\u00A0"}</small>
              </button>
            ))}
          </div>

          {selectedDay ? (
            <div className="ledger-day-panel">
              <div className="card-header">
                <div>
                  <h2>{formatDate(selectedDay.date)}</h2>
                  <span>{selectedDay.transactions.length} transaction{selectedDay.transactions.length === 1 ? "" : "s"}</span>
                </div>
                <strong className={selectedDay.netMinorUnits < 0 ? "negative" : "positive"}>{formatMoney(selectedDay.netMinorUnits, { sign: selectedDay.netMinorUnits > 0 })}</strong>
              </div>
              <div className="transaction-table compact day-transactions">
                {selectedDay.transactions.map((transaction) => (
                  <Link className="transaction-line transaction-button" href={`/transactions/${transaction.id}`} key={transaction.id}>
                    <span>{formatDate(transaction.date)}</span>
                    <strong>{transaction.payee}</strong>
                    <span>{transaction.category}</span>
                    <span>{transaction.account}</span>
                    <b className={transaction.amountMinorUnits < 0 ? "negative" : transaction.kind === "transfer" ? "" : "positive"}>{formatMoney(transaction.amountMinorUnits, { sign: transaction.amountMinorUnits > 0 })}</b>
                  </Link>
                ))}
              </div>
            </div>
          ) : (
            <p className="calendar-hint">Choose a date with transactions to see the daily detail.</p>
          )}
        </article>

        <article className="card detail-card">
          <div className="card-header">
            <div><h2>Ledger Transactions</h2><span>All active transactions in this ledger</span></div>
            <strong>{transactions.length}</strong>
          </div>
          <div className="transaction-table compact">
            <div className="transaction-head"><span>Date</span><span>Payee</span><span>Category</span><span>Account</span><span>Amount</span></div>
            {transactions.map((transaction) => (
              <Link className="transaction-line transaction-button" href={`/transactions/${transaction.id}`} key={transaction.id}>
                <span>{formatDate(transaction.date)}</span>
                <strong>{transaction.payee}</strong>
                <span>{transaction.category}</span>
                <span>{transaction.account}</span>
                <b className={transaction.amountMinorUnits < 0 ? "negative" : transaction.kind === "transfer" ? "" : "positive"}>{formatMoney(transaction.amountMinorUnits, { sign: transaction.amountMinorUnits > 0 })}</b>
              </Link>
            ))}
            {transactions.length === 0 ? <div className="empty-state compact-empty"><h3>No transactions</h3><p>Transactions posted to this ledger will appear here.</p></div> : null}
          </div>
        </article>
      </section>
    </div>
  );
}

function DetailItem({ label, value }: { label: string; value: string }) {
  return <div><span>{label}</span><strong>{value}</strong></div>;
}

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

interface LedgerCalendarDay {
  date: string;
  dayNumber: number;
  transactions: Transaction[];
  incomeMinorUnits: number;
  expenseMinorUnits: number;
  netMinorUnits: number;
}

function currentMonthValue() {
  const today = new Date();
  return `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}`;
}

function addMonths(value: string, delta: number) {
  const [year, month] = value.split("-").map(Number);
  const date = new Date(Date.UTC(year, month - 1 + delta, 1));
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, "0")}`;
}

function buildLedgerCalendar(value: string, transactions: Transaction[]) {
  const [year, month] = value.split("-").map(Number);
  const monthIndex = month - 1;
  const firstDate = new Date(Date.UTC(year, monthIndex, 1));
  const totalDays = new Date(Date.UTC(year, monthIndex + 1, 0)).getUTCDate();
  const leadingBlankDays = firstDate.getUTCDay();
  const label = new Intl.DateTimeFormat("en-US", {
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  }).format(firstDate);

  const days: LedgerCalendarDay[] = Array.from({ length: totalDays }, (_, index) => {
    const dayNumber = index + 1;
    const date = `${year}-${String(month).padStart(2, "0")}-${String(dayNumber).padStart(2, "0")}`;
    const dayTransactions = transactions.filter((transaction) => transaction.date === date);
    const incomeMinorUnits = dayTransactions
      .filter((transaction) => transaction.kind === "income")
      .reduce((sum, transaction) => sum + Math.abs(transaction.amountMinorUnits), 0);
    const expenseMinorUnits = dayTransactions
      .filter((transaction) => transaction.kind === "expense")
      .reduce((sum, transaction) => sum + Math.abs(transaction.amountMinorUnits), 0);

    return {
      date,
      dayNumber,
      transactions: dayTransactions,
      incomeMinorUnits,
      expenseMinorUnits,
      netMinorUnits: incomeMinorUnits - expenseMinorUnits,
    };
  });

  return { label, leadingBlankDays, days };
}
