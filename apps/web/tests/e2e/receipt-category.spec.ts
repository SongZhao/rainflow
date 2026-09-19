import { expect, test } from "@playwright/test";
import { canonicalMerchant, frequentExpenseCategories, suggestExpenseCategory } from "../../lib/receipt-category";
import type { Account, TransactionKind } from "../../lib/types";

function expenseCategory(id: string, name: string): Account {
  return {
    id,
    name,
    subtype: "Expense",
    type: "expense",
    group: "Expenses",
    balanceMinorUnits: 0,
  };
}

const categories = [
  expenseCategory("class-material", "Class material supplies"),
  expenseCategory("office", "Office supplies"),
  expenseCategory("employee-benefits", "Employee benefits"),
  expenseCategory("business-operation", "Business operation"),
  expenseCategory("dining", "Dining"),
  expenseCategory("transportation", "Transportation"),
  expenseCategory("shopping", "Shopping"),
  expenseCategory("other", "Other Expenses"),
];

const history: Array<{ payee: string; categoryId: string; kind: TransactionKind }> = [
  { payee: "MICHAELS STORE #6713", categoryId: "class-material", kind: "expense" },
  { payee: "Daiso", categoryId: "class-material", kind: "expense" },
  { payee: "Target", categoryId: "employee-benefits", kind: "expense" },
  { payee: "Pho Tick Tock", categoryId: "employee-benefits", kind: "expense" },
  { payee: "Gardenia Los Gatos", categoryId: "employee-benefits", kind: "expense" },
  { payee: "The UPS Store #5833", categoryId: "office", kind: "expense" },
];

test("canonicalizes store-number merchant variants", () => {
  expect(canonicalMerchant("Michaels")).toBe("michaels");
  expect(canonicalMerchant("MICHAELS STORE #9999")).toBe("michaels");
  expect(canonicalMerchant("The UPS Store #9999")).toBe("ups store");
});

test("confirmed merchant history wins over generic receipt rules", () => {
  expect(suggestExpenseCategory("Target", [{ description: "Simply Saline" }], categories, history)?.account.name)
    .toBe("Employee benefits");
  expect(suggestExpenseCategory("Pho Tick Tock", [{ description: "Pho" }], categories, history)?.account.name)
    .toBe("Employee benefits");
  expect(suggestExpenseCategory("Gardenia Los Gatos", [{ description: "French Omelette" }], categories, history)?.account.name)
    .toBe("Employee benefits");
});

test("business receipt rules use the new categories when merchant history is absent", () => {
  expect(suggestExpenseCategory("New Craft Shop", [{ description: "Artist's Loft Canvas" }], categories, [])?.account.name)
    .toBe("Class material supplies");
  expect(suggestExpenseCategory("Copy Center", [{ description: "Print Color 8.5X11" }], categories, [])?.account.name)
    .toBe("Office supplies");
  expect(suggestExpenseCategory("Cloudflare", [], categories, [])?.account.name)
    .toBe("Business operation");
  expect(suggestExpenseCategory("City Parking", [], categories, [])?.account.name)
    .toBe("Transportation");
});

test("known merchant variants reuse corrected categories", () => {
  expect(suggestExpenseCategory("Michaels", [], categories, history)?.account.name)
    .toBe("Class material supplies");
  expect(suggestExpenseCategory("MICHAELS STORE #1234", [], categories, history)?.account.name)
    .toBe("Class material supplies");
  expect(suggestExpenseCategory("Daiso", [], categories, history)?.account.name)
    .toBe("Class material supplies");
  expect(suggestExpenseCategory("The UPS Store #9999", [{ description: "Printing" }], categories, history)?.account.name)
    .toBe("Office supplies");
});

test("new restaurants remain Dining without confirmed employee-benefit history", () => {
  expect(suggestExpenseCategory("New Cafe", [{ description: "Latte" }], categories, [])?.account.name)
    .toBe("Dining");
});


test("frequent category quick picks rank expense history and cap at six", () => {
  const ranked = frequentExpenseCategories(categories, [
    { payee: "A", categoryId: "employee-benefits", kind: "expense" },
    { payee: "B", categoryId: "class-material", kind: "expense" },
    { payee: "C", categoryId: "employee-benefits", kind: "expense" },
    { payee: "D", categoryId: "office", kind: "expense" },
    { payee: "E", categoryId: "class-material", kind: "expense" },
    { payee: "F", categoryId: "class-material", kind: "expense" },
    { payee: "Income", categoryId: "office", kind: "income" },
  ], 6);

  expect(ranked).toHaveLength(6);
  expect(ranked.slice(0, 3).map((item) => item.name)).toEqual([
    "Class material supplies",
    "Employee benefits",
    "Office supplies",
  ]);
});

test("low-confidence fallback requires a user category choice", () => {
  const suggestion = suggestExpenseCategory("Unknown Merchant", [], categories, []);
  expect(suggestion?.source).toBe("fallback");
  expect(suggestion?.account.name).toBe("Other Expenses");
});
