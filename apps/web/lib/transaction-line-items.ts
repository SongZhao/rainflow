import { createClient, SupabaseClient } from "@supabase/supabase-js";

export type ReceiptLineItem = {
  description: string;
  amountMinorUnits?: number;
  quantity?: number;
  unitPriceMinorUnits?: number;
};

type StoredLineItem = {
  position: number;
  description: string;
  quantity: number | string | null;
  unit_price_minor_units: number | string | null;
  amount_minor_units: number | string | null;
};

let lineItemClient: SupabaseClient | null | undefined;

function client() {
  if (lineItemClient !== undefined) return lineItemClient;
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim() ?? "";
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim() ?? "";
  lineItemClient = url.startsWith("https://") && key.length > 40 ? createClient(url, key) : null;
  return lineItemClient;
}

export async function saveTransactionLineItems(ledgerID: string, transactionID: string, items: ReceiptLineItem[]) {
  const supabase = client();
  if (!supabase) throw new Error("Supabase is not configured.");
  const payload = items
    .filter((item) => item.description.trim().length > 0)
    .slice(0, 50)
    .map((item) => ({
      description: item.description.trim(),
      quantity: finiteNumber(item.quantity),
      unitPriceMinorUnits: finiteInteger(item.unitPriceMinorUnits),
      amountMinorUnits: finiteInteger(item.amountMinorUnits),
    }));

  const { error } = await supabase.rpc("replace_transaction_line_items", {
    p_ledger_id: ledgerID,
    p_transaction_id: transactionID,
    p_items: payload,
  });
  if (error) throw error;
}

export async function loadTransactionLineItems(transactionID: string) {
  const supabase = client();
  if (!supabase) return [] as ReceiptLineItem[];
  const { data, error } = await supabase
    .from("transaction_line_items")
    .select("position, description, quantity, unit_price_minor_units, amount_minor_units")
    .eq("transaction_id", transactionID)
    .order("position", { ascending: true });
  if (error) throw error;

  return ((data ?? []) as StoredLineItem[]).map((item) => ({
    description: item.description,
    quantity: nullableNumber(item.quantity),
    unitPriceMinorUnits: nullableNumber(item.unit_price_minor_units),
    amountMinorUnits: nullableNumber(item.amount_minor_units),
  }));
}

export function isMissingLineItemSchema(error: unknown) {
  const message = error instanceof Error ? error.message.toLowerCase() : String(error ?? "").toLowerCase();
  return message.includes("transaction_line_items")
    && (message.includes("does not exist") || message.includes("schema cache") || message.includes("could not find"));
}

function finiteNumber(value: number | undefined) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function finiteInteger(value: number | undefined) {
  return typeof value === "number" && Number.isFinite(value) ? Math.round(value) : null;
}

function nullableNumber(value: number | string | null) {
  if (value === null) return undefined;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : undefined;
}
