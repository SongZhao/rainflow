"use client";

import { Eye, FileImage, ShieldCheck, X } from "lucide-react";
import { useState } from "react";
import { useLedger } from "@/components/LedgerProvider";
import { formatDate } from "@/lib/format";

export default function AttachmentsPage() {
  const { attachments, transactions, getReceiptViewURL } = useLedger();
  const activeAttachments = attachments.filter((item) => item.status === "active");
  const transactionByID = new Map(transactions.map((item) => [item.id, item]));
  const [receiptPreview, setReceiptPreview] = useState<{ url: string; name: string } | null>(null);
  const [receiptError, setReceiptError] = useState<string | null>(null);

  async function openReceipt(attachmentID: string, name: string) {
    try {
      setReceiptError(null);
      const url = await getReceiptViewURL(attachmentID);
      setReceiptPreview({ url, name });
    } catch (error) {
      setReceiptError(error instanceof Error ? error.message : "Could not open receipt.");
    }
  }

  return (
    <div className="page-stack">
      <div className="page-heading"><div><span className="eyebrow">Managed files</span><h1>Attachments</h1><p>Receipts are copied into private application storage and included in backups.</p></div></div>

      <section className="card integrity-banner"><ShieldCheck size={24} /><div><h2>Attachment integrity</h2><p>Active files are verified against stored checksums. Missing authoritative objects create one in-app incident and one deduplicated email.</p></div><strong>Healthy</strong></section>

      <section className="attachment-grid">
        {activeAttachments.map((attachment) => {
          const transaction = attachment.transactionId ? transactionByID.get(attachment.transactionId) : null;
          return <article className="card attachment-card" key={attachment.id}>
          <div className="attachment-thumbnail"><FileImage size={32} /></div>
          <div>
            <strong>{attachment.originalFileName}</strong>
            <span>{transaction ? `${transaction.payee} · ${formatDate(transaction.date)}` : "Unlinked receipt"}</span>
            <small>Private · {(attachment.byteSize / 1024).toFixed(0)} KB</small>
            <button className="inline-link" type="button" onClick={() => void openReceipt(attachment.id, attachment.originalFileName)}>
              <Eye size={14} /> View receipt
            </button>
          </div>
        </article>;
        })}
        {activeAttachments.length === 0 ? <div className="card empty-state attachment-empty"><FileImage size={36} /><h2>No receipt files yet</h2><p>Use Add transaction and choose a photo to store the first receipt.</p></div> : null}
      </section>
      {receiptPreview ? <ReceiptPreviewDialog preview={receiptPreview} onClose={() => setReceiptPreview(null)} /> : null}
      {receiptError ? <p className="floating-error">{receiptError}</p> : null}
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
