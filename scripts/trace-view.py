#!/usr/bin/env python3
"""trace-view.py: render the agent tree from the trace as static HTML.

Usage:
  trace-view.py [--events FILE] [--out FILE] [--text]

Reads the JSONL trace (default: .process/events.jsonl in the main checkout)
and always writes a self-contained HTML tree (default: .process/tree.html).
With --text it also prints the tree as plain text on stdout (paste it in a PR).
With --pairs ISSUE it only prints the "requested x used" table of the phase of
the issue, in Markdown, and writes no HTML: one row for each session that ran
check-env.sh in the phase (pair asked by the spec x real pair, both from its
phase_session event) and one row for each subagent of those sessions (pair asked
in the Agent call x model and effort it ran with). A used value that differs
from the requested one is marked "(diverge)"; a value the trace does not hold
is "?". close-phase.sh --prepare writes this table in the PR body.
Invalid JSON lines are skipped and counted ("skipped N bad line").

Tree: planning -> triage -> phase #N -> subagents -> reviewer -> bots.
Each node shows status (running/done/closed/waiting/replied), model, effort
and duration. Synthetic events (planning that ran before the hook) are marked.
"""

import argparse
import datetime
import html
import json
import os
import subprocess
import sys

SCRIPT_EVENTS = ("bot_ask", "bot_reply", "review_round", "phase_closed")
SUB_LABELS = {"triage": "triage", "close-reviewer": "reviewer"}


def parse_ts(value):
    """Converts the ISO UTC ts to a datetime; None if invalid."""
    try:
        text = str(value)
        if text.endswith("Z"):
            text = text[:-1] + "+00:00"
        dt = datetime.datetime.fromisoformat(text)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=datetime.timezone.utc)
        return dt
    except (ValueError, TypeError):
        return None


def load_events(lines):
    """Returns (events in time order, number of invalid lines). Blank lines do not count."""
    events, bad = [], 0
    for n, line in enumerate(lines):
        if not line.strip():
            continue
        try:
            ev = json.loads(line)
        except ValueError:
            bad += 1
            continue
        if not isinstance(ev, dict) or not ev.get("event") or parse_ts(ev.get("ts")) is None:
            bad += 1
            continue
        ev["_t"] = parse_ts(ev["ts"])
        ev["_n"] = n
        events.append(ev)
    events.sort(key=lambda e: (e["_t"], e["_n"]))
    return events, bad


def node(kind, label, status="", model="", effort="", start=None, end=None):
    return {"kind": kind, "label": label, "status": status, "model": model, "effort": effort,
            "model_requested": False, "start": start, "end": end, "synthetic": False,
            "notes": [], "children": []}


def span(nd, t):
    """Extends the interval of the node up to the instant t."""
    if nd["start"] is None or t < nd["start"]:
        nd["start"] = t
    if nd["end"] is None or t > nd["end"]:
        nd["end"] = t


def build_sessions(events):
    """One node per session_id (hook events), with subagents as children."""
    sessions, order = {}, []
    for ev in events:
        sid = ev.get("session_id") or ""
        if not sid or ev["event"] in SCRIPT_EVENTS:
            continue
        if sid not in sessions:
            sessions[sid] = {"id": sid, "events": [], "issue": "", "node": None}
            order.append(sid)
        s = sessions[sid]
        s["events"].append(ev)
        if not s["issue"] and ev.get("issue"):
            s["issue"] = str(ev["issue"])
    # A session with only SessionEnd/Stop (e.g. a `claude plugin ...` run by a subagent) is left out.
    order = [sid for sid in order
             if any(e["event"] not in ("SessionEnd", "Stop") for e in sessions[sid]["events"])]
    for sid in order:
        s = sessions[sid]
        issue = s["issue"]
        nd = node("phase" if issue else "planning", ("phase #%s" % issue) if issue else "planning")
        s["node"] = nd
        own = [e for e in s["events"] if not e.get("agent_id") and e["event"] != "PreToolUse"]
        for e in own:
            if e.get("model") and not nd["model"]:
                nd["model"] = e["model"]
            if e.get("effort") and not nd["effort"]:
                nd["effort"] = e["effort"]
        for e in s["events"]:
            span(nd, e["_t"])
            if e.get("synthetic"):
                nd["synthetic"] = True
        ended = any(e["event"] == "SessionEnd" for e in own)
        nd["status"] = "done" if ended or nd["synthetic"] else "running"
        add_subagents(s)
    return sessions, order


