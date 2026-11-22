#!/usr/bin/env bash
# block-dangerous-git.sh: PreToolUse (Bash) hook that blocks forbidden git/gh commands.
#
# Reads the hook JSON on stdin (tool_input.command, cwd). Before tokenizing,
# its own scan, which respects quotes, joins line continuations (\),
# strips comments (#), ANSI-C quotes ($'…') and heredoc bodies that are only
# data; a heredoc handed to a shell (bash <<, | sh, source, eval) and the
# $(…)/`…` are checked apart as commands. Then
# Python's shlex splits the command respecting quotes: quoted text is
# one argument, never becomes a flag and never hides commands. It enters `bash -c`,
# `eval`, `bash <<<`, a heredoc to a shell and `echo … | bash`; it skips `env`,
# `command`, `nice`, `timeout`, `sudo`, blocks (`{ }`, `if … fi`, `!`) and
# absolute paths (/usr/bin/git). It follows `cd`, `pushd`, `git -C` and
# `git switch/checkout` within the same command.
#
# Blocks with exit 2 and the reason on stderr: git commit on main, commit with
# --no-verify/-n, turning hooks off (core.hooksPath by -c, --config-env, config
# in any syntax or GIT_CONFIG_*), git commit -a/--all, git add/stage
# -A/./:/ /-u, git push --force/-f/--mirror/+refspec, git reset --hard (also
# abbreviated) and any direct PR merge (`gh pr merge`, `gh api …
# pulls/N/merge`): the merge goes through scripts/close-phase.sh --merge.
# Also blocks the other ways around the gate: `gh api graphql` with a merge or
# branch-protection mutation (inline, by -F query=@file or --input; a request
# that cannot be read is blocked) and any write on …/branches/*/protection
# (a method other than GET, or request fields, which make gh send a POST).
# Also blocks `git clean` with `-f`/`--force` and `git branch -D` (or
# `--delete --force`). Also blocks every deploy dispatch outside scripts/deploy.sh:
# `gh workflow run`, `gh run rerun`, and `gh api` on a …/dispatches or …/rerun endpoint.
#
# Fails closed: a line that cannot be read safely, or a command too large
# to check quickly (>256 KB or >400 parts), that cites git/gh is
# blocked; a heredoc followed by `|` at the end of the line is checked as a command;
# any internal error exits 2.
#
# Known limit: it is a safeguard against mistakes, not against deliberate
# obfuscation (the same account can do anything). The real barriers are the protection
# of main (CI + review/independent, applies to admins) and .githooks/pre-commit.
#
# --git-writes (used by block-phase-commit.sh): blocks nothing and prints what
# the same parser found, one finding per line:
#   write<TAB><dir>   a git command outside the read-only list would run in <dir>
#                     (cwd, cd/pushd, -C, --git-dir, --work-tree, GIT_DIR, GIT_WORK_TREE)
#   push<TAB><dir><TAB><branch>  a git push run in <dir> would update <branch> on the
#                     remote (refspec destination, or the current branch when there is
#                     none); <branch> is * when it cannot be named (--all, --mirror,
#                     --branches, a pattern, an unexpanded variable)
#   forge<TAB><name>  the command sets or unsets a variable the phase locks read
#   unreadable        a part that cites git/gh could not be read safely
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "blocked by block-dangerous-git: python3 is required to check commands" >&2
  exit 2
fi

# The code goes by argument; the hook JSON stays on stdin (no size limit).
code=""
IFS= read -r -d '' code <<'PY' || true
import json
import os
import re
import shlex
import subprocess
import sys

SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
KEYWORDS = {"{", "}", "!", "if", "then", "else", "elif", "fi", "do", "done", "while",
            "until", "case", "esac", "function", "time"}
