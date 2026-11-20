"""Tests of gen-changelog.py and gen-roadmap.py."""

import importlib.util
import os
import time
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), os.path.join(ROOT, "scripts", name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


changelog = load("gen-changelog")
roadmap = load("gen-roadmap")


def pr(n, title, labels, merged="2026-01-10T10:00:00Z"):
    return {"number": n, "title": title, "labels": [{"name": l} for l in labels],
            "mergedAt": merged, "url": "https://x/pull/%d" % n}


def issue(n, title, labels):
    return {"number": n, "title": title, "labels": [{"name": l} for l in labels],
            "url": "https://x/issues/%d" % n}


class ChangelogTests(unittest.TestCase):
    def test_groups_by_type_and_skips_test(self):
        text = changelog.render([pr(1, "feat: a", ["type:feature"]), pr(2, "fix: b", ["type:bug"]),
                                 pr(3, "test pr", ["test", "type:feature"]), pr(4, "x", [])])
        self.assertIn("## Funcionalidades\n\n- feat: a ([#1](https://x/pull/1))", text)
        self.assertIn("## Correções", text)
        self.assertIn("## Outros", text)
        self.assertNotIn("#3", text)

    def test_skips_the_prs_of_gen_docs(self):
        gen = dict(pr(9, "docs: regenerate changelog and roadmap", []), headRefName="gen-docs/abc123")
        phase = dict(pr(8, "feat: x", ["type:feature"]), headRefName="feat/issue-8-x")
        text = changelog.render([gen, phase])
        self.assertIn("feat: x", text)
        self.assertNotIn("regenerate", text)

    def test_included_pr_counts_as_merged_and_comes_first(self):
        current = pr(9, "chore: fase 0", ["type:chore"], merged=None)
        text = changelog.render([pr(1, "chore: old", ["type:chore"]), current])
        self.assertLess(text.index("#9"), text.index("#1"))

    def test_pr_with_two_types_appears_once_in_the_first_group(self):
        text = changelog.render([pr(7, "feat: x", ["type:chore", "type:feature"])])
        self.assertEqual(1, text.count("#7]"))
        self.assertIn("## Funcionalidades", text)
        self.assertNotIn("## Manutenção", text)

    def test_date_is_local_not_utc(self):
        old_tz = os.environ.get("TZ")
        os.environ["TZ"] = "America/Sao_Paulo"
        time.tzset()
        try:
            text = changelog.render([pr(6, "chore: x", ["type:chore"], merged="2026-01-18T01:40:59Z")])
        finally:
            if old_tz is None:
                os.environ.pop("TZ", None)
            else:
                os.environ["TZ"] = old_tz
            time.tzset()
        self.assertIn("2026-01-17", text)
        self.assertNotIn("2026-01-18", text)


class RoadmapTests(unittest.TestCase):
    def test_by_area_and_priority_without_closing_and_test(self):
        issues = [issue(1, "fase 0", ["type:chore", "area:process"]),
                  issue(2, "baixa", ["type:feature", "area:app", "priority:low"]),
                  issue(3, "alta", ["type:feature", "area:app", "priority:high", "group:app"]),
                  issue(4, "débito", ["debt", "priority:low"]),
                  issue(5, "teste", ["test"])]
        text = roadmap.render(issues, {1})
        self.assertNotIn("#1]", text)
        self.assertNotIn("#5]", text)
        self.assertIn("## app", text)
        self.assertLess(text.index("#3]"), text.index("#2]"))
        self.assertIn("alta · group:app", text)
        self.assertIn("## Débito técnico\n\n- [#4]", text)

    def test_empty(self):
        self.assertIn("Nenhuma issue aberta.", roadmap.render([], set()))


if __name__ == "__main__":
    unittest.main(verbosity=0)
