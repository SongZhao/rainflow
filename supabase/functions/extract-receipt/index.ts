type ExtractionStatus = "ok" | "incomplete" | "not_configured" | "no_text" | "error";

type ReceiptLineItem = {
  description: string;
  amountMinorUnits?: number;
};

type ReceiptFields = {
  merchant?: string | null;
  amountMinorUnits?: number | null;
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

if (import.meta.main) {
  Deno.serve(handleRequest);
}

export async function handleRequest(request: Request) {
  const requestID = crypto.randomUUID();
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ status: "error", fields: emptyFields(), warnings: ["Use POST."], requestID }, 405);
  }

  try {
    const user = await requireUser(request.headers.get("authorization") ?? "");
    if (!user?.id) {
      logReceiptEvent("auth_failed", requestID);
      return json({ status: "error", fields: emptyFields(), warnings: ["Sign in before extracting a receipt."], requestID }, 401);
    }

    const body = await request.json();
    const images = normalizeImages(body);
    const firstImage = images[0];

    if (images.length === 0 || !firstImage) {
      return json({ status: "error", fields: emptyFields(), warnings: ["Add at least one receipt image."], requestID }, 400);
    }
    if (images.some((image) => !/^image\/(jpeg|png|heic|heif)$/.test(image.mimeType))) {
      return json({ status: "error", fields: emptyFields(), warnings: ["Choose JPG, PNG, HEIC, or HEIF receipt images."], requestID }, 400);
    }
    if (images.some((image) => image.imageBase64.length < 64 || image.imageBase64.length > 14_000_000)) {
      return json({ status: "error", fields: emptyFields(), warnings: ["Each receipt image must be smaller than 10 MB."], requestID }, 400);
    }

    const googleVisionAPIKey = Deno.env.get("GOOGLE_VISION_API_KEY")?.trim();
    if (!googleVisionAPIKey) {
      return json({
        status: "not_configured",
        fields: emptyFields(),
        warnings: ["Receipt OCR is not configured for this environment yet."],
        missingFields: [],
        recommendedAction: "manual_entry",
        requestID,
      });
    }

    const rawTexts = await Promise.all(images.map((image) => readTextWithGoogleVision(image.imageBase64, googleVisionAPIKey, requestID)));
    const rawText = mergeReceiptText(rawTexts);
    if (!rawText.trim()) {
      return json({
        status: "no_text",
        fields: emptyFields(),
        warnings: ["No readable receipt text was found."],
        missingFields: ["merchant", "amount", "date"],
        recommendedAction: "add_clearer_photo",
        requestID,
      });
    }

    const parsed = parseReceiptText(rawText);
    logReceiptEvent("parsed", requestID, {
      status: parsed.status,
      imageCount: images.length,
      missingFields: parsed.missingFields,
      warningCount: parsed.warnings.length,
    });
    return json({
      status: parsed.status,
      fields: parsed.fields,
      warnings: parsed.warnings,
      missingFields: parsed.missingFields,
      recommendedAction: parsed.recommendedAction,
      requestID,
      rawText: rawText.slice(0, 12_000),
    });
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

  const response = await fetch(`${supabaseURL}/auth/v1/user`, {
    headers: {
      authorization: authHeader,
      apikey: anonKey,
    },
  });
  if (!response.ok) return null;
  return response.json();
}