# Prefixes that run the next command, with the options that take a value.
WRAPPERS = {
    "env": {"-u", "--unset", "-C", "--chdir", "-S", "--split-string"},
    "command": set(), "exec": {"-a"}, "nohup": set(), "builtin": set(),
    "nice": {"-n", "--adjustment"}, "ionice": {"-c", "-n", "-p"},
    "sudo": {"-u", "-g", "-C", "-D", "-h", "-p", "-U"},
    "xargs": {"-I", "-n", "-P", "-L", "-d", "-s", "-E", "-a"},
    "timeout": {"-s", "--signal", "-k", "--kill-after"},
    "stdbuf": {"-i", "-o", "-e"},
    "caffeinate": {"-t", "-w"}, "arch": set(), "watch": {"-n", "--interval", "-d"},
    "chronic": set(), "unbuffer": set(), "doas": {"-u"}, "flock": {"-w", "-E"},
}
POSITIONAL_WRAPPER_ARGS = {"timeout": 1}  # timeout <duration> command
OPERATOR_CHARS = set(";&|()\n")
# --git-writes: findings are collected here instead of blocking.
COLLECT = [] if sys.argv[1:2] == ["--git-writes"] else None
# Git subcommands that never write history, the index or the work tree.
READ_ONLY = {"status", "log", "diff", "show", "rev-parse", "rev-list", "ls-files", "ls-tree",
             "cat-file", "blame", "grep", "describe", "for-each-ref", "show-ref", "merge-base",
             "diff-tree", "shortlog", "name-rev", "check-ignore", "ls-remote", "fetch",
             "version", "help"}
READ_ONLY_BRANCH_ARGS = {"--show-current", "-a", "--all", "-r", "--remotes", "-v", "-vv", "--list", "-l"}
# Variables the phase locks read: no command sets or unsets them.
LOCK_VARS = r"(CLAUDE_CODE_SESSION_ID|PROCESS_EVENTS_FILE)"
DECLARERS = {"unset", "export", "env", "declare", "typeset", "readonly", "local"}


class Blocked(Exception):
    pass


def block(reason):
    if COLLECT is not None:
        return
    raise Blocked(reason)


def unreadable(reason):
    """A part that cannot be read safely: blocked, or reported under --git-writes."""
    if COLLECT is not None:
        COLLECT.append("unreadable")
        return
    raise Blocked(reason)


def expand(word, variables):
    """$VAR and ${VAR} of simple assignments seen earlier in the command."""
    return re.sub(r"\$(\w+)|\$\{(\w+)\}",
                  lambda m: variables.get(m.group(1) or m.group(2), m.group(0)), word)


# ---------- scan before shlex ----------

HEREDOC_RE = re.compile(r"<<(-?)[ \t]*([^\s;&|()<>]+)")
# Line that hands the heredoc to a shell (bash <<, cat <<X | sh, source, eval, .).
SHELLISH_RE = re.compile(r"(^|[\s|;&(])((\S*/)?(ba|z|da|k)?sh|source|eval|\.)(\s|$)")
MAX_CHECKED = 262144  # above this there is no fast check: fail closed
MAX_SEGMENTS = 400    # the same for commands with many parts


def heredoc_delim(word):
    """Delimiter as the shell reads it: without quotes and backslashes (E"OF" -> EOF)."""
    return re.sub(r"\\(.)", r"\1", word).replace('"', "").replace("'", "")


