"use client";

import Link from "next/link";
import { ArrowLeft, Eye, FileImage, Pencil, Trash2, X } from "lucide-react";
import { useParams, useRouter } from "next/navigation";
import { ChangeEvent, FormEvent, useMemo, useState } from "react";
import { useLedger } from "@/components/LedgerProvider";
import { formatDate, formatMoney } from "@/lib/format";
import type { Account, Transaction, TransactionKind } from "@/lib/types";

export default function TransactionDetailPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const { ledger, accounts, transactions, getReceiptViewURL, updateTransaction, deleteTransaction, isWorking, errorMessage } = useLedger();
  const transaction = transactions.find((item) => item.id === params.id);
  const [receiptPreview, setReceiptPreview] = useState<{ url: string; name: string } | null>(null);
  const [receiptError, setReceiptError] = useState<string | null>(null);
  const [editOpen, setEditOpen] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);

  if (!transaction) {
    return (
      <div className="page-stack">
        <Link className="inline-link" href={ledger ? `/ledgers/${ledger.id}` : "/accounts"}><ArrowLeft size={14} /> Back to ledger</Link>
        <section className="card detail-card">
          <div className="empty-state"><h3>Transaction not found</h3><p>Refresh the ledger or return to the transaction list.</p></div>
        </section>
      </div>
    );
  }

  return (
    <div className="page-stack">
      <div className="page-heading">
        <div>
          <span className="eyebrow">Transaction</span>
          <h1>{transaction.payee}</h1>
          <p>{formatDate(transaction.date)} · Revision {transaction.revision}</p>
        </div>
        <div className="heading-actions">
          <button className="secondary-button" type="button" onClick={() => setEditOpen(true)}>
            <Pencil size={17} />Edit
          </button>
          <Link className="secondary-button" href={ledger ? `/ledgers/${ledger.id}` : "/accounts"}><ArrowLeft size={17} />Back</Link>
        </div>
      </div>

      <section className="detail-layout">
        <article className="card detail-card">
          <span className="eyebrow">Amount</span>
          <strong className={transaction.amountMinorUnits < 0 ? "detail-amount negative" : "detail-amount positive"}>
            {formatMoney(transaction.amountMinorUnits, { sign: transaction.amountMinorUnits > 0 })}
          </strong>
          <div className="detail-grid">
            <DetailItem label="Type" value={transaction.kind} />
            <DetailItem label="Date" value={formatDate(transaction.date)} />
            <DetailItem label="Account" value={transaction.account} />
            <DetailItem label="Category" value={transaction.category} />
            <DetailItem label="Revision" value={`${transaction.revision}`} />
            <DetailItem label="Receipt" value={transaction.receiptName ?? "None"} />
          </div>
          {transaction.receiptAttachmentId ? (
            <button className="secondary-button" type="button" onClick={async () => {
              try {
                setReceiptError(null);
                const url = await getReceiptViewURL(transaction.receiptAttachmentId as string);
                setReceiptPreview({ url, name: transaction.receiptName ?? "Receipt" });
              } catch (error) {
                setReceiptError(error instanceof Error ? error.message : "Could not open receipt.");
              }
            }}>
              <Eye size={17} />View receipt
            </button>
          ) : null}
          {receiptError ? <p className="auth-error">{receiptError}</p> : null}
          {deleteError ? <p className="auth-error">{deleteError}</p> : null}
          {errorMessage ? <p className="auth-error">{errorMessage}</p> : null}
          <div className="detail-actions">
            <button className="primary-button" type="button" onClick={() => setEditOpen(true)}>
              <Pencil size={17} />Edit transaction
            </button>
            <button className="secondary-button danger-button" type="button" disabled={isWorking} onClick={async () => {
              const confirmed = window.confirm("Remove this transaction? It will stop affecting balances, but the record remains recoverable.");
              if (!confirmed) return;
              try {
                setDeleteError(null);
                await deleteTransaction(transaction);
                router.push(ledger ? `/ledgers/${ledger.id}` : "/dashboard");
              } catch (error) {
                setDeleteError(error instanceof Error ? error.message : "Could not remove transaction.");
              }
            }}>
              <Trash2 size={17} />Remove
            </button>
          </div>
        </article>
      </section>

      {editOpen ? (
        <EditTransactionDialog
          transaction={transaction}
          accounts={accounts}
          isWorking={isWorking}
          onClose={() => setEditOpen(false)}
          onSave={async (input) => {
            await updateTransaction(input);
            setEditOpen(false);
          }}
        />
      ) : null}

      {receiptPreview ? (
        <ReceiptPreviewDialog preview={receiptPreview} onClose={() => setReceiptPreview(null)} />
      ) : null}
    </div>
  );
}

