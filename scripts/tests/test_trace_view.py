"""Tests of trace-view.py."""

import contextlib
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPT = os.path.join(ROOT, "scripts", "trace-view.py")


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), os.path.join(ROOT, "scripts", name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


tv = load("trace-view")

PHASE = "phase-session-16"
PLAN = "plan-session"
BR = "chore/issue-16-x"


def ev(ts, event, sid, **kw):
    d = {"ts": "2026-01-18T" + ts + "Z", "event": event, "session_id": sid, "agent_id": "", "agent_type": "",
         "model": "", "effort": "", "cwd": "/x", "branch": "", "issue": ""}
    d.update(kw)
    return json.dumps(d)


def phase(ts, event, **kw):
    kw.setdefault("branch", BR)
    kw.setdefault("issue", "16")
    return ev(ts, event, kw.pop("sid", PHASE), **kw)


SAMPLE = [
    ev("02:00:00", "SessionStart", PLAN, model="opus", synthetic=True, branch="main"),
    ev("02:10:00", "SubagentStart", PLAN, agent_id="t1", agent_type="triage", model="haiku", branch="main"),
    ev("02:10:40", "SubagentStop", PLAN, agent_id="t1", agent_type="triage", branch="main"),
    phase("03:00:00", "SessionStart", model="opus", effort="high", source="startup"),
    phase("03:01:00", "PreToolUse", model="sonnet", effort="high", tool_use_id="u1",
          subagent_type="general-purpose", description="Step 1 <b>x</b>"),
    phase("03:01:01", "SubagentStart", agent_id="a1", agent_type="general-purpose"),
    phase("03:13:31", "SubagentStop", agent_id="a1", agent_type="general-purpose"),
    phase("03:14:00", "PreToolUse", model="sonnet", effort="medium", tool_use_id="u2",
          subagent_type="general-purpose", description="Step 2"),
    phase("03:14:01", "SubagentStart", agent_id="a2", agent_type="general-purpose"),
    phase("03:15:01", "SubagentStop", agent_id="a2", agent_type="general-purpose"),
    phase("03:20:00", "SubagentStart", agent_id="r1", agent_type="close-reviewer"),
    phase("03:22:00", "SubagentStop", agent_id="r1", agent_type="close-reviewer"),
    phase("03:23:00", "bot_ask", bot="bot-a", ask_id="7"),
    phase("03:24:00", "bot_reply", bot="bot-a", ask_id="7"),
    phase("03:25:00", "bot_ask", bot="outro", ask_id="8"),
    phase("03:26:00", "review_round", round="1", verdict="approved"),
    phase("03:27:00", "phase_closed"),
]


def find(nd, label):
    for c in nd["children"]:
        if c["label"] == label:
            return c
    raise AssertionError("no child %r under %r" % (label, nd["label"]))


class TraceViewTests(unittest.TestCase):
    def tree(self, lines=None):
        events, _ = tv.load_events(SAMPLE if lines is None else lines)
        return tv.build_tree(events)

    def test_hierarchy(self):
        root = self.tree()
        self.assertEqual(["planning"], [c["label"] for c in root["children"]])
        plan = root["children"][0]
        self.assertEqual({"triage", "phase #16"}, {c["label"] for c in plan["children"]})
        ph = find(plan, "phase #16")
        labels = [c["label"] for c in ph["children"]]
        self.assertEqual(["general-purpose", "general-purpose", "reviewer", "bot bot-a", "bot outro"], labels)

    def test_synthetic_planning_is_marked(self):
        plan = self.tree()["children"][0]
        self.assertTrue(plan["synthetic"])
        self.assertIn("(synthetic)", tv.render_text(self.tree()))

    def test_pairs_table_requested_and_used(self):
        lines = SAMPLE + [
            phase("03:00:30", "phase_session", model="claude-opus-9", effort="high",
                  requested_model="opus", requested_effort="high"),
            phase("03:13:31", "SubagentStop", agent_id="a1", agent_type="general-purpose",
                  model="claude-sonnet-9", effort="high"),
            phase("03:15:01", "SubagentStop", agent_id="a2", agent_type="general-purpose",
                  model="claude-opus-9", effort="low"),
        ]
        events, _ = tv.load_events(lines)
        table = tv.render_pairs(events, "16").splitlines()
        self.assertEqual("| etapa | modelo/esforço pedido | modelo/esforço usado |", table[0])
        self.assertEqual("| sessão da fase | opus · high | claude-opus-9 · high |", table[2])
        self.assertEqual("| subagente: general-purpose — Step 1 <b>x</b> | sonnet · high | claude-sonnet-9 · high |", table[3])
        # Another model and another effort than the requested ones: marked.
        self.assertEqual("| subagente: general-purpose — Step 2 | sonnet · medium | claude-opus-9 · low (diverge) |", table[4])
        # The reviewer of the sample has no Agent request: it is not a row.
        self.assertEqual(5, len(table))

    def test_pairs_table_session_divergence_and_empty(self):
        ev_ = phase("03:00:30", "phase_session", model="claude-sonnet-9", effort="low",
                    requested_model="opus", requested_effort="high")
        events, _ = tv.load_events([ev_])
        self.assertIn("| sessão da fase | opus · high | claude-sonnet-9 · low (diverge) |",
                      tv.render_pairs(events, "16"))
        self.assertIn("sem `phase_session` no trace", tv.render_pairs(events, "99"))

    def test_pairs_cli_prints_only_the_table(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "events.jsonl")
            with open(path, "w", encoding="utf-8") as f:
                f.write(phase("03:00:30", "phase_session", model="m", effort="low",
                              requested_model="m", requested_effort="low") + "\n")
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                self.assertEqual(0, tv.main(["--events", path, "--pairs", "16"]))
            self.assertTrue(out.getvalue().startswith("| etapa |"))
            self.assertEqual(["events.jsonl"], os.listdir(d))

    def test_requested_model_and_effort(self):
        ph = find(self.tree()["children"][0], "phase #16")
        s1, s2 = ph["children"][0], ph["children"][1]
        self.assertEqual(("sonnet", "high", True), (s1["model"], s1["effort"], s1["model_requested"]))
        self.assertEqual(("sonnet", "medium"), (s2["model"], s2["effort"]))
        self.assertEqual(["Step 1 <b>x</b>"], s1["notes"])
        self.assertEqual("opus", ph["model"])

    def test_post_tool_use_links_parallel_subagents(self):
        # Three requests in the same second, starts out of order: PostToolUse gives the exact link.
        lines = [
            phase("04:00:00", "PreToolUse", model="sonnet", effort="medium", tool_use_id="u7", description="Step 7"),
            phase("04:00:00", "PostToolUse", tool_use_id="u7", subagent_id="b7"),
            phase("04:00:01", "PreToolUse", model="sonnet", effort="low", tool_use_id="u8", description="Step 8"),
            phase("04:00:01", "PostToolUse", tool_use_id="u8", subagent_id="b8"),
            phase("04:00:02", "SubagentStart", agent_id="b8", agent_type="general-purpose"),
            phase("04:00:02", "SubagentStart", agent_id="b7", agent_type="general-purpose"),
            phase("04:00:30", "SubagentStop", agent_id="b8", agent_type="general-purpose"),
        ]
        lines[-1] = phase("04:00:30", "SubagentStop", agent_id="b8", agent_type="general-purpose", effort="low")
        ph = self.tree(lines)["children"][0]
        got = {c["notes"][0]: (c["effort"], c["status"]) for c in ph["children"]}
        used = {c["notes"][0]: c.get("effort_used") for c in ph["children"]}
        self.assertEqual({"Step 8": "low", "Step 7": None}, used)
        self.assertIn("effort used low", tv.render_text(self.tree(lines)))
        self.assertEqual({"Step 8": ("low", "done"), "Step 7": ("medium", "running")}, got)

    def test_session_with_only_session_end_is_ignored(self):
        lines = SAMPLE + [ev("03:30:00", "SessionEnd", "stray", branch=BR, issue="16")]
        plan = self.tree(lines)["children"][0]
        self.assertEqual(1, [c["label"] for c in plan["children"]].count("phase #16"))

    def test_status_and_duration(self):
        plan = self.tree()["children"][0]
        ph = find(plan, "phase #16")
        self.assertEqual("closed", ph["status"])
        self.assertEqual("done", ph["children"][0]["status"])
        self.assertEqual("done", plan["status"])
        self.assertEqual("12m 30s", tv.fmt_duration(ph["children"][0]["start"], ph["children"][0]["end"]))
        self.assertEqual("1m 00s", tv.fmt_duration(ph["children"][1]["start"], ph["children"][1]["end"]))
        self.assertIn("phase #16 [closed] opus/high 27m 00s", tv.render_text(self.tree()))

    def test_running_when_no_stop(self):
        lines = [l for l in SAMPLE if not ('SubagentStop' in l and '"a1"' in l)]
        ph = find(self.tree(lines)["children"][0], "phase #16")
        self.assertEqual("running", ph["children"][0]["status"])

    def test_reviewer_and_triage_labels(self):
        plan = self.tree()["children"][0]
        tri = find(plan, "triage")
        self.assertEqual("done", tri["status"])
        self.assertEqual("40s", tv.fmt_duration(tri["start"], tri["end"]))
        self.assertEqual("reviewer", find(find(plan, "phase #16"), "reviewer")["label"])

    def test_bots_and_notes(self):
        ph = find(self.tree()["children"][0], "phase #16")
        self.assertEqual("replied", find(ph, "bot bot-a")["status"])
        self.assertEqual("waiting", find(ph, "bot outro")["status"])
        self.assertIn("review round 1: approved", ph["notes"])

    def test_phase_without_planning_hangs_on_root(self):
        lines = [l for l in SAMPLE if PLAN not in l]
        root = self.tree(lines)
        self.assertEqual(["phase #16"], [c["label"] for c in root["children"]])

    def test_bad_lines_are_skipped_and_counted(self):
        events, bad = tv.load_events(SAMPLE + ["{not json", "", "[1]", '{"event":"x","ts":"nope"}'])
        self.assertEqual(3, bad)
        self.assertEqual(len(SAMPLE), len(events))

    def test_html_escapes_values_and_is_self_contained(self):
        page = tv.render_html(self.tree())
        self.assertIn("Step 1 &lt;b&gt;x&lt;/b&gt;", page)
        self.assertNotIn("<b>x</b>", page)
        self.assertIn("prefers-color-scheme: dark", page)
        self.assertIn("<details", page)
        self.assertNotIn("http", page)
        self.assertNotIn("<script", page)

    def test_empty_trace(self):
        self.assertEqual("(empty trace)\n", tv.render_text(self.tree([])))
        self.assertIn("Empty trace", tv.render_html(self.tree([])))

    def test_cli_writes_html_and_prints_text(self):
        with tempfile.TemporaryDirectory() as d:
            src = os.path.join(d, "events.jsonl")
            out = os.path.join(d, "sub", "tree.html")
            with open(src, "w", encoding="utf-8") as f:
                f.write("\n".join(SAMPLE) + "\n{broken\n")
            r = subprocess.run([sys.executable, SCRIPT, "--events", src, "--out", out, "--text"],
                               text=True, capture_output=True)
            self.assertEqual(0, r.returncode, r.stderr)
            self.assertIn("skipped 1 bad line", r.stdout)
            self.assertIn("phase #16 [closed]", r.stdout)
            with open(out, encoding="utf-8") as f:
                self.assertIn("<title>Agent tree</title>", f.read())

    def test_cli_without_text_prints_no_tree(self):
        with tempfile.TemporaryDirectory() as d:
            src = os.path.join(d, "e.jsonl")
            out = os.path.join(d, "t.html")
            with open(src, "w", encoding="utf-8") as f:
                f.write("\n".join(SAMPLE) + "\n")
            r = subprocess.run([sys.executable, SCRIPT, "--events", src, "--out", out], text=True, capture_output=True)
            self.assertEqual(0, r.returncode, r.stderr)
            self.assertNotIn("phase #16", r.stdout)
            self.assertTrue(os.path.exists(out))

    def test_cli_missing_events_file_fails(self):
        with tempfile.TemporaryDirectory() as d:
            r = subprocess.run([sys.executable, SCRIPT, "--events", os.path.join(d, "no.jsonl"),
                                "--out", os.path.join(d, "t.html")], text=True, capture_output=True)
            self.assertEqual(1, r.returncode)


if __name__ == "__main__":
    unittest.main()
