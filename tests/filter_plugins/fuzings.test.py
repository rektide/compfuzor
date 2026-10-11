#!/usr/bin/env python3
"""Declaration errors must fail before filesystem generation."""
import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "library/filter_plugins"))
from ansible.errors import AnsibleFilterError
from fuzings import compile_fuzings


FUZE = {"id": "client", "scope": "user", "actions": {"refresh": {"kind": "zim-import"}}}
MEMBER = {"id": "proxy", "target": {"dir": "/owned/client", "fuze": "client", "scope": "user"},
          "actions": {"refresh": {"kind": "zim-import", "order": 60}}}


class FuzingsTest(unittest.TestCase):
    def compile(self, fuze=None, members=None):
        return compile_fuzings(fuze, members, "proxy-git", "/owned/proxy")

    def test_closed_index_can_withdraw_offers_without_pruning(self):
        files = self.compile(FUZE, [MEMBER])["etc_files"]
        self.assertEqual(files[-1]["json"]["sources"], ["fuzings/proxy.json"])
        empty = self.compile(None, [])["etc_files"]
        self.assertEqual(empty, [{"name": "fuzings.json", "json": {
            "version": 1, "deployment": {"id": "proxy-git", "dir": "/owned/proxy"}, "sources": []}}])
        self.assertEqual(self.compile(), {"etc_files": [], "etc_dirs": []})

    def test_rejects_invalid_members_before_render(self):
        variants = [
            {"id": "../escape"}, {"extra": True}, {"actions": {}},
            {"target": {**MEMBER["target"], "scope": "all"}},
            {"target": {**MEMBER["target"], "dir": "relative"}},
            {"target": {**MEMBER["target"], "dir": "/owned/../client"}},
        ]
        bad_actions = [
            {"kind": "unknown", "order": 1},
            {"kind": "zim-import", "order": True},
            {"kind": "zim-import", "order": -1},
            {"kind": "zim-import", "order": 1.5},
            {"kind": "zim-import", "order": 2**53},
            {"kind": "zim-import", "order": 1, "path": "bin/no.sh"},
            {"kind": "zim-import", "order": 1, "args": []},
            {"kind": "exec", "order": 1, "path": "bin/../../no.sh"},
            {"kind": "exec", "order": 1, "path": "bin/run.sh", "args": "--all"},
            {"kind": "exec", "order": 1, "path": "bin/run.sh", "args": ["bad\0arg"]},
            {"kind": "shell-source", "order": 1, "path": "etc/a.zsh", "args": []},
        ]
        variants += [{"actions": {"refresh": action}} for action in bad_actions]
        for variant in variants:
            with self.subTest(variant=variant), self.assertRaises(AnsibleFilterError):
                self.compile(members=[{**copy.deepcopy(MEMBER), **variant}])
        with self.assertRaisesRegex(AnsibleFilterError, "duplicate fuzing"):
            self.compile(members=[MEMBER, MEMBER])

    def test_owner_and_required_ids_are_strict(self):
        for value in [[], {**FUZE, "scope": "all"}, {**FUZE, "actions": {}},
                      {**FUZE, "actions": {"refresh": {"kind": "zim-import", "required": ["proxy", "proxy"]}}}]:
            with self.subTest(value=value), self.assertRaises(AnsibleFilterError):
                self.compile(fuze=value)


if __name__ == "__main__":
    unittest.main()