def matching(text, start, open_ch, close_ch):
    """Index of the closing of $( … ) from start (after the opener),
    skipping quotes and heredoc bodies."""
    depth, i, quote, pending = 1, start, None, []
    while i < len(text):
        c = text[i]
        if quote is None and c == "\n" and pending:
            # Skip heredoc bodies: quotes inside them are text.
            i += 1
            for strip_tabs, delim in pending:
                while i < len(text):
                    end = text.find("\n", i)
                    end = len(text) if end < 0 else end
                    raw = text[i:end]
                    i = end + 1
                    if (raw.lstrip("\t") if strip_tabs else raw) == delim:
                        break
            pending = []
            continue
        if quote is None and text.startswith("<<", i) and not text.startswith("<<<", i):
            m = HEREDOC_RE.match(text, i)
            if m:
                pending.append((m.group(1) == "-", heredoc_delim(m.group(2))))
                i = m.end(); continue
        if quote:
            if c == "\\" and quote == '"':
                i += 2; continue
            if c == quote:
                quote = None
        elif c in "'\"":
            quote = c
        elif c == "\\":
            i += 2; continue
        elif c == open_ch:
            depth += 1
        elif c == close_ch:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def prescan(text):
    """Strip comments and $'…'; extract $(…) and `…`. Returns (text, subcommands)."""
    out, subs, i, quote = [], [], 0, None
    pending, line_start = [], 0  # heredocs opened on this line
    escaped_end = -1  # position right after the last escaped character
    n = len(text)
    while i < n:
        c = text[i]
        if c == "\\" and quote != "'" and text.startswith("\\\n", i):
            i += 2; continue  # line continuation: joins the lines
        if c == "\n" and quote is None and pending:
            line = text[line_start:i]
            out.append(c); i += 1
            for strip_tabs, delim in pending:
                body = []
                while i < n:
                    end = text.find("\n", i)
                    end = n if end < 0 else end
                    raw = text[i:end]
                    i = end + 1
                    if (raw.lstrip("\t") if strip_tabs else raw) == delim:
                        break
                    body.append(raw)
                if SHELLISH_RE.search(line) or re.search(r"\|\s*$", line):
                    subs.append("\n".join(body))  # goes (or may go) to a shell: it is a command
            pending, line_start = [], i
            continue
        if c == "\n" and quote is None:
            line_start = i + 1
        if quote is None and c == "<" and text.startswith("<<", i) and not text.startswith("<<<", i):
            m = HEREDOC_RE.match(text, i)
            if m:
                pending.append((m.group(1) == "-", heredoc_delim(m.group(2))))
                out.append(text[i:m.end()]); i = m.end(); continue
        if quote == "'":
            out.append(c)
            if c == "'":
                quote = None
            i += 1; continue
        if c == "\\" and i + 1 < n:
            out.append(text[i:i + 2]); i += 2; escaped_end = i; continue
        if c == "$" and text.startswith("$(", i) and not text.startswith("$((", i):
            end = matching(text, i + 2, "(", ")")
            if end < 0:
                raise ValueError("unclosed $(")
            subs.append(text[i + 2:end]); out.append("X"); i = end + 1; continue
        if c == "`":
            end = text.find("`", i + 1)
            if end < 0:
                raise ValueError("unclosed backtick")
            subs.append(text[i + 1:end]); out.append("X"); i = end + 1; continue
        if quote == '"':
            out.append(c)
            if c == '"':
                quote = None
            i += 1; continue
        # Outside quotes.
        if c == "$" and text.startswith("$'", i):
            j = i + 2
            while j < n and text[j] != "'":
                j += 2 if text[j] == "\\" else 1
            if j >= n:
                raise ValueError("unclosed $'")
            out.append("'X'"); i = j + 1; continue
        if c == "#" and i != escaped_end and (i == 0 or text[i - 1] in " \t\n;&|("):
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c in "'\"":
            quote = c
        out.append(c)
        i += 1
    if quote:
        raise ValueError("unbalanced quotes")
    return "".join(out), subs


def tokenize(text):
    lex = shlex.shlex(text, posix=True, punctuation_chars=";&|()<>\n")
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    lex.commenters = ""
    return list(lex)


def segments(tokens):
    """Tokens -> list of (command, previous operator)."""
    out, cur, before = [], [], None
    for t in tokens:
        if t and set(t) <= OPERATOR_CHARS:
            if cur:
                out.append((cur, before))
            cur, before = [], t
        else:
            cur.append(t)
    if cur:
        out.append((cur, before))
    return out


def take_herestring(argv):
    """Strip `<<< text` and redirections; returns (argv, herestring text)."""
    out, here, i = [], None, 0
    while i < len(argv):
        t = argv[i]
        if t == "<<<" and i + 1 < len(argv):
            here = argv[i + 1]; i += 2; continue
        if re.fullmatch(r"[0-9]*(>>?|<|&>)", t):
            i += 2; continue
        if re.fullmatch(r"[0-9]*[<>]+&?[0-9-]*", t):
            i += 1; continue
        out.append(t); i += 1
    return out, here


# ---------- regras ----------

def abbrev(arg, full, minlen):
    """True if arg is full or an abbreviation accepted by git (--forc)."""
    name = arg.split("=", 1)[0]
    return name.startswith("--") and len(name) >= minlen and full.startswith(name)


def short_flags(tok):
    return tok[1:] if re.fullmatch(r"-[A-Za-z]+", tok) else ""


def hookspath_off(key, value):
    return key.lower() == "core.hookspath" and value.strip() != ".githooks"


BRANCH_CACHE = {}


