"use client";

import { Camera, Check, FileImage, PenLine, X } from "lucide-react";
import { ChangeEvent, FormEvent, useEffect, useMemo, useRef, useState } from "react";
import type { TransactionKind } from "@/lib/types";
import { formatMoney } from "@/lib/format";
import { useLedger } from "./LedgerProvider";

type Mode = "menu" | "form" | "success";

export function CaptureDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { accounts, addTransaction, isWorking, errorMessage } = useLedger();
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const cameraInputRef = useRef<HTMLInputElement | null>(null);
  const [mode, setMode] = useState<Mode>("menu");
  const [kind, setKind] = useState<TransactionKind>("expense");
  const [amount, setAmount] = useState("");
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [payee, setPayee] = useState("");
  const [accountID, setAccountID] = useState("");
  const [categoryID, setCategoryID] = useState("");
  const [note, setNote] = useState("");
  const [receipt, setReceipt] = useState<File | null>(null);
  const [savedAmount, setSavedAmount] = useState(0);
  const [saveError, setSaveError] = useState<string | null>(null);

  const previewUrl = useMemo(() => (receipt ? URL.createObjectURL(receipt) : null), [receipt]);
  const sourceAccounts = useMemo(() => accounts.filter((item) => item.type === "asset" || item.type === "liability"), [accounts]);
  const destinationAccounts = useMemo(() => {
    if (kind === "expense") return accounts.filter((item) => item.type === "expense");
    if (kind === "income") return accounts.filter((item) => item.type === "income");
    return sourceAccounts.filter((item) => item.id !== accountID);
  }, [accountID, accounts, kind, sourceAccounts]);

  useEffect(() => {
    return () => {
      if (previewUrl) URL.revokeObjectURL(previewUrl);
    };
  }, [previewUrl]);

  useEffect(() => {
    if (!sourceAccounts.some((item) => item.id === accountID)) {
      setAccountID(sourceAccounts[0]?.id ?? "");
    }
  }, [accountID, sourceAccounts]);

  useEffect(() => {
    if (!destinationAccounts.some((item) => item.id === categoryID)) {
      setCategoryID(destinationAccounts[0]?.id ?? "");
    }
  }, [categoryID, destinationAccounts]);

  if (!open) return null;

  function resetAndClose() {
    setMode("menu");
    setKind("expense");
    setAmount("");
    setPayee("");
    setNote("");
    setReceipt(null);
    setSaveError(null);
    onClose();
  }

  function selectFile(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    setReceipt(file);
    setMode("form");
  }

  function clearReceipt() {
    setReceipt(null);
    if (fileInputRef.current) fileInputRef.current.value = "";
    if (cameraInputRef.current) cameraInputRef.current.value = "";
  }

  async function save(event: FormEvent) {
    event.preventDefault();
    const parsed = Math.round(Number(amount) * 100);
    if (!Number.isFinite(parsed) || parsed <= 0) return;
    if (!accountID || !categoryID || accountID === categoryID) return;
    setSaveError(null);
    try {
      const transaction = await addTransaction({
        date,
        payee: payee.trim() || (receipt ? "Receipt draft" : "Manual transaction"),
        accountId: accountID,
        categoryId: categoryID,
        amountMinorUnits: parsed,
        kind,
        note: note.trim(),
        receiptFile: receipt
      });
      setSavedAmount(transaction.amountMinorUnits);
      setMode("success");
    } catch (error) {
      setSaveError(error instanceof Error ? error.message : "Could not save transaction.");
    }
  }

  return (
    <div className="dialog-backdrop" role="presentation" onMouseDown={resetAndClose}>
      <section className="dialog" role="dialog" aria-modal="true" aria-labelledby="capture-title" onMouseDown={(event) => event.stopPropagation()}>
        <div className="dialog-header">
          <div>
            <span className="eyebrow">Primary action</span>
            <h2 id="capture-title">Add transaction</h2>
          </div>
          <button className="icon-button" type="button" onClick={resetAndClose} aria-label="Close">
            <X size={20} />
          </button>
        </div>

        {mode === "menu" ? (
          <div className="capture-menu">
            <CaptureOption icon={<Camera size={21} />} title="Take photo" description="Capture a receipt" onClick={() => cameraInputRef.current?.click()} />
            <CaptureOption icon={<FileImage size={21} />} title="Choose from library" description="Select a receipt image" onClick={() => fileInputRef.current?.click()} />
            <CaptureOption icon={<PenLine size={21} />} title="Add manually" description="Enter without a receipt" onClick={() => {
              clearReceipt();
              setMode("form");
            }} />
            <input ref={fileInputRef} hidden type="file" accept="image/*" onChange={selectFile} />
            <input ref={cameraInputRef} hidden type="file" accept="image/*" capture="environment" onChange={selectFile} />
          </div>
        ) : null}

        {mode === "form" ? (
          <form className="transaction-form" onSubmit={save}>
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
                <span>{receipt ? "Receipt date" : "Date"}</span>
                <input type="date" value={date} onChange={(event) => setDate(event.target.value)} />
              </label>
              <label className="field">
                <span>{kind === "income" ? "Deposit account" : kind === "transfer" ? "From account" : "Payment account"}</span>
                <select value={accountID} onChange={(event) => setAccountID(event.target.value)}>
                  {sourceAccounts.map((item) => <option value={item.id} key={item.id}>{item.name}</option>)}
                </select>
              </label>
              <label className="field">
                <span>{kind === "transfer" ? "To account" : kind === "income" ? "Income category" : "Category"}</span>
                <select value={categoryID} onChange={(event) => setCategoryID(event.target.value)}>
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
            </div>

            {previewUrl ? (
              <div className="receipt-preview">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={previewUrl} alt="Selected receipt preview" />
                <div>
                  <strong>{receipt?.name}</strong>
                  <span>This receipt will be stored privately with the transaction.</span>
                  <button className="inline-link" type="button" onClick={clearReceipt}>Remove receipt</button>
                </div>
              </div>
            ) : null}

            {receipt ? (
              <p className="form-note receipt-review-note">Web OCR is not enabled yet, so Rainflow will not guess the amount, merchant, receipt date, or line items. Enter the receipt values manually; the image will still be attached.</p>
            ) : (
              <p className="form-note">This saves to the same Supabase ledger as the iPhone app.</p>
            )}
            {saveError || errorMessage ? <p className="auth-error">{saveError ?? errorMessage}</p> : null}
            <div className="dialog-actions">
              <button className="secondary-button" type="button" onClick={() => setMode("menu")}>Back</button>
              <button className="primary-button" type="submit" disabled={isWorking || !accountID || !categoryID || accountID === categoryID}>{isWorking ? "Saving..." : "Review & save"}</button>
            </div>
          </form>
        ) : null}

        {mode === "success" ? (
          <div className="success-state">
            <span className="success-icon"><Check size={32} /></span>
            <h3>Transaction saved</h3>
            <strong className={savedAmount < 0 ? "amount negative" : "amount positive"}>{formatMoney(savedAmount, { sign: savedAmount > 0 })}</strong>
            <p>Saved to Supabase. It should appear on your iPhone after refresh.</p>
            <button className="primary-button" type="button" onClick={resetAndClose}>Done</button>
          </div>
        ) : null}
      </section>
    </div>
  );
}

function CaptureOption({ icon, title, description, onClick }: { icon: React.ReactNode; title: string; description: string; onClick: () => void }) {
  return (
    <button className="capture-option" type="button" onClick={onClick}>
      <span className="capture-option-icon">{icon}</span>
      <span><strong>{title}</strong><small>{description}</small></span>
      <span aria-hidden="true">›</span>
    </button>
  );
}