function DetailItem({ label, value }: { label: string; value: string }) {
  return <div><span>{label}</span><strong>{value}</strong></div>;
}

function EditTransactionDialog({
  transaction,
  accounts,
  isWorking,
  onClose,
  onSave
}: {
  transaction: Transaction;
  accounts: Account[];
  isWorking: boolean;
  onClose: () => void;
  onSave: (input: {
    id: string;
    expectedRevision: number;
    date: string;
    payee: string;
    accountId: string;
    categoryId: string;
    amountMinorUnits: number;
    kind: TransactionKind;
    note?: string;
    receiptFile?: File | null;
  }) => Promise<void>;
}) {
  const [kind, setKind] = useState<TransactionKind>(transaction.kind);
  const [amount, setAmount] = useState(() => (Math.abs(transaction.amountMinorUnits) / 100).toFixed(2));
  const [date, setDate] = useState(transaction.date);
  const [payee, setPayee] = useState(transaction.payee);
  const [accountID, setAccountID] = useState(transaction.accountId);
  const [categoryID, setCategoryID] = useState(transaction.categoryId);
  const [note, setNote] = useState("");
  const [receiptFile, setReceiptFile] = useState<File | null>(null);
  const [localError, setLocalError] = useState<string | null>(null);

  const sourceAccounts = useMemo(() => accounts.filter((item) => item.type === "asset" || item.type === "liability"), [accounts]);
  const destinationAccounts = useMemo(() => {
    if (kind === "expense") return accounts.filter((item) => item.type === "expense");
    if (kind === "income") return accounts.filter((item) => item.type === "income");
    return sourceAccounts.filter((item) => item.id !== accountID);
  }, [accountID, accounts, kind, sourceAccounts]);

  function chooseReceipt(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0] ?? null;
    setReceiptFile(file);
  }

  async function submit(event: FormEvent) {
    event.preventDefault();
    const amountMinorUnits = Math.round(Number(amount) * 100);
    if (!Number.isFinite(amountMinorUnits) || amountMinorUnits <= 0) {
      setLocalError("Enter a valid amount.");
      return;
    }
    if (!accountID || !categoryID || accountID === categoryID) {
      setLocalError("Choose two different accounts.");
      return;
    }
    setLocalError(null);
    try {
      await onSave({
        id: transaction.id,
        expectedRevision: transaction.revision,
        date,
        payee: payee.trim() || "Transaction",
        accountId: accountID,
        categoryId: categoryID,
        amountMinorUnits,
        kind,
        note: note.trim(),
        receiptFile
      });
    } catch (error) {
      setLocalError(error instanceof Error ? error.message : "Could not save changes.");
    }
  }

  return (
    <div className="dialog-backdrop" role="presentation" onMouseDown={onClose}>
      <section className="dialog" role="dialog" aria-modal="true" aria-labelledby="edit-transaction-title" onMouseDown={(event) => event.stopPropagation()}>
        <div className="dialog-header">
          <div>
            <span className="eyebrow">Transaction</span>
            <h2 id="edit-transaction-title">Edit transaction</h2>
          </div>
          <button className="icon-button" type="button" onClick={onClose} aria-label="Close">
            <X size={20} />
          </button>
        </div>

        <form className="transaction-form" onSubmit={submit}>
          <div className="segmented-control" aria-label="Transaction type">
            {(["expense", "income", "transfer"] as TransactionKind[]).map((item) => (
              <button key={item} type="button" className={kind === item ? "active" : ""} onClick={() => {
                setKind(item);
                setCategoryID("");
              }}>
                {item[0].toUpperCase() + item.slice(1)}
              </button>
            ))}
          </div>

          <div className="form-grid">
            <label className="field field-amount">
              <span>Amount</span>
              <div className="money-input"><span>$</span><input required inputMode="decimal" value={amount} onChange={(event) => setAmount(event.target.value)} placeholder="0.00" autoFocus /></div>
            </label>
            <label className="field">
              <span>Date</span>
              <input type="date" value={date} onChange={(event) => setDate(event.target.value)} />
            </label>
            <label className="field">
              <span>{kind === "income" ? "Deposit account" : kind === "transfer" ? "From account" : "Payment account"}</span>
              <select value={accountID} onChange={(event) => {
                setAccountID(event.target.value);
                if (event.target.value === categoryID) setCategoryID("");
              }}>
                {sourceAccounts.map((item) => <option value={item.id} key={item.id}>{item.name}</option>)}
              </select>
            </label>
            <label className="field">
              <span>{kind === "transfer" ? "To account" : kind === "income" ? "Income category" : "Category"}</span>
              <select value={categoryID} onChange={(event) => setCategoryID(event.target.value)}>
                <option value="" disabled>Choose</option>
                {destinationAccounts.map((item) => <option value={item.id} key={item.id}>{item.name}</option>)}
              </select>
            </label>
            <label className="field field-wide">
              <span>Payee or description</span>
              <input value={payee} onChange={(event) => setPayee(event.target.value)} placeholder="Optional" />
            </label>
            <label className="field field-wide">
              <span>Note</span>
              <input value={note} onChange={(event) => setNote(event.target.value)} placeholder="Optional" />
            </label>
            <label className="field field-wide receipt-file-field">
              <span>Receipt</span>
              <input type="file" accept="image/*" onChange={chooseReceipt} />
              <small>{receiptFile ? receiptFile.name : transaction.receiptName ? `Current: ${transaction.receiptName}` : "No receipt attached"}</small>
            </label>
          </div>

          <p className="form-note"><FileImage size={14} /> Selecting a new receipt attaches it to this transaction after the edit is saved.</p>
          {localError ? <p className="auth-error">{localError}</p> : null}
          <div className="dialog-actions">
            <button className="secondary-button" type="button" onClick={onClose}>Cancel</button>
            <button className="primary-button" type="submit" disabled={isWorking || !accountID || !categoryID || accountID === categoryID}>{isWorking ? "Saving..." : "Save changes"}</button>
          </div>
        </form>
      </section>
    </div>
  );
}

function ReceiptPreviewDialog({ preview, onClose }: { preview: { url: string; name: string }; onClose: () => void }) {
  return (
    <div className="dialog-backdrop" role="presentation" onMouseDown={onClose}>
      <section className="dialog receipt-dialog" role="dialog" aria-modal="true" aria-labelledby="receipt-preview-title" onMouseDown={(event) => event.stopPropagation()}>
        <div className="dialog-header">
          <div>
            <span className="eyebrow">Private receipt</span>
            <h2 id="receipt-preview-title">{preview.name}</h2>
          </div>
          <button className="icon-button" type="button" onClick={onClose} aria-label="Close">
            <X size={20} />
          </button>
        </div>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img className="receipt-full-preview" src={preview.url} alt={preview.name} />
        <p className="form-note">This temporary viewing link expires automatically.</p>
      </section>
    </div>
  );
}
