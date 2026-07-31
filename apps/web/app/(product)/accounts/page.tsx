"use client";

import Link from "next/link";
import { BookOpen, Plus } from "lucide-react";
import { formatMoney } from "@/lib/format";
import { useLedger } from "@/components/LedgerProvider";

export default function AccountsPage() {
  const { accounts, ledger, ledgers, transactions } = useLedger();
  const groups = Array.from(new Set(accounts.map((account) => account.group)));
  const netWorth = accounts
    .filter((account) => account.type === "asset" || account.type === "liability")
    .reduce((sum, account) => sum + account.balanceMinorUnits, 0);

  return (
    <div className="page-stack">
      <div className="page-heading"><div><span className="eyebrow">Portfolio</span><h1>Accounts</h1><p>Balances derived from the posting journal.</p></div><button className="primary-button" type="button"><Plus size={18} />Add account</button></div>

      <section className="account-hero card">
        <div>
          <span className="eyebrow">Net worth</span>
          <strong className={netWorth < 0 ? "negative" : undefined}>{formatMoney(netWorth)}</strong>
          <span><small>Assets plus liabilities in the current ledger. Historical change will appear after trend data is implemented.</small></span>
        </div>
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

      <section className="account-grid">
        {groups.map((group) => {
          const groupAccounts = accounts.filter((account) => account.group === group);
          const groupTotal = groupAccounts.reduce((sum, account) => sum + account.balanceMinorUnits, 0);
          return <article className="card account-group" key={group}>
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

      <button className="add-account-dashed" type="button"><Plus size={18} />Add an account</button>
    </div>
  );
}