def add_subagents(s):
    """Subagents by agent_id, linked to the previous PreToolUse Agent of the same session (in order)."""
    nd = s["node"]
    requests = [e for e in s["events"] if e["event"] == "PreToolUse"]
    # PostToolUse of the Agent: subagent_id -> tool_use_id of the request (exact link).
    by_tool = {r.get("tool_use_id"): r for r in requests if r.get("tool_use_id")}
    linked = {e["subagent_id"]: by_tool.get(e.get("tool_use_id"))
              for e in s["events"] if e["event"] == "PostToolUse" and e.get("subagent_id")}
    used = set(id(r) for r in linked.values() if r is not None)
    subs, sub_order = {}, []
    for e in s["events"]:
        aid = e.get("agent_id")
        if not aid or e["event"] not in ("SubagentStart", "SubagentStop"):
            continue
        if aid not in subs:
            subs[aid] = {"start": None, "stop": None, "type": e.get("agent_type") or "", "ev": e}
            sub_order.append(aid)
        if e["event"] == "SubagentStart":
            subs[aid]["start"] = e
        else:
            subs[aid]["stop"] = e
    for aid in sub_order:
        sub = subs[aid]
        first = sub["start"] or sub["stop"]
        pick = linked.get(aid)
        if pick is None:
            # Without PostToolUse: the previous request still free, in order.
            cands = [r for r in requests if id(r) not in used and r["_t"] <= first["_t"]]
            pick = next((r for r in cands if r.get("subagent_type") == sub["type"]), cands[0] if cands else None)
            if pick is not None:
                used.add(id(pick))
        label = SUB_LABELS.get(sub["type"], sub["type"] or "subagent")
        child = node("subagent", label, "done" if sub["stop"] else "running")
        if pick is not None and pick.get("description"):
            child["notes"].append(pick["description"])
        # The request (PreToolUse) wins over the SubagentStart value, which may come from the session.
        req = pick or {}
        model = req.get("model") or first.get("model") or ""
        effort = req.get("effort") or first.get("effort") or ""
        child["model"], child["effort"] = model, effort
        child["model_requested"] = bool(req.get("model") or req.get("effort"))
        # Effort the subagent ran with: the one from SubagentStop (the SubagentStart one is the default).
        if sub["stop"] is not None and sub["stop"].get("effort"):
            child["effort_used"] = sub["stop"]["effort"]
        # Model it ran with: the hook reads it from the subagent transcript at SubagentStop.
        if sub["stop"] is not None and sub["stop"].get("model"):
            child["model_used"] = sub["stop"]["model"]
        for e in (sub["start"], sub["stop"]):
            if e is not None:
                span(child, e["_t"])
        nd["children"].append(child)


def fmt_duration(start, end):
    if start is None or end is None:
        return ""
    secs = max(0, int((end - start).total_seconds()))
    h, rem = divmod(secs, 3600)
    m, s = divmod(rem, 60)
    if h:
        return "%dh %02dm" % (h, m)
    if m:
        return "%dm %02ds" % (m, s)
    return "%ds" % s


def build_tree(events):
    """Tree: root -> planning -> phases/subagents -> bots. Returns the root node."""
    root = node("root", "trace", "")
    sessions, order = build_sessions(events)
    plannings = [sessions[i] for i in order if not sessions[i]["issue"]]
    phases = [sessions[i] for i in order if sessions[i]["issue"]]
    for s in plannings:
        root["children"].append(s["node"])
    for s in phases:
        parent = root
        for p in plannings:
            if p["node"]["start"] <= s["node"]["start"]:
                parent = p["node"]
        parent["children"].append(s["node"])

    def phase_for(ev):
        """Phase of a script event: by the session; otherwise the last one of the same issue that started before."""
        s = sessions.get(ev.get("session_id") or "")
        if s is not None and s["issue"]:
            return s
        found = None
        for p in phases:
            if p["issue"] == str(ev.get("issue") or "") and p["node"]["start"] <= ev["_t"]:
                found = p
        return found

    bots = {}
    for ev in events:
        kind = ev["event"]
        if kind not in SCRIPT_EVENTS:
            continue
        ph = phase_for(ev)
        target = ph["node"] if ph else root
        if kind in ("bot_ask", "bot_reply"):
            key = (str(ev.get("issue") or ""), str(ev.get("ask_id") or ev["_n"]), str(ev.get("bot") or ""))
            if key not in bots:
                b = node("bot", "bot %s" % (ev.get("bot") or "?"), "waiting")
                bots[key] = b
                target["children"].append(b)
            b = bots[key]
            span(b, ev["_t"])
            if kind == "bot_reply":
                b["status"] = "replied"
        elif kind == "review_round":
            target["notes"].append("review round %s: %s" % (ev.get("round", "?"), ev.get("verdict", "?")))
            span(target, ev["_t"])
        else:  # phase_closed
            target["status"] = "closed"
            target["notes"].append("phase closed")
            span(target, ev["_t"])
    return root


