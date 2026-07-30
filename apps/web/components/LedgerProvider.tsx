"use client";

import { createClient, SupabaseClient, User } from "@supabase/supabase-js";
import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import type { Account, AccountType, Attachment, Ledger, LedgerKind, LedgerRole, Transaction, TransactionKind } from "@/lib/types";

type RemoteLedger = {
  id: string;
  owner_user_id: string;
  name: string;
  currency_code: string;
  ledger_type?: LedgerKind;
  created_at: string;
  updated_at: string;
};

type RemoteLedgerMembership = {
  ledger_id: string;
  user_id: string;
  role: LedgerRole;
};

type RemoteAccount = {
  id: string;
  ledger_id: string;
  name: string;
  type: AccountType;
  parent_id: string | null;
  display_order: number;
  archived_at: string | null;
  created_at: string;
  updated_at: string;
};

type RemotePosting = {
  id: string;
  transaction_id: string;
  account_id: string;
  amount_minor_units: number;
  currency_code: string;
  memo: string | null;
  created_at: string;
};

type RemoteTransaction = {
  id: string;
  ledger_id: string;
  accounting_date: string;
  description: string;
  payee: string | null;
  note: string | null;
  revision: number;
  deleted_at: string | null;
  created_at: string;
  updated_at: string;
  postings: RemotePosting[];
};

type RemoteAttachment = {
  id: string;
  ledger_id: string;
  transaction_id: string | null;
  object_key: string;
  original_file_name: string;
  mime_type: string;
  byte_size: number;
  sha256_hex: string;
  status: string;
  created_at: string;
};

type NewTransaction = {
  date: string;
  payee: string;
  accountId: string;
  categoryId: string;
  amountMinorUnits: number;
  kind: TransactionKind;
  note?: string;
  receiptFile?: File | null;
};

type NewLedger = {
  name: string;
  currencyCode: string;
  kind: LedgerKind;
};

type EditTransaction = NewTransaction & {
  id: string;
  expectedRevision: number;
};

type AuthPhase = "checking" | "configurationRequired" | "signedOut" | "ready" | "needsLedger" | "failed";

type LedgerContextValue = {
  phase: AuthPhase;
  user: User | null;
  ledger: Ledger | null;
  ledgers: Ledger[];
  accounts: Account[];
  transactions: Transaction[];
  attachments: Attachment[];
  errorMessage: string | null;
  isWorking: boolean;
  sendCode: (email: string) => Promise<void>;
  verifyCode: (email: string, token: string) => Promise<void>;
  signOut: () => Promise<void>;
  refresh: () => Promise<void>;
  createLedger: (input?: Partial<NewLedger>) => Promise<void>;
  switchLedger: (ledgerID: string) => Promise<void>;
  inviteLedgerMember: (email: string, role?: "admin" | "member") => Promise<void>;
  addTransaction: (input: NewTransaction) => Promise<Transaction>;
  updateTransaction: (input: EditTransaction) => Promise<void>;
  deleteTransaction: (transaction: Transaction) => Promise<void>;
  getReceiptViewURL: (attachmentID: string) => Promise<string>;
};

const LedgerContext = createContext<LedgerContextValue | null>(null);

const supabaseURL = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim() ?? "";
const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim() ?? "";
const hasConfig = supabaseURL.startsWith("https://") && supabaseKey.length > 40;
const supabase = hasConfig ? createClient(supabaseURL, supabaseKey) : null;

