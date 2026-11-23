"""Checks of the template's example files. Not copied into an adopted repository."""

import os
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))


class ExampleFileTests(unittest.TestCase):
    def test_deploy_example_is_dispatch_only(self):
        path = os.path.join(ROOT, ".github", "workflows", "deploy-example.yml")
        text = open(path, encoding="utf-8").read()
        on = text.split("\non:\n", 1)[1].split("\npermissions:", 1)[0]
        self.assertIn("workflow_dispatch", on)
        self.assertNotIn("\n  push", "\n" + on)
        self.assertNotIn("pull_request", on)

    def test_app_readme_names_deploy(self):
        text = open(os.path.join(ROOT, "app", "README.md"), encoding="utf-8").read()
        self.assertIn("deploy.sh", text)


if __name__ == "__main__":
    unittest.main()
