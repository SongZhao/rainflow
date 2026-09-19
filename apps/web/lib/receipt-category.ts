import type { Account, TransactionKind } from "@/lib/types";
import type { ReceiptLineItem } from "@/lib/transaction-line-items";

export type CategorySuggestion = { account: Account; reason: string };

export function suggestExpenseCategory(
  merchant: string,
  items: ReceiptLineItem[],
  categories: Account[],
  transactions: Array<{ payee: string; categoryId: string; kind: TransactionKind }>
): CategorySuggestion | null {
  const merchantKey = canonicalMerchant(merchant);

  if (merchantKey) {
    const previous = transactions.find((transaction) =>
      transaction.kind === "expense"
      && canonicalMerchant(transaction.payee) === merchantKey
      && categories.some((category) => category.id === transaction.categoryId)
    );
    const account = previous ? categories.find((category) => category.id === previous.categoryId) : undefined;
    if (account) return { account, reason: "Auto-selected from your previous transactions with this merchant." };
  }

  const text = normalizeWords([merchant, ...items.map((item) => item.description)].join(" "));
  const rules: Array<{ aliases: string[]; words: RegExp }> = [
    {
      aliases: ["class material supplies"],
      words: /\b(michaels|daiso|artist s loft|art supply|class material|canvas|paint brush|brush set|craft|floral|flower stem|skewer|toothpick)\b/,
    },
    {
      aliases: ["office supplies"],
      words: /\b(staples|office depot|office max|ups store|printing|print color|copy service|printer ink|toner|office paper|shipping label|envelope)\b/,
    },
    {
      aliases: ["employee benefits"],
      words: /\b(employee benefit|employee meal|staff meal|team lunch|team dinner|staff lunch|staff dinner)\b/,
    },
    {
      aliases: ["business operation"],
      words: /\b(business license|registered agent|bookkeeping|accounting service|software subscription|domain renewal|web hosting|cloudflare|resend|supabase)\b/,
    },
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

  const fallback = findCategory(categories, ["other expenses"]);
  if (fallback) return { account: fallback, reason: "Auto-selected as Other Expenses. Review if needed." };

  return null;
}

export function canonicalMerchant(value: string) {
  const normalized = normalizeWords(value);
  if (!normalized) return "";

  if (/^michaels(?: store(?: \d+)?)?$/.test(normalized)) return "michaels";
  if (/^daiso(?: japan)?(?: \d+)?$/.test(normalized)) return "daiso";
  if (/^target(?: store)?(?: \d+)?$/.test(normalized)) return "target";
  if (/^(?:the )?ups store(?: \d+)?$/.test(normalized)) return "ups store";

  return normalized
    .replace(/\b(store|location)\s+(?:no|number\s+)?\d+\b/g, "$1")
    .replace(/\s+\d{3,}$/g, "")
    .trim();
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
