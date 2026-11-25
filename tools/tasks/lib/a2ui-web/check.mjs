// The A2UI tab's page in a headless browser, offline (tools/tasks/vendor/a2ui-web.sh --check):
// only App/A2UI's own files load and every other request is blocked and reported. Each fixture in
// FIXTURES/agent (a JSONL stream of A2UI messages) is rendered (in two reads, as the app does), every enabled button is clicked once,
// and what the page sends back is written to FIXTURES/renderer/<fixture>.jsonl. Fails when a page
// error happens, a request leaves the bundle, or a surface draws nothing.
//
//   node check.mjs APP_A2UI FIXTURES        (playwright-core from A2UI_CHECK_MODULES, Chromium from CHROMIUM)
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const [dist, fixtures] = process.argv.slice(2);
const require = createRequire(path.join(process.env.A2UI_CHECK_MODULES ?? process.cwd(), "noop.js"));
const { chromium } = require("playwright-core");
const ORIGIN = "https://paddock-a2ui.invalid/";
const PIXEL = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==", "base64");
const manifest = JSON.parse(fs.readFileSync(path.join(dist, "manifest.json"), "utf8")).files;

const browser = await chromium.launch({ executablePath: process.env.CHROMIUM || "/usr/bin/chromium", args: ["--no-sandbox"] });
let failed = false;
const outDir = path.join(fixtures, "renderer");
fs.mkdirSync(outDir, { recursive: true });
for (const name of fs.readdirSync(path.join(fixtures, "agent")).filter((f) => f.endsWith(".jsonl")).sort()) {
  const lines = fs.readFileSync(path.join(fixtures, "agent", name), "utf8").split("\n").filter((l) => l.trim());
  const page = await browser.newPage({ viewport: { width: 980, height: 1400 } });
  const blocked = [];
  const errors = [];
  const media = [];
  await page.route("**/*", (route) => {
    const url = route.request().url();
    const rel = url.startsWith(ORIGIN) ? decodeURIComponent(new URL(url).pathname.slice(1)) : null;
    // What the app answers through the sandbox (media.ts): here a 1x1 picture.
    if (rel !== null && rel.startsWith("__media/")) {
      const [, kind, encoded] = rel.split("/");
      media.push(`${kind} ${Buffer.from(encoded, "base64url").toString("utf8")}`);
      return route.fulfill({ body: PIXEL, contentType: "image/png" });
    }
    if (rel !== null && manifest[rel]) {
      return route.fulfill({ body: fs.readFileSync(path.join(dist, rel)), contentType: manifest[rel] });
    }
    if (!url.startsWith("data:") && !url.startsWith("blob:")) blocked.push(url);
    return route.abort();
  });
  page.on("pageerror", (e) => errors.push(e.message.slice(0, 300)));
  page.on("console", (m) => { if (m.type() === "error") errors.push(m.text().slice(0, 300)); });
  await page.goto(ORIGIN + "index.html");
  await page.waitForFunction(() => window.paddockA2UI);
  // As the app does: every message so far at each read, here the first half and then all.
  const all = lines.map((l) => JSON.parse(l));
  await page.evaluate((json) => window.paddockA2UI.render(json), JSON.stringify(all.slice(0, Math.ceil(all.length / 2))));
  await page.waitForTimeout(300);
  await page.evaluate((json) => window.paddockA2UI.render(json), JSON.stringify(all));
  await page.waitForTimeout(2500);
  const drawn = await page.evaluate(() => [...document.querySelectorAll(".paddock-surface")].map((s) => s.getBoundingClientRect().height));
  const buttons = await page.locator(".paddock-surface button:not([disabled])").all();
  for (const button of buttons) {
    await button.click({ timeout: 2000 }).catch(() => {});
    await page.waitForTimeout(200);
  }
  await page.waitForTimeout(500);
  const outbox = (await page.evaluate(() => window.paddockOutbox ?? [])).map((t) => JSON.parse(t));
  const actions = outbox.filter((m) => m.kind === "action").map((m) => JSON.stringify(m.message));
  const problems = outbox.filter((m) => m.kind === "problem").map((m) => m.text)
    .concat(outbox.filter((m) => m.kind === "error").map((m) => JSON.stringify(m.message.error)));
  if (actions.length) fs.writeFileSync(path.join(outDir, name), actions.map((a) => a + "\n").join(""));
  else fs.rmSync(path.join(outDir, name), { force: true });
  await page.screenshot({ path: path.join(process.env.A2UI_CHECK_SHOTS ?? outDir, name.replace(/\.jsonl$/, ".png")), fullPage: true }).catch(() => {});
  const empty = drawn.length === 0 || drawn.some((n) => n === 0);
  const ok = blocked.length === 0 && errors.length === 0 && problems.length === 0 && !empty;
  if (!ok) failed = true;
  console.log(`${ok ? "ok  " : "FAIL"} ${name}: ${drawn.length} surface(s), ${buttons.length} button(s), ${actions.length} action(s)`
    + (blocked.length ? `\n     blocked: ${blocked.slice(0, 5).join(" ")}` : "")
    + (errors.length ? `\n     errors: ${errors.slice(0, 3).join(" | ")}` : "")
    + (problems.length ? `\n     problems: ${problems.slice(0, 3).join(" | ")}` : "")
    + (empty ? "\n     a surface drew nothing" : "")
    + (media.length ? `\n     media through the sandbox: ${media.length} (${media.slice(0, 2).join(", ")})` : ""));
  await page.close();
}
await browser.close();
process.exit(failed ? 1 : 0);
