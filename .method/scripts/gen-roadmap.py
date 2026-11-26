#!/usr/bin/env python3
"""gen-roadmap.py: generate ROADMAP.md from open issues, by area and priority, with links.

Usage:
  gen-roadmap.py [--output ROADMAP.md]
  gen-roadmap.py --input issues.json   (no network; tests)

Issues labeled `test` are left out.
Debt (`debt`) gets its own section; the rest goes by area.
"""

import argparse
import json
import subprocess
import sys

PRIORITIES = ["priority:high", "priority:medium", "priority:low"]
PRIORITY_NAMES = {"priority:high": "alta", "priority:medium": "média", "priority:low": "baixa"}


def labels_of(issue):
    return [l["name"] if isinstance(l, dict) else l for l in issue.get("labels", [])]


def priority_rank(labels):
    for i, p in enumerate(PRIORITIES):
        if p in labels:
            return i
    return len(PRIORITIES)


def line(issue):
    labels = labels_of(issue)
    prio = next((PRIORITY_NAMES[p] for p in PRIORITIES if p in labels), "sem prioridade")
    extra = [l for l in labels if l.startswith(("group:", "end:"))]
    tail = " · ".join([prio] + extra)
    return "- [#%d](%s) %s · %s" % (issue["number"], issue["url"], issue["title"], tail)


def render(issues):
    issues = [i for i in issues if "test" not in labels_of(i)]
    issues.sort(key=lambda i: (priority_rank(labels_of(i)), i["number"]))
    out = ["# Roadmap", "",
           "<!-- Gerado por .method/scripts/gen-roadmap.py; não editar à mão. -->", ""]
    if not issues:
        return "\n".join(out + ["Nenhuma issue aberta.", ""])
    debt = [i for i in issues if "debt" in labels_of(i)]
    rest = [i for i in issues if "debt" not in labels_of(i)]
    areas = {}
    for i in rest:
        names = [l for l in labels_of(i) if l.startswith("area:")] or ["sem área"]
        areas.setdefault(sorted(names)[0], []).append(i)
    for area in sorted(areas, key=lambda a: (a == "sem área", a)):
        out += ["## " + area.replace("area:", ""), ""] + [line(i) for i in areas[area]] + [""]
    if debt:
        out += ["## Débito técnico", ""] + [line(i) for i in debt] + [""]
    return "\n".join(out).rstrip() + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter,
                                 epilog="\n".join(__doc__.splitlines()[2:]))
    ap.add_argument("--input")
    ap.add_argument("--output", default="ROADMAP.md")
    a = ap.parse_args()
    if a.input:
        issues = json.load(open(a.input, encoding="utf-8"))
    else:
        out = subprocess.run(["gh", "issue", "list", "--state", "open", "--limit", "1000",
                              "--json", "number,title,labels,url"],
                             check=True, text=True, capture_output=True).stdout
        issues = json.loads(out)
    text = render(issues)
    if a.output == "-":
        sys.stdout.write(text)
    else:
        open(a.output, "w", encoding="utf-8").write(text)
        print("wrote %s" % a.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
