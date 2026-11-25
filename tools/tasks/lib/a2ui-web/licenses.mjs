// Writes THIRD_PARTY_LICENSES.txt for App/A2UI (tools/tasks/vendor/a2ui-web.sh): the license of the
// A2UI Playground (CopilotKit, MIT) and of every npm package installed for its build, from
// `pnpm licenses list`. node licenses.mjs PLAYGROUND OUT STORE (the pnpm store the install used)
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const [playground, out, store] = process.argv.slice(2);
const listed = JSON.parse(execFileSync("npx", ["--yes", "pnpm@10.33.4", "licenses", "list", "--prod", "--json", `--config.store-dir=${store}`], { cwd: playground, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }));
const parts = [];
const repoLicense = path.join(playground, "..", "..", "..", "LICENSE");
if (fs.existsSync(repoLicense)) parts.push(`CopilotKit A2UI Playground (examples/showcases/a2ui-playground)\n\n${fs.readFileSync(repoLicense, "utf8").trim()}`);
const transitions = path.join(playground, "src", "vendor", "transitions", "LICENSE.txt");
if (fs.existsSync(transitions)) parts.push(`transitions (src/vendor/transitions)\n\n${fs.readFileSync(transitions, "utf8").trim()}`);
for (const [license, packages] of Object.entries(listed).sort()) {
  for (const pkg of packages.sort((a, b) => a.name.localeCompare(b.name))) {
    const dir = (pkg.paths ?? [pkg.path]).find(Boolean);
    let text = "";
    if (dir && fs.existsSync(dir)) {
      const file = fs.readdirSync(dir).find((f) => /^(licen[cs]e|copying|notice)(\..*)?$/i.test(f));
      if (file) text = fs.readFileSync(path.join(dir, file), "utf8").trim();
    }
    parts.push(`${pkg.name} ${[].concat(pkg.versions ?? pkg.version ?? []).join(", ")} (${license})${text ? "\n\n" + text : ""}`);
  }
}
fs.writeFileSync(out, parts.join("\n\n" + "-".repeat(72) + "\n\n") + "\n");
console.log(`==> ${parts.length} licenses in ${out}`);
