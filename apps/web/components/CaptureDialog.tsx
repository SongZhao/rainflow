"use client";

import { Camera, Check, FileImage, Images, PenLine, X } from "lucide-react";
import { ChangeEvent, FormEvent, useEffect, useMemo, useRef, useState } from "react";
import type { Account, TransactionKind } from "@/lib/types";
import { formatMoney } from "@/lib/format";
import { saveTransactionLineItems, type ReceiptLineItem } from "@/lib/transaction-line-items";
import { useLedger } from "./LedgerProvider";

type Mode = "menu" | "form" | "success";
type CategorySuggestion = { account: Account; reason: string };

export function CaptureDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { ledger, accounts, transactions, addTransaction, extractReceipt, isWorking, errorMessage } = useLedger();
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const cameraInputRef = useRef<HTMLInputElement | null>(null);
  const [mode, setMode] = useState<Mode>("menu");
  const [kind, setKind] = useState<TransactionKind>("expense");
  const [amount, setAmount] = useState("");
  const [date, setDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [payee, setPayee] = useState("");
  const [receiptMerchant, setReceiptMerchant] = useState("");
  const [accountID, setAccountID] = useState("");
  const [categoryID, setCategoryID] = useState("");
  const [categorySuggestion, setCategorySuggestion] = useState<string | null>(null);
  const [categoryWasManuallyChosen, setCategoryWasManuallyChosen] = useState(false);
  const [note, setNote] = useState("");
  const [receipts, setReceipts] = useState<File[]>([]);
  const [ocrStatus, setOcrStatus] = useState<"idle" | "reading" | "applied" | "needsReview" | "unavailable">("idle");
  const [ocrWarnings, setOcrWarnings] = useState<string[]>([]);
  const [missingFields, setMissingFields] = useState<string[]>([]);
  const [lineItems, setLineItems] = useState<ReceiptLineItem[]>([]);
  const [savedAmount, setSavedAmount] = useState(0);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [savedWarning, setSavedWarning] = useState<string | null>(null);

  const receipt = receipts[0] ?? null;
  const previewUrl = useMemo(() => (receipt ? URL.createObjectURL(receipt) : null), [receipt]);
  const sourceAccounts = useMemo(() => accounts.filter((item) => item.type === "asset" || item.type === "liability"), [accounts]);
  const destinationAccounts = useMemo(() => {
    if (kind === "expense") return accounts.filter((item) => item.type === "expense");
    if (kind === "income") return accounts.filter((item) => item.type === "income");
    return sourceAccounts.filter((item) => item.id !== accountID);
  }, [accountID, accounts, kind, sourceAccounts]);

  useEffect(() => () => {
    if (previewUrl) URL.revokeObjectURL(previewUrl);
  }, [previewUrl]);

  useEffect(() => {
    if (!sourceAccounts.some((item) => item.id === accountID)) setAccountID(sourceAccounts[0]?.id ?? "");
  }, [accountID, sourceAccounts]);

  useEffect(() => {
    if (categoryID && !destinationAccounts.some((item) => item.id === categoryID)) setCategoryID("");
  }, [categoryID, destinationAccounts]);

  // Category suggestions are derived continuously instead of only once when OCR
  // finishes. This makes auto-selection work even when the ledger categories are
  // refreshed after OCR returns. A user's explicit choice always wins.
  useEffect(() => {
    if (!receipt || kind !== "expense" || categoryWasManuallyChosen) return;
    const expenseCategories = accounts.filter((item) => item.type === "expense");
    if (expenseCategories.length === 0) return;

    const suggestion = suggestExpenseCategory(
      receiptMerchant || payee,
      lineItems,
      expenseCategories,
      transactions,
    );

    if (suggestion) {
      setCategoryID(suggestion.account.id);
      setCategorySuggestion(suggestion.reason);
    }
  }, [accounts, categoryWasManuallyChosen, kind, lineItems, payee, receipt, receiptMerchant, transactions]);

  if (!open) return null;

  function resetAndClose() {
    setMode("menu");
    setKind("expense");
    setAmount("");
    setPayee("");
    setReceiptMerchant("");
    setNote("");
    setReceipts([]);
    setCategoryID("");
    setCategorySuggestion(null);
    setCategoryWasManuallyChosen(false);
    setOcrStatus("idle");
    setOcrWarnings([]);
    setMissingFields([]);
    setLineItems([]);
    setSaveError(null);
    setSavedWarning(null);
    onClose();
  }

  function selectFile(event: ChangeEvent<HTMLInputElement>) {
    const selectedFiles = Array.from(event.target.files ?? []);
    if (!selectedFiles.length) return;
    const files = timestampReceiptFiles(selectedFiles, receipts);
    const nextReceipts = [...receipts, ...files];
    setReceipts(nextReceipts);
    setOcrStatus("reading");
    setOcrWarnings([]);
    setMissingFields([]);
    setLineItems([]);
    setReceiptMerchant("");
    setCategoryID("");
    setCategorySuggestion(null);
    setCategoryWasManuallyChosen(false);
    setMode("form");
    void extract(nextReceipts);
  }

  function clearReceipt() {
    setReceipts([]);
    setReceiptMerchant("");
    setOcrStatus("idle");
    setOcrWarnings([]);
    setMissingFields([]);
    setLineItems([]);
    setCategoryID("");
    setCategorySuggestion(null);
    setCategoryWasManuallyChosen(false);
    if (fileInputRef.current) fileInputRef.current.value = "";
    if (cameraInputRef.current) cameraInputRef.current.value = "";
  }

  async function extract(files: File[]) {
    try {
      const result = await extractReceipt(files);
      const merchant = result.fields.merchant?.trim() ?? "";
      const items = result.fields.lineItems ?? [];
      if (result.fields.amountMinorUnits) setAmount((result.fields.amountMinorUnits / 100).toFixed(2));
      if (result.fields.date) setDate(result.fields.date);
      if (merchant) setPayee(merchant);
      setReceiptMerchant(merchant);
      setLineItems(items);
      setMissingFields(result.missingFields);
      setOcrWarnings(result.warnings);
      setOcrStatus(result.status === "ok" ? "applied" : result.status === "not_configured" ? "unavailable" : "needsReview");
    } catch (error) {
      setOcrStatus("needsReview");
      setOcrWarnings(await receiptErrorWarnings(error));
    }
  }

  async function save(event: FormEvent) {
    event.preventDefault();
    const parsed = Math.round(Number(amount) * 100);
    if (!Number.isFinite(parsed) || parsed <= 0 || !accountID || !categoryID || accountID === categoryID) return;
    setSaveError(null);
    setSavedWarning(null);

    try {
      const transaction = await addTransaction({
        date,
        payee: payee.trim() || (receipt ? "Receipt draft" : "Manual transaction"),
        accountId: accountID,
        categoryId: categoryID,
        amountMinorUnits: parsed,
        kind,
        note: note.trim(),
        receiptFile: receipt,
      });

      if (ledger && lineItems.length > 0) {
        try {
          await saveTransactionLineItems(ledger.id, transaction.id, lineItems);
        } catch (error) {
          setSavedWarning(error instanceof Error
            ? `Transaction saved, but receipt items were not stored: ${error.message}`
            : "Transaction saved, but receipt items were not stored.");
        }
      }

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
          <div><span className="eyebrow">Primary action</span><h2 id="capture-title">Add transaction</h2></div>
          <button className="icon-button" type="button" onClick={resetAndClose} aria-label="Close"><X size={20} /></button>
        </div>

        {mode === "menu" ? (
          <div className="capture-menu">
            <CaptureOption icon={<Camera size={21} />} title="Take photo" description="Capture a receipt" onClick={() => cameraInputRef.current?.click()} />
            <CaptureOption icon={<FileImage size={21} />} title="Choose from library" description="Select receipt images" onClick={() => fileInputRef.current?.click()} />
            <CaptureOption icon={<PenLine size={21} />} title="Add manually" description="Enter without a receipt" onClick={() => { clearReceipt(); setMode("form"); }} />
            <input ref={fileInputRef} hidden type="file" accept="image/*" multiple onChange={selectFile} />
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
                  setCategorySuggestion(null);
                  setCategoryWasManuallyChosen(false);
                }}>
                  {item[0].toUpperCase() + item.slice(1)}
                </button>
              ))}
            </div>

            <div className="form-grid">
              <label className="field field-amount"><span>Amount</span><div className="money-input"><span>$</span><input required inputMode="decimal" value={amount} onChange={(event) => setAmount(event.target.value)} placeholder="0.00" autoFocus /></div></label>
              <label className="field"><span>{receipt ? "Receipt date" : "Date"}</span><input type="date" value={date} onChange={(event) => setDate(event.target.value)} /></label>
              <label className="field"><span>{kind === "income" ? "Deposit account" : kind === "transfer" ? "From account" : "Payment account"}</span><select value={accountID} onChange={(event) => setAccountID(event.target.value)}>{sourceAccounts.map((item) => <option value={item.id} key={item.id}>{item.name}</option>)}</select></label>
              <label className="field">
                <span>{kind === "transfer" ? "To account" : kind === "income" ? "Income category" : "Category"}</span>
                <select required value={categoryID} onChange={(event) => {
                  setCategoryID(event.target.value);
                  setCategorySuggestion(null);
                  setCategoryWasManuallyChosen(true);
                }}>
                  <option value="" disabled>Choose category</option>
                  {destinationAccounts.map((item) => <option value={item.id} key={item.id}>{item.name}</option>)}
                </select>
                {categorySuggestion ? <small>{categorySuggestion}</small> : null}
              </label>
              <label className="field field-wide"><span>Payee or description</span><input value={payee} onChange={(event) => setPayee(event.target.value)} placeholder="Optional" /></label>
              <label className="field field-wide"><span>Note</span><input value={note} onChange={(event) => setNote(event.target.value)} placeholder="Optional" /></label>
            </div>

            {previewUrl ? (
              <div className="receipt-preview">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={previewUrl} alt="Selected receipt preview" />
                <div>
                  <strong>{receipts.length > 1 ? `${receipts.length} receipt photos selected` : receipt?.name}</strong>
                  <span>{receipts.length > 1 ? "Rainflow will read the photos together. The first image will be attached to the saved transaction." : "This receipt will be stored privately with the transaction."}</span>
                  <button className="inline-link" type="button" onClick={() => fileInputRef.current?.click()}><Images size={13} /> Add another photo</button>
                  <button className="inline-link" type="button" onClick={clearReceipt}>Remove receipt</button>
                </div>
              </div>
            ) : null}

            {receipt ? <ReceiptExtractionState status={ocrStatus} warnings={ocrWarnings} missingFields={missingFields} lineItems={lineItems} onAddPhoto={() => fileInputRef.current?.click()} onUseExtracted={() => setOcrStatus("applied")} /> : <p className="form-note">This saves to the same Supabase ledger as the iPhone app.</p>}
            {saveError || errorMessage ? <p className="auth-error">{saveError ?? errorMessage}</p> : null}
            <div className="dialog-actions"><button className="secondary-button" type="button" onClick={() => setMode("menu")}>Back</button><button className="primary-button" type="submit" disabled={isWorking || !accountID || !categoryID || accountID === categoryID}>{isWorking ? "Saving..." : "Review & save"}</button></div>
          </form>
        ) : null}

        {mode === "success" ? (
          <div className="success-state">
            <span className="success-icon"><Check size={32} /></span>
            <h3>Transaction saved</h3>
            <strong className={savedAmount < 0 ? "amount negative" : "amount positive"}>{formatMoney(savedAmount, { sign: savedAmount > 0 })}</strong>
            <p>Saved to Supabase. Receipt items will remain attached to this transaction.</p>
            {savedWarning ? <p className="auth-error">{savedWarning}</p> : null}
            <button className="primary-button" type="button" onClick={resetAndClose}>Done</button>
          </div>
        ) : null}
      </section>
    </div>
  );
}

