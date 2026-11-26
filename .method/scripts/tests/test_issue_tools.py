"""Tests of issue_template.py and auto-label.py (same titles as the templates)."""

import importlib.util
import os
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, os.path.join(ROOT, ".method", "scripts", "lib"))
os.environ["REPO_ROOT"] = ROOT
import issue_template as it  # noqa: E402

spec = importlib.util.spec_from_file_location("auto_label", os.path.join(ROOT, ".method", "scripts", "auto-label.py"))
auto_label = importlib.util.module_from_spec(spec)
spec.loader.exec_module(auto_label)


def body(**sections):
    return "\n".join("## %s\n\n%s\n" % (k, v) for k, v in sections.items())


def areas():
    path = os.path.join(ROOT, ".github", "labels.tsv")
    found = [l.split("\t", 1)[0] for l in open(path, encoding="utf-8") if l.startswith("area:")]
    if len(found) < 2:
        raise AssertionError(".github/labels.tsv needs at least two area:* labels for these tests (has %d)" % len(found))
    return found


AREAS = areas()
AREA = AREAS[0]
FULL_FEATURE = {"Objetivo": "Listar issues", "Pronto quando": "- [ ] lista",
                "Arquivos ou áreas afetadas": AREA, "Prioridade sugerida": "alta"}


class TemplateTests(unittest.TestCase):
    def test_every_template_has_the_common_required_sections(self):
        for kind in it.TYPES:
            tpl = it.load_template(kind, ROOT)
            required = [s["title"] for s in tpl["sections"] if s["required"]]
            for title in ("Objetivo", "Pronto quando", "Arquivos ou áreas afetadas"):
                self.assertIn(title, required, kind)
            self.assertTrue(tpl["labels"], kind)

    def test_type_specific_sections(self):
        req = lambda k: {s["title"] for s in it.load_template(k, ROOT)["sections"] if s["required"]}
        self.assertIn("Como reproduzir", req("bug"))
        self.assertIn("Risco de não fazer", req("debt"))
        self.assertIn("Achado em", req("finding"))
        self.assertNotIn("Prioridade sugerida", req("finding"))

    def test_templates_are_markdown_with_front_matter(self):
        for kind, name in it.TYPES.items():
            text = open(os.path.join(ROOT, ".github", "ISSUE_TEMPLATE", name), encoding="utf-8").read()
            self.assertTrue(text.startswith("---\nname: "), name)
            self.assertIn("\nabout: ", text)

    def test_render_keeps_titles_and_drops_empty_optional(self):
        out = it.render("feature", FULL_FEATURE, ROOT)
        self.assertIn("## Objetivo\n\nListar issues", out)
        self.assertNotIn("## Bots", out)
        self.assertEqual(it.missing_required("feature", out, ROOT), [])

    def test_render_rejects_unknown_section(self):
        with self.assertRaises(ValueError):
            it.render("feature", {"Inventada": "x"}, ROOT)

    def test_guide_comment_does_not_count_as_content(self):
        text = "## Objetivo\n\n<!-- obrigatório: uma frase -->\n"
        self.assertIn("Objetivo", it.missing_required("feature", text, ROOT))