def branch_of(path):
    if path in BRANCH_CACHE:
        return BRANCH_CACHE[path]
    BRANCH_CACHE[path] = _branch_of(path)
    return BRANCH_CACHE[path]


def _branch_of(path):
    try:
        return subprocess.run(["git", "-C", path, "branch", "--show-current"],
                              capture_output=True, text=True, timeout=5).stdout.strip()
    except Exception:
        return ""


class State:
    def __init__(self, cwd):
        self.dir = cwd
        self.switched = None
        self.vars = {}      # simple assignments (d=/path; git -C $d ...)
        self.exported = {}  # export NAME=value: environment of the next commands


def resolve(base, path):
    path = os.path.expanduser(path)
    return path if os.path.isabs(path) else os.path.join(base, path)


PUSH_VALUED = {"-o", "--push-option", "--repo", "--receive-pack", "--exec", "--recurse-submodules"}


def push_destinations(rest, current):
    """Branches a `git push` would update on the remote: the destination of each
    refspec, or the current branch when there is none. "*" stands for every branch."""
    dests, positional, j = [], [], 0
    while j < len(rest):
        a = rest[j]
        if a in PUSH_VALUED:
            j += 2; continue
        if abbrev(a, "--all", 4) or abbrev(a, "--mirror", 4) or abbrev(a, "--branches", 4):
            dests.append("*")
        elif not a.startswith("-"):
            positional.append(a)
        j += 1
    refspecs = positional[1:]  # the first one is the remote
    if not refspecs and not dests:
        refspecs = ["HEAD"]
    for spec in refspecs:
        dest = spec.lstrip("+").rsplit(":", 1)[-1]
        if dest in ("HEAD", "@"):
            dest = current
        if "*" in dest or "$" in dest:
            dest = "*"
        elif dest.startswith("refs/heads/"):
            dest = dest[len("refs/heads/"):]
        elif dest.startswith("refs/"):
            continue  # a tag or another namespace: not a branch
        if dest:
            dests.append(dest)
    return dests