export function LedgerProvider({ children }: { children: React.ReactNode }) {
  const [phase, setPhase] = useState<AuthPhase>(hasConfig ? "checking" : "configurationRequired");
  const [user, setUser] = useState<User | null>(null);
  const [ledgers, setLedgers] = useState<Ledger[]>([]);
  const [ledger, setLedger] = useState<Ledger | null>(null);
  const [activeLedgerID, setActiveLedgerID] = useState<string | null>(null);
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [attachments, setAttachments] = useState<Attachment[]>([]);
  const [errorMessage, setErrorMessage] = useState<string | null>(hasConfig ? null : "Add NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY to apps/web/.env.local.");
  const [isWorking, setIsWorking] = useState(false);

  const loadSnapshot = useCallback(async (preferredLedgerID?: string) => {
    if (!supabase) {
      setPhase("configurationRequired");
      return;
    }

    setIsWorking(true);
    setErrorMessage(null);
    try {
      await acceptInvitesIfAvailable(supabase);

      const { data: ledgerRows, error: ledgerError } = await supabase
        .from("ledgers")
        .select("*")
        .order("created_at", { ascending: true });
      if (ledgerError) throw ledgerError;

      const remoteLedgers = (ledgerRows as RemoteLedger[] | null) ?? [];
      const memberships = await loadMembershipsIfAvailable(supabase);
      const visibleLedgers = remoteLedgers.map((item) => toLedger(item, memberships, user?.id));
      setLedgers(visibleLedgers);

      const storedLedgerID = typeof window === "undefined" ? null : window.localStorage.getItem("rainflow.activeLedgerID");
      const requestedLedgerID = preferredLedgerID ?? activeLedgerID ?? storedLedgerID;
      const remoteLedger = remoteLedgers.find((item) => item.id === requestedLedgerID) ?? remoteLedgers[0] ?? null;
      const selectedLedger = remoteLedger ? toLedger(remoteLedger, memberships, user?.id) : null;
      if (!remoteLedger) {
        setLedger(null);
        setAccounts([]);
        setTransactions([]);
        setAttachments([]);
        setPhase("needsLedger");
        return;
      }
      setLedger(selectedLedger);
      setActiveLedgerID(remoteLedger.id);
      if (typeof window !== "undefined") {
        window.localStorage.setItem("rainflow.activeLedgerID", remoteLedger.id);
      }

      const [accountResult, transactionResult, attachmentResult] = await Promise.all([
        supabase
          .from("accounts")
          .select("*")
          .eq("ledger_id", remoteLedger.id)
          .order("display_order", { ascending: true }),
        supabase
          .from("ledger_transactions")
          .select("*, postings(*)")
          .eq("ledger_id", remoteLedger.id)
          .order("accounting_date", { ascending: false }),
        supabase
          .from("attachment_manifests")
          .select("id, ledger_id, transaction_id, object_key, original_file_name, mime_type, byte_size, sha256_hex, status, created_at")
          .eq("ledger_id", remoteLedger.id)
      ]);

      if (accountResult.error) throw accountResult.error;
      if (transactionResult.error) throw transactionResult.error;
      if (attachmentResult.error) throw attachmentResult.error;

      const remoteAccounts = (accountResult.data ?? []) as RemoteAccount[];
      const remoteTransactions = (transactionResult.data ?? []) as RemoteTransaction[];
      const remoteAttachments = (attachmentResult.data ?? []) as RemoteAttachment[];

      const activeTransactions = remoteTransactions.filter((item) => !item.deleted_at);
      const attachmentByTransaction = new Map(
        remoteAttachments
          .filter((item) => item.transaction_id && item.status === "active")
          .map((item) => [item.transaction_id as string, item])
      );

      setAccounts(deriveAccounts(remoteAccounts, activeTransactions));
      setTransactions(deriveTransactions(activeTransactions, remoteAccounts, attachmentByTransaction));
      setAttachments(remoteAttachments.map((item) => ({
        id: item.id,
        transactionId: item.transaction_id,
        objectKey: item.object_key,
        originalFileName: item.original_file_name,
        mimeType: item.mime_type,
        byteSize: Number(item.byte_size),
        status: item.status,
        createdAt: item.created_at
      })));
      setPhase("ready");
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : "Rainflow could not load.");
      setPhase("failed");
    } finally {
      setIsWorking(false);
    }
  }, [activeLedgerID, user?.id]);

  useEffect(() => {
    if (!supabase) return;

    supabase.auth.getSession().then(({ data, error }) => {
      if (error) {
        setErrorMessage(error.message);
        setPhase("failed");
        return;
      }
      setUser(data.session?.user ?? null);
      if (data.session?.user) {
        void loadSnapshot();
      } else {
        setPhase("signedOut");
      }
    });

    const { data: listener } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
      if (session?.user) {
        void loadSnapshot();
      } else {
        setLedger(null);
        setAccounts([]);
        setTransactions([]);
        setAttachments([]);
        setPhase("signedOut");
      }
    });

    return () => listener.subscription.unsubscribe();
  }, [loadSnapshot]);

  const sendCode = useCallback(async (email: string) => {
    const client = requireSupabase(supabase);
    setIsWorking(true);
    setErrorMessage(null);
    try {
      const { error } = await client.auth.signInWithOtp({
        email,
        options: { shouldCreateUser: true }
      });
      if (error) throw error;
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : "Could not send sign-in code.");
      throw error;
    } finally {
      setIsWorking(false);
    }
  }, []);

  const verifyCode = useCallback(async (email: string, token: string) => {
    const client = requireSupabase(supabase);
    setIsWorking(true);
    setErrorMessage(null);
    try {
      const { error } = await client.auth.verifyOtp({
        email,
        token,
        type: "email"
      });
      if (error) throw error;
      await loadSnapshot();
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : "Could not verify sign-in code.");
      throw error;
    } finally {
      setIsWorking(false);
    }
  }, [loadSnapshot]);

  const signOut = useCallback(async () => {
    const client = requireSupabase(supabase);
    await client.auth.signOut();
  }, []);

  const createLedger = useCallback(async (input?: Partial<NewLedger>) => {
    const client = requireSupabase(supabase);
    setIsWorking(true);
    setErrorMessage(null);
    try {
      const name = input?.name?.trim() || (input?.kind === "shared" ? "Shared Ledger" : "Personal");
      const currencyCode = input?.currencyCode ?? "USD";
      const kind = input?.kind ?? "personal";
      let { data, error } = await client.rpc("create_ledger_with_type", {
        ledger_name: name,
        ledger_currency: currencyCode,
        ledger_kind: kind
      });
      if (error && kind === "personal" && isMissingSchemaFeature(error.message)) {
        const fallback = await client.rpc("create_ledger", {
          ledger_name: name,
          ledger_currency: currencyCode
        });
        data = fallback.data;
        error = fallback.error;
      }
      if (error) throw error;
      const created = data as RemoteLedger | null;
      await loadSnapshot(created?.id);
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : "Could not create ledger.");
      throw error;
    } finally {
      setIsWorking(false);
    }
  }, [loadSnapshot]);

  const switchLedger = useCallback(async (ledgerID: string) => {
    setActiveLedgerID(ledgerID);
    if (typeof window !== "undefined") {
      window.localStorage.setItem("rainflow.activeLedgerID", ledgerID);
    }
    await loadSnapshot(ledgerID);
  }, [loadSnapshot]);

  const inviteLedgerMember = useCallback(async (email: string, role: "admin" | "member" = "member") => {
    const client = requireSupabase(supabase);
    if (!ledger) throw new Error("Choose a shared ledger before inviting people.");
    if (ledger.kind !== "shared") throw new Error("Only shared ledgers can invite people.");
    if (ledger.role === "member") throw new Error("Only ledger admins can invite people.");

    setIsWorking(true);
    setErrorMessage(null);
    try {
      const { error } = await client.rpc("invite_ledger_member", {
        p_ledger_id: ledger.id,
        p_invited_email: email.trim().toLowerCase(),
        p_role: role
      });
      if (error) throw error;
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : "Could not send ledger invitation.");
      throw error;
    } finally {
      setIsWorking(false);
    }
  }, [ledger]);

  const addTransaction = useCallback(async (input: NewTransaction) => {
    const client = requireSupabase(supabase);
    if (!ledger) throw new Error("Create a ledger before adding transactions.");
    const sourceAccount = accounts.find((item) => item.id === input.accountId);
    const destinationAccount = accounts.find((item) => item.id === input.categoryId);
    if (!sourceAccount || !destinationAccount) throw new Error("Choose valid accounts.");

    const amount = Math.abs(Math.round(input.amountMinorUnits));
    const transactionID = crypto.randomUUID();
    const postings = buildPostings(input.kind, amount, ledger.currencyCode, sourceAccount.id, destinationAccount.id);

    setIsWorking(true);
    setErrorMessage(null);
    try {
      const { error } = await client.rpc("create_transaction", {
        p_ledger_id: ledger.id,
        p_transaction_id: transactionID,
        p_idempotency_key: crypto.randomUUID(),
        p_accounting_date: input.date,
        p_description: input.payee.trim() || "Transaction",
        p_payee: input.payee.trim(),
        p_note: input.note?.trim() ?? "",
        p_postings: postings
      });
      if (error) throw error;

      if (input.receiptFile) {
        await uploadAndFinalizeReceipt({
          client,
          user,
          ledgerID: ledger.id,
          transactionID,
          receiptFile: input.receiptFile
        });
      }

      await loadSnapshot();

      return {
        id: transactionID,
        date: input.date,
        payee: input.payee.trim() || "Transaction",
        category: destinationAccount.name,
        account: sourceAccount.name,
        accountId: sourceAccount.id,
        categoryId: destinationAccount.id,
        amountMinorUnits: input.kind === "expense" ? -amount : amount,
        kind: input.kind,
        receiptName: input.receiptFile?.name,
        revision: 1
      };
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : "Could not save transaction.");
      throw error;
    } finally {
      setIsWorking(false);
    }
  }, [accounts, ledger, loadSnapshot, user]);

  const updateTransaction = useCallback(async (input: EditTransaction) => {
    const client = requireSupabase(supabase);
    if (!ledger) throw new Error("Create a ledger before editing transactions.");
    const sourceAccount = accounts.find((item) => item.id === input.accountId);
    const destinationAccount = accounts.find((item) => item.id === input.categoryId);
    if (!sourceAccount || !destinationAccount) throw new Error("Choose valid accounts.");

    const amount = Math.abs(Math.round(input.amountMinorUnits));
    const postings = buildPostings(input.kind, amount, ledger.currencyCode, sourceAccount.id, destinationAccount.id);

    setIsWorking(true);
    setErrorMessage(null);
    try {
      const { error } = await client.rpc("update_transaction", {
        p_ledger_id: ledger.id,
        p_transaction_id: input.id,
        p_expected_revision: input.expectedRevision,
        p_accounting_date: input.date,
        p_description: input.payee.trim() || "Transaction",
        p_payee: input.payee.trim(),
        p_note: input.note?.trim() ?? "",
        p_postings: postings
      });
      if (error) throw error;

      if (input.receiptFile) {
        await uploadAndFinalizeReceipt({
          client,
          user,
          ledgerID: ledger.id,
          transactionID: input.id,
          receiptFile: input.receiptFile
        });
      }

      await loadSnapshot();
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : "Could not update transaction.");
      throw error;
    } finally {
      setIsWorking(false);
    }
  }, [accounts, ledger, loadSnapshot, user]);

  const deleteTransaction = useCallback(async (transaction: Transaction) => {
    const client = requireSupabase(supabase);
    if (!ledger) throw new Error("Create a ledger before removing transactions.");

    setIsWorking(true);
    setErrorMessage(null);
    try {
      const { error } = await client.rpc("soft_delete_transaction", {
        p_ledger_id: ledger.id,
        p_transaction_id: transaction.id,
        p_expected_revision: transaction.revision
      });
      if (error) throw error;
      await loadSnapshot();
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : "Could not remove transaction.");
      throw error;
    } finally {
      setIsWorking(false);
    }
  }, [ledger, loadSnapshot]);

  const getReceiptViewURL = useCallback(async (attachmentID: string) => {
    const client = requireSupabase(supabase);
    const attachment = attachments.find((item) => item.id === attachmentID);
    if (!attachment) throw new Error("Receipt attachment was not found.");
    if (attachment.status !== "active") throw new Error("This receipt is not available yet.");

    const { data, error } = await client.storage
      .from("receipts")
      .createSignedUrl(attachment.objectKey, 300);
    if (error) throw error;
    if (!data?.signedUrl) throw new Error("Could not create a receipt viewing link.");
    return data.signedUrl;
  }, [attachments]);

  const value = useMemo<LedgerContextValue>(() => ({
    phase,
    user,
    ledger,
    ledgers,
    accounts,
    transactions,
    attachments,
    errorMessage,
    isWorking,
    sendCode,
    verifyCode,
    signOut,
    refresh: loadSnapshot,
    createLedger,
    switchLedger,
    inviteLedgerMember,
    addTransaction,
    updateTransaction,
    deleteTransaction,
    getReceiptViewURL
  }), [phase, user, ledger, ledgers, accounts, transactions, attachments, errorMessage, isWorking, sendCode, verifyCode, signOut, loadSnapshot, createLedger, switchLedger, inviteLedgerMember, addTransaction, updateTransaction, deleteTransaction, getReceiptViewURL]);

  return <LedgerContext.Provider value={value}>{children}</LedgerContext.Provider>;
}

