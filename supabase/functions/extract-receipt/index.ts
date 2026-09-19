type ExtractionStatus = "ok" | "incomplete" | "not_configured" | "no_text" | "error";

type ReceiptLineItem = {
  description: string;
  quantity?: number;
  unitPriceMinorUnits?: number;
  amountMinorUnits?: number;
};

type ReceiptFields = {
  merchant?: string | null;
  amountMinorUnits?: number | null;
  subtotalMinorUnits?: number | null;
  taxMinorUnits?: number | null;
  date?: string | null;
  lineItems: ReceiptLineItem[];
};

type ExtractReceiptResponse = {
  status: ExtractionStatus;
  fields: ReceiptFields;
  warnings: string[];
  missingFields?: string[];
  recommendedAction?: "add_top_photo" | "add_clearer_photo" | "review_and_save" | "manual_entry" | "technical_support";
  requestID?: string;
  rawText?: string;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

if (import.meta.main) Deno.serve(handleRequest);

export async function handleRequest(request: Request) {
  const requestID = crypto.randomUUID();
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ status: "error", fields: emptyFields(), warnings: ["Use POST."], requestID }, 405);

  try {
    const user = await requireUser(request.headers.get("authorization") ?? "");
    if (!user?.id) return json({ status: "error", fields: emptyFields(), warnings: ["Sign in before extracting a receipt."], requestID }, 401);

    const body = await request.json();
    const images = normalizeImages(body);
    if (!images[0]) return json({ status: "error", fields: emptyFields(), warnings: ["Add at least one receipt image."], requestID }, 400);
    if (images.some((image) => !/^image\/(jpeg|png|heic|heif)$/.test(image.mimeType))) return json({ status: "error", fields: emptyFields(), warnings: ["Choose JPG, PNG, HEIC, or HEIF receipt images."], requestID }, 400);
    if (images.some((image) => image.imageBase64.length < 64 || image.imageBase64.length > 14_000_000)) return json({ status: "error", fields: emptyFields(), warnings: ["Each receipt image must be smaller than 10 MB."], requestID }, 400);

    const apiKey = Deno.env.get("GOOGLE_VISION_API_KEY")?.trim();
    if (!apiKey) return json({ status: "not_configured", fields: emptyFields(), warnings: ["Receipt OCR is not configured for this environment yet."], missingFields: [], recommendedAction: "manual_entry", requestID });

    const rawTexts = await Promise.all(images.map((image) => readTextWithGoogleVision(image.imageBase64, apiKey, requestID)));
    const rawText = mergeReceiptText(rawTexts);
    if (!rawText.trim()) return json({ status: "no_text", fields: emptyFields(), warnings: ["No readable receipt text was found."], missingFields: ["merchant", "amount", "date"], recommendedAction: "add_clearer_photo", requestID });

    const parsed = parseReceiptText(rawText);
    logReceiptEvent("parsed", requestID, { status: parsed.status, imageCount: images.length, itemCount: parsed.fields.lineItems.length, missingFields: parsed.missingFields });
    return json({ ...parsed, requestID, rawText: rawText.slice(0, 12_000) });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Receipt OCR failed.";
    logReceiptEvent("technical_error", requestID, { message: sanitizeLogMessage(message) });
    return json({ status: "error", fields: emptyFields(), warnings: [message], recommendedAction: "technical_support", requestID }, 500);
  }
}

async function requireUser(authHeader: string) {
  if (!authHeader.toLowerCase().startsWith("bearer ")) return null;
  const supabaseURL = Deno.env.get("SUPABASE_URL")?.replace(/\/$/, "");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  if (!supabaseURL || !anonKey) throw new Error("Supabase function environment is incomplete.");
  const response = await fetch(`${supabaseURL}/auth/v1/user`, { headers: { authorization: authHeader, apikey: anonKey } });
  return response.ok ? response.json() : null;
}

