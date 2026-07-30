import { chromium } from "@playwright/test";
import { spawn } from "node:child_process";
import { mkdir } from "node:fs/promises";
import path from "node:path";

const baseURL = process.env.PLAYWRIGHT_BASE_URL ?? "http://127.0.0.1:3210";
const authStatePath = process.env.E2E_AUTH_STATE ?? "tests/e2e/.auth/rainflow.json";
const resolvedAuthStatePath = path.resolve(process.cwd(), authStatePath);

let serverProcess;

async function main() {
  const serverWasRunning = await isServerReady();

  if (!serverWasRunning) {
    serverProcess = spawn("npm", ["run", "dev:e2e"], {
      cwd: process.cwd(),
      stdio: "inherit",
      env: process.env,
    });
    await waitForServer();
  }

  await mkdir(path.dirname(resolvedAuthStatePath), { recursive: true });

  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext({
    viewport: { width: 390, height: 844 },
    isMobile: true,
    hasTouch: true,
    userAgent:
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
  });
  const page = await context.newPage();

  console.log("");
  console.log("Rainflow auth capture");
  console.log(`1. Sign in at ${baseURL}/dashboard using your Rainflow email code.`);
  console.log("2. Wait until the app dashboard/navigation is visible.");
  console.log("3. Leave this terminal running; it will save the session automatically.");
  console.log("");

  await page.goto(`${baseURL}/dashboard`);
  await page.getByRole("navigation", { name: "Phone navigation" }).waitFor({ timeout: 300_000 });
  await context.storageState({ path: resolvedAuthStatePath });
  await browser.close();

  console.log(`Saved Playwright auth state to ${authStatePath}`);
  console.log("Run signed-in tests with: npm run test:e2e:phone");
}

async function isServerReady() {
  try {
    const response = await fetch(baseURL);
    return response.ok || response.status < 500;
  } catch {
    return false;
  }
}

async function waitForServer() {
  const startedAt = Date.now();
  while (Date.now() - startedAt < 120_000) {
    if (await isServerReady()) return;
    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  throw new Error(`Timed out waiting for ${baseURL}`);
}

process.on("exit", () => {
  if (serverProcess) serverProcess.kill();
});

main().catch((error) => {
  if (serverProcess) serverProcess.kill();
  console.error(error);
  process.exit(1);
});