export function useLedger() {
  const value = useContext(LedgerContext);
  if (!value) throw new Error("useLedger must be used inside LedgerProvider");
  return value;
}

function requireSupabase(client: SupabaseClient | null): SupabaseClient {
  if (!client) throw new Error("Supabase is not configured.");
  return client;
}

async function acceptInvitesIfAvailable(client: SupabaseClient) {
  const { error } = await client.rpc("accept_current_user_ledger_invites");
  if (error && !isMissingSchemaFeature(error.message)) throw error;
}

async function loadMembershipsIfAvailable(client: SupabaseClient) {
  const { data, error } = await client
    .from("ledger_memberships")
    .select("ledger_id, user_id, role");
  if (error) {
    if (isMissingSchemaFeature(error.message)) return [] as RemoteLedgerMembership[];
    throw error;
  }
  return (data ?? []) as RemoteLedgerMembership[];
}

function toLedger(remote: RemoteLedger, memberships: RemoteLedgerMembership[], userID?: string): Ledger {
  const membership = memberships.find((item) => item.ledger_id === remote.id && item.user_id === userID);
  return {
    id: remote.id,
    name: remote.name,
    currencyCode: remote.currency_code,
    kind: remote.ledger_type ?? "personal",
    role: membership?.role ?? (remote.owner_user_id === userID ? "owner" : "member")
  };
}

