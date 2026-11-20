"""Read the issue templates and the `##` sections of an issue body.

CLI (used by open-issue.sh):
  issue_template.py sections <type>            # JSON of the template sections
  issue_template.py render <type> <json-file>  # body built from the template
"""

# Single source of the section titles: the files in .github/ISSUE_TEMPLATE/. open-issue.sh and
# auto-label.py use this module, so both always read the same titles.

import json
import os
import re
import sys

# Issue type -> template file.
TYPES = {
    "feature": "feature.md",
    "bug": "bug.md",
    "debt": "debt.md",
    "finding": "finding.md",
}

# Label that identifies the type (comes from the template front matter).
MARKER_LABELS = {
    "feature": "type:feature",
    "bug": "type:bug",
    "debt": "debt",
    "finding": "finding",
}

HEADING_RE = re.compile(r"^##\s+(.+?)\s*$")
COMMENT_RE = re.compile(r"<!--.*?-->", re.S)
REQUIRED_RE = re.compile(r"<!--\s*(obrigatório|opcional)\s*:", re.I)


def template_dir(root=None):
    root = root or os.environ.get("REPO_ROOT") or os.getcwd()
    return os.path.join(root, ".github", "ISSUE_TEMPLATE")


def parse_front_matter(text):
    """Returns (front_matter_dict, rest). Only the subset we use."""
    fm = {}
    if not text.startswith("---"):
        return fm, text
    end = text.find("\n---", 3)
    if end < 0:
        return fm, text
    for line in text[3:end].strip().splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        value = value.strip()
        if value.startswith("["):
            value = [v.strip().strip('"').strip("'") for v in value.strip("[]").split(",") if v.strip()]
        else:
            value = value.strip('"').strip("'")
        fm[key.strip()] = value
    return fm, text[end + 4:].lstrip("\n")


def split_sections(body):
    """Body -> ordered list of (title, raw text of the section)."""
    sections = []
    title, lines = None, []
    for line in (body or "").splitlines():
        m = HEADING_RE.match(line)
        if m:
            if title is not None:
                sections.append((title, "\n".join(lines)))
            title, lines = m.group(1), []
        elif title is not None:
            lines.append(line)
    if title is not None:
        sections.append((title, "\n".join(lines)))
    return sections


def section_text(raw):
    """Real text of the section, without guide comments and surrounding spaces."""
    return COMMENT_RE.sub("", raw or "").strip()


def load_template(kind, root=None):
    """Template of a type -> dict with labels and sections (title, required, guide)."""
    if kind not in TYPES:
        raise ValueError("unknown issue type: %s" % kind)
    path = os.path.join(template_dir(root), TYPES[kind])
    with open(path, encoding="utf-8") as f:
        fm, rest = parse_front_matter(f.read())
    sections = []
    for title, raw in split_sections(rest):
        m = REQUIRED_RE.search(raw)
        sections.append({
            "title": title,
            "required": bool(m and m.group(1).lower() == "obrigatório"),
            "guide": raw.strip(),
        })
    labels = fm.get("labels") or []
    if isinstance(labels, str):
        labels = [labels] if labels else []
    return {"type": kind, "labels": labels, "sections": sections}


def detect_type(labels, sections, root=None):
    """Issue type: by the template labels, otherwise by the sections present."""
    labels = set(labels or [])
    for kind in ("finding", "debt", "bug", "feature"):
        if MARKER_LABELS[kind] in labels:
            return kind
    titles = {t for t, _ in sections}
    if "Achado em" in titles:
        return "finding"
    if "Risco de não fazer" in titles:
        return "debt"
    if "Como reproduzir" in titles and "Prioridade sugerida" in titles:
        return "bug"
    if "Objetivo" in titles:
        return "feature"
    return None


def missing_required(kind, body, root=None):
    """Titles of the required sections missing or empty in the body."""
    present = {t: section_text(raw) for t, raw in split_sections(body)}
    return [s["title"] for s in load_template(kind, root)["sections"]
            if s["required"] and not present.get(s["title"])]


def render(kind, values, root=None):
    """Builds the body from the template: keeps the order and the titles,
    replaces the guide comment with the given text; an empty optional section is dropped."""
    tpl = load_template(kind, root)
    known = {s["title"] for s in tpl["sections"]}
    unknown = sorted(set(values) - known)
    if unknown:
        raise ValueError("unknown sections for %s: %s" % (kind, ", ".join(unknown)))
    parts = []
    for s in tpl["sections"]:
        text = (values.get(s["title"]) or "").strip()
        if not text and not s["required"]:
            continue
        parts.append("## %s\n\n%s\n" % (s["title"], text))
    return "\n".join(parts)


def main(argv):
    if len(argv) < 3 or argv[1] not in ("sections", "render"):
        print(__doc__.strip())
        return 2
    kind = argv[2]
    if argv[1] == "sections":
        print(json.dumps(load_template(kind), ensure_ascii=False))
        return 0
    with open(argv[3], encoding="utf-8") as f:
        values = json.load(f)
    body = render(kind, values)
    missing = missing_required(kind, body)
    if missing:
        print("error: missing required sections: " + "; ".join(missing), file=sys.stderr)
        return 3
    sys.stdout.write(body)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