function suggestExpenseCategory(
  merchant: string,
  items: ReceiptLineItem[],
  categories: Account[],
  transactions: Array<{ payee: string; categoryId: string; kind: TransactionKind }>
): CategorySuggestion | null {
  const text = normalizeWords([merchant, ...items.map((item) => item.description)].join(" "));
  const rules: Array<{ aliases: string[]; words: RegExp }> = [
    { aliases: ["home repairs", "home improvement", "hardware", "home"], words: /\b(ace|hardware|lumber|coupling|cupling|screw|bolt|nail|paint|plumbing|pipe|tool|faucet|fixture)\b/ },
    { aliases: ["groceries", "grocery"], words: /\b(grocery|groceries|safeway|trader joe|whole foods|costco|supermarket|produce|milk|bread|vegetable|fruit)\b/ },
    { aliases: ["dining", "restaurant"], words: /\b(restaurant|cafe|coffee|starbucks|doordash|ubereats|grubhub|pizza|burger|sushi)\b/ },
    { aliases: ["gas"], words: /\b(shell|chevron|exxon|mobil|gasoline|fuel pump|unleaded|diesel)\b/ },
    { aliases: ["transportation"], words: /\b(uber|lyft|parking|toll|transit|metro|bus|train)\b/ },
    { aliases: ["healthcare", "health", "medical"], words: /\b(pharmacy|cvs|walgreens|rite aid|medical|clinic|dental|prescription)\b/ },
    { aliases: ["utilities"], words: /\b(electric|electricity|water bill|utility|internet|comcast|xfinity|phone bill|wireless)\b/ },
    { aliases: ["shopping"], words: /\b(target|walmart|amazon|clothing|apparel|shoes|nike|uniqlo|department store)\b/ },
    { aliases: ["entertainment"], words: /\b(movie|cinema|netflix|spotify|game|theater|concert)\b/ },
    { aliases: ["travel"], words: /\b(hotel|airbnb|airline|flight|airport|rental car)\b/ },
    { aliases: ["education"], words: /\b(tuition|school|university|college|course|textbook|bookstore)\b/ },
    { aliases: ["personal care"], words: /\b(salon|barber|haircut|spa|beauty|cosmetic)\b/ },
    { aliases: ["insurance"], words: /\b(insurance|premium)\b/ },
    { aliases: ["fees taxes", "fees"], words: /\b(service fee|bank fee|late fee|tax payment|dmv fee)\b/ },
  ];

  for (const rule of rules) {
    if (!rule.words.test(text)) continue;
    const account = findCategory(categories, rule.aliases);
    if (account) return { account, reason: "Auto-selected from the receipt merchant and items." };
  }

  const normalizedMerchant = normalizeWords(merchant);
  if (normalizedMerchant) {
    const previous = transactions.find((transaction) =>
      transaction.kind === "expense"
      && normalizeWords(transaction.payee) === normalizedMerchant
      && categories.some((category) => category.id === transaction.categoryId)
    );
    const account = previous ? categories.find((category) => category.id === previous.categoryId) : undefined;
    if (account) return { account, reason: "Auto-selected from your previous transactions with this merchant." };
  }

  const fallback = findCategory(categories, ["other expenses"]);
  if (fallback) return { account: fallback, reason: "Auto-selected as Other Expenses. Review if needed." };

  return null;
}

