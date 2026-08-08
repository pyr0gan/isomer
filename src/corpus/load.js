import { readdirSync, readFileSync, existsSync, statSync } from "node:fs";
import { join, relative, sep } from "node:path";
import { parse as parseYaml } from "yaml";

const ROOT = process.cwd();

function readYaml(absPath) {
  return parseYaml(readFileSync(absPath, "utf8"));
}

function listFiles(dir, predicate) {
  if (!existsSync(dir)) return [];
  const out = [];
  for (const name of readdirSync(dir)) {
    const abs = join(dir, name);
    const st = statSync(abs);
    if (st.isDirectory()) out.push(...listFiles(abs, predicate));
    else if (predicate(abs, name)) out.push(abs);
  }
  return out.sort();
}

function underRequirementsDir(absPath) {
  const parts = absPath.split(sep);
  return parts.includes("requirements");
}

/**
 * Load the on-disk governance corpus into plain JS objects ready for Surreal upsert.
 * Paths are relative to the repo root (process.cwd()).
 */
export function loadCorpus(root = ROOT) {
  const domainsPath = join(root, "vocab", "domains.yaml");
  const domainsDoc = existsSync(domainsPath) ? readYaml(domainsPath) : { domains: [] };
  const domains = (domainsDoc.domains || []).map((d) => ({
    ...d,
    source_path: relative(root, domainsPath),
  }));

  const frameworkFiles = listFiles(join(root, "frameworks"), (_abs, name) =>
    name === "framework.yaml",
  );
  const frameworks = frameworkFiles.map((abs) => ({
    ...readYaml(abs),
    source_path: relative(root, abs),
  }));

  const requirementFiles = listFiles(join(root, "frameworks"), (abs, name) =>
    name.endsWith(".yaml") && underRequirementsDir(abs),
  );
  const requirements = requirementFiles.map((abs) => ({
    ...readYaml(abs),
    source_path: relative(root, abs),
  }));

  const mappingFiles = listFiles(join(root, "mappings"), (_abs, name) =>
    name.endsWith(".yaml"),
  );
  const mappingSets = mappingFiles.map((abs) => ({
    ...readYaml(abs),
    source_path: relative(root, abs),
  }));

  const rulesetFiles = listFiles(join(root, "rulesets"), (_abs, name) =>
    name.endsWith(".yaml"),
  );
  const rulesets = rulesetFiles.map((abs) => ({
    ...readYaml(abs),
    source_path: relative(root, abs),
  }));

  const rubricFiles = listFiles(join(root, "rubrics"), (_abs, name) =>
    name.endsWith(".yaml"),
  );
  const rubrics = rubricFiles.map((abs) => ({
    ...readYaml(abs),
    source_path: relative(root, abs),
  }));

  return {
    root,
    domains,
    frameworks,
    requirements,
    mappingSets,
    rulesets,
    rubrics,
    counts: {
      domains: domains.length,
      frameworks: frameworks.length,
      requirements: requirements.length,
      mappingSets: mappingSets.length,
      rulesets: rulesets.length,
      rubrics: rubrics.length,
    },
  };
}

/** Framework Surreal record key: `<id>:<version>`. */
export function frameworkKey(doc) {
  return `${doc.id}:${doc.version}`;
}

/** Ruleset Surreal record key from `ruleset` field. */
export function rulesetKey(doc) {
  return doc.ruleset;
}

/** Mapping-set Surreal record key from `id` field. */
export function mappingSetKey(doc) {
  return doc.id;
}

/** Domain Surreal record key. */
export function domainKey(doc) {
  return doc.id;
}

/** Requirement Surreal record key = corpus id. */
export function requirementKey(doc) {
  return doc.id;
}

/** Rubric Surreal record key = domain id. */
export function rubricKey(doc) {
  return doc.domain;
}
