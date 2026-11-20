#!/usr/bin/env python3
"""gen-changelog.py: generate CHANGELOG.md from merged PRs, grouped by type:*.

Usage:
  gen-changelog.py [--include-pr N] [--output CHANGELOG.md]
  gen-changelog.py --input prs.json [--include-pr-json pr.json]   (no network; tests)

--include-pr N counts PR N as already merged. PRs labeled `test` are left out,
and so are the PRs of gen-docs.sh (branch gen-docs/*), which hold only generated files.
"""

import argparse
import json
import subprocess
import sys
from datetime import date, datetime

GROUPS = [("type:feature", "Funcionalidades"), ("type:bug", "Correções"),
          ("type:docs", "Documentação"), ("type:chore", "Manutenção")]
OTHER = "Outros"


def gh_json(*args):
    out = subprocess.run(["gh"] + list(args), check=True, text=True, capture_output=True).stdout
    return json.loads(out)


def labels_of(pr):
    return [l["name"] if isinstance(l, dict) else l for l in pr.get("labels", [])]


def first_type(pr):
    # A PR with more than one type:* goes only to the first group in the order of GROUPS.
    labels = labels_of(pr)
    for label, _ in GROUPS:
        if label in labels:
            return label
    return None


def local_day(merged_at):
    # mergedAt comes in UTC; the CHANGELOG shows the day in the local time zone.
    if not merged_at:
        return date.today().isoformat()
    return datetime.fromisoformat(merged_at.replace("Z", "+00:00")).astimezone().date().isoformat()


def render(prs):
    prs = [p for p in prs if "test" not in labels_of(p)
           and not (p.get("headRefName") or "").startswith("gen-docs/")]
    # Newest first; the included PR has no merge date yet.
    prs.sort(key=lambda p: (p.get("mergedAt") or "9999", p["number"]), reverse=True)
    lines = ["# Changelog", "",
             "<!-- Gerado por scripts/gen-changelog.py; não editar à mão. -->", ""]
    for label, title in GROUPS + [(None, OTHER)]:
        group = [p for p in prs if first_type(p) == label]
        if not group:
            continue
        lines += ["## " + title, ""]
        for p in group:
            day = local_day(p.get("mergedAt"))
            lines.append("- %s ([#%d](%s)) · %s" % (p["title"], p["number"], p["url"], day))
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter,
                                 epilog="\n".join(__doc__.splitlines()[2:]))
    ap.add_argument("--include-pr", type=int)
    ap.add_argument("--input")
    ap.add_argument("--include-pr-json")
    ap.add_argument("--output", default="CHANGELOG.md")
    a = ap.parse_args()
    fields = "number,title,labels,mergedAt,url,headRefName"
    if a.input:
        prs = json.load(open(a.input, encoding="utf-8"))
    else:
        prs = gh_json("pr", "list", "--state", "merged", "--base", "main",
                      "--limit", "1000", "--json", fields)
    extra = None
    if a.include_pr_json:
        extra = json.load(open(a.include_pr_json, encoding="utf-8"))
    elif a.include_pr:
        extra = gh_json("pr", "view", str(a.include_pr), "--json", "number,title,labels,url")
    if extra:
        extra["mergedAt"] = None
        prs = [p for p in prs if p["number"] != extra["number"]] + [extra]
    text = render(prs)
    if a.output == "-":
        sys.stdout.write(text)
    else:
        open(a.output, "w", encoding="utf-8").write(text)
        print("wrote %s (%d PRs)" % (a.output, len([p for p in prs if "test" not in labels_of(p)])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
