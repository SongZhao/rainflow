export type TransactionKind = "income" | "expense" | "transfer";
export type AccountType = "asset" | "liability" | "income" | "expense" | "equity";
export type LedgerKind = "personal" | "shared";
export type LedgerRole = "owner" | "admin" | "member";

export interface Transaction {
  id: string;
  date: string;
  payee: string;
  category: string;
  account: string;
  accountId: string;
  categoryId: string;
  amountMinorUnits: number;
  kind: TransactionKind;
  receiptAttachmentId?: string;
  receiptName?: string;
  receiptStatus?: string;
  revision: number;
}

export interface Account {
  id: string;
  name: string;
  subtype: string;
  type: AccountType;
  group: string;
  balanceMinorUnits: number;
}

export interface Attachment {
  id: string;
  transactionId: string | null;
  objectKey: string;
  originalFileName: string;
  mimeType: string;
  byteSize: number;
  status: string;
  createdAt: string;
}

export interface Ledger {
  id: string;
  name: string;
  currencyCode: string;
  kind: LedgerKind;
  role: LedgerRole;
}
