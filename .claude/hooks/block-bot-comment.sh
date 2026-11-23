#!/usr/bin/env bash
# block-bot-comment.sh: PreToolUse (Bash) hook for comments an agent posts by hand.
#
# Applies to gh issue comment, gh pr comment and gh issue|pr close --comment.
# Blocks (exit 2, reason on stderr) when:
#  - the text has no authorship header line (scripts/lib/author.sh): the owner, the
#    manager, the children and the bots share one account, and a comment without the
#    header is read as the owner's;
#  - the text cites a bot of .github/bots.tsv (slug or name, any case; BOTS_FILE
#    overrides) or carries an <!-- ask:...: --> marker: a loose comment never
#    notifies the bot, so the request goes through scripts/ask-bot.sh (--append
#    for new information on an open question).
# The text is the command, its arguments and the files named by --body-file/-F; a
# heredoc stays in the command, so it is seen too.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$here/../../scripts/lib/common.sh"

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
[ -n "$cmd" ] || exit 0
[ -n "$cwd" ] || cwd="$PWD"

printf '%s' "$cmd" | stdin_grep -qE '(^|[;&| ])gh( +(-R|--repo)[ =]+[^ ]+)? +((issue|pr) +comment|(issue|pr) +close)( |$)' || exit 0
# close without --comment posts no comment.
if printf '%s' "$cmd" | stdin_grep -qE 'gh( +(-R|--repo)[ =]+[^ ]+)? +(issue|pr) +close'; then
  printf '%s' "$cmd" | stdin_grep -qE '(--comment|-c)([ =]|$)' || exit 0
fi

bots="${BOTS_FILE:-}"
[ -n "$bots" ] || bots="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$here/../..")/.github/bots.tsv"
# A request is explicit: @slug, the whole Para: recipient, or a complete
# <!-- ask:slug:id --> marker outside a code span. A slug inside another
# word, inside -R, or inside a path is not a request.
BOT_COMMENT_CMD="$cmd" python3 - "$cwd" "$bots" <<'PY'
import os, re, shlex, sys
cwd, bots_path = sys.argv[1], sys.argv[2]
cmd = os.environ.get("BOT_COMMENT_CMD", "")
UNREAD = "blocked by block-bot-comment: não li o --body-file; use caminho literal de um arquivo que já existe"

def die(msg):
    print(msg, file=sys.stderr)
    sys.exit(2)

try:
    words = shlex.split(cmd)
except ValueError:
    if "--body-file" in cmd or " -F " in cmd or "--file" in cmd:
        die(UNREAD)
    words = cmd.split()

paths = []
i = 0
while i < len(words):
    w = words[i]
    for flag in ("--body-file", "--file", "-F"):
        if w == flag and i + 1 < len(words):
            paths.append(words[i + 1]); i += 2; break
        if w.startswith(flag + "="):
            paths.append(w.split("=", 1)[1]); i += 1; break
    else:
        i += 1

files_text = []
for raw in paths:
    if raw == "-":
        continue
    if "$" in raw or raw.startswith("~") or not raw:
        die(UNREAD)
    path = raw if os.path.isabs(raw) else os.path.join(cwd, raw)
    if not os.path.isfile(path):
        die(UNREAD)
    with open(path, encoding="utf-8", errors="replace") as fh:
        files_text.append(fh.read())

text = cmd + "\n" + "\n".join(words) + "\n" + "\n".join(files_text)
# Drop the flag paths so a bot slug in -R or in the file path is not the comment.
for raw in paths:
    text = text.replace(raw, " ")

def bots():
    if not os.path.isfile(bots_path):
        return
    with open(bots_path, encoding="utf-8") as fh:
        for line in fh:
            if not line.strip() or line.startswith("#"):
                continue
            parts = line.rstrip("\n").split("\t")
            if parts and parts[0]:
                yield parts[0], parts[1] if len(parts) > 1 else ""

def header_ok(body):
    return re.search(r"(?m)^\*\*De:\*\* .+ · \*\*Para:\*\* .+ · \*\*Pedido:\*\* .+ · \*\*Responde a:\*\* .+", body) is not None

if not header_ok(text):
    die("blocked by block-bot-comment: a comment from an agent starts with the authorship header (AGENTS.md rule 6):\n"
        "**De:** <papel> · **Para:** <papel> · **Pedido:** <ask_id ou o quê> · **Responde a:** <link ou —>\n"
        "scripts/lib/author.sh: author_header; no header means the owner wrote it")

def recipients(body):
    m = re.search(r"\*\*Para:\*\*\s*(.*?)(?:\s*·|\s*$)", body)
    if not m:
        return []
    return [p.strip() for p in re.split(r"\s*,\s*|\s+e\s+", m.group(1).strip()) if p.strip()]

def names_bot(part, slug, name):
    bare = re.sub(r"(?i)^bot\s+", "", part).strip()
    return bare.lower() in {slug.lower(), (name or "").lower()}

for slug, name in bots():
    if re.search(r"(?<![\w-])@" + re.escape(slug) + r"(?![\w-])", text, re.I):
        die('blocked by block-bot-comment: the comment cites the bot "%s"; a request to a bot goes through scripts/ask-bot.sh <bot> <issue> "text" (--append for new information on an open question); a loose comment never notifies the bot' % slug)
    if any(names_bot(p, slug, name) for p in recipients(text)):
        die('blocked by block-bot-comment: the comment cites the bot "%s"; a request to a bot goes through scripts/ask-bot.sh <bot> <issue> "text" (--append for new information on an open question); a loose comment never notifies the bot' % (name or slug))

plain = re.sub(r"```.*?```", "", text, flags=re.S)
plain = re.sub(r"`[^`]*`", "", plain)
if re.search(r"<!--\s*ask:[A-Za-z0-9-]+:[A-Za-z0-9_-]+\s*-->", plain):
    die("blocked by block-bot-comment: <!-- ask: markers come only from scripts/ask-bot.sh")
sys.exit(0)
PY
