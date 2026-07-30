"use client";

import Link from "next/link";
import { ArrowLeft, Eye, X } from "lucide-react";
import { useParams } from "next/navigation";
import { useState } from "react";
import { useLedger } from "@/components/LedgerProvider";
import { formatDate, formatMoney } from "@/lib/format";

export default function TransactionDetailPage() {
  const params = useParams<{ id: string }>();
  const { ledger, transactions, getReceiptViewURL } = useLedger();
  const transaction = transactions.find((item) => item.id === params.id);
  const [receiptPreview, setReceiptPreview] = useState<{ url: string; name: string } | null>(null);
  const [receiptError, setReceiptError] = useState<string | null>(null);

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
        <Link className="secondary-button" href={ledger ? `/ledgers/${ledger.id}` : "/accounts"}><ArrowLeft size={17} />Back</Link>
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
        </article>
      </section>

      {receiptPreview ? (
        <ReceiptPreviewDialog preview={receiptPreview} onClose={() => setReceiptPreview(null)} />
      ) : null}
    </div>
  );
}

function DetailItem({ label, value }: { label: string; value: string }) {
  return <div><span>{label}</span><strong>{value}</strong></div>;
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
