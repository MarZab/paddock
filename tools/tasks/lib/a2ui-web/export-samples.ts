// The A2UI Playground's own preview of every component, as A2UI 1.0 messages (PAD-152 fixtures):
// one JSONL file per group, each component its own surface, the way the playground's component docs
// render them (sampleOps). Run by tools/tasks/vendor/a2ui-web.sh inside the playground's checkout.
//
//   npx tsx --tsconfig tsconfig.json paddock-host/export-samples.ts OUT_FOLDER
import fs from "node:fs";
import path from "node:path";
import { CATALOG_ID } from "@/a2ui/catalog/ids";
import { sampleOps } from "@/a2ui/catalog/samples";
import { chartsSamples } from "@/a2ui/catalog/samples/charts";
import { contentSamples } from "@/a2ui/catalog/samples/content";
import { dataSamples } from "@/a2ui/catalog/samples/data";
import { domainSamples } from "@/a2ui/catalog/samples/domain";
import { feedbackSamples } from "@/a2ui/catalog/samples/feedback";
import { inputsSamples } from "@/a2ui/catalog/samples/inputs";
import { layoutSamples } from "@/a2ui/catalog/samples/layout";
import { mapsSamples } from "@/a2ui/catalog/samples/maps";
import { standardSamples } from "@/a2ui/catalog/samples/standard";
import type { Sample } from "@/a2ui/catalog/samples/types";

const out = process.argv[2];
fs.mkdirSync(out, { recursive: true });
const groups: Record<string, Record<string, Sample>> = {
  charts: chartsSamples, content: contentSamples, data: dataSamples, domain: domainSamples, feedback: feedbackSamples,
  inputs: inputsSamples, layout: layoutSamples, maps: mapsSamples, standard: standardSamples,
};
let count = 0;
for (const [group, samples] of Object.entries(groups)) {
  const lines = Object.entries(samples).sort(([a], [b]) => a.localeCompare(b))
    .flatMap(([name, sample]) => sampleOps(name, sample, CATALOG_ID))
    .map((op) => JSON.stringify(op));
  count += lines.length;
  fs.writeFileSync(path.join(out, `samples-${group}.jsonl`), lines.join("\n") + "\n");
}
console.log(`==> ${count} sample surfaces in ${out}`);
