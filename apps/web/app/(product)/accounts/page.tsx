"use client";

import Link from "next/link";
import { createClient } from "@supabase/supabase-js";
import { BookOpen, Plus } from "lucide-react";
import { FormEvent, useState } from "react";
import { formatMoney } from "@/lib/format";
import { useLedger } from "@/components/LedgerProvider";

const supabaseURL = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim() ?? "";
const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim() ?? "";
const supabase = supabaseURL.startsWith("https://") && supabaseKey.length > 40
  ? createClient(supabaseURL, supabaseKey)
  : null;

export default function AccountsPage() {
  const { accounts, ledger, ledgers, transactions, refresh } = useLedger();
  const [addAccountOpen, setAddAccountOpen] = useState(false);
  const financialAccounts = accounts.filter((account) => account.type === "asset" || account.type === "liability");
  const categories = accounts.filter((account) => account.type === "income" || account.type === "expense");
  const canManageAccounts = Boolean(ledger && ledger.role !== "member");
  const netWorth = financialAccounts.reduce((sum, account) => sum + account.balanceMinorUnits, 0);

  async function createFinancialAccount(input: { name: string; type: "asset" | "liability" }) {
    if (!supabase) throw new Error("Supabase is not configured.");
    if (!ledger) throw new Error("Choose a ledger before adding an account.");
    if (!canManageAccounts) throw new Error("Only ledger owners and admins can add accounts.");

    const { error } = await supabase.rpc("create_financial_account", {
      p_ledger_id: ledger.id,
      p_name: input.name.trim(),
      p_type: input.type,
    });
    if (error) throw new Error(friendlyAccountError(error.message));
    await refresh();
  }

  return (
    <div className="page-stack">
      <div className="page-heading">
        <div>
          <span className="eyebrow">Portfolio</span>
          <h1>Accounts</h1>
          <p>Bank, cash, card, and loan accounts for the current ledger.</p>
        </div>
        {canManageAccounts ? (
          <button className="primary-button" type="button" onClick={() => setAddAccountOpen(true)}>
            <Plus size={18} />Add account
          </button>
        ) : null}
      </div>

      <section className="account-hero card">
        <div>
          <span className="eyebrow">Net worth</span>
          <strong className={netWorth < 0 ? "negative" : undefined}>{formatMoney(netWorth)}</strong>
          <span><small>Assets plus liabilities in the current ledger. Category and system accounts are excluded.</small></span>
        </div>
      </section>

      <section className="card accounts-summary-card">
        <div className="card-header">
          <div><h2>Ledger structure</h2><span>{ledger?.name ?? "Current ledger"}</span></div>
          <strong>{ledger?.currencyCode ?? "USD"}</strong>
        </div>
        <div className="metric-row"><span>Financial accounts</span><strong>{financialAccounts.length}</strong></div>
        <div className="metric-row"><span>Categories</span><strong>{categories.length}</strong></div>
        <div className="metric-row"><span>Transactions</span><strong>{transactions.length}</strong></div>
        <p className="form-note">Income and expense categories, plus the hidden Opening Balances account, are bookkeeping structure rather than real-world accounts.</p>
      </section>

      <section className="card ledger-card">
        <div className="card-header">
          <div><h2>Ledgers</h2><span>{ledgers.length} accessible ledger{ledgers.length === 1 ? "" : "s"}</span></div>
          <strong>{ledger?.currencyCode ?? "USD"}</strong>
        </div>
        {ledgers.length > 0 ? ledgers.map((item) => (
          <Link className="account-row" href={`/ledgers/${item.id}`} key={item.id}>
            <span className="account-avatar"><BookOpen size={16} /></span>
            <span><strong>{item.name}</strong><small>{item.kind === "shared" ? "Shared" : "Personal"} · {item.role}</small></span>
            <span className="account-balance">{item.id === ledger?.id ? formatMoney(netWorth) : item.currencyCode}<small>{item.id === ledger?.id ? `${transactions.length} transactions` : "Open ledger"}</small></span>
          </Link>
        )) : (
          <div className="empty-state compact-empty"><h3>No ledger yet</h3><p>Create a ledger to view its details.</p></div>
        )}
      </section>

      {financialAccounts.length === 0 ? (
        <section className="card empty-state">
          <div>
            <h3>No financial accounts yet</h3>
            <p>{canManageAccounts
              ? "Add the bank account, cash wallet, credit card, or loan you actually use. Rainflow will not invent placeholder accounts."
              : "This ledger does not have a financial account yet. An owner or admin can add one."}</p>
            {canManageAccounts ? (
              <button className="primary-button" type="button" onClick={() => setAddAccountOpen(true)}>
                <Plus size={18} />Add your first account
              </button>
            ) : null}
          </div>
        </section>
      ) : (
        <section className="account-grid">
          {(["asset", "liability"] as const).map((type) => {
            const groupAccounts = financialAccounts.filter((account) => account.type === type);
            if (groupAccounts.length === 0) return null;
            const groupTotal = groupAccounts.reduce((sum, account) => sum + account.balanceMinorUnits, 0);
            const group = type === "asset" ? "Assets" : "Liabilities";
            return <article className="card account-group" key={type}>
              <div className="card-header"><div><h2>{group}</h2><span>{groupAccounts.length} account{groupAccounts.length === 1 ? "" : "s"}</span></div><strong className={groupTotal < 0 ? "negative" : ""}>{formatMoney(groupTotal)}</strong></div>
              <div className="account-list">
                {groupAccounts.map((account) => <Link className="account-row" href={`/accounts/${account.id}`} key={account.id}>
                  <span className="account-avatar">{account.name.slice(0, 2).toUpperCase()}</span>
                  <span><strong>{account.name}</strong><small>{account.subtype}</small></span>
                  <span className={account.balanceMinorUnits < 0 ? "negative account-balance" : "account-balance"}>{formatMoney(account.balanceMinorUnits)}<small>Open account</small></span>
                </Link>)}
              </div>
            </article>;
          })}
        </section>
      )}

      {canManageAccounts && financialAccounts.length > 0 ? (
        <button className="add-account-dashed" type="button" onClick={() => setAddAccountOpen(true)}><Plus size={18} />Add an account</button>
      ) : null}

      <AddAccountDialog
        open={addAccountOpen}
        onClose={() => setAddAccountOpen(false)}
        onCreate={async (input) => {
          await createFinancialAccount(input);
          setAddAccountOpen(false);
        }}
      />
    </div>
  );
}