function findCategory(categories: Account[], aliases: string[]) {
  const normalizedAliases = aliases.map(normalizeWords);
  return categories.find((category) => normalizedAliases.includes(normalizeWords(category.name)))
    ?? categories.find((category) => {
      const name = normalizeWords(category.name);
      return normalizedAliases.some((alias) => name.includes(alias) || alias.includes(name));
    });
}

function normalizeWords(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
}

function CaptureOption({ icon, title, description, onClick }: { icon: React.ReactNode; title: string; description: string; onClick: () => void }) {
  return <button className="capture-option" type="button" onClick={onClick}><span className="capture-option-icon">{icon}</span><span><strong>{title}</strong><small>{description}</small></span><span aria-hidden="true">›</span></button>;
}

function ReceiptExtractionState({ status, warnings, missingFields, lineItems, onAddPhoto, onUseExtracted }: { status: "idle" | "reading" | "applied" | "needsReview" | "unavailable"; warnings: string[]; missingFields: string[]; lineItems: ReceiptLineItem[]; onAddPhoto: () => void; onUseExtracted: () => void }) {
  if (status === "reading") return <p className="form-note receipt-review-note">Reading receipt with OCR. Keep reviewing the fields; Rainflow will fill suggestions when they are ready.</p>;
  if (status === "applied") return <div className="receipt-review-note receipt-review-panel"><strong>Receipt suggestions applied</strong><span>Review the amount, merchant, category, and receipt date before saving.</span>{lineItems.length ? <ReceiptLineItems items={lineItems} /> : null}{warnings.length ? <ReceiptWarnings warnings={warnings} /> : null}</div>;
  if (status === "unavailable") return <p className="form-note receipt-review-note">Receipt OCR is not configured in Supabase yet. Enter the receipt values manually; the image will still be attached.</p>;
  if (status === "needsReview") return <div className="receipt-review-note receipt-review-panel"><strong>Receipt needs manual review</strong><span>{missingFields.length ? `Rainflow filled what it could. Missing: ${missingFields.join(", ")}.` : "Rainflow could not confidently read every field. Enter or correct the values before saving."}</span><div className="receipt-review-actions"><button className="secondary-button" type="button" onClick={onAddPhoto}><Images size={14} /> Add another photo</button><button className="secondary-button" type="button" onClick={onUseExtracted}><Check size={14} /> Use extracted info</button></div><ReceiptWarnings warnings={warnings} /></div>;
  return <p className="form-note receipt-review-note">Receipt selected. Rainflow will store it privately with this transaction.</p>;
}

