#!/usr/bin/env python3
"""auto-label.py: derive labels from the `##` sections of an issue body.

Usage:
  auto-label.py --issue N [--dry-run]
  auto-label.py --body-file F [--labels a,b] [--dry-run]   (no network; prints JSON)

Simple, free rules (design §8): type from the template label or the sections;
priority from "Prioridade sugerida"; end mode from "Sugestão de fim"; size
from "Achado em"; area from `area:x` in the body, sensitive-area words and
the top folder of cited paths; group from `group:x`. An empty required
section -> `needs-context` + one short comment (edited in place next time).
When everything is filled in, `needs-context` is removed.
Called by the issues-label.yml workflow.
"""

import argparse
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "lib"))
import issue_template as it  # noqa: E402

ROOT = os.path.dirname(HERE)
COMMENT_MARK = "<!-- auto-label:needs-context -->"

TYPE_LABELS = {"feature": ["type:feature"], "bug": ["type:bug"],
               "debt": ["type:chore", "debt"], "finding": ["finding"]}
PRIORITY = [(r"\b(alta|high)\b", "priority:high"),
            (r"\b(m[ée]dia|medium)\b", "priority:medium"),
            (r"\b(baixa|low)\b", "priority:low")]
END = [(r"lab-test", "end:lab-test"), (r"auto-close", "end:auto-close")]
SIZE = [(r"\b(small|pequeno)\b", "size:small"),
        (r"\b(medium|m[ée]dio)\b", "size:medium"),
        (r"\b(large|grande)\b", "size:large")]
SENSITIVE = [(r"\b(auth|login|autentica\w*|oauth|sso)\b", "area:auth"),
             (r"\b(billing|cobran\w*|pagamento\w*|payment\w*)\b", "area:billing"),
             (r"\b(migration\w*|migra[çc][ãa]o|migra[çc][õo]es)\b", "area:migration"),
             (r"\b(credentials?|credencia\w*|segredos?|secrets?)\b|\.env\b", "area:credentials")]
PATH_AREAS = [(r"(^|\s|`)scripts/", "area:scripts"),
              (r"(^|\s|`)\.github/", "area:ci"),
              (r"(^|\s|`)docs/", "area:docs"),
              (r"(^|\s|`)\.claude/", "area:process")]


def known_labels():
    names = set()
    with open(os.path.join(ROOT, ".github", "labels.tsv"), encoding="utf-8") as f:
        for line in f:
            if line.strip() and not line.startswith("#"):
                names.add(line.split("\t")[0])
    return names


def area_rules():
    """Sensitive areas and path areas. A repository file replaces the defaults.

    .github/label-areas.tsv (or LABEL_AREAS_FILE), one rule per line:
    kind, pattern and label, separated by tabs. kind is path or sensitive.
    A label that is not in .github/labels.tsv is not applied.
    """
    path = os.environ.get("LABEL_AREAS_FILE") or os.path.join(ROOT, ".github", "label-areas.tsv")
    if not os.path.isfile(path):
        return SENSITIVE, PATH_AREAS
    sensitive, paths = [], []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            kind, pattern, label = line.split("\t")
            if kind == "sensitive":
                sensitive.append((pattern, label))
            elif kind == "path":
                paths.append((pattern, label))
    return sensitive, paths


def first_match(rules, text):
    for pattern, label in rules:
        if re.search(pattern, text, re.I):
            return label
    return None


