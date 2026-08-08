#!/usr/bin/env python3
"""Content-layer validator. Run from the repo root: python3 tools/validate.py

Checks, in order:
  1. Schema conformance for every framework.yaml, requirement, mapping set,
     and ruleset (JSON Schema 2020-12).
  2. Requirement id uniqueness across the corpus.
  3. id <-> path coherence: id must be <framework>/<version>/<ref> and the
     file must live under frameworks/<framework>/<version>/requirements/.
  4. Every requirement domain resolves against vocab/domains.yaml.
  5. Every mapping endpoint resolves to a real requirement id.
  6. Mapping relations partially_satisfied_by / conflicts must carry a note.
  7. Ruleset 'activates' refs resolve within the ruleset's target framework.
  8. Obligations (type: obligation) must carry applicable_from.

Exit code 0 = clean, 1 = failures (prints a report either way).
"""

import glob
import json
import os
import sys

import yaml
from jsonschema import Draft202012Validator, FormatChecker

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMA_DIR = os.path.join(ROOT, "schemas")

errors: list[str] = []
warnings: list[str] = []


def load_yaml(path):
    with open(path) as f:
        return yaml.safe_load(f)


def load_schema(name):
    with open(os.path.join(SCHEMA_DIR, name)) as f:
        return Draft202012Validator(json.load(f), format_checker=FormatChecker())


def schema_check(validator, doc, path):
    for err in sorted(validator.iter_errors(doc), key=lambda e: e.json_path):
        errors.append(f"{path}: schema: {err.json_path}: {err.message}")


def main():
    req_schema = load_schema("requirement.schema.json")
    fw_schema = load_schema("framework.schema.json")
    map_schema = load_schema("mapping.schema.json")
    rs_schema = load_schema("ruleset.schema.json")

    # ---- vocab ----
    domains_path = os.path.join(ROOT, "vocab", "domains.yaml")
    domain_ids = set()
    if os.path.exists(domains_path):
        vocab = load_yaml(domains_path)
        domain_ids = {d["id"] for d in vocab.get("domains", [])}
    else:
        errors.append("vocab/domains.yaml missing")

    # ---- frameworks ----
    for path in sorted(glob.glob(os.path.join(ROOT, "frameworks", "*", "*", "framework.yaml"))):
        doc = load_yaml(path)
        schema_check(fw_schema, doc, os.path.relpath(path, ROOT))
        rel = os.path.relpath(path, os.path.join(ROOT, "frameworks"))
        dir_fw, dir_ver = rel.split(os.sep)[0], rel.split(os.sep)[1]
        if doc.get("id") != dir_fw or str(doc.get("version")) != dir_ver:
            errors.append(f"{rel}: framework id/version does not match directory ({dir_fw}/{dir_ver})")

    # ---- requirements ----
    req_ids: dict[str, str] = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "frameworks", "*", "*", "requirements", "*.yaml"))):
        relpath = os.path.relpath(path, ROOT)
        doc = load_yaml(path)
        schema_check(req_schema, doc, relpath)
        rid = doc.get("id", "")
        if rid in req_ids:
            errors.append(f"{relpath}: duplicate id {rid} (also in {req_ids[rid]})")
        else:
            req_ids[rid] = relpath
        # id <-> path coherence
        parts = relpath.split(os.sep)
        dir_fw, dir_ver = parts[1], parts[2]
        expected_prefix = f"{dir_fw}/{dir_ver}/"
        if not rid.startswith(expected_prefix):
            errors.append(f"{relpath}: id {rid} does not match directory {expected_prefix}")
        if doc.get("framework") != dir_fw or str(doc.get("framework_version")) != dir_ver:
            errors.append(f"{relpath}: framework/framework_version fields disagree with directory")
        if rid and not rid.endswith("/" + str(doc.get("ref", ""))):
            errors.append(f"{relpath}: id {rid} does not end with ref {doc.get('ref')}")
        # domains resolve
        for d in doc.get("domains", []):
            if domain_ids and d not in domain_ids:
                errors.append(f"{relpath}: unknown domain '{d}'")
        # obligations need effective dates
        if doc.get("type") == "obligation" and "applicable_from" not in doc:
            errors.append(f"{relpath}: obligation missing applicable_from")

    # ---- mappings ----
    for path in sorted(glob.glob(os.path.join(ROOT, "mappings", "*.yaml"))):
        relpath = os.path.relpath(path, ROOT)
        doc = load_yaml(path)
        schema_check(map_schema, doc, relpath)
        for i, m in enumerate(doc.get("mappings", [])):
            for end in ("from", "to"):
                target = m.get(end, "")
                if target and target not in req_ids:
                    errors.append(f"{relpath}: mappings[{i}].{end} unresolved: {target}")
            if m.get("relation") in ("partially_satisfied_by", "conflicts") and not m.get("note"):
                errors.append(f"{relpath}: mappings[{i}] relation '{m.get('relation')}' requires a note")

    # ---- rulesets ----
    for path in sorted(glob.glob(os.path.join(ROOT, "rulesets", "*.yaml"))):
        relpath = os.path.relpath(path, ROOT)
        doc = load_yaml(path)
        schema_check(rs_schema, doc, relpath)
        fw = doc.get("framework", "")
        q_ids = {q["id"] for q in doc.get("questions", []) if "id" in q}
        for i, o in enumerate(doc.get("outcomes", [])):
            for qid in o.get("when", {}):
                if qid not in q_ids:
                    errors.append(f"{relpath}: outcomes[{i}].when references unknown question '{qid}'")
            for ref in o.get("activates", []):
                full = f"{fw}/{ref}"
                if req_ids and full not in req_ids:
                    warnings.append(f"{relpath}: outcomes[{i}] activates '{ref}' — {full} not yet authored")

    # ---- report ----
    print(f"requirements: {len(req_ids)}")
    for w in warnings:
        print(f"WARN  {w}")
    for e in errors:
        print(f"ERROR {e}")
    print(f"{len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