function isMissingSchemaFeature(message: string) {
  const normalized = message.toLowerCase();
  return normalized.includes("could not find the function")
    || normalized.includes("does not exist")
    || normalized.includes("schema cache")
    || normalized.includes("relation")
    || normalized.includes("ledger_memberships");
}

function deriveAccounts(remoteAccounts: RemoteAccount[], transactions: RemoteTransaction[]): Account[] {
  const balances = new Map<string, number>();
  for (const transaction of transactions) {
    for (const posting of transaction.postings ?? []) {
      balances.set(posting.account_id, (balances.get(posting.account_id) ?? 0) + Number(posting.amount_minor_units));
    }
  }

  return remoteAccounts
    .filter((account) => !account.archived_at)
    .map((account) => ({
      id: account.id,
      name: account.name,
      subtype: titleCase(account.type),
      type: account.type,
      group: accountGroup(account.type),
      balanceMinorUnits: balances.get(account.id) ?? 0
    }));
}

function deriveTransactions(
  transactions: RemoteTransaction[],
  accounts: RemoteAccount[],
  attachmentByTransaction: Map<string, RemoteAttachment>
): Transaction[] {
  const accountMap = new Map(accounts.map((account) => [account.id, account]));

  return transactions.map((transaction) => {
    const postings = transaction.postings ?? [];
    const expensePosting = postings.find((posting) => accountMap.get(posting.account_id)?.type === "expense" && Number(posting.amount_minor_units) > 0);
    const incomePosting = postings.find((posting) => accountMap.get(posting.account_id)?.type === "income" && Number(posting.amount_minor_units) < 0);
    const sourcePosting = postings.find((posting) => {
      const type = accountMap.get(posting.account_id)?.type;
      return (type === "asset" || type === "liability") && Number(posting.amount_minor_units) < 0;
    }) ?? postings.find((posting) => {
      const type = accountMap.get(posting.account_id)?.type;
      return type === "asset" || type === "liability";
    });
    const destinationPosting = expensePosting ?? incomePosting ?? postings.find((posting) => posting.account_id !== sourcePosting?.account_id);
    const kind: TransactionKind = expensePosting ? "expense" : incomePosting ? "income" : "transfer";
    const amount = expensePosting
      ? -Math.abs(Number(expensePosting.amount_minor_units))
      : incomePosting
        ? Math.abs(Number(incomePosting.amount_minor_units))
        : Math.abs(Number(destinationPosting?.amount_minor_units ?? sourcePosting?.amount_minor_units ?? 0));

    return {
      id: transaction.id,
      date: transaction.accounting_date,
      payee: transaction.payee || transaction.description || "Transaction",
      category: accountMap.get(destinationPosting?.account_id ?? "")?.name ?? (kind === "transfer" ? "Transfer" : "Uncategorized"),
      account: accountMap.get(sourcePosting?.account_id ?? "")?.name ?? "Account",
      accountId: sourcePosting?.account_id ?? "",
      categoryId: destinationPosting?.account_id ?? "",
      amountMinorUnits: amount,
      kind,
      receiptAttachmentId: attachmentByTransaction.get(transaction.id)?.id,
      receiptName: attachmentByTransaction.get(transaction.id)?.original_file_name,
      receiptStatus: attachmentByTransaction.get(transaction.id)?.status,
      revision: transaction.revision
    };
  });
}