function ReceiptLineItems({ items }: { items: ReceiptLineItem[] }) {
  return <div className="receipt-line-items">{items.slice(0, 12).map((item, index) => <span key={`${item.description}-${index}`}><small>{lineItemLabel(item)}</small><b>{typeof item.amountMinorUnits === "number" ? formatMoney(item.amountMinorUnits) : "Read"}</b></span>)}</div>;
}

function lineItemLabel(item: ReceiptLineItem) {
  if (item.quantity && item.unitPriceMinorUnits && item.quantity !== 1) {
    return `${item.quantity} × ${formatMoney(item.unitPriceMinorUnits)} · ${item.description}`;
  }
  return `${item.quantity && item.quantity !== 1 ? `${item.quantity}× ` : ""}${item.description}`;
}

function ReceiptWarnings({ warnings }: { warnings: string[] }) {
  return warnings.length ? <ul className="receipt-warnings">{warnings.slice(0, 4).map((warning) => <li key={warning}>{warning}</li>)}</ul> : null;
}

function timestampReceiptFiles(files: File[], existingFiles: File[]) {
  const usedNames = new Set(existingFiles.map((file) => file.name.toLowerCase()));
  let timestamp = new Date();
  return files.map((file) => {
    let fileName = timestampReceiptFileName(file, timestamp);
    while (usedNames.has(fileName.toLowerCase())) {
      timestamp = new Date(timestamp.getTime() + 1000);
      fileName = timestampReceiptFileName(file, timestamp);
    }
    usedNames.add(fileName.toLowerCase());
    timestamp = new Date(timestamp.getTime() + 1000);
    return new File([file], fileName, { type: file.type, lastModified: file.lastModified });
  });
}