function AddAccountDialog({
  open,
  onClose,
  onCreate,
}: {
  open: boolean;
  onClose: () => void;
  onCreate: (input: { name: string; type: "asset" | "liability" }) => Promise<void>;
}) {
  const [name, setName] = useState("");
  const [type, setType] = useState<"asset" | "liability">("asset");
  const [isSaving, setIsSaving] = useState(false);
  const [localError, setLocalError] = useState<string | null>(null);

  if (!open) return null;

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!name.trim()) return;
    setIsSaving(true);
    setLocalError(null);
    try {
      await onCreate({ name: name.trim(), type });
      setName("");
      setType("asset");
    } catch (error) {
      setLocalError(error instanceof Error ? error.message : "Could not add account.");
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <div className="dialog-backdrop" role="presentation" onMouseDown={onClose}>
      <section className="dialog" role="dialog" aria-modal="true" aria-labelledby="add-account-title" onMouseDown={(event) => event.stopPropagation()}>
        <div className="dialog-header">
          <div><span className="eyebrow">Financial account</span><h2 id="add-account-title">Add account</h2></div>
          <button className="icon-button" type="button" onClick={onClose} aria-label="Close">×</button>
        </div>
        <form className="transaction-form" onSubmit={submit}>
          <div className="form-grid">
            <label className="field field-wide">
              <span>Account name</span>
              <input value={name} onChange={(event) => setName(event.target.value)} placeholder={type === "asset" ? "Checking" : "Credit Card"} autoFocus maxLength={120} />
            </label>
            <label className="field field-wide">
              <span>Account type</span>
              <select value={type} onChange={(event) => setType(event.target.value as "asset" | "liability")}>
                <option value="asset">Asset — bank, cash, investment</option>
                <option value="liability">Liability — credit card, loan</option>
              </select>
            </label>
          </div>
          <p className="form-note">Categories such as Groceries or Salary are managed separately and cannot be created here.</p>
          {localError ? <p className="auth-error">{localError}</p> : null}
          <div className="dialog-actions">
            <button className="secondary-button" type="button" onClick={onClose}>Cancel</button>
            <button className="primary-button" type="submit" disabled={isSaving || !name.trim()}>{isSaving ? "Adding..." : "Add account"}</button>
          </div>
        </form>
      </section>
    </div>
  );
}

function friendlyAccountError(message: string) {
  const normalized = message.toLowerCase();
  if (normalized.includes("account_name_already_exists") || normalized.includes("duplicate")) return "An active account with this name already exists.";
  if (normalized.includes("ledger_admin_required") || normalized.includes("permission")) return "Only ledger owners and admins can add accounts.";
  if (normalized.includes("could not find the function") || normalized.includes("schema cache")) return "The account-creation database migration has not been deployed yet.";
  return message;
}
