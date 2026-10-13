// Real browser screenshots of the Kurtosis Enclave Manager for a running enclave.
//
//   node scripts/screenshots.mjs <enclave-name> <out-dir> [service ...]
//
// Uses Playwright's Chromium. The Enclave Manager is a single-page app that renders blank when a
// deep link is opened directly in a headless browser, so this navigates the way a user does: open
// the enclave list, click the enclave, click each service, click its Logs tab. Every screenshot is
// the page exactly as the UI renders it. Requires `npm install && npx playwright install chromium`.
import { mkdirSync } from "node:fs";
import { chromium } from "playwright";

const [enclave, outDir, ...services] = process.argv.slice(2);
if (!enclave || !outDir) {
  console.error("usage: node screenshots.mjs <enclave-name> <out-dir> [service ...]");
  process.exit(2);
}
mkdirSync(outDir, { recursive: true });

const base = process.env.KURTOSIS_UI_URL ?? "http://localhost:9711";
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1600, height: 1000 }, colorScheme: "dark" });
const settle = async () => { await page.waitForLoadState("networkidle"); await page.waitForTimeout(1500); };
const save = async (name) => {
  const file = `${outDir}/${name}.png`;
  await page.screenshot({ path: file, fullPage: true });
  console.log(`saved ${file} (${page.url()})`);
};

// enclave list -> enclave overview
await page.goto(`${base}/`, { waitUntil: "networkidle" });
await page.getByRole("link", { name: enclave, exact: true }).first().waitFor({ timeout: 60_000 });
await save("enclave-list");
await page.getByRole("link", { name: enclave, exact: true }).first().click();
await page.getByText("Services", { exact: true }).first().waitFor({ timeout: 60_000 });
await settle();
await save("enclave-overview");

for (const svc of services) {
  const link = page.getByRole("link", { name: svc, exact: true }).first();
  if (await link.count() === 0) { console.error(`service ${svc} not found on the overview page`); continue; }
  await link.click();
  await page.getByRole("heading", { name: svc }).first().waitFor({ timeout: 60_000 });
  await settle();
  await save(`service-${svc}`);
  const logsTab = page.getByRole("tab", { name: "Logs" }).first();
  if (await logsTab.count() > 0) {
    await logsTab.click();
    await settle();
    await page.waitForTimeout(3000); // let the log stream fill
    await save(`logs-${svc}`);
  }
  // back to the overview via the breadcrumb
  await page.getByRole("link", { name: enclave, exact: true }).first().click();
  await page.getByText("Services", { exact: true }).first().waitFor({ timeout: 60_000 });
  await settle();
}
await browser.close();