async function readTextWithGoogleVision(imageBase64: string, apiKey: string, requestID: string) {
  const response = await fetch(`https://vision.googleapis.com/v1/images:annotate?key=${encodeURIComponent(apiKey)}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      requests: [
        {
          image: { content: imageBase64 },
          features: [{ type: "TEXT_DETECTION", maxResults: 1 }],
        },
      ],
    }),
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
  const lines = rawText
    .split(/\r?\n/)
    .map((line) => line.replace(/\s+/g, " ").trim())
    .filter(Boolean);
  const warnings: string[] = [];
  const amount = chooseAmount(lines);
  const date = chooseDate(lines);
  const merchant = chooseMerchant(lines);
  const lineItems = chooseLineItems(lines);
  const missingFields = [
    merchant ? null : "merchant",
    amount ? null : "amount",
    date ? null : "date",
  ].filter((item): item is string => Boolean(item));

  if (!amount) warnings.push("No high-confidence receipt total was found.");
  if (!date) warnings.push("No receipt transaction date was found.");
  if (!merchant) warnings.push("No merchant name was found.");
  if (missingFields.includes("merchant") || missingFields.includes("date")) {
    warnings.push("This looks like a partial receipt. Add the top section or fill the missing fields manually.");
  }

  return {
    status: missingFields.length > 0 ? "incomplete" as const : "ok" as const,
    fields: {
      merchant: merchant ?? null,
      amountMinorUnits: amount?.amountMinorUnits ?? null,
      date: date ?? null,
      lineItems,
    },
    missingFields,
    recommendedAction: missingFields.includes("merchant") || missingFields.includes("date") ? "add_top_photo" as const : "review_and_save" as const,
    warnings,
  };
}

function normalizeImages(body: unknown) {
  const candidate = body as {
    imageBase64?: unknown;
    mimeType?: unknown;
    images?: Array<{ imageBase64?: unknown; mimeType?: unknown }>;
  } | null;
  if (Array.isArray(candidate?.images)) {
    return candidate.images.map((image) => ({
      imageBase64: typeof image.imageBase64 === "string" ? image.imageBase64 : "",
      mimeType: typeof image.mimeType === "string" ? image.mimeType : "image/jpeg",
    }));
  }
  return [{
    imageBase64: typeof candidate?.imageBase64 === "string" ? candidate.imageBase64 : "",
    mimeType: typeof candidate?.mimeType === "string" ? candidate.mimeType : "image/jpeg",
  }];
}

export function mergeReceiptText(parts: string[]) {
  const seen = new Set<string>();
  const merged: string[] = [];
  for (const part of parts) {
    for (const line of part.split(/\r?\n/)) {
      const normalized = line.replace(/\s+/g, " ").trim();
      if (!normalized || seen.has(normalized.toLowerCase())) continue;
      seen.add(normalized.toLowerCase());
      merged.push(normalized);
    }
  }
  return merged.join("\n");
}

function chooseAmount(lines: string[]) {
  const candidates: Array<{ amountMinorUnits: number; score: number; line: string }> = [];
  lines.forEach((line, index) => {
    if (isIgnoredAmountLine(line)) return;
    for (const match of line.matchAll(/(?:[$€£]\s*)?((?:(?:\d{1,3}(?:,\d{3})+|\d+)?\.\d{2}))\b/g)) {
      const amountMinorUnits = Math.round(Number(match[1].replace(/,/g, "")) * 100);
      if (!Number.isFinite(amountMinorUnits) || amountMinorUnits <= 0) continue;
      let score = amountContextScore(line, match.index ?? 0, match[0]);
      if (index > lines.length * 0.55) score += 1;
      candidates.push({ amountMinorUnits, score, line });
    }
  });

  candidates.sort((a, b) => b.score - a.score || b.amountMinorUnits - a.amountMinorUnits);
  const winner = candidates[0];
  if (!winner || winner.score < 2) return null;
  return winner;
}

function amountContextScore(line: string, amountIndex: number, matchedAmount: string) {
  let score = /[$€£]/.test(matchedAmount) ? 3 : 0;
  const prefix = line.slice(0, amountIndex).toLowerCase();
  const contexts: Array<{ pattern: RegExp; score: number }> = [
    { pattern: /\bgrand total\b/g, score: 18 },
    { pattern: /\b(?:total due|amount due|amount charged|total charged|transaction amount)\b/g, score: 17 },
    { pattern: /(?<!sub )(?<!sub-)\btotal\b/g, score: 15 },
    { pattern: /\b(?:bc\s*)?amt\b/g, score: 12 },
    { pattern: /\b(?:amount|paid|payment|tendered)\b/g, score: 10 },
    { pattern: /\b(?:sub[- ]?total|tax|tip|fee|discount|change|cashback)\b/g, score: -12 },
  ];

  let nearestPosition = -1;
  let nearestScore = 0;
  for (const context of contexts) {
    for (const label of prefix.matchAll(context.pattern)) {
      const position = label.index ?? -1;
      if (position >= nearestPosition) {
        nearestPosition = position;
        nearestScore = context.score;
      }
    }
  }

  score += nearestScore;
  return score;
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

function chooseMerchant(lines: string[]) {
  const topLines = lines.slice(0, 12);

  for (let index = 0; index < topLines.length; index += 1) {
    if (!/\b(?:thank you for (?:shopping|your purchase)(?: at)?|welcome to|purchased at|sold by)\b/i.test(topLines[index])) continue;
    for (let candidateIndex = index + 1; candidateIndex < Math.min(index + 4, topLines.length); candidateIndex += 1) {
      const candidate = topLines[candidateIndex];
      if (isMerchantCandidate(candidate)) return normalizeMerchant(candidate);
    }
  }

  const candidates = topLines
    .map((line, index) => ({
      line,
      score: 20 - index
        + (/\b(?:hardware|supply|market|mart|store|pharmacy|cafe|coffee|restaurant|grocery|foods|auto|ace)\b/i.test(line) ? 4 : 0)
        - (/,\s*[a-z]{2,}(?:\s|$)/i.test(line) ? 2 : 0),
    }))
    .filter((candidate) => isMerchantCandidate(candidate.line))
    .sort((a, b) => b.score - a.score);

  return candidates[0] ? normalizeMerchant(candidates[0].line) : undefined;
}

function isMerchantCandidate(line: string) {
  if (line.length < 2 || line.length > 64) return false;
  if (!/[a-z]/i.test(line)) return false;
  if (isIgnoredAmountLine(line) || extractDates(line).length > 0) return false;
  if (/(?:[$€£]?\s*(?:\d+)?\.\d{2})/.test(line)) return false;
  if (/\b(?:thank you|shopping at|welcome|receipt|invoice|transaction|sale|type|method|category|reference|store number|customer|subtotal|total|tax|date|time|terminal|register|cashier|auth|approval|card|visa|mastercard|contactless)\b/i.test(line)) return false;
  if (/https?:\/\/|www\.|\S+@\S+/i.test(line)) return false;
  if (/^\(?\d{3}\)?[\s.-]\d{3}[\s.-]\d{4}$/.test(line)) return false;
  if (/^[\d\s#*:/.,-]+$/.test(line)) return false;
  return true;
}

function chooseLineItems(lines: string[]): ReceiptLineItem[] {
  const summaryWords = /\b(?:grand total|total|sub[- ]?total|tax|tip|fee|discount|payment|paid|change|balance|reward|points|reference|card|auth|amt|amount|tender)\b/i;
  const items: ReceiptLineItem[] = [];
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    if (summaryWords.test(line)) continue;
    const match = line.match(/(.{2,80}?)\s+[$€£]?\s*((?:\d{1,3}(?:,\d{3})+|\d+)\.\d{2})\b/);
    if (!match) continue;
    const amountMinorUnits = Math.round(Number(match[2].replace(/,/g, "")) * 100);
    if (!Number.isFinite(amountMinorUnits) || amountMinorUnits <= 0) continue;

    let description = match[1].trim().replace(/^\d{5,}\s+/, "").trim();
    const nextLine = lines[index + 1];
    if (isQuantityOnlyDescription(description) && nextLine && isLineItemDescription(nextLine)) {
      description = nextLine;
    }
    if (description.length < 2) continue;

    items.push({ description, amountMinorUnits });
    if (items.length >= 12) break;
  }
  return items;
}

function isQuantityOnlyDescription(value: string) {
  return /^(?:\d+\s*)?(?:ea|each|x)?$/i.test(value.trim());
}

function isLineItemDescription(line: string) {
  if (line.length < 2 || line.length > 90) return false;
  if (!/[a-z]/i.test(line)) return false;
  if (/(?:[$€£]?\s*(?:\d+)?\.\d{2})/.test(line)) return false;
  if (/\b(?:grand total|total|sub[- ]?total|tax|tip|fee|discount|payment|paid|change|balance|reference|card|auth|amt|amount)\b/i.test(line)) return false;
  return true;
}

function isIgnoredAmountLine(line: string) {
  return /\b(points?|rewards?|earned|miles?|reference|ref(?:erence)? number|card number|account number|approval|authorization|auth|balance|available|cash back|cashback)\b/i.test(line);
}

function extractDates(line: string) {
  const results: string[] = [];
  for (const match of line.matchAll(/\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\.?\s+(\d{1,2}),?\s+(\d{4})\b/gi)) {
    const month = monthNumber(match[1]);
    const day = Number(match[2]);
    const year = Number(match[3]);
    if (isValidDate(year, month, day)) results.push(toISODate(year, month, day));
  }
  for (const match of line.matchAll(/\b(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})\b/g)) {
    const month = Number(match[1]);
    const day = Number(match[2]);
    const year = Number(match[3].length === 2 ? `20${match[3]}` : match[3]);
    if (isValidDate(year, month, day)) results.push(toISODate(year, month, day));
  }
  return [...new Set(results)];
}

function monthNumber(value: string) {
  return ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"].indexOf(value.slice(0, 3).toLowerCase()) + 1;
}

function isValidDate(year: number, month: number, day: number) {
  if (year < 2000 || year > 2100 || month < 1 || month > 12 || day < 1 || day > 31) return false;
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

function toISODate(year: number, month: number, day: number) {
  return `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

function normalizeMerchant(value: string) {
  return value
    .replace(/^[^a-zA-Z0-9]+|[^a-zA-Z0-9]+$/g, "")
    .replace(/\s{2,}/g, " ")
    .trim();
}

function emptyFields(): ReceiptFields {
  return { merchant: null, amountMinorUnits: null, date: null, lineItems: [] };
}

function json(body: ExtractReceiptResponse, status = 200) {
  return Response.json(body, {
    status,
    headers: {
      ...corsHeaders,
      "content-type": "application/json",
    },
  });
}

function logReceiptEvent(event: string, requestID: string, details: Record<string, unknown> = {}) {
  console.log(JSON.stringify({ event: `receipt_ocr_${event}`, requestID, ...details }));
}

function sanitizeLogMessage(value: string) {
  return value.replace(/key=[^&\s]+/gi, "key=[redacted]").slice(0, 240);
}