def line_of(nd):
    """One-line text of the node."""
    parts = [nd["label"]]
    if nd["synthetic"]:
        parts.append("(synthetic)")
    if nd["status"]:
        parts.append("[%s]" % nd["status"])
    me = "/".join(x for x in (nd["model"], nd["effort"]) if x)
    if me:
        parts.append(me + (" (requested)" if nd["model_requested"] else ""))
    if nd.get("effort_used"):
        parts.append("effort used %s" % nd["effort_used"])
    dur = fmt_duration(nd["start"], nd["end"])
    if dur:
        parts.append(dur)
    return " ".join(parts)


def render_text(tree):
    out = []

    def walk(nd, depth):
        out.append("%s- %s" % ("  " * depth, line_of(nd)))
        for note in nd["notes"]:
            out.append("%s  · %s" % ("  " * depth, note))
        for c in nd["children"]:
            walk(c, depth + 1)

    if not tree["children"]:
        return "(empty trace)\n"
    for c in tree["children"]:
        walk(c, 0)
    return "\n".join(out) + "\n"


CSS = """
:root { --bg:#fff; --fg:#1b1f24; --muted:#586069; --line:#d0d7de; --card:#f6f8fa;
  --running:#9a6700; --done:#1a7f37; --closed:#0969da; --waiting:#bc4c00; --replied:#8250df; }
@media (prefers-color-scheme: dark) { :root { --bg:#0d1117; --fg:#e6edf3; --muted:#8b949e; --line:#30363d;
  --card:#161b22; --running:#d29922; --done:#3fb950; --closed:#58a6ff; --waiting:#f0883e; --replied:#bc8cff; } }
body { background:var(--bg); color:var(--fg); font:15px/1.5 system-ui,-apple-system,sans-serif; margin:0; padding:16px; }
h1 { font-size:1.2rem; margin:0 0 12px; }
ul { list-style:none; margin:0; padding-left:20px; border-left:1px solid var(--line); }
body > ul { border-left:0; padding-left:0; }
li { margin:4px 0; }
summary, .leaf { background:var(--card); border:1px solid var(--line); border-radius:6px; padding:4px 8px; }
summary { cursor:pointer; }
.badge { font-size:.8rem; font-weight:600; margin:0 4px; }
.running { color:var(--running); } .done { color:var(--done); } .closed { color:var(--closed); }
.waiting { color:var(--waiting); } .replied { color:var(--replied); }
.meta { color:var(--muted); font-size:.85rem; }
.note { color:var(--muted); font-size:.85rem; margin:2px 0 0 12px; }
.synthetic { font-style:italic; color:var(--muted); }
"""


def render_html(tree):
    esc = html.escape

    def head(nd):
        bits = ['<strong>%s</strong>' % esc(nd["label"])]
        if nd["synthetic"]:
            bits.append('<span class="synthetic">(synthetic)</span>')
        if nd["status"]:
            bits.append('<span class="badge %s">%s</span>' % (esc(nd["status"], quote=True), esc(nd["status"])))
        me = "/".join(x for x in (nd["model"], nd["effort"]) if x)
        if me:
            bits.append('<span class="meta">%s</span>' % esc(me + (" (requested)" if nd["model_requested"] else "")))
        if nd.get("effort_used"):
            bits.append('<span class="meta">%s</span>' % esc("effort used " + nd["effort_used"]))
        dur = fmt_duration(nd["start"], nd["end"])
        if dur:
            bits.append('<span class="meta">%s</span>' % esc(dur))
        return " ".join(bits)

    def item(nd):
        notes = "".join('<div class="note">%s</div>' % esc(n) for n in nd["notes"])
        if not nd["children"]:
            return '<li><div class="leaf">%s%s</div></li>' % (head(nd), notes)
        kids = "".join(item(c) for c in nd["children"])
        return '<li><details open><summary>%s</summary>%s<ul>%s</ul></details></li>' % (head(nd), notes, kids)

    body = "<ul>%s</ul>" % "".join(item(c) for c in tree["children"]) if tree["children"] else "<p>Empty trace.</p>"
    return ('<!doctype html>\n<html lang="en"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width, initial-scale=1">'
            '<title>Agent tree</title><style>%s</style></head><body><h1>Agent tree</h1>%s</body></html>\n'
            % (CSS, body))