async function readTextWithGoogleVision(imageBase64: string, apiKey: string, requestID: string) {
  const response = await fetch(`https://vision.googleapis.com/v1/images:annotate?key=${encodeURIComponent(apiKey)}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ requests: [{ image: { content: imageBase64 }, features: [{ type: "TEXT_DETECTION", maxResults: 1 }] }] }),
  });
  const result = await response.json().catch(() => null);
  if (!response.ok) {
    const message = result?.error?.message ?? "Google Vision OCR request failed.";
    logReceiptEvent("provider_error", requestID, { status: response.status, message: sanitizeLogMessage(message) });
    throw new Error(message);
  }
  const first = result?.responses?.[0];
  if (first?.error?.message) throw new Error(first.error.message);
  return String(first?.fullTextAnnotation?.text ?? first?.textAnnotations?.[0]?.description ?? "");
}

export function parseReceiptText(rawText: string) {
  const lines = rawText.split(/\r?\n/).map((line) => line.replace(/\s+/g, " ").trim()).filter(Boolean);
  const warnings: string[] = [];
  const amount = chooseAmount(lines);
  const subtotal = chooseLabeledAmount(lines, /\bsub[- ]?total\b/i);
  const tax = chooseLabeledAmount(lines, /\btax\b/i);
  const date = chooseDate(lines);
  const lineItems = chooseLineItems(lines, subtotal ?? amount?.amountMinorUnits ?? null);
  const merchant = chooseMerchant(lines, lineItems);
  const missingFields = [merchant ? null : "merchant", amount ? null : "amount", date ? null : "date"].filter((item): item is string => Boolean(item));

  if (!amount) warnings.push("No high-confidence receipt total was found.");
  if (!date) warnings.push("No receipt transaction date was found.");
  if (!merchant) warnings.push("No merchant name was found.");
  if (lineItems.length === 0) warnings.push("No product line items were confidently identified.");
  if (subtotal && lineItems.length > 0) {
    const itemSum = lineItems.reduce((sum, item) => sum + (item.amountMinorUnits ?? 0), 0);
    if (Math.abs(itemSum - subtotal) > 2) warnings.push("Line items do not exactly match the receipt subtotal; review the item list.");
  }
  if (missingFields.includes("merchant") || missingFields.includes("date")) warnings.push("This looks like a partial receipt. Add the top section or fill the missing fields manually.");

  return {
    status: missingFields.length > 0 ? "incomplete" as const : "ok" as const,
    fields: { merchant: merchant ?? null, amountMinorUnits: amount?.amountMinorUnits ?? null, subtotalMinorUnits: subtotal, taxMinorUnits: tax, date: date ?? null, lineItems },
    missingFields,
    recommendedAction: missingFields.includes("merchant") || missingFields.includes("date") ? "add_top_photo" as const : "review_and_save" as const,
    warnings,
  };
}

function normalizeImages(body: unknown) {
  const candidate = body as { imageBase64?: unknown; mimeType?: unknown; images?: Array<{ imageBase64?: unknown; mimeType?: unknown }> } | null;
  if (Array.isArray(candidate?.images)) return candidate.images.map((image) => ({ imageBase64: typeof image.imageBase64 === "string" ? image.imageBase64 : "", mimeType: typeof image.mimeType === "string" ? image.mimeType : "image/jpeg" }));
  return [{ imageBase64: typeof candidate?.imageBase64 === "string" ? candidate.imageBase64 : "", mimeType: typeof candidate?.mimeType === "string" ? candidate.mimeType : "image/jpeg" }];
}

export function mergeReceiptText(parts: string[]) {
  const seen = new Set<string>();
  const merged: string[] = [];
  for (const part of parts) for (const line of part.split(/\r?\n/)) {
    const normalized = line.replace(/\s+/g, " ").trim();
    if (!normalized || seen.has(normalized.toLowerCase())) continue;
    seen.add(normalized.toLowerCase());
    merged.push(normalized);
  }
  return merged.join("\n");
}

function moneyValues(line: string) {
  return [...line.matchAll(/(?:[$€£]\s*)?((?:\d{1,3}(?:,\d{3})+|\d+)\.\d{2})\b/g)].map((match) => ({ value: Math.round(Number(match[1].replace(/,/g, "")) * 100), index: match.index ?? 0, raw: match[0] }));
}

function chooseLabeledAmount(lines: string[], label: RegExp) {
  for (const line of lines) {
    if (!label.test(line)) continue;
    const values = moneyValues(line);
    if (values.length) return values.at(-1)!.value;
  }
  return null;
}

function chooseAmount(lines: string[]) {
  const candidates: Array<{ amountMinorUnits: number; score: number }> = [];
  lines.forEach((line, index) => {
    if (isIgnoredAmountLine(line)) return;
    for (const match of moneyValues(line)) {
      if (match.value <= 0) continue;
      let score = amountContextScore(line, match.index, match.raw);
      if (index > lines.length * 0.55) score += 1;
      candidates.push({ amountMinorUnits: match.value, score });
    }
  });
  candidates.sort((a, b) => b.score - a.score || b.amountMinorUnits - a.amountMinorUnits);
  return candidates[0] && candidates[0].score >= 2 ? candidates[0] : null;
}

function amountContextScore(line: string, amountIndex: number, matchedAmount: string) {
  let score = /[$€£]/.test(matchedAmount) ? 3 : 0;
  const prefix = line.slice(0, amountIndex).toLowerCase();
  const contexts = [
    { pattern: /\bgrand total\b/g, score: 18 }, { pattern: /\b(?:total due|amount due|amount charged|total charged|transaction amount)\b/g, score: 17 },
    { pattern: /(?<!sub )(?<!sub-)\btotal\b/g, score: 15 }, { pattern: /\b(?:bc\s*)?amt\b/g, score: 12 },
    { pattern: /\b(?:amount|paid|payment|tendered)\b/g, score: 10 }, { pattern: /\b(?:sub[- ]?total|tax|tip|fee|discount|change|cashback)\b/g, score: -12 },
  ];
  let nearestPosition = -1, nearestScore = 0;
  for (const context of contexts) for (const label of prefix.matchAll(context.pattern)) if ((label.index ?? -1) >= nearestPosition) { nearestPosition = label.index ?? -1; nearestScore = context.score; }
  return score + nearestScore;
}

function chooseDate(lines: string[]) {
  const candidates: Array<{ date: string; score: number }> = [];
  lines.forEach((line) => {
    if (/\b(posted|settled|reference|card|expires|expiration)\b/i.test(line)) return;
    const lower = line.toLowerCase();
    const score = /\b(transaction date|purchase date|receipt date|sale date)\b/.test(lower) ? 6 : /\bdate\b/.test(lower) ? 3 : 1;
    for (const date of extractDates(line)) candidates.push({ date, score });
  });
  candidates.sort((a, b) => b.score - a.score);
  return candidates[0]?.date;
}

function chooseMerchant(lines: string[], lineItems: ReceiptLineItem[]) {
  const topLines = lines.slice(0, 16);
  const itemDescriptions = lineItems
    .map((item) => normalizeComparableText(item.description))
    .filter(Boolean);

  for (let index = 0; index < topLines.length; index += 1) {
    if (!/\b(?:thank you for (?:shopping|your purchase)(?: at)?|welcome to|purchased at|sold by)\b/i.test(topLines[index])) continue;
    for (let candidateIndex = index + 1; candidateIndex < Math.min(index + 4, topLines.length); candidateIndex += 1) {
      const candidate = topLines[candidateIndex];
      if (isMerchantCandidate(candidate, itemDescriptions)) return normalizeMerchant(candidate);
    }
  }

  for (const line of topLines) {
    const known = knownMerchantName(line);
    if (known && isMerchantCandidate(line, itemDescriptions)) return known;
  }

  const candidates = topLines
    .map((line, index) => ({ line, index, score: merchantCandidateScore(line, index) }))
    .filter((candidate) =>
      candidate.score >= 8
      && isMerchantCandidate(candidate.line, itemDescriptions)
      && hasMerchantEvidence(candidate.line, candidate.index, topLines)
    )
    .sort((a, b) => b.score - a.score);

  return candidates[0] ? normalizeMerchant(candidates[0].line) : undefined;
}

function knownMerchantName(line: string) {
  const normalized = normalizeComparableText(line);
  if (/^michaels(?: store(?: \d+)?)?$/.test(normalized)) return "Michaels";
  if (/^daiso(?: japan)?(?: \d+)?$/.test(normalized)) return "Daiso";
  if (/^target(?: store)?(?: \d+)?$/.test(normalized)) return "Target";
  if (/^(?:the )?ups store(?: \d+)?$/.test(normalized)) return "The UPS Store";
  return null;
}

function hasMerchantEvidence(line: string, index: number, topLines: string[]) {
  if (knownMerchantName(line)) return true;
  if (/\b(?:hardware|supply|market|mart|store|pharmacy|cafe|coffee|restaurant|grocery|foods|auto|studio|company|co\.?|inc\.?|llc)\b/i.test(line)) return true;
  if (/^[A-Z0-9 &'’.-]{3,32}$/.test(line) && /[A-Z]{3}/.test(line)) return true;

  const words = normalizeComparableText(line).split(" ").filter(Boolean);
  if (words.length < 2 || index > 4) return false;

  const nearby = topLines.slice(index + 1, Math.min(index + 4, topLines.length)).join(" ");
  return /\b(?:store|location)\s*(?:no|number|#)?\s*\d+\b/i.test(nearby)
    || /\(?\d{3}\)?[\s.-]\d{3}[\s.-]\d{4}/.test(nearby)
    || /\b\d{2,6}\s+[A-Za-z0-9 .'-]+\s(?:st|street|ave|avenue|rd|road|blvd|boulevard|dr|drive|way|ln|lane)\b/i.test(nearby);
}

function merchantCandidateScore(line: string, index: number) {
  let score = 16 - index;
  if (/\b(?:hardware|supply|market|mart|store|pharmacy|cafe|coffee|restaurant|grocery|foods|auto|studio|company|co\.?|inc\.?|llc)\b/i.test(line)) score += 6;
  if (/^[A-Z0-9 &'’.-]{3,32}$/.test(line) && /[A-Z]{3}/.test(line)) score += 5;
  if (line.length <= 32) score += 2;
  if (looksLikeProductDescription(line)) score -= 20;
  return score;
}

function isMerchantCandidate(line: string, itemDescriptions: string[] = []) {
  if (line.length < 2 || line.length > 64 || !/[a-z]/i.test(line)) return false;
  if (isIgnoredAmountLine(line) || extractDates(line).length || /(?:[$€£]?\s*(?:\d+)?\.\d{2})/.test(line)) return false;
  if (/\b(?:thank you|shopping at|welcome|receipt|invoice|transaction|sale|type|method|category|reference|store number|customer|subtotal|total|tax|date|time|terminal|register|cashier|auth|approval|card|visa|mastercard|contactless|order summary|item description|qty|quantity)\b/i.test(line)) return false;
  if (/https?:\/\/|www\.|\S+@\S+/i.test(line) || /^\(?\d{3}\)?[\s.-]\d{3}[\s.-]\d{4}$/.test(line) || /^[\d\s#*:/.,-]+$/.test(line)) return false;
  if (looksLikeProductDescription(line)) return false;

  const normalized = normalizeComparableText(line);
  if (itemDescriptions.some((item) =>
    normalized === item
    || (normalized.length >= 12 && item.length >= 12 && (normalized.includes(item) || item.includes(normalized)))
  )) return false;

  return true;
}

function looksLikeProductDescription(line: string) {
  if (/\b\d+(?:\.\d+)?\s*(?:piece|pieces|pc|pcs|pack|packs|ct|count|oz|lb|lbs|ml|cm|mm|inch|inches)\b/i.test(line)) return true;
  if (/\bby\s+[a-z0-9][a-z0-9 &'’™®.-]{1,40}$/i.test(line)) return true;
  if (/[™®]/.test(line) && /\b(?:set|canvas|brush|kit|mix|stem|bush|flower|pack|bottle|shirt|shoe)\b/i.test(line)) return true;
  return false;
}

function normalizeComparableText(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
}

function chooseLineItems(lines: string[], expectedSubtotal: number | null): ReceiptLineItem[] {
  const summary = /\b(?:grand total|total|sub[- ]?total|tax|tip|fee|discount|payment|paid|change|balance|reward|points|reference|card|auth|amt|amount|tender|cash|visa|mastercard)\b/i;
  const items: ReceiptLineItem[] = [];
  const seen = new Set<string>();

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    if (summary.test(line)) continue;
    const values = moneyValues(line);
    if (!values.length) continue;

    const last = values.at(-1)!;
    let description = line.slice(0, last.index).replace(/^\s*\d{5,}\s+/, "").trim();
    let quantity: number | undefined;
    let unitPriceMinorUnits: number | undefined;

    const qtyUnit = description.match(/^(.*?)(?:\s+)?(\d+(?:\.\d+)?)\s*(?:x|@)\s*$/i);
    if (qtyUnit) {
      description = qtyUnit[1].trim();
      quantity = Number(qtyUnit[2]);
      unitPriceMinorUnits = last.value;
    }

    const aceQty = description.match(/^(\d+(?:\.\d+)?)\s*(?:EA|EACH)$/i);
    if (aceQty) {
      quantity = Number(aceQty[1]);
      unitPriceMinorUnits = last.value;
      const next = lines[index + 1];
      if (next && isLineItemDescription(next)) description = next.trim();
    }

    if (!description || isQuantityOnlyDescription(description)) {
      const previous = lines[index - 1];
      const next = lines[index + 1];
      if (previous && isLineItemDescription(previous)) description = previous.trim();
      else if (next && isLineItemDescription(next)) description = next.trim();
    }

    description = description.replace(/^\d{5,}\s+/, "").replace(/\s+(?:EA|EACH)$/i, "").trim();
    if (!isLineItemDescription(description)) continue;

    let amountMinorUnits = last.value;
    const next = lines[index + 1];
    if (next && !summary.test(next)) {
      const nextValues = moneyValues(next);
      if (nextValues.length === 1 && next.trim().match(/^(?:[$€£]\s*)?\d[\d,]*\.\d{2}$/)) amountMinorUnits = nextValues[0].value;
    }
    if (expectedSubtotal && amountMinorUnits > expectedSubtotal) continue;

    const key = `${description.toLowerCase()}|${amountMinorUnits}`;
    if (seen.has(key)) continue;
    seen.add(key);
    items.push({ description, quantity, unitPriceMinorUnits, amountMinorUnits });
    if (items.length >= 30) break;
  }
  return items;
}

function isQuantityOnlyDescription(value: string) { return /^(?:\d+(?:\.\d+)?\s*)?(?:ea|each|x)?$/i.test(value.trim()); }
function isLineItemDescription(line: string) {
  if (line.length < 2 || line.length > 90 || !/[a-z]/i.test(line)) return false;
  if (/(?:[$€£]?\s*(?:\d+)?\.\d{2})/.test(line)) return false;
  if (/\b(?:grand total|total|sub[- ]?total|tax|tip|fee|discount|payment|paid|change|balance|reference|card|auth|amt|amount|sale|store|customer|cashier)\b/i.test(line)) return false;
  return true;
}
function isIgnoredAmountLine(line: string) { return /\b(points?|rewards?|earned|miles?|reference|ref(?:erence)? number|card number|account number|approval|authorization|auth|balance|available|cash back|cashback)\b/i.test(line); }

function extractDates(line: string) {
  const results: string[] = [];
  for (const match of line.matchAll(/\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\.?\s+(\d{1,2}),?\s+(\d{4})\b/gi)) {
    const month = monthNumber(match[1]), day = Number(match[2]), year = Number(match[3]);
    if (isValidDate(year, month, day)) results.push(toISODate(year, month, day));
  }
  for (const match of line.matchAll(/\b(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})\b/g)) {
    const month = Number(match[1]), day = Number(match[2]), year = Number(match[3].length === 2 ? `20${match[3]}` : match[3]);
    if (isValidDate(year, month, day)) results.push(toISODate(year, month, day));
  }
  return [...new Set(results)];
}
function monthNumber(value: string) { return ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"].indexOf(value.slice(0, 3).toLowerCase()) + 1; }
function isValidDate(year: number, month: number, day: number) { if (year < 2000 || year > 2100 || month < 1 || month > 12 || day < 1 || day > 31) return false; const date = new Date(Date.UTC(year, month - 1, day)); return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day; }
function toISODate(year: number, month: number, day: number) { return `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`; }
function normalizeMerchant(value: string) { return value.replace(/^[^a-zA-Z0-9]+|[^a-zA-Z0-9]+$/g, "").replace(/\s{2,}/g, " ").trim(); }
function emptyFields(): ReceiptFields { return { merchant: null, amountMinorUnits: null, subtotalMinorUnits: null, taxMinorUnits: null, date: null, lineItems: [] }; }
function json(body: ExtractReceiptResponse, status = 200) { return Response.json(body, { status, headers: { ...corsHeaders, "content-type": "application/json" } }); }
function logReceiptEvent(event: string, requestID: string, details: Record<string, unknown> = {}) { console.log(JSON.stringify({ event: `receipt_ocr_${event}`, requestID, ...details })); }
function sanitizeLogMessage(value: string) { return value.replace(/key=[^&\s]+/gi, "key=[redacted]").slice(0, 240); }
