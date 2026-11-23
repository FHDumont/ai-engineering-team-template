#!/usr/bin/env bash
# refs.sh: a spec can keep an issue open until a post-merge proof. Sourced.
#
#   issue_kept_open <issue> <repo root>   0 when the phase section says
#       "issue fica aberta até a prova"
#   body_keep_open <body file> <issue> <repo root>
#       turns Closes/Fixes/Resolves of that issue into Refs

issue_kept_open() { # issue_kept_open <issue> <repo root>
  python3 - "$1" "$2" <<'PY'
import pathlib, re, sys
issue, root = sys.argv[1], pathlib.Path(sys.argv[2])
folder = root / "docs" / "specs"
if not folder.is_dir():
    sys.exit(1)
phrase = "issue fica aberta até a prova"
head = re.compile(r"^## .*#%s(?:\D|$)" % re.escape(issue))
for path in folder.glob("*.md"):
    text = path.read_text(encoding="utf-8")
    for part in re.split(r"(?m)^(?=## )", text):
        if part.startswith("## ") and head.search(part.split("\n", 1)[0]) and phrase in part:
            sys.exit(0)
sys.exit(1)
PY
}

body_keep_open() { # body_keep_open <file> <issue> <repo root>
  issue_kept_open "$2" "$3" || return 0
  python3 - "$1" "$2" <<'PY'
import re, sys
path, issue = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
text = re.sub(
    r"(?i)\b(?:closes|close|closed|fixes|fixed|fix|resolves|resolved|resolve)\s+#%s\b" % re.escape(issue),
    "Refs #%s" % issue,
    text,
)
if not re.search(r"(?i)\bRefs\s+#%s\b" % re.escape(issue), text):
    text = text.rstrip() + "\n\nRefs #%s\n" % issue
open(path, "w", encoding="utf-8").write(text if text.endswith("\n") else text + "\n")
PY
}