def check_git(args, state, env):
    if any(k.startswith("GIT_CONFIG_KEY") and v.lower() == "core.hookspath" for k, v in env.items()):
        block("never disable or redirect the git hooks")
    target, i = state.dir, 0
    env = dict(state.exported, **env)
    places = [env[k] for k in ("GIT_DIR", "GIT_WORK_TREE") if env.get(k)]
    while i < len(args) and args[i].startswith("-"):
        a = args[i]
        if a == "-C" and i + 1 < len(args):
            target = resolve(target, args[i + 1]); i += 2; continue
        if a in ("-c", "--config-env") and i + 1 < len(args):
            key = args[i + 1].split("=", 1)[0]
            if key.lower() == "core.hookspath":
                value = args[i + 1].split("=", 1)[1] if "=" in args[i + 1] else ""
                if a == "--config-env" or hookspath_off(key, value):
                    block("never disable or redirect the git hooks")
            i += 2; continue
        if a.startswith("--config-env="):
            if a.split("=", 2)[1].lower() == "core.hookspath":
                block("never disable or redirect the git hooks")
            i += 1; continue
        if a in ("--git-dir", "--work-tree") and i + 1 < len(args):
            places.append(args[i + 1])
        if a.startswith(("--git-dir=", "--work-tree=")):
            places.append(a.split("=", 1)[1])
        if a in ("--git-dir", "--work-tree", "--namespace", "--exec-path"):
            i += 2; continue
        i += 1
    if i >= len(args):
        return
    sub, rest = args[i], args[i + 1:]
    if COLLECT is not None and sub not in READ_ONLY \
            and not (sub == "branch" and set(rest) <= READ_ONLY_BRANCH_ARGS):
        for place in [target] + [resolve(target, p) for p in places]:
            COLLECT.append("write\t" + os.path.normpath(place))

    if sub in ("switch", "checkout"):
        if "--" in rest:
            return  # checkout -- file: only restores files
        new = None
        for j, a in enumerate(rest):
            if a in ("-c", "-C", "-b", "-B", "--create", "--orphan") and j + 1 < len(rest):
                new = rest[j + 1]
        positional = [a for a in rest if not a.startswith("-")]
        if sub == "checkout" and not new and len(positional) >= 2:
            return  # checkout <ref> <file>: only restores files
        name = new or (positional[0] if positional else None)
        if name:
            state.switched = name
        return

    if sub == "config":
        # Any syntax: `config k v`, `config set k v`, `--file f k v`, `unset k`.
        takes_value = {"-f", "--file", "--blob", "--type", "--default", "--comment", "--value"}
        positional, j = [], 0
        while j < len(rest):
            a = rest[j]
            if a in takes_value:
                j += 2; continue
            if not a.startswith("-"):
                positional.append(a)
            j += 1
        lowered = [p.lower() for p in positional]
        if "core.hookspath" in lowered:
            k = lowered.index("core.hookspath")
            unset = any(a.startswith("--unset") for a in rest) or "unset" in lowered[:k]
            value = positional[k + 1] if k + 1 < len(positional) else None
            if unset or (value is not None and value != ".githooks"):
                block("never disable or redirect the git hooks")
        return

    if sub == "commit":
        branch = state.switched or branch_of(target)
        if branch in ("main", "master"):
            block("never commit on %s (open a phase branch with scripts/phase-start.sh)" % branch)
        takes_value = {"-m", "-F", "-c", "-C", "-t", "--author", "--date", "--message",
                       "--file", "--template", "--cleanup", "--fixup", "--squash", "--trailer"}
        j = 0
        while j < len(rest):
            a = rest[j]
            if abbrev(a, "--no-verify", 6):
                block("never skip the git hooks (--no-verify)")
            if a == "--all":
                block("git commit -a/--all adds files blindly; stage files by name")
            flags = short_flags(a)
            if flags:
                # Letters that take a value (-m, -F, -c, -C, -t) or an optional
                # attached value (-u, -S<keyid>) end the flags: the rest is the value (-uno,
                # -mrename, -Sabc).
                stop = ""
                for pos, ch in enumerate(flags):
                    if ch == "n":
                        block("never skip the git hooks (--no-verify)")
                    if ch == "a":
                        block("git commit -a/--all adds files blindly; stage files by name")
                    if ch in "mFcCtuS":
                        stop = ch if pos == len(flags) - 1 else "attached"
                        break
                if stop in ("m", "F", "c", "C", "t"):
                    j += 2; continue
                j += 1; continue
            if a in takes_value:
                j += 2; continue
            j += 1
        return

    if sub in ("add", "stage"):
        for a in rest:
            if a in (".", ":/", ":", "-A", "-u") or a.startswith(":/") \
                    or abbrev(a, "--all", 4) or abbrev(a, "--update", 4) \
                    or abbrev(a, "--no-ignore-removal", 6):
                block("git add -A/./--all stages blindly; add files by name")
            flags = short_flags(a)
            if flags and ("A" in flags or "u" in flags):
                block("git add -A/./--all stages blindly; add files by name")
        return

    if sub == "push":
        if COLLECT is not None:
            current = state.switched or branch_of(target)
            for dest in push_destinations(rest, current):
                COLLECT.append("push\t%s\t%s" % (os.path.normpath(target), dest))
        for a in rest:
            if abbrev(a, "--force", 5) or abbrev(a, "--force-with-lease", 5) \
                    or abbrev(a, "--force-if-includes", 5) or abbrev(a, "--mirror", 4) \
                    or a.startswith("+"):
                block("never force-push or rewrite published history")
            flags = short_flags(a)
            if flags and "f" in flags:
                block("never force-push or rewrite published history")
        return

    if sub == "reset":
        if any(abbrev(a, "--hard", 4) for a in rest):
            block("never git reset --hard")
        return

    if sub == "clean":
        for a in rest:
            if abbrev(a, "--force", 5):
                block("never git clean -f")
            flags = short_flags(a)
            if flags and "f" in flags:
                block("never git clean -f")
        return

    if sub == "branch":
        force_delete = False
        delete = False
        for a in rest:
            if a in ("-D",):
                force_delete = True
            if a in ("-d", "--delete") or abbrev(a, "--delete", 5):
                delete = True
            if a in ("-f", "--force") or abbrev(a, "--force", 5):
                force_delete = force_delete or delete
            flags = short_flags(a)
            if flags and "D" in flags:
                force_delete = True
            if flags and "d" in flags:
                delete = True
            if flags and "f" in flags and delete:
                force_delete = True
        if force_delete:
            block("never git branch -D")
        return