async function uploadAndFinalizeReceipt({
  client,
  user,
  ledgerID,
  transactionID,
  receiptFile
}: {
  client: SupabaseClient;
  user: User | null;
  ledgerID: string;
  transactionID: string;
  receiptFile: File;
}) {
  if (!user) throw new Error("Sign in before uploading a receipt.");
  const prepared = await prepareReceiptFile(receiptFile);
  const attachmentID = crypto.randomUUID();
  const extension = fileExtension(prepared.fileName, prepared.mimeType);
  const objectKey = [
    user.id,
    ledgerID,
    transactionID,
    `${attachmentID}.${extension}`
  ].join("/");

  const { error: uploadError } = await client.storage
    .from("receipts")
    .upload(objectKey, prepared.blob, {
      cacheControl: "3600",
      contentType: prepared.mimeType,
      upsert: false
    });
  if (uploadError) throw uploadError;

  const { error: finalizeError } = await client.rpc("finalize_attachment", {
    p_ledger_id: ledgerID,
    p_transaction_id: transactionID,
    p_attachment_id: attachmentID,
    p_object_key: objectKey,
    p_original_file_name: prepared.fileName,
    p_mime_type: prepared.mimeType,
    p_byte_size: prepared.byteSize,
    p_sha256_hex: prepared.sha256Hex
  });
  if (finalizeError) throw finalizeError;
}

