"""A flag cited next to a script is a flag of that script (issue #144)."""

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).absolute().parents[3]


def accepts(text, name):
    if re.search(r"(?m)^[ \t|-]*--%s(\||\))" % re.escape(name), text):
        return True
    if re.search(r"""=\s*["']--%s["']""" % re.escape(name), text):
        return True
    for line in text.splitlines():
        if not line.startswith("#:"):
            continue
        if re.search(r"\bgh\b|\bgit\b", line):
            continue
        if re.search(r"--%s\b" % re.escape(name), line):
            return True
    return False


class ScriptFlagTests(unittest.TestCase):
    def test_texts_do_not_offer_rebase_as_an_option(self):
        agents = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
        skill = (ROOT / ".claude/skills/close-phase/SKILL.md").read_text(encoding="utf-8")
        self.assertIn("por rebase (o script faz)", agents)
        self.assertIn("por rebase (o script faz)", skill)
        self.assertNotIn("--rebase", agents)
        self.assertNotIn("--rebase", skill)

    def test_every_cited_flag_exists(self):
        files = [ROOT / "AGENTS.md"] + list((ROOT / ".claude/skills").rglob("*.md"))
        cite = re.compile(
            r"`.method/scripts/([A-Za-z0-9_.-]+\.sh)([^`]*)`\s*(?:\(\s*`?(--[A-Za-z0-9-]+)`?\s*\))?"
        )
        flag = re.compile(r"--([A-Za-z0-9][\w-]*)")
        bad = []
        for path in files:
            for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                for match in cite.finditer(line):
                    script, rest, paren = match.group(1), match.group(2) or "", match.group(3)
                    flags = flag.findall(rest)
                    if paren:
                        flags.append(paren[2:])
                    body_path = ROOT / ".method" / "scripts" / script
                    body = body_path.read_text(encoding="utf-8") if body_path.is_file() else ""
                    for name in flags:
                        if not body or not accepts(body, name):
                            bad.append("%s:%d .method/scripts/%s --%s" % (path.relative_to(ROOT), n, script, name))
        self.assertEqual([], bad)


if __name__ == "__main__":
    unittest.main()
