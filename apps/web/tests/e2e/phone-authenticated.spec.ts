import { expect, test } from "@playwright/test";
import fs from "node:fs";

const authStatePath = process.env.E2E_AUTH_STATE ?? "tests/e2e/.auth/rainflow.json";

test.skip(!authStatePath || !fs.existsSync(authStatePath), "Set E2E_AUTH_STATE to a saved Rainflow login state to run authenticated phone-web checks.");

test.use(authStatePath ? { storageState: authStatePath } : {});

test("signed-in phone web exposes core app navigation and capture", async ({ page }) => {
  await page.goto("/dashboard");

  await expect(page.getByRole("navigation", { name: "Phone navigation" })).toBeVisible();
  await expect(page.getByText("Home")).toBeVisible();
  await expect(page.getByText("Ledgers")).toBeVisible();
  await expect(page.getByText("Accounts")).toBeVisible();
  await expect(page.getByText("Reports")).toBeVisible();

  await page.getByRole("button", { name: "Capture receipt or add transaction" }).click();
  await expect(page.getByRole("dialog", { name: "Add transaction" })).toBeVisible();
  await expect(page.getByText("Take photo")).toBeVisible();
  await expect(page.getByText("Choose from library")).toBeVisible();
  await expect(page.getByText("Add manually")).toBeVisible();

  await page.getByRole("button", { name: "Close" }).click();
  await page.getByRole("link", { name: /Ledgers/ }).click();
  await expect(page.getByRole("heading", { name: "Your ledgers" })).toBeVisible();
});
