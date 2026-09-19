import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { mergeReceiptText, parseReceiptText } from "./index.ts";

Deno.test("partial bottom receipt returns incomplete fields without discarding values", () => {
  const parsed = parseReceiptText(`
    ORGANIC BANANAS 2.49
    COFFEE 5.25
    SUBTOTAL 7.74
    TAX 0.77
    TOTAL $8.51
    VISA 8.51
  `);

  assertEquals(parsed.status, "incomplete");
  assertEquals(parsed.fields.amountMinorUnits, 851);
  assertEquals(parsed.fields.lineItems.length, 2);
  assertEquals(parsed.fields.merchant, null);
  assertEquals(parsed.fields.date, null);
  assertEquals(parsed.missingFields, ["merchant", "date"]);
  assertEquals(parsed.recommendedAction, "add_top_photo");
});

Deno.test("complete receipt returns ok", () => {
  const parsed = parseReceiptText(`
    Rainflow Market
    Receipt date 07/29/2026
    Apples 3.99
    TOTAL $3.99
  `);

  assertEquals(parsed.status, "ok");
  assertEquals(parsed.fields.merchant, "Rainflow Market");
  assertEquals(parsed.fields.date, "2026-07-29");
  assertEquals(parsed.fields.amountMinorUnits, 399);
  assertEquals(parsed.missingFields, []);
});

Deno.test("merged multi-photo receipt deduplicates overlapping text", () => {
  const merged = mergeReceiptText([
    "Rainflow Market\nApples 3.99\nSubtotal 3.99",
    "Subtotal 3.99\nTax 0.40\nTotal 4.39",
  ]);

  assertEquals(merged, "Rainflow Market\nApples 3.99\nSubtotal 3.99\nTax 0.40\nTotal 4.39");
});

Deno.test("Ace Hardware receipt uses the tax-inclusive total and real merchant", () => {
  const parsed = parseReceiptText(`
    THANK YOU FOR SHOPPING AT
    Ag Supply Ace Hardware SL
    (425) 224-4273
    Silver Lake Ace, Washington
    Store Number 18471
    08/04/26 6:10PM RYAB 831 SALE
    4020052 1 EA $9.59 EA
    CUPLING BRASS 5/8\"X3/8\"
    $9.59
    SUB-TOTAL:$ 9.59 TAX: $ .95
    TOTAL: $ 10.54
    BC AMT: $ 10.54
    BK CARD#: XXXXXXXXXXXX1795
    AUTH: 01025D AMT: $ 10.54
    Bank card USD$ 10.54
  `);

  assertEquals(parsed.status, "ok");
  assertEquals(parsed.fields.amountMinorUnits, 1054);
  assertEquals(parsed.fields.merchant, "Ag Supply Ace Hardware SL");
  assertEquals(parsed.fields.date, "2026-08-04");
  assertEquals(parsed.fields.lineItems, [
    { description: "CUPLING BRASS 5/8\"X3/8\"", amountMinorUnits: 959 },
  ]);
});


Deno.test("product title is not promoted to merchant when a store name is present", () => {
  const parsed = parseReceiptText(`
    Super Value 50 Piece Brush Set by Artist's Loft™ Necessities
    MICHAELS
    Order date 08/19/2026
    3 x $9.99
    SUBTOTAL $44.97
    DISCOUNT $14.99
    TOTAL $33.16
  `);

  assertEquals(parsed.fields.merchant, "MICHAELS");
  assertEquals(parsed.fields.amountMinorUnits, 3316);
});

Deno.test("product-only receipt fragment leaves merchant for manual review", () => {
  const parsed = parseReceiptText(`
    Super Value 50 Piece Brush Set by Artist's Loft™ Necessities
    Order date 08/19/2026
    3 x $9.99
    SUBTOTAL $29.97
    TOTAL $33.16
  `);

  assertEquals(parsed.fields.merchant, null);
  assertEquals(parsed.missingFields.includes("merchant"), true);
});
