#!/usr/bin/env python3
"""Integration delta report.

Usage:
  python3 tools/delta_report.py mappings/iso42001-2023--iso27001-2022.yaml
  python3 tools/delta_report.py mappings/eu-ai-act-2024-2026-1744--iso42001-2023.yaml

For the mapping set's from_framework, reports each requirement's best
coverage by mapping edges (to_framework may span inherited namespaces):
  covered   - has a satisfied_by edge
  partial   - best edge is partially_satisfied_by (gap notes shown)
  adjacent  - only related/supports edges
  net-new   - no edges at all

Used for tier residuals (ISMS→AIMS, AIMS→AI Act); the product's roadmap
generator consumes the same logic.
"""

import glob
import os
import sys

import yaml

RANK = {"satisfied_by": 3, "partially_satisfied_by": 2, "supports": 1, "related": 1}
LABEL = {3: "covered", 2: "partial", 1: "adjacent", 0: "net-new"}


def main(map_path):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ms = yaml.safe_load(open(map_path))
    from_fw = ms["from_framework"]  # e.g. iso42001/2023

    fw, ver = from_fw.split("/")
    reqs = {}
    for p in sorted(glob.glob(os.path.join(root, "frameworks", fw, ver, "requirements", "*.yaml"))):
        d = yaml.safe_load(open(p))
        reqs[d["id"]] = d["title"]

    best = {rid: 0 for rid in reqs}
    notes = {rid: [] for rid in reqs}
    for m in ms["mappings"]:
        rid = m["from"]
        if rid not in best:
            continue
        r = RANK.get(m["relation"], 0)
        best[rid] = max(best[rid], r)
        if m["relation"] == "partially_satisfied_by" and m.get("note"):
            notes[rid].append(m["note"].strip().replace("\n", " "))

    buckets = {"covered": [], "partial": [], "adjacent": [], "net-new": []}
    for rid, title in reqs.items():
        buckets[LABEL[best[rid]]].append((rid, title))

    print(f"Integration delta: {from_fw} against {ms['to_framework']}")
    print(f"{len(reqs)} requirements: "
          + ", ".join(f"{k}={len(v)}" for k, v in buckets.items()) + "\n")
    for bucket in ["net-new", "partial", "adjacent", "covered"]:
        if not buckets[bucket]:
            continue
        print(f"== {bucket} ({len(buckets[bucket])}) ==")
        for rid, title in buckets[bucket]:
            print(f"  {rid.split('/')[-1]:>8}  {title}")
            if bucket == "partial":
                for n in notes[rid]:
                    gap = n.split("Gap:")[-1].strip().rstrip(".") if "Gap:" in n else n
                    print(f"            gap: {gap}")
        print()


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1]) or 0)
    except BrokenPipeError:
        os._exit(0)  # graceful under `| head`