def compute(body, labels):
    """Body + current labels -> {"add": [...], "remove": [...], "missing": [...]}."""
    labels = set(labels or [])
    sections = it.split_sections(body)
    text = {t: it.section_text(raw) for t, raw in sections}
    kind = it.detect_type(labels, sections, ROOT)
    add = set()
    missing = []
    if kind is None:
        missing = ["(nenhuma seção do template)"]
    else:
        add.update(TYPE_LABELS[kind])
        missing = it.missing_required(kind, body, ROOT)
    for title, rules in (("Prioridade sugerida", PRIORITY), ("Sugestão de fim", END),
                         ("Achado em", SIZE)):
        label = first_match(rules, text.get(title, ""))
        if label:
            add.add(label)
    clean = it.section_text(body)
    add.update(re.findall(r"\b((?:area|group):[a-z0-9-]+)", clean))
    areas_text = text.get("Arquivos ou áreas afetadas", "")
    for rules in area_rules():
        for pattern, label in rules:
            if re.search(pattern, areas_text, re.I):
                add.add(label)
    # Single-choice prefixes: do not add a second priority/end/size.
    for prefix in ("priority:", "end:", "size:"):
        if any(l.startswith(prefix) for l in labels):
            add = {l for l in add if not l.startswith(prefix)}
    # Type is also single-choice: if the issue already has a type:*, do not add another.
    if any(l.startswith("type:") for l in labels):
        add = {l for l in add if not l.startswith("type:")}
    known = known_labels()
    add = {l for l in add if l in known or l.startswith("group:")}
    remove = set()
    if missing:
        add.add("needs-context")
    elif "needs-context" in labels:
        remove.add("needs-context")
    return {"type": kind, "add": sorted(add - labels), "remove": sorted(remove),
            "missing": missing}


def comment_body(missing):
    items = "\n".join("- %s" % m for m in missing)
    return ("%s\nFaltam seções obrigatórias do template; a issue ficou com "
            "`needs-context` até serem preenchidas:\n\n%s\n" % (COMMENT_MARK, items))


def gh(*args, **kw):
    return subprocess.run(["gh"] + list(args), check=True, text=True,
                          capture_output=True, **kw).stdout


def apply(issue, result):
    repo = os.environ.get("GH_REPO") or gh("repo", "view", "--json", "nameWithOwner",
                                           "--jq", ".nameWithOwner").strip()
    for label in result["add"]:
        if label.startswith("group:") and label not in known_labels():
            # Without --force: if it already exists in the repository, keep it as it is.
            try:
                gh("label", "create", label, "--repo", repo, "--color", "d4c5f9",
                   "--description", "Grupo de afinidade")
            except subprocess.CalledProcessError:
                pass
    args = ["issue", "edit", str(issue), "--repo", repo]
    for label in result["add"]:
        args += ["--add-label", label]
    for label in result["remove"]:
        args += ["--remove-label", label]
    if result["add"] or result["remove"]:
        gh(*args)
    if result["missing"]:
        comments = json.loads(gh("api", "repos/%s/issues/%s/comments" % (repo, issue),
                                 "--paginate", "--slurp"))
        flat = [c for page in comments for c in page]
        mine = [c for c in flat if COMMENT_MARK in (c.get("body") or "")]
        body = comment_body(result["missing"])
        if mine:
            gh("api", "-X", "PATCH", "repos/%s/issues/comments/%s" % (repo, mine[-1]["id"]),
               "-f", "body=" + body)
        else:
            gh("issue", "comment", str(issue), "--repo", repo, "--body", body)


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0],
                                formatter_class=argparse.RawDescriptionHelpFormatter,
                                epilog="\n".join(__doc__.splitlines()[2:]))
    p.add_argument("--issue", type=int)
    p.add_argument("--body-file")
    p.add_argument("--labels", default="")
    p.add_argument("--dry-run", action="store_true")
    a = p.parse_args()
    if a.body_file:
        with open(a.body_file, encoding="utf-8") as f:
            body = f.read()
        labels = [l for l in a.labels.split(",") if l]
    elif a.issue:
        data = json.loads(gh("issue", "view", str(a.issue), "--json", "body,labels"))
        body = data.get("body") or ""
        labels = [l["name"] for l in data.get("labels", [])]
    else:
        p.error("use --issue or --body-file")
    result = compute(body, labels)
    print(json.dumps(result, ensure_ascii=False))
    if a.issue and not a.dry_run:
        apply(a.issue, result)
    return 0


if __name__ == "__main__":
    sys.exit(main())