function timestampReceiptFileName(file: File, timestamp: Date) {
  const digits = [timestamp.getFullYear(), String(timestamp.getMonth() + 1).padStart(2, "0"), String(timestamp.getDate()).padStart(2, "0"), String(timestamp.getHours()).padStart(2, "0"), String(timestamp.getMinutes()).padStart(2, "0"), String(timestamp.getSeconds()).padStart(2, "0")].join("");
  return `${digits}.${receiptExtension(file)}`;
}

function receiptExtension(file: File) {
  const mimeType = file.type.toLowerCase();
  const originalName = file.name.toLowerCase();
  if (mimeType === "image/png" || originalName.endsWith(".png")) return "png";
  if (mimeType === "image/heic" || originalName.endsWith(".heic")) return "heic";
  if (mimeType === "image/heif" || originalName.endsWith(".heif")) return "heif";
  return "jpg";
}

async function receiptErrorWarnings(error: unknown) {
  const context = typeof error === "object" && error !== null && "context" in error ? (error as { context?: unknown }).context : null;
  if (context instanceof Response) {
    const fallback = functionResponseFallback(context);
    try {
      const payload = await context.clone().json() as { warnings?: unknown; message?: unknown; error?: unknown; requestID?: unknown };
      const warnings = Array.isArray(payload.warnings) ? payload.warnings.filter((item): item is string => typeof item === "string" && item.trim().length > 0) : [];
      const message = typeof payload.message === "string" ? payload.message : typeof payload.error === "string" ? payload.error : null;
      const requestID = typeof payload.requestID === "string" ? payload.requestID : null;
      const details = warnings.length ? warnings : message ? [message] : [fallback];
      return requestID ? [...details, `Request ID: ${requestID}`] : details;
    } catch {
      const text = (await context.text().catch(() => "")).trim();
      return [text ? text.slice(0, 300) : fallback];
    }
  }
  return [error instanceof Error ? error.message : "Receipt OCR failed. Enter the values manually."];
}

function functionResponseFallback(response: Response) {
  const code = response.headers.get("sb-error-code");
  return code ? `Receipt OCR request failed (${response.status}, ${code}).` : `Receipt OCR request failed (${response.status}).`;
}