GH_VALUED = ("-R", "--repo", "-X", "--method", "-H", "--header", "-f", "-F", "--field",
             "--raw-field", "--jq", "-q", "--template", "-t", "--hostname", "--input", "--cache",
             "-p", "--preview")
GH_FIELD_FLAGS = ("-f", "-F", "--field", "--raw-field", "--input")
# GraphQL mutations that merge a PR or change the protection of a branch.
GRAPHQL_GATE = re.compile(r"\b(mergePullRequest|enablePullRequestAutoMerge|enqueuePullRequest|mergeBranch"
                          r"|(create|update|delete)BranchProtectionRule)\b")
PROTECTION_PATH = re.compile(r"branches/[^/\s]+/protection")


def gh_api_request(args):
    """(method or None, has request fields, files the request body comes from)."""
    method, fields, files, i = None, False, [], 0
    while i < len(args):
        a = args[i]
        value = args[i + 1] if i + 1 < len(args) else ""
        if a in ("-X", "--method"):
            method = value.upper(); i += 2; continue
        if a.startswith("--method="):
            method = a.split("=", 1)[1].upper()
        elif re.fullmatch(r"-X[A-Za-z]+", a):
            method = a[2:].upper()
        if a in GH_FIELD_FLAGS:
            fields = True
            if a == "--input":
                files.append(value)
            elif a in ("-F", "--field") and "=@" in value:
                files.append(value.split("=@", 1)[1])
            i += 2; continue
        if a.startswith(("--field=", "--raw-field=", "--input=")) or re.fullmatch(r"-[fF].+", a):
            fields = True
            if a.startswith("--input="):
                files.append(a.split("=", 1)[1])
            elif not a.startswith(("--raw-field=", "-f")) and "=@" in a:
                files.append(a.split("=@", 1)[1])
        i += 1
    return method, fields, files


def check_gh(args, state):
    positional, i = [], 0
    while i < len(args):
        a = args[i]
        if a in GH_VALUED:
            i += 2; continue
        if not a.startswith("-"):
            positional.append(a)
        i += 1
    if positional[:2] == ["pr", "merge"]:
        if "--admin" in args:
            block("never merge as admin; go through the gate (CI + review/independent)")
        block("merge only with scripts/close-phase.sh --merge (checks needs-owner-ok and the gate, then --rebase)")
    if positional[:1] == ["api"] and any(re.search(r"pulls/[0-9]+/merge", a) for a in args):
        block("merge only with scripts/close-phase.sh --merge")
    deploy_only = "deploy only with scripts/deploy.sh, run by the main session after the last merge"
    if positional[:2] in (["workflow", "run"], ["run", "rerun"]):
        block(deploy_only)
    if positional[:1] == ["api"] and any(re.search(r"(^|/)(dispatches|rerun(-failed-jobs)?)/?([?#]|$)", a) for a in args):
        block(deploy_only)
    if positional[:1] != ["api"]:
        return
    method, fields, files = gh_api_request(args)
    if any(PROTECTION_PATH.search(a) for a in args) and (method not in (None, "GET") or (method is None and fields)):
        block("never write the branch protection by hand; it is set only by scripts/setup-repo.sh")
    if positional[:2] == ["api", "graphql"]:
        # The query may come from a file: read it, and fail closed when it cannot be read.
        text = list(args)
        for f in files:
            try:
                with open(resolve(state.dir, f), encoding="utf-8", errors="replace") as fh:
                    text.append(fh.read(MAX_CHECKED))
            except OSError:
                block("could not read the GraphQL request of this gh api call (%s); pass the query inline" % f)
        if any(GRAPHQL_GATE.search(t) for t in text):
            block("never merge or change the branch protection through GraphQL; "
                  "merge only with scripts/close-phase.sh --merge")


# ---------- analysis ----------

def analyze(text, state, depth=0):
    if depth > 6:
        unreadable("command nesting too deep to check")
        return
    if len(text) > MAX_CHECKED:
        if re.search(r"\b(git|gh)\b", text):
            unreadable("command too long to check safely; write large content with a file tool")
        return
    try:
        clean, subs = prescan(text)
        tokens = tokenize(clean)
    except ValueError:
        # Fail closed: what cannot be read and cites git/gh does not pass.
        if re.search(r"\b(git|gh)\b", text):
            unreadable("could not parse this git/gh command safely; simplify the quoting")
        return
    for sub in subs:
        analyze(sub, state, depth + 1)
    analyze_tokens(tokens, state, depth)


