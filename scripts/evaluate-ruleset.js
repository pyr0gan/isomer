#!/usr/bin/env node
/**
 * Evaluate a classification ruleset (first-match) against JSON answers.
 *
 *   npm run ruleset:evaluate -- \
 *     --ruleset rulesets/eu-ai-act-classification.yaml \
 *     --answers '{"role":"provider","annex-iii-area":"employment"}'
 *
 * Outcome order in the YAML is semantic (first match wins). Effective dates
 * on the matching outcome override requirement-level applicable_from.
 */

import { readFileSync } from "node:fs";
import { parse as parseYaml } from "yaml";
import { loadCorpus } from "../src/corpus/load.js";
import { evaluateRuleset } from "../src/ruleset/evaluate.js";

function usage(code = 1) {
  console.error(`Usage: node scripts/evaluate-ruleset.js --ruleset <path> --answers <json>

  --ruleset   Path to ruleset YAML (default: rulesets/eu-ai-act-classification.yaml)
  --answers   JSON object of question id -> answer
  --help      Show this help
`);
  process.exit(code);
}

function parseArgs(argv) {
  const out = {
    ruleset: "rulesets/eu-ai-act-classification.yaml",
    answers: null,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--help" || a === "-h") usage(0);
    if (a === "--ruleset") {
      out.ruleset = argv[++i];
      continue;
    }
    if (a === "--answers") {
      out.answers = argv[++i];
      continue;
    }
    console.error(`Unknown argument: ${a}`);
    usage(1);
  }
  if (!out.answers) {
    console.error("Missing --answers JSON");
    usage(1);
  }
  return out;
}

const args = parseArgs(process.argv.slice(2));
let answers;
try {
  answers = JSON.parse(args.answers);
} catch (err) {
  console.error("Failed to parse --answers JSON:", err.message);
  process.exit(1);
}

const ruleset = parseYaml(readFileSync(args.ruleset, "utf8"));
const corpus = loadCorpus();
const requirementsById = new Map(
  corpus.requirements.map((r) => [r.id, r]),
);

const result = evaluateRuleset({ ruleset, answers, requirementsById });
console.log(JSON.stringify(result, null, 2));
