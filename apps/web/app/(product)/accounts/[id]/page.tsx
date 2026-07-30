"use client";

import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { useParams } from "next/navigation";
import { useMemo } from "react";
import { useLedger } from "@/components/LedgerProvider";
import { formatDate, formatMoney } from "@/lib/format";

export default function AccountDetailPage() {
  const params = useParams<{ id: string }>();
  const { accounts, transactions } = useLedger();
  const account = accounts.find((item) => item.id === params.id);
  const accountTransactions = useMemo(
    () => transactions.filter((transaction) => transaction.accountId === params.id || transaction.categoryId === params.id),
    [params.id, transactions]
  );

  if (!account) {
    return (
      <div className="page-stack">
        <Link className="inline-link" href="/accounts"><ArrowLeft size={14} /> Back to accounts</Link>
        <section className="card detail-card">
          <div className="empty-state"><h3>Account not found</h3><p>Refresh the ledger or return to the accounts list.</p></div>
        </section>
      </div>
    );
  }

  return (
    <div className="page-stack">
      <div className="page-heading">
        <div>
          <span className="eyebrow">{account.group}</span>
          <h1>{account.name}</h1>
          <p>{account.subtype} · {accountTransactions.length} transaction{accountTransactions.length === 1 ? "" : "s"}</p>
        </div>
        <Link className="secondary-button" href="/accounts"><ArrowLeft size={17} />Back</Link>
      </div>

      <section className="detail-layout">
        <article className="card detail-card">
          <span className="eyebrow">Balance</span>
          <strong className={account.balanceMinorUnits < 0 ? "detail-amount negative" : "detail-amount"}>
            {formatMoney(account.balanceMinorUnits)}
          </strong>
          <div className="detail-grid">
            <DetailItem label="Group" value={account.group} />
            <DetailItem label="Type" value={account.type} />
            <DetailItem label="Subtype" value={account.subtype} />
            <DetailItem label="Transactions" value={`${accountTransactions.length}`} />
          </div>
        </article>

        <article className="card detail-card">
          <div className="card-header">
            <div><h2>Account Transactions</h2><span>Activity involving this account</span></div>
            <strong>{accountTransactions.length}</strong>
          </div>
          <div className="transaction-table compact">
            <div className="transaction-head"><span>Date</span><span>Payee</span><span>Category</span><span>Account</span><span>Amount</span></div>
            {accountTransactions.map((transaction) => (
              <Link className="transaction-line transaction-button" href={`/transactions/${transaction.id}`} key={transaction.id}>
                <span>{formatDate(transaction.date)}</span>
                <strong>{transaction.payee}</strong>
                <span>{transaction.category}</span>
                <span>{transaction.account}</span>
                <b className={transaction.amountMinorUnits < 0 ? "negative" : transaction.kind === "transfer" ? "" : "positive"}>{formatMoney(transaction.amountMinorUnits, { sign: transaction.amountMinorUnits > 0 })}</b>
              </Link>
            ))}
            {accountTransactions.length === 0 ? <div className="empty-state compact-empty"><h3>No transactions</h3><p>Transactions involving this account will appear here.</p></div> : null}
          </div>
        </article>
      </section>
    </div>
  );
}

function DetailItem({ label, value }: { label: string; value: string }) {
  return <div><span>{label}</span><strong>{value}</strong></div>;
}