class AutoLabelTests(unittest.TestCase):
    def test_full_feature(self):
        r = auto_label.compute(body(**FULL_FEATURE, **{"Sugestão de fim": "auto-close"}), ["type:feature"])
        self.assertEqual(r["missing"], [])
        self.assertIn("priority:high", r["add"])
        self.assertIn(AREA, r["add"])
        self.assertIn("end:auto-close", r["add"])
        self.assertNotIn("needs-context", r["add"])

    def test_empty_required_section_gives_needs_context(self):
        sections = dict(FULL_FEATURE, **{"Pronto quando": ""})
        r = auto_label.compute(body(**sections), ["type:feature"])
        self.assertIn("needs-context", r["add"])
        self.assertEqual(r["missing"], ["Pronto quando"])

    def test_untouched_template_gives_needs_context(self):
        tpl = open(os.path.join(ROOT, ".github", "ISSUE_TEMPLATE", "bug.md"), encoding="utf-8").read()
        _, rest = it.parse_front_matter(tpl)
        r = auto_label.compute(rest, ["type:bug"])
        self.assertIn("needs-context", r["add"])
        self.assertIn("Como reproduzir", r["missing"])

    def test_no_sections_gives_needs_context(self):
        r = auto_label.compute("texto solto", [])
        self.assertIn("needs-context", r["add"])

    def test_filled_later_removes_needs_context(self):
        r = auto_label.compute(body(**FULL_FEATURE), ["type:feature", "needs-context"])
        self.assertEqual(r["remove"], ["needs-context"])

    def test_type_detected_from_sections(self):
        sections = dict(FULL_FEATURE, **{"Risco de não fazer": "piora"})
        r = auto_label.compute(body(**sections), [])
        self.assertEqual(r["type"], "debt")
        self.assertIn("debt", r["add"])

    def test_sensitive_and_path_areas(self):
        # Areas come from the repository's own labels.tsv; rules are written for them.
        sens, path = AREAS[0], AREAS[1]
        self.with_rules("sensitive\t\\blogin\\b\t%s\npath\t(^|\\s)apps/\t%s\n" % (sens, path),
                        lambda: self.check_areas(sens, path))

    def check_areas(self, sens, path):
        sections = dict(FULL_FEATURE, **{"Arquivos ou áreas afetadas": "apps/ e o login"})
        r = auto_label.compute(body(**sections), ["type:feature"])
        self.assertIn(sens, r["add"])
        self.assertIn(path, r["add"])

    def with_rules(self, text, check):
        handle = tempfile.NamedTemporaryFile("w", suffix=".tsv", delete=False, encoding="utf-8")
        handle.write(text)
        handle.close()
        previous = os.environ.get("LABEL_AREAS_FILE")
        os.environ["LABEL_AREAS_FILE"] = handle.name
        try:
            check()
        finally:
            os.unlink(handle.name)
            if previous is None:
                os.environ.pop("LABEL_AREAS_FILE", None)
            else:
                os.environ["LABEL_AREAS_FILE"] = previous

    def test_relay_note_between_repos_does_not_get_needs_context(self):
        note = "**De:** gerenciadora A · **Para:** gerenciadora B · **Pedido:** x · **Responde a:** —\n\ntexto livre"
        r = auto_label.compute(note, [])
        self.assertNotIn("needs-context", r["add"])
        self.assertEqual(r["missing"], [])
        r = auto_label.compute(note, ["needs-context"])
        self.assertEqual(r["remove"], ["needs-context"])
        r = auto_label.compute("texto livre sem cabeçalho", [])
        self.assertIn("needs-context", r["add"])

    def test_existing_priority_is_kept(self):
        r = auto_label.compute(body(**FULL_FEATURE), ["type:feature", "priority:low"])
        self.assertNotIn("priority:high", r["add"])

    def test_finding_size(self):
        sections = {"Objetivo": "x", "Pronto quando": "- [ ] y", "Arquivos ou áreas afetadas": "docs/",
                    "Achado em": "PR #3, tamanho medium"}
        r = auto_label.compute(body(**sections), ["finding"])
        self.assertIn("size:medium", r["add"])
        self.assertEqual(r["missing"], [])

    def test_existing_type_label_is_not_duplicated(self):
        # Issue already with type:chore and a feature body: does not add a second type:*.
        r = auto_label.compute(body(**FULL_FEATURE), ["type:chore"])
        self.assertEqual([l for l in r["add"] if l.startswith("type:")], [])

    def test_unknown_area_is_ignored(self):
        sections = dict(FULL_FEATURE, **{"Arquivos ou áreas afetadas": "area:nao-existe"})
        r = auto_label.compute(body(**sections), ["type:feature"])
        self.assertNotIn("area:nao-existe", r["add"])

    def test_area_rules_come_from_configuration(self):
        # A repository maps its own paths without editing auto-label.py (#101).
        a, b = AREAS[0], AREAS[1]

        def check():
            sections = dict(FULL_FEATURE, **{"Arquivos ou áreas afetadas": "apps/web e pagamento"})
            r = auto_label.compute(body(**sections), ["type:feature"])
            self.assertIn(a, r["add"])
            self.assertIn(b, r["add"])
            for other in AREAS[2:]:
                self.assertNotIn(other, r["add"])

        self.with_rules("path\tapps/\t%s\nsensitive\t\\bpagamento\\b\t%s\n" % (a, b), check)


if __name__ == "__main__":
    unittest.main(verbosity=0)