def analyze_tokens(tokens, state, depth):
    prev = None
    parts = segments(tokens)
    if len(parts) > MAX_SEGMENTS and any(t in ("git", "gh") or re.fullmatch(r"\S*/(git|gh)", t) for t in tokens):
        unreadable("too many commands in one call to check safely; split it")
    for argv, before in parts:
        argv, herestring = take_herestring(argv)
        argv = [expand(t, state.vars) for t in argv]
        if COLLECT is not None:
            declares = any(os.path.basename(t) in DECLARERS for t in argv)
            for t in argv:
                m = re.fullmatch(LOCK_VARS + r"(=.*)?", t, re.S)
                if m and (m.group(2) is not None or declares):
                    COLLECT.append("forge\t" + m.group(1))
        env = {}
        while argv:
            m = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_]*)=(.*)", argv[0], re.S)
            if m:
                env[m.group(1)] = m.group(2); argv = argv[1:]; continue
            if argv[0] in KEYWORDS:
                argv = argv[1:]; continue
            name = os.path.basename(argv[0].lstrip("\\"))
            if name in WRAPPERS:
                valued, argv = WRAPPERS[name], argv[1:]
                while argv and (argv[0].startswith("-") or re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", argv[0], re.S)):
                    argv = argv[2:] if argv[0] in valued else argv[1:]
                argv = argv[POSITIONAL_WRAPPER_ARGS.get(name, 0):]
                continue
            break
        if not argv:
            state.vars.update(env)
            prev = None
            continue
        # Unknown prefix followed by /path/git: check from there.
        for k in range(1, len(argv)):
            if re.fullmatch(r"\S*/(git|gh)", argv[k]):
                analyze_tokens(argv[k:], state, depth)
                break
        name = os.path.basename(argv[0].lstrip("\\"))
        args = argv[1:]
        if name in SHELLS:
            payload, j = None, 0
            while j < len(args):
                a = args[j]
                if a in ("-o", "+o", "-O", "+O"):
                    j += 2; continue
                if a.startswith("-") and not a.startswith("--") and "c" in a[1:]:
                    rest = [x for x in args[j + 1:] if not x.startswith("-")]
                    payload = rest[0] if rest else ""
                    break
                if not a.startswith(("-", "+")):
                    break
                j += 1
            if payload is not None:
                analyze(payload, state, depth + 1)
            elif herestring is not None:
                analyze(herestring, state, depth + 1)
            elif before in ("|", "|&") and prev:
                # echo "…" | bash: the text that enters the shell is a command.
                analyze(" ".join(prev[1:]), state, depth + 1)
        elif name == "eval":
            analyze(" ".join(args), state, depth + 1)
        elif name == "export":
            for a in args:
                m = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_]*)=(.*)", a, re.S)
                if m:
                    state.vars[m.group(1)] = state.exported[m.group(1)] = m.group(2)
        elif name in ("cd", "pushd"):
            dest = [a for a in args if a != "--" and not a.startswith("-")]
            if dest:
                state.dir = resolve(state.dir, dest[0])
        elif name == "git":
            check_git(args, state, env)
        elif name == "gh":
            check_gh(args, state)
        prev = argv


def main():
    raw = sys.stdin.read()
    try:
        data = json.loads(raw) if raw.strip() else {}
    except ValueError:
        block("invalid hook input")
    command = (data.get("tool_input") or {}).get("command") or ""
    cwd = data.get("cwd") or os.getcwd()
    analyze(command, State(cwd))
    if COLLECT is not None:
        sys.stdout.write("".join(line + "\n" for line in COLLECT))


try:
    main()
except Blocked as e:
    sys.stderr.write("blocked by block-dangerous-git: %s\n" % e)
    sys.exit(2)
except Exception as e:  # internal error: fail closed
    sys.stderr.write("blocked by block-dangerous-git: internal error (%s)\n" % e)
    sys.exit(2)
sys.exit(0)
PY
exec python3 -c "$code" "$@"