def family(model):
    """Model family: "claude-sonnet-5-5" and "sonnet" are both "sonnet"."""
    words = [w for w in str(model).lower().split("[")[0].split("-") if w.isalpha() and w != "claude"]
    return words[0] if words else str(model)


def pair_cell(model, effort):
    return "%s · %s" % (model or "?", effort or "?")


def render_pairs(events, issue):
    """Markdown table requested x used for the issue phase (phase sessions and their subagents)."""
    last = {}
    for ev in events:
        if ev["event"] == "phase_session" and str(ev.get("issue") or "") == str(issue) and ev.get("session_id"):
            last[ev["session_id"]] = ev
    sessions, _ = build_sessions(events)
    rows = []
    for sid, ev in last.items():
        rows.append(("sessão da fase", (ev.get("requested_model"), ev.get("requested_effort")),
                     (ev.get("model"), ev.get("effort"))))
        s = sessions.get(sid)
        for child in (s["node"]["children"] if s else []):
            # Only agents opened by an Agent call: the harness's own helpers have no request.
            if child["kind"] != "subagent" or not child["model_requested"]:
                continue
            what = " — ".join([child["label"]] + child["notes"][:1])
            rows.append(("subagente: " + what, (child["model"], child["effort"]),
                         (child.get("model_used"), child.get("effort_used"))))
    out = ["| etapa | modelo/esforço pedido | modelo/esforço usado |", "|---|---|---|"]
    for what, req, used in rows:
        # A value the trace does not hold ("?") is unknown, not a divergence.
        same = all(not a or not b or a == b
                   for a, b in ((family(req[0] or ""), family(used[0] or "")), (req[1], used[1])))
        out.append("| %s | %s | %s%s |" % (what.replace("|", "/"), pair_cell(*req), pair_cell(*used),
                                           "" if same else " (diverge)"))
    if not rows:
        out.append("| sessão da fase | ? · ? | ? · ? (sem `phase_session` no trace) |")
    return "\n".join(out) + "\n"


def default_dir():
    """Root of the main checkout (dirname of git-common-dir), where .process/ lives."""
    common = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
                            text=True, capture_output=True)
    if common.returncode != 0 or not common.stdout.strip():
        return os.getcwd()
    return os.path.dirname(common.stdout.strip())


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter,
                                 epilog="\n".join(__doc__.splitlines()[2:]))
    ap.add_argument("--events", help="trace file (default: .process/events.jsonl in the main checkout)")
    ap.add_argument("--out", help="HTML file to write (default: .process/tree.html in the main checkout)")
    ap.add_argument("--text", action="store_true", help="also print the tree as text on stdout")
    ap.add_argument("--pairs", metavar="ISSUE", help="only print the requested x used table of the phase (Markdown)")
    a = ap.parse_args(argv)
    base = None
    if not (a.events and (a.out or a.pairs)):
        base = os.path.join(default_dir(), ".process")
    events_path = a.events or os.path.join(base, "events.jsonl")
    out_path = a.out or (None if a.pairs else os.path.join(base, "tree.html"))
    try:
        with open(events_path, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError as e:
        print("cannot read %s: %s" % (events_path, e.strerror), file=sys.stderr)
        return 1
    events, bad = load_events(lines)
    if a.pairs:
        sys.stdout.write(render_pairs(events, a.pairs))
        return 0
    tree = build_tree(events)
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(render_html(tree))
    if bad:
        print("skipped %d bad line%s" % (bad, "" if bad == 1 else "s"))
    print("wrote %s" % out_path)
    if a.text:
        sys.stdout.write(render_text(tree))
    return 0


if __name__ == "__main__":
    sys.exit(main())