async function prepareReceiptFile(file: File) {
  const mimeType = normalizedMimeType(file);
  if (!["image/jpeg", "image/png", "image/heic", "image/heif"].includes(mimeType)) {
    throw new Error("Choose a JPG, PNG, HEIC, or HEIF receipt image.");
  }
  if (file.size <= 0 || file.size > 10 * 1024 * 1024) {
    throw new Error("Receipt images must be smaller than 10 MB.");
  }

  const buffer = await file.arrayBuffer();
  const digest = await crypto.subtle.digest("SHA-256", buffer);
  return {
    blob: new Blob([buffer], { type: mimeType }),
    fileName: sanitizeFileName(file.name || "receipt.jpg"),
    mimeType,
    byteSize: file.size,
    sha256Hex: Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, "0")).join("")
  };
}

function normalizedMimeType(file: File) {
  if (file.type) return file.type.toLowerCase();
  const name = file.name.toLowerCase();
  if (name.endsWith(".png")) return "image/png";
  if (name.endsWith(".heic")) return "image/heic";
  if (name.endsWith(".heif")) return "image/heif";
  return "image/jpeg";
}

function sanitizeFileName(value: string) {
  const sanitized = value.replace(/[^a-zA-Z0-9._-]/g, "_").slice(0, 120);
  return sanitized || "receipt.jpg";
}

function fileExtension(fileName: string, mimeType: string) {
  const normalized = fileName.toLowerCase();
  if (normalized.endsWith(".png") || mimeType === "image/png") return "png";
  if (normalized.endsWith(".heic") || mimeType === "image/heic") return "heic";
  if (normalized.endsWith(".heif") || mimeType === "image/heif") return "heif";
  return "jpg";
}

function buildPostings(kind: TransactionKind, amount: number, currencyCode: string, sourceAccountID: string, destinationAccountID: string) {
  if (kind === "income") {
    return [
      { id: crypto.randomUUID(), account_id: sourceAccountID, amount_minor_units: amount, currency_code: currencyCode, memo: null },
      { id: crypto.randomUUID(), account_id: destinationAccountID, amount_minor_units: -amount, currency_code: currencyCode, memo: null }
    ];
  }

  return [
    { id: crypto.randomUUID(), account_id: sourceAccountID, amount_minor_units: -amount, currency_code: currencyCode, memo: null },
    { id: crypto.randomUUID(), account_id: destinationAccountID, amount_minor_units: amount, currency_code: currencyCode, memo: null }
  ];
}

function accountGroup(type: AccountType) {
  switch (type) {
    case "asset": return "Assets";
    case "liability": return "Liabilities";
    case "income": return "Income";
    case "expense": return "Expenses";
    case "equity": return "Equity";
  }
}

function titleCase(value: string) {
  return value[0].toUpperCase() + value.slice(1);
}
