"use client";

import Link from "next/link";
import { BookOpen, ChevronRight, Plus, Users } from "lucide-react";
import { FormEvent, useMemo, useState } from "react";
import { useLedger } from "@/components/LedgerProvider";
import { formatMoney } from "@/lib/format";

export default function LedgersPage() {
  const { ledger, ledgers, accounts, transactions, createLedger, isWorking } = useLedger();
  const [createOpen, setCreateOpen] = useState(false);
  const total = accounts.reduce((sum, account) => sum + account.balanceMinorUnits, 0);
  const activeLedgerTransactionCount = transactions.length;
  const ledgerSummaries = useMemo(() => {
    return ledgers.map((item) => ({
      ledger: item,
      isActive: item.id === ledger?.id,
      balance: item.id === ledger?.id ? total : null,
      transactions: item.id === ledger?.id ? activeLedgerTransactionCount : null,
    }));
  }, [activeLedgerTransactionCount, ledger?.id, ledgers, total]);

  return (
    <div className="page-stack">
      <div className="page-heading">
        <div>
          <span className="eyebrow">Ledgers</span>
          <h1>Your ledgers</h1>
          <p>Open a ledger to see its summary, calendar, and transactions.</p>
        </div>
        <button className="primary-button" type="button" onClick={() => setCreateOpen(true)}>
          <Plus size={17} />
          New ledger
        </button>
      </div>

      {ledger ? (
        <Link className="card account-hero ledger-hero-link" href={`/ledgers/${ledger.id}`}>
          <div>
            <span className="eyebrow">Current Ledger</span>
            <h2>{ledger.name}</h2>
            <small>{ledger.kind === "shared" ? "Shared ledger" : "Personal ledger"} · {ledger.currencyCode}</small>
          </div>
          <div>
            <strong className={total < 0 ? "negative" : ""}>{formatMoney(total)}</strong>
            <p>{accounts.length} account{accounts.length === 1 ? "" : "s"} · {transactions.length} transaction{transactions.length === 1 ? "" : "s"}</p>
          </div>
        </Link>
      ) : null}

      <section className="account-grid">
        {ledgerSummaries.map(({ ledger: item, isActive, balance, transactions }) => (
          <Link className="card ledger-card ledger-list-card" href={`/ledgers/${item.id}`} key={item.id}>
            <div className="card-header">
              <div>
                <h2>{item.name}</h2>
                <span>{item.currencyCode} · {item.kind === "shared" ? "Shared" : "Personal"}</span>
              </div>
              <span className="account-avatar">{item.kind === "shared" ? <Users size={16} /> : <BookOpen size={16} />}</span>
            </div>
            <div className="ledger-list-meta">
              {isActive ? (
                <>
                  <strong className={balance !== null && balance < 0 ? "negative" : undefined}>{formatMoney(balance ?? 0)}</strong>
                  <small>{transactions ?? 0} transaction{transactions === 1 ? "" : "s"}</small>
                </>
              ) : (
                <>
                  <strong>Open ledger</strong>
                  <small>Switch to view balance and activity</small>
                </>
              )}
              <ChevronRight size={18} aria-hidden="true" />
            </div>
          </Link>
        ))}
      </section>

      <button className="add-account-dashed" type="button" onClick={() => setCreateOpen(true)}>
        <Plus size={18} />
        Create personal or shared ledger
      </button>

      <CreateLedgerSheet
        open={createOpen}
        isWorking={isWorking}
        onClose={() => setCreateOpen(false)}
        onCreate={async (input) => {
          await createLedger(input);
          setCreateOpen(false);
        }}
      />
    </div>
  );
}

function CreateLedgerSheet({
  open,
  isWorking,
  onClose,
  onCreate
}: {
  open: boolean;
  isWorking: boolean;
  onClose: () => void;
  onCreate: (input: { name: string; currencyCode: string; kind: "personal" | "shared" }) => Promise<void>;
}) {
  const [name, setName] = useState("Personal");
  const [currencyCode, setCurrencyCode] = useState("USD");
  const [kind, setKind] = useState<"personal" | "shared">("personal");
  const [localError, setLocalError] = useState<string | null>(null);

  if (!open) return null;

  async function submit(event: FormEvent) {
    event.preventDefault();
    setLocalError(null);
    try {
      await onCreate({ name: name.trim() || (kind === "shared" ? "Shared Ledger" : "Personal"), currencyCode, kind });
    } catch (error) {
      setLocalError(error instanceof Error ? error.message : "Could not create ledger.");
    }
  }

  return (
    <div className="dialog-backdrop" role="presentation" onMouseDown={onClose}>
      <section className="dialog" role="dialog" aria-modal="true" aria-labelledby="phone-create-ledger-title" onMouseDown={(event) => event.stopPropagation()}>
        <div className="dialog-header">
          <div><span className="eyebrow">Ledger</span><h2 id="phone-create-ledger-title">Create ledger</h2></div>
          <button className="icon-button" type="button" onClick={onClose} aria-label="Close">×</button>
        </div>
        <form className="transaction-form" onSubmit={submit}>
          <div className="segmented-control" aria-label="Ledger type">
            <button type="button" className={kind === "personal" ? "active" : ""} onClick={() => setKind("personal")}>Personal</button>
            <button type="button" className={kind === "shared" ? "active" : ""} onClick={() => setKind("shared")}>Shared</button>
          </div>
          <div className="form-grid">
            <label className="field field-wide">
              <span>Ledger name</span>
              <input value={name} onChange={(event) => setName(event.target.value)} placeholder={kind === "shared" ? "Household" : "Personal"} autoFocus />
            </label>
            <label className="field">
              <span>Currency</span>
              <select value={currencyCode} onChange={(event) => setCurrencyCode(event.target.value)}>
                {["USD", "CAD", "EUR", "GBP", "JPY", "AUD"].map((item) => <option value={item} key={item}>{item}</option>)}
              </select>
            </label>
          </div>
          <p className="form-note">Shared ledgers can invite other Rainflow users after the ledger is created.</p>
          {localError ? <p className="auth-error">{localError}</p> : null}
          <div className="dialog-actions">
            <button className="secondary-button" type="button" onClick={onClose}>Cancel</button>
            <button className="primary-button" type="submit" disabled={isWorking}>{isWorking ? "Creating..." : "Create ledger"}</button>
          </div>
        </form>
      </section>
    </div>
  );
}
