import { expect, test } from "@playwright/test";

test("phone web opens cleanly for signed-out users", async ({ page }) => {
  await page.goto("/dashboard");

  await expect(page).toHaveTitle(/Rainflow/);
  await expect(page.getByRole("heading", { name: "Welcome to Rainflow" })).toBeVisible();
  await expect(page.getByPlaceholder("you@example.com")).toBeVisible();
  await expect(page.getByRole("button", { name: "Send code" })).toBeVisible();

  const horizontalOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth + 1);
  expect(horizontalOverflow).toBe(false);
});

test("missing Supabase config shows setup guidance", async ({ page }) => {
  await page.goto("/");

  await expect(page).toHaveTitle(/Rainflow/);
  await expect(page.getByRole("heading", { name: "Welcome to Rainflow" })).toBeVisible();
});
